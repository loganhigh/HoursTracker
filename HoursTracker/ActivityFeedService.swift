import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

/// Kind of social activity event written to `users/{authorUid}/activity/{eventId}`.
/// The raw values are the on-the-wire contract read by the Cloud Function that
/// fans these out to friends as push notifications — do not rename them.
enum ActivityEventKind: String {
    case shiftLogged           // "Jake worked 12.5h today"
    case badgeUnlocked         // "Logan unlocked Iron Month"
    case monthlyMilestone      // "Tyler hit 200h this month"
    case weeklyMilestone       // "Sam crossed 50h this week"
    case streakMilestone       // "Pat hit a 10-day streak"
    case prestige              // "Alex reached Prestige 2"
    case challengeCompleted    // (Phase 2 — kept for forward compat)
    case crewJoined            // (Phase 2 — kept for forward compat)
    case other
}

// MARK: - Service

/// Publishes the current user's social activity events. Writing a document
/// under `users/{uid}/activity` is what triggers the Cloud Function that sends
/// friends their push notifications, so this is a write-only service — nothing
/// in the app reads the feed back.
@MainActor
final class ActivityFeedService {
    static let shared = ActivityFeedService()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: Publishing

    /// Convenience overload used by HoursStore — does nothing if the user is
    /// not signed in, has opted out of activity sharing, or Firestore is
    /// not reachable. Errors are swallowed and logged; the activity feed is
    /// best-effort and never blocks the entry-logging flow.
    func publish(
        kind: ActivityEventKind,
        body: String,
        metric: Double? = nil,
        documentId: String? = nil
    ) {
        guard SocialPrivacyStore.shared.flags.shareActivity else { return }
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "Worker"
        let eventId = documentId ?? UUID().uuidString
        var payload: [String: Any] = [
            "kind": kind.rawValue,
            "authorDisplayName": displayName,
            "body": body,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let metric {
            payload["metric"] = metric
        }

        db.collection("users").document(uid).collection("activity").document(eventId)
            .setData(payload, merge: true) { error in
                if let error {
                    #if DEBUG
                    print("ActivityFeedService.publish error: \(error.localizedDescription)")
                    #endif
                }
            }
    }
}
