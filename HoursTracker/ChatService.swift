import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Board chat & direct messages
//
// One room everyone on the global board shares (`globalChat`) plus a private
// thread per pair of people (`dmThreads/{a_b}/messages`). Every message goes
// through a callable (sendGlobalChatMessage / sendDirectMessage) that checks
// the username, the word filter, the rate limit and blocks; this service
// only listens, sends, and keeps the viewer's block list. Plain chat
// messages never push — tagging an @username pushes that person, and every
// direct message pushes its recipient.

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let uid: String
    let username: String
    let prestige: Int
    let photoURL: String
    let text: String
    let mentions: [String]
    let createdAt: Date
    /// `ChatReaction.rawValue` → uids who reacted with it.
    var reactions: [String: [String]] = [:]

    static func parse(_ doc: QueryDocumentSnapshot) -> ChatMessage? {
        let data = doc.data()
        guard let uid = data["uid"] as? String, let text = data["text"] as? String else { return nil }
        if let supporter = data["isSupporter"] as? Bool, let name = data["username"] as? String {
            let perks = data["supporter"]
            Task { @MainActor in
                SupporterRegistry.shared.record(name: name, isSupporter: supporter, uid: uid, supporter: perks)
            }
        }
        return ChatMessage(
            id: doc.documentID,
            uid: uid,
            username: data["username"] as? String ?? "",
            prestige: (data["prestige"] as? NSNumber)?.intValue ?? 0,
            photoURL: data["photoURL"] as? String ?? "",
            text: text,
            mentions: data["mentions"] as? [String] ?? [],
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            reactions: ChatReaction.parse(data["reactions"])
        )
    }

    /// Reactions with at least one person, in the picker's order.
    var activeReactions: [(reaction: ChatReaction, uids: [String])] {
        ChatReaction.allCases.compactMap { r in
            guard let uids = reactions[r.rawValue], !uids.isEmpty else { return nil }
            return (r, uids)
        }
    }
}

/// The fixed set of Board Chat reactions. The raw values are the Firestore
/// map keys, and firestore.rules only accepts these six.
enum ChatReaction: String, CaseIterable, Identifiable {
    case like, heart, laugh, fire, strong, clap

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .like: return "👍"
        case .heart: return "❤️"
        case .laugh: return "😂"
        case .fire: return "🔥"
        case .strong: return "💪"
        case .clap: return "👏"
        }
    }

    static func parse(_ raw: Any?) -> [String: [String]] {
        guard let map = raw as? [String: Any] else { return [:] }
        var out: [String: [String]] = [:]
        for r in allCases {
            if let uids = map[r.rawValue] as? [String], !uids.isEmpty { out[r.rawValue] = uids }
        }
        return out
    }
}

struct DirectThread: Identifiable, Equatable {
    let id: String
    let otherUid: String
    let otherUsername: String
    let lastText: String
    let lastSenderUid: String
    let lastAt: Date
    let unread: Int
    /// When each participant last had the thread open (read receipts).
    var myLastReadAt: Date? = nil
    var otherLastReadAt: Date? = nil

    static func parse(_ doc: QueryDocumentSnapshot, myUid: String) -> DirectThread? {
        let data = doc.data()
        guard let participants = data["participants"] as? [String],
              let other = participants.first(where: { $0 != myUid }) else { return nil }
        let names = data["usernames"] as? [String: Any] ?? [:]
        let unread = data["unread"] as? [String: Any] ?? [:]
        let reads = data["lastReadAt"] as? [String: Any] ?? [:]
        // supporters.{uid} is the server's perk map (or a bare Bool from the
        // first version of this field).
        if let raw = (data["supporters"] as? [String: Any])?[other],
           let name = names[other] as? String {
            let isSupporter = (raw as? Bool) ?? ((raw as? [String: Any])?["isSupporter"] as? Bool ?? false)
            let perks = raw as? [String: Any]
            Task { @MainActor in
                SupporterRegistry.shared.record(name: name, isSupporter: isSupporter, uid: other, supporter: perks)
            }
        }
        return DirectThread(
            id: doc.documentID,
            otherUid: other,
            otherUsername: names[other] as? String ?? "",
            lastText: data["lastText"] as? String ?? "",
            lastSenderUid: data["lastSenderUid"] as? String ?? "",
            lastAt: (data["lastAt"] as? Timestamp)?.dateValue() ?? Date(),
            unread: (unread[myUid] as? NSNumber)?.intValue ?? 0,
            myLastReadAt: (reads[myUid] as? Timestamp)?.dateValue(),
            otherLastReadAt: (reads[other] as? Timestamp)?.dateValue()
        )
    }
}

