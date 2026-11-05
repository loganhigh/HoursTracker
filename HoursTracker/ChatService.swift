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

    static func parse(_ doc: QueryDocumentSnapshot) -> ChatMessage? {
        let data = doc.data()
        guard let uid = data["uid"] as? String, let text = data["text"] as? String else { return nil }
        return ChatMessage(
            id: doc.documentID,
            uid: uid,
            username: data["username"] as? String ?? "",
            prestige: (data["prestige"] as? NSNumber)?.intValue ?? 0,
            photoURL: data["photoURL"] as? String ?? "",
            text: text,
            mentions: data["mentions"] as? [String] ?? [],
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
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

    static func parse(_ doc: QueryDocumentSnapshot, myUid: String) -> DirectThread? {
        let data = doc.data()
        guard let participants = data["participants"] as? [String],
              let other = participants.first(where: { $0 != myUid }) else { return nil }
        let names = data["usernames"] as? [String: Any] ?? [:]
        let unread = data["unread"] as? [String: Any] ?? [:]
        return DirectThread(
            id: doc.documentID,
            otherUid: other,
            otherUsername: names[other] as? String ?? "",
            lastText: data["lastText"] as? String ?? "",
            lastSenderUid: data["lastSenderUid"] as? String ?? "",
            lastAt: (data["lastAt"] as? Timestamp)?.dateValue() ?? Date(),
            unread: (unread[myUid] as? NSNumber)?.intValue ?? 0
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

    var unreadDirectCount: Int { threads.filter { !blockedUids.contains($0.otherUid) }.reduce(0) { $0 + $1.unread } }

    /// Chat with blocked people filtered out.
    var visibleGlobalMessages: [ChatMessage] { globalMessages.filter { !blockedUids.contains($0.uid) } }
    var visibleThreads: [DirectThread] { threads.filter { !blockedUids.contains($0.otherUid) } }

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-central1")
    private var globalListener: ListenerRegistration?
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
    }

    func stopGlobal() {
        globalViewers = max(0, globalViewers - 1)
        guard globalViewers == 0 else { return }
        globalListener?.remove()
        globalListener = nil
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

    func markRead(_ threadId: String) {
        guard let uid = myUid,
              threads.first(where: { $0.id == threadId }).map({ $0.unread > 0 }) ?? false else { return }
        db.collection("dmThreads").document(threadId).updateData(["unread.\(uid)": 0])
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
        try? await db.collection("dmThreads").document(threadId).updateData(["unread.\(uid)": 0])
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
