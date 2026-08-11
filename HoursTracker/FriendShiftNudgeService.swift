import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Nudge catalog

/// One sendable nudge. Two tones, deliberately: cheering a friend on and
/// goading them are both reasons to open the app, and a single generic
/// "don't forget to log your shifts" served neither.
///
/// `id` is what lands in Firestore and what the Cloud Function keys its push
/// copy off, so the values are stable strings — renaming one silently
/// downgrades in-flight nudges to the generic fallback.
struct NudgeKind: Identifiable, Equatable, Hashable {
    enum Tone: String, CaseIterable {
        case cheer
        case compete

        var sectionTitle: String {
            switch self {
            case .cheer: return "Cheer them on"
            case .compete: return "Talk some trash"
            }
        }
    }

    let id: String
    let emoji: String
    /// What the sender picks from.
    let label: String
    /// What the recipient reads. `{name}` is replaced with their first name,
    /// Apple-Fitness style, so the message lands as addressed to them.
    let messageTemplate: String
    let tone: Tone

    func message(recipientFirstName: String) -> String {
        let name = recipientFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            // Drop the direct address rather than greeting an empty string.
            return messageTemplate
                .replacingOccurrences(of: ", {name}", with: "")
                .replacingOccurrences(of: " {name}", with: "")
                .replacingOccurrences(of: "{name}", with: "")
        }
        return messageTemplate.replacingOccurrences(of: "{name}", with: name)
    }

    static let all: [NudgeKind] = [
        NudgeKind(id: "goodJob", emoji: "👏", label: "Good job",
                  messageTemplate: "Good job, {name}! Those hours are stacking up.",
                  tone: .cheer),
        NudgeKind(id: "keepGoing", emoji: "💪", label: "Keep going",
                  messageTemplate: "Keep going, {name}! You've got this.",
                  tone: .cheer),
        NudgeKind(id: "proudOfYou", emoji: "🙌", label: "Proud of you",
                  messageTemplate: "Proud of you, {name}. Great week of work.",
                  tone: .cheer),
        NudgeKind(id: "almostThere", emoji: "⭐️", label: "Almost there",
                  messageTemplate: "Almost there, {name} — finish strong!",
                  tone: .cheer),
        NudgeKind(id: "beatMyHours", emoji: "🔥", label: "Beat my hours",
                  messageTemplate: "Think you can beat my hours, {name}? Go on then.",
                  tone: .compete),
        NudgeKind(id: "slacking", emoji: "😴", label: "You're slacking",
                  messageTemplate: "You're slacking, {name}. Get back out there!",
                  tone: .compete),
        NudgeKind(id: "catchMe", emoji: "🏆", label: "Catch me if you can",
                  messageTemplate: "Catch me if you can, {name}!",
                  tone: .compete),
        logShifts,
    ]

    /// Nudges written before this catalog existed carry no type. They were all
    /// the generic reminder, so that is what they resolve to. Declared
    /// standalone rather than looked up out of `all`, so the fallback can never
    /// be a force-unwrapped search that trips if the id is ever renamed.
    static let logShifts = NudgeKind(
        id: "logShifts", emoji: "👋", label: "Log your shifts",
        messageTemplate: "Don't forget to log your shifts, {name}!",
        tone: .compete
    )

    static var fallback: NudgeKind { logShifts }

    static func kind(id: String?) -> NudgeKind {
        guard let id else { return fallback }
        return all.first { $0.id == id } ?? fallback
    }

    static func kinds(tone: Tone) -> [NudgeKind] { all.filter { $0.tone == tone } }
}

// MARK: - Model

struct FriendShiftNudge: Identifiable, Equatable {
    let id: String
    let fromUid: String
    let fromName: String
    let createdAt: Date
    let reaction: String?
    let kind: NudgeKind

    static func from(id: String, data: [String: Any]) -> FriendShiftNudge? {
        guard
            let fromUid = data["fromUid"] as? String,
            let fromName = data["fromName"] as? String
        else { return nil }
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let reaction = data["reaction"] as? String
        return FriendShiftNudge(
            id: id,
            fromUid: fromUid,
            fromName: fromName,
            createdAt: createdAt,
            reaction: reaction,
            kind: NudgeKind.kind(id: data["type"] as? String)
        )
    }
}