struct DirectMessage: Identifiable, Equatable {
    let id: String
    let uid: String
    let text: String
    let createdAt: Date
}

enum ChatError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }

    /// The callable's own message when it sent one ("Keep it friendly…"),
    /// otherwise a generic line.
    static func from(_ error: Error) -> ChatError {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain, !nsError.localizedDescription.isEmpty,
           FunctionsErrorCode(rawValue: nsError.code) != .internal {
            return .server(nsError.localizedDescription)
        }
        return .server("Couldn't send — check your connection and try again.")
    }
}

@MainActor
final class ChatService: ObservableObject {
    static let shared = ChatService()

    /// Oldest first, so the newest sits at the bottom of the chat.
    @Published private(set) var globalMessages: [ChatMessage] = []
    @Published private(set) var hasLoadedGlobal = false
    @Published private(set) var threads: [DirectThread] = []
    @Published private(set) var blockedUids: Set<String> = []
    /// uid → when they last had Board Chat open; drives "Seen by N".
    @Published private(set) var globalReadTimes: [String: Date] = [:]

    var unreadDirectCount: Int { threads.filter { !blockedUids.contains($0.otherUid) }.reduce(0) { $0 + $1.unread } }

    /// Chat with blocked people filtered out.
    var visibleGlobalMessages: [ChatMessage] { globalMessages.filter { !blockedUids.contains($0.uid) } }
    var visibleThreads: [DirectThread] { threads.filter { !blockedUids.contains($0.otherUid) } }

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-central1")
    private var globalListener: ListenerRegistration?
    private var globalReadsListener: ListenerRegistration?
    private var lastGlobalReadWrite: Date?
    private var globalViewers = 0
    private var inboxListener: ListenerRegistration?
    private var blockedListener: ListenerRegistration?
    private var inboxUid: String?

    private static let globalPageSize = 150

    private init() {}

    private var myUid: String? { Auth.auth().currentUser?.uid }

    // MARK: Global room

