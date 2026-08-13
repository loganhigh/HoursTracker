import Foundation
import Combine
import os
import FirebaseAuth
import FirebaseFirestore

// MARK: - Presence
//
// "Active now" for the global leaderboard. Each signed-in client stamps
// `presence/{uid}.lastActiveAt` while the app is foregrounded — once on
// activation, then on a slow heartbeat — and anyone can count how many
// stamps are recent with a server-side aggregation query, so no client ever
// downloads the presence collection itself.
//
// Presence is inherently approximate: someone who force-quits stays "active"
// until their last stamp ages out of the window. A tighter figure needs a
// realtime-database onDisconnect hook, which isn't worth a second database
// dependency for one stat tile.

@MainActor
final class PresenceService: ObservableObject {
    static let shared = PresenceService()

    /// Signed-in users stamped within `activeWindow` of now. `nil` until the
    /// first count resolves — callers show a placeholder rather than 0, so an
    /// unresolved query never reads as "nobody's here".
    @Published private(set) var activeNowCount: Int?

    /// How recent a stamp must be to count as "on the app right now".
    /// Generous relative to the heartbeat so one dropped write doesn't flick
    /// an active user off the count.
    private static let activeWindow: TimeInterval = 5 * 60
    private static let heartbeatInterval: TimeInterval = 2 * 60

    private let db = Firestore.firestore()
    private var heartbeatTask: Task<Void, Never>?

    private init() {}

    // MARK: Heartbeat (this user's own stamp)

    /// Begins stamping presence. Call on foreground activation; safe to call
    /// repeatedly (a live heartbeat is left alone).
    func startHeartbeating() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.stampPresence()
                try? await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))
            }
        }
    }

    /// Stops stamping. Call on background — the last stamp then ages out of
    /// the window naturally, which is what marks this user inactive.
    func stopHeartbeating() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func stampPresence() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("presence").document(uid).setData([
                "lastActiveAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            // Missed stamps only shorten this user's apparent activity; the
            // next beat repairs it. Not worth surfacing.
            AppLogger.leaderboard.info("presence stamp failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes this user's stamp entirely (sign-out, account deletion).
    func clearPresence(uid: String) async {
        try? await db.collection("presence").document(uid).delete()
    }

    // MARK: Count (everyone's stamps)

    /// Friend uids whose presence stamp is inside the active window. Drives
    /// the green dot beside names on the Friends board.
    @Published private(set) var onlineFriendUids: Set<String> = []

    /// Looks up which of the given uids are active right now. Unlike the
    /// aggregate count this reads the actual docs, but only the friends' own —
    /// a friends list is dozens of docs at most. Timestamps are compared
    /// client-side so the `in` query needs no composite index.
    func refreshOnlineFriends(uids: [String]) async {
        guard Auth.auth().currentUser != nil else { return }
        guard !uids.isEmpty else {
            onlineFriendUids = []
            return
        }
        let cutoff = Date().addingTimeInterval(-Self.activeWindow)
        var online: Set<String> = []
        // Firestore caps documentID `in` filters at 30 values per query.
        for chunk in stride(from: 0, to: uids.count, by: 30).map({ Array(uids[$0..<min($0 + 30, uids.count)]) }) {
            do {
                let snap = try await db.collection("presence")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                for doc in snap.documents {
                    if let stamp = doc.data()["lastActiveAt"] as? Timestamp,
                       stamp.dateValue() > cutoff {
                        online.insert(doc.documentID)
                    }
                }
            } catch {
                // A failed chunk leaves those friends undotted this round;
                // the next refresh repairs it.
                AppLogger.leaderboard.info("presence friends lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        onlineFriendUids = online
    }

    /// Re-counts recent stamps via a server aggregation — the collection's
    /// documents are never downloaded.
    func refreshActiveCount() async {
        guard Auth.auth().currentUser != nil else { return }
        let cutoff = Timestamp(date: Date().addingTimeInterval(-Self.activeWindow))
        do {
            let snapshot = try await db.collection("presence")
                .whereField("lastActiveAt", isGreaterThan: cutoff)
                .count
                .getAggregation(source: .server)
            activeNowCount = snapshot.count.intValue
        } catch {
            // Keep the last figure on a failed refresh — a stale count beats
            // a tile that flickers to placeholder on every network blip.
            AppLogger.leaderboard.info("presence count failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
