import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct FriendShiftNudge: Identifiable, Equatable {
    let id: String
    let fromUid: String
    let fromName: String
    let createdAt: Date
    let reaction: String?

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
            reaction: reaction
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

    func sendNudge(to friendUid: String, myUid: String, myName: String) async throws {
        guard !friendUid.isEmpty else { return }
        guard friendUid != myUid else { throw NudgeError.selfNudge }
        if isOnCooldown(to: friendUid) { throw NudgeError.cooldown }

        let trimmedName = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedName = trimmedName.isEmpty ? "A friend" : String(trimmedName.prefix(40))

        let ref = db.collection("users").document(friendUid).collection("shiftNudges").document()
        let payload: [String: Any] = [
            "fromUid": myUid,
            "fromName": clampedName,
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