    /// Reference-counted so the board's preview card and the full chat can
    /// both be on screen without double listeners.
    func startGlobal() {
        globalViewers += 1
        guard globalListener == nil else { return }
        globalListener = db.collection("globalChat")
            .order(by: "createdAt", descending: true)
            .limit(to: Self.globalPageSize)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                let messages = snapshot.documents.compactMap(ChatMessage.parse).reversed()
                Task { @MainActor in
                    self?.globalMessages = Array(messages)
                    self?.hasLoadedGlobal = true
                }
            }
        globalReadsListener = db.collection("globalChatReads")
            .order(by: "lastReadAt", descending: true)
            .limit(to: 500)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                var times: [String: Date] = [:]
                for doc in snapshot.documents {
                    if let t = (doc.data()["lastReadAt"] as? Timestamp)?.dateValue() {
                        times[doc.documentID] = t
                    }
                }
                Task { @MainActor in self?.globalReadTimes = times }
            }
    }

    /// How many other people have opened Board Chat since `message` landed.
    func seenCount(_ message: ChatMessage) -> Int {
        globalReadTimes.reduce(0) { count, item in
            item.key != message.uid && item.value >= message.createdAt ? count + 1 : count
        }
    }

    /// Marks Board Chat read up to now. Called by the full chat screen only
    /// (not the board's preview card), at most once every 15 seconds, and
    /// only when something newer than the last mark has arrived.
    func markGlobalRead() {
        guard let uid = myUid, let newest = globalMessages.last?.createdAt else { return }
        if let mine = globalReadTimes[uid], mine >= newest { return }
        if let last = lastGlobalReadWrite, Date().timeIntervalSince(last) < 15 { return }
        lastGlobalReadWrite = Date()
        db.collection("globalChatReads").document(uid).setData([
            "lastReadAt": FieldValue.serverTimestamp()
        ])
    }

    func stopGlobal() {
        globalViewers = max(0, globalViewers - 1)
        guard globalViewers == 0 else { return }
        globalListener?.remove()
        globalListener = nil
        globalReadsListener?.remove()
        globalReadsListener = nil
    }

    func sendGlobal(_ text: String) async throws {
        do {
            _ = try await functions.httpsCallable("sendGlobalChatMessage").call(["text": text])
        } catch {
            throw ChatError.from(error)
        }
    }

    func delete(_ message: ChatMessage) async {
        try? await db.collection("globalChat").document(message.id).delete()
    }

    /// Adds or removes the viewer's reaction. Updates the list at once so
    /// the chip responds before the listener catches up.
    func toggleReaction(_ reaction: ChatReaction, on message: ChatMessage) {
        guard let uid = myUid, let index = globalMessages.firstIndex(where: { $0.id == message.id }) else { return }
        let key = reaction.rawValue
        var uids = globalMessages[index].reactions[key] ?? []
        let removing = uids.contains(uid)
        if removing { uids.removeAll { $0 == uid } } else { uids.append(uid) }
        globalMessages[index].reactions[key] = uids.isEmpty ? nil : uids
        db.collection("globalChat").document(message.id).updateData([
            FieldPath(["reactions", key]): removing ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid])
        ])
    }

    func hasReacted(_ reaction: ChatReaction, to message: ChatMessage) -> Bool {
        guard let uid = myUid else { return false }
        return message.reactions[reaction.rawValue]?.contains(uid) ?? false
    }

    func canDelete(_ message: ChatMessage) -> Bool {
        message.uid == myUid || DeveloperConfig.isCEO(uid: myUid)
    }

    // MARK: Direct messages

    /// Inbox and block list for the signed-in user; safe to call repeatedly.
    func startInbox() {
        guard let uid = myUid else { return }
        guard inboxUid != uid else { return }
        stopInbox()
        inboxUid = uid
        // Sorted here rather than with orderBy, so no composite index is needed.
        inboxListener = db.collection("dmThreads")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                let threads = snapshot.documents
                    .compactMap { DirectThread.parse($0, myUid: uid) }
                    .sorted { $0.lastAt > $1.lastAt }
                Task { @MainActor in self?.threads = threads }
            }
        blockedListener = db.collection("users").document(uid).collection("blockedUsers")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                let ids = Set(snapshot.documents.map(\.documentID))
                Task { @MainActor in self?.blockedUids = ids }
            }
    }

    func stopInbox() {
        inboxListener?.remove()
        blockedListener?.remove()
        inboxListener = nil
        blockedListener = nil
        inboxUid = nil
        threads = []
        blockedUids = []
    }

    /// Sends to a known person (`toUid`) or by handle; returns the thread id.
    @discardableResult
    func sendDirect(_ text: String, toUid: String?, toUsername: String) async throws -> String {
        var payload: [String: Any] = ["text": text, "toUsername": toUsername]
        if let toUid { payload["toUid"] = toUid }
        do {
            let result = try await functions.httpsCallable("sendDirectMessage").call(payload)
            return (result.data as? [String: Any])?["threadId"] as? String ?? ""
        } catch {
            throw ChatError.from(error)
        }
    }

    /// The uid behind a handle, or nil when no one has it.
    func uid(forUsername name: String) async -> String? {
        let handle = Username.normalize(name)
        guard !handle.isEmpty else { return nil }
        if let known = threads.first(where: { $0.otherUsername == handle }) { return known.otherUid }
        let snap = try? await db.collection("usernames").document(handle).getDocument()
        return snap?.data()?["uid"] as? String
    }

    func threadId(with otherUid: String) -> String? {
        guard let myUid else { return nil }
        return [myUid, otherUid].sorted().joined(separator: "_")
    }

    func listenToThread(_ threadId: String, onChange: @escaping ([DirectMessage]) -> Void) -> ListenerRegistration {
        db.collection("dmThreads").document(threadId).collection("messages")
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let messages: [DirectMessage] = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    guard let uid = data["uid"] as? String, let text = data["text"] as? String else { return nil }
                    return DirectMessage(id: doc.documentID, uid: uid, text: text,
                                         createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date())
                }
                onChange(messages.reversed())
            }
    }

    /// Zeroes unread and stamps the read receipt the other person sees.
    /// Writes only when there's something new from them since the last stamp.
    func markRead(_ threadId: String) {
        guard let uid = myUid, let thread = threads.first(where: { $0.id == threadId }) else { return }
        let newFromThem = thread.lastSenderUid != uid
            && (thread.myLastReadAt.map { $0 < thread.lastAt } ?? true)
        guard thread.unread > 0 || newFromThem else { return }
        db.collection("dmThreads").document(threadId).updateData([
            "unread.\(uid)": 0,
            "lastReadAt.\(uid)": FieldValue.serverTimestamp(),
        ])
    }

    func thread(_ threadId: String) -> DirectThread? {
        threads.first { $0.id == threadId }
    }

    // MARK: One-off reads (Apple Watch)

    /// The block list right now, without waiting for the listener.
    func refreshBlocked() async {
        guard let uid = myUid,
              let snap = try? await db.collection("users").document(uid).collection("blockedUsers").getDocuments()
        else { return }
        blockedUids = Set(snap.documents.map(\.documentID))
    }

    /// The latest Board Chat messages, oldest first, blocked people removed.
    func fetchRecentGlobal(limit: Int) async -> [ChatMessage] {
        guard let snap = try? await db.collection("globalChat")
            .order(by: "createdAt", descending: true).limit(to: limit).getDocuments() else { return [] }
        return snap.documents.compactMap(ChatMessage.parse).reversed().filter { !blockedUids.contains($0.uid) }
    }

    func fetchThreads() async -> [DirectThread] {
        guard let uid = myUid,
              let snap = try? await db.collection("dmThreads").whereField("participants", arrayContains: uid).getDocuments()
        else { return visibleThreads }
        return snap.documents.compactMap { DirectThread.parse($0, myUid: uid) }
            .filter { !blockedUids.contains($0.otherUid) }
            .sorted { $0.lastAt > $1.lastAt }
    }

    func fetchThreadMessages(_ threadId: String, limit: Int) async -> [DirectMessage] {
        guard let snap = try? await db.collection("dmThreads").document(threadId).collection("messages")
            .order(by: "createdAt", descending: true).limit(to: limit).getDocuments() else { return [] }
        return snap.documents.compactMap { doc -> DirectMessage? in
            let data = doc.data()
            guard let uid = data["uid"] as? String, let text = data["text"] as? String else { return nil }
            return DirectMessage(id: doc.documentID, uid: uid, text: text,
                                 createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date())
        }.reversed()
    }

    /// Zeroes the viewer's unread count whether or not the inbox is loaded.
    func markReadNow(_ threadId: String) async {
        guard let uid = myUid else { return }
        try? await db.collection("dmThreads").document(threadId).updateData([
            "unread.\(uid)": 0,
            "lastReadAt.\(uid)": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: Safety

    func isBlocked(_ uid: String) -> Bool { blockedUids.contains(uid) }

    func block(uid: String, username: String) async {
        guard let myUid, uid != myUid else { return }
        try? await db.collection("users").document(myUid).collection("blockedUsers").document(uid)
            .setData(["username": username, "createdAt": FieldValue.serverTimestamp()])
    }

    func unblock(uid: String) async {
        guard let myUid else { return }
        try? await db.collection("users").document(myUid).collection("blockedUsers").document(uid).delete()
    }

    func report(uid: String, username: String, text: String, reason: String,
                messageId: String? = nil, threadId: String? = nil) async {
        guard let myUid else { return }
        var data: [String: Any] = [
            "reporterUid": myUid,
            "reportedUid": uid,
            "reportedUsername": username,
            "text": String(text.prefix(600)),
            "reason": String(reason.prefix(100)),
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let messageId { data["messageId"] = messageId }
        if let threadId { data["threadId"] = threadId }
        try? await db.collection("chatReports").addDocument(data: data)
    }

    #if DEBUG
    /// Screen renders only: stand-in messages and threads.
    func seedForPreview(messages: [ChatMessage], threads: [DirectThread]) {
        globalMessages = messages
        hasLoadedGlobal = true
        self.threads = threads
    }
    #endif

    static let reportReasons = ["Harassment or bullying", "Hate or slurs", "Sexual content", "Spam or scam", "Something else"]
}
