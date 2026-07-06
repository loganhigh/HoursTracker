import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

/// One entry in the social activity feed. Stored at
/// `users/{authorUid}/activity/{eventId}` — fan-in: each friend's feed is the
/// union of *their* recent events from each of their friends' subcollections.
/// This avoids the Firestore `in`-query limit (max 30 ids) that a single
/// global collection would hit, and naturally garbage-collects when an author
/// removes themselves.
struct ActivityEvent: Identifiable, Equatable, Hashable {
    enum Kind: String {
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

    let id: String
    /// Author of the event — the friend (or current user) it's about.
    let authorUid: String
    /// Resolved at write-time so the feed can render without an extra lookup.
    let authorDisplayName: String
    let kind: Kind
    /// Free-form, already-formatted message body (e.g. "worked 12.5h today").
    /// We render headline as "{authorDisplayName} {body}" so the feed reads
    /// like sentences without per-event string templates in the view layer.
    let body: String
    /// Optional numeric payload (hours, milestone value, streak length, …).
    /// Used by some kinds for richer rendering — never required.
    let metric: Double?
    let createdAt: Date

    /// SF Symbol that the feed cell uses for the leading icon. Keeps the
    /// rendering logic out of the view file.
    var iconName: String {
        switch kind {
        case .shiftLogged:        return "clock.fill"
        case .badgeUnlocked:      return "rosette"
        case .monthlyMilestone:   return "calendar.badge.checkmark"
        case .weeklyMilestone:    return "calendar"
        case .streakMilestone:    return "flame.fill"
        case .prestige:           return "crown.fill"
        case .challengeCompleted: return "flag.checkered"
        case .crewJoined:         return "person.3.fill"
        case .other:              return "sparkles"
        }
    }

    static func from(uid authorUid: String, id: String, data: [String: Any]) -> ActivityEvent? {
        guard
            let kindRaw = data["kind"] as? String,
            let kind = Kind(rawValue: kindRaw),
            let name = data["authorDisplayName"] as? String,
            let body = data["body"] as? String
        else { return nil }
        let metric = data["metric"] as? Double
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return ActivityEvent(
            id: id,
            authorUid: authorUid,
            authorDisplayName: name,
            kind: kind,
            body: body,
            metric: metric,
            createdAt: createdAt
        )
    }
}

// MARK: - Service

/// Owns the social activity feed: pushes events for the current user and
/// subscribes to one snapshot listener per friend (plus the user themselves)
/// to assemble a merged, time-ordered timeline.
///
/// Lifecycle is tied to `startListening(uid:friendUids:)`; pass a fresh
/// friend list each time the friends graph changes (the service will diff
/// listeners and only add/remove what's needed).
@MainActor
final class ActivityFeedService: ObservableObject {
    static let shared = ActivityFeedService()

    @Published var events: [ActivityEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    /// uid → listener for that user's `activity` subcollection.
    private var listeners: [String: ListenerRegistration] = [:]
    /// uid → most recent decoded events. Merged into `events` whenever any
    /// per-user listener fires, so the timeline updates incrementally.
    private var perAuthor: [String: [ActivityEvent]] = [:]
    private var currentUid: String?
    /// Authors whose first snapshot has been ingested — we skip push alerts for
    /// that initial hydration so opening the app doesn't notify for old shifts.
    private var hydratedAuthors: Set<String> = []

    /// Cap on how many events we keep per author in-memory. The feed view
    /// shows a global window, so we don't need long per-author histories —
    /// this also limits Firestore read costs.
    private let maxEventsPerAuthor = 30
    /// Lower bound for "recent" — we only surface events created within this
    /// rolling window. Older events stay in Firestore (for analytics) but
    /// don't clutter the feed.
    private let recentWindow: TimeInterval = 14 * 24 * 3600 // 14 days

    private init() {}

    // MARK: Subscription

    /// Start (or refresh) listeners for the user + all current friends.
    /// Idempotent — call again whenever the friends list changes.
    func startListening(uid: String, friendUids: [String]) {
        currentUid = uid
        let wanted = Set([uid] + friendUids)
        let current = Set(listeners.keys)
        isLoading = current.isEmpty && !wanted.isEmpty

        for removed in current.subtracting(wanted) {
            listeners[removed]?.remove()
            listeners.removeValue(forKey: removed)
            perAuthor.removeValue(forKey: removed)
            hydratedAuthors.remove(removed)
        }
        for added in wanted.subtracting(current) {
            attach(uid: added)
        }
        rebuildEvents()
    }

    func stopListening() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
        perAuthor.removeAll()
        hydratedAuthors.removeAll()
        currentUid = nil
        events = []
        isLoading = false
    }

    private func attach(uid: String) {
        let query = db.collection("users").document(uid).collection("activity")
            .order(by: "createdAt", descending: true)
            .limit(to: maxEventsPerAuthor)

        listeners[uid] = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    return
                }
                let previousIds = Set((self.perAuthor[uid] ?? []).map(\.id))
                let parsed = snapshot?.documents.compactMap { doc in
                    ActivityEvent.from(uid: uid, id: doc.documentID, data: doc.data())
                } ?? []

                let isInitialHydration = !self.hydratedAuthors.contains(uid)
                if isInitialHydration {
                    self.hydratedAuthors.insert(uid)
                } else {
                    let newEvents = parsed.filter { !previousIds.contains($0.id) }
                    self.notifyForNewFriendEvents(newEvents, authorUid: uid)
                }

                self.perAuthor[uid] = parsed
                self.isLoading = false
                self.rebuildEvents()
            }
        }
    }

    private func rebuildEvents() {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        let merged = perAuthor.values
            .flatMap { $0 }
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
        events = merged
    }

    // MARK: Publishing

    /// Convenience overload used by HoursStore — does nothing if the user is
    /// not signed in, has opted out of activity sharing, or Firestore is
    /// not reachable. Errors are swallowed and logged; the activity feed is
    /// best-effort and never blocks the entry-logging flow.
    func publish(
        kind: ActivityEvent.Kind,
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

    private func notifyForNewFriendEvents(_ events: [ActivityEvent], authorUid: String) {
        // Friend shift alerts are delivered via FCM (Cloud Function) so they
        // reach friends when the app is backgrounded or closed. Foreground
        // display is handled by PushAppDelegate.willPresent.
        _ = events
        _ = authorUid
    }
}