// MARK: - Service

@MainActor
final class FriendShiftNudgeService: ObservableObject {
    static let shared = FriendShiftNudgeService()

    /// The most recent nudge waiting for an emoji reply.
    @Published var pendingNudge: FriendShiftNudge?
    @Published var lastSentFriendUid: String?
    @Published var errorMessage: String?

    /// Emojis a friend can tap to respond to a nudge.
    static let responseEmojis: [String] = ["👍", "💪", "🔥", "😅", "🙏", "✅"]

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var activeUid: String?
    private let cooldownKeyPrefix = "shift_nudge_sent_"
    private let cooldownInterval: TimeInterval = 24 * 3600

    private init() {}

    func startListening(uid: String) {
        guard activeUid != uid || listener == nil else { return }
        stopListening()
        activeUid = uid

        listener = db.collection("users").document(uid).collection("shiftNudges")
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .limit(to: 5)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let pending = snapshot?.documents.compactMap { doc in
                        FriendShiftNudge.from(id: doc.documentID, data: doc.data())
                    }.first { $0.reaction == nil }
                    self.pendingNudge = pending
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        activeUid = nil
        pendingNudge = nil
    }

    enum NudgeError: LocalizedError {
        case notSignedIn
        case cooldown
        case selfNudge

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to nudge friends."
            case .cooldown: return "You already nudged them today. Try again tomorrow."
            case .selfNudge: return "You can't nudge yourself."
            }
        }
    }

    /// - Parameter bypassCooldown: set only when firing straight back at a
    ///   nudge just received. A volley is the point of the feature, and the
    ///   per-friend daily cooldown would otherwise kill it on the first
    ///   return shot. Each direction still marks its own cooldown, so this
    ///   buys one reply, not an open channel.
    func sendNudge(
        to friendUid: String,
        myUid: String,
        myName: String,
        kind: NudgeKind,
        bypassCooldown: Bool = false
    ) async throws {
        guard !friendUid.isEmpty else { return }
        guard friendUid != myUid else { throw NudgeError.selfNudge }
        if !bypassCooldown, isOnCooldown(to: friendUid) { throw NudgeError.cooldown }

        let trimmedName = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedName = trimmedName.isEmpty ? "A friend" : String(trimmedName.prefix(40))

        let ref = db.collection("users").document(friendUid).collection("shiftNudges").document()
        let payload: [String: Any] = [
            "fromUid": myUid,
            "fromName": clampedName,
            "type": kind.id,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ]

        // Firestore persists the write to its local cache the moment `setData`
        // is issued, so it will sync once connectivity allows. Don't block the
        // UI on the server acknowledgment — that await can suspend indefinitely
        // when offline, leaving the nudge button spinning forever. Race the ack
        // against a short timeout; on timeout we treat the durable local write
        // as sent. A genuine permission error still propagates and surfaces.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await ref.setData(payload) }
            group.addTask { try await Task.sleep(nanoseconds: 6_000_000_000) }
            defer { group.cancelAll() }
            try await group.next()
        }

        markSent(to: friendUid)
        lastSentFriendUid = friendUid
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.lastSentFriendUid == friendUid {
                self?.lastSentFriendUid = nil
            }
        }
    }

    func respond(to nudge: FriendShiftNudge, emoji: String, myUid: String) async throws {
        guard Self.responseEmojis.contains(emoji) else { return }
        let ref = db.collection("users").document(myUid).collection("shiftNudges").document(nudge.id)
        try await ref.updateData([
            "status": "reacted",
            "reaction": emoji,
            "reactedAt": FieldValue.serverTimestamp()
        ])
        if pendingNudge?.id == nudge.id {
            pendingNudge = nil
        }
    }

    func dismissPendingNudge() {
        pendingNudge = nil
    }

    private func isOnCooldown(to friendUid: String) -> Bool {
        let key = cooldownKeyPrefix + friendUid
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else { return false }
        return Date().timeIntervalSince(last) < cooldownInterval
    }

    private func markSent(to friendUid: String) {
        UserDefaults.standard.set(Date(), forKey: cooldownKeyPrefix + friendUid)
    }
}
