import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Announcements
//
// The admin publishes one live announcement (`announcements/current`, written
// only by the adminPublishAnnouncement callable). Each client checks the doc
// on app open and shows it ONCE per announcement id — an "update now" prompt
// that meets every user the next time they use the app, then stays out of the
// way. Dismissing and updating both count as seen; re-publishing with a fresh
// id re-prompts everyone.

struct Announcement: Equatable {
    let id: String
    let title: String
    let message: String
    /// "update" routes the primary button to the App Store listing.
    let kind: String
    let buttonTitle: String

    var isUpdatePrompt: Bool { kind == "update" }
}

@MainActor
final class AnnouncementService: ObservableObject {
    static let shared = AnnouncementService()

    /// The announcement waiting to be shown, nil when there's nothing new.
    @Published private(set) var pending: Announcement?

    private static let seenKey = "announcement_last_seen_id_v1"
    private let db = Firestore.firestore()
    private var isFetching = false

    private init() {}

    /// One-shot check — called on app open / foreground, not a listener: the
    /// ask is "next time they use the app", and a live push mid-session would
    /// interrupt someone mid-shift-entry for no gain.
    func checkForAnnouncement() {
        // Dev-only rehearsal, same pattern as LEVELUP_DEMO: shows a sample
        // announcement without touching Firestore or auth. Inert unless the
        // launch environment carries the variable, which production never does.
        if let demo = ProcessInfo.processInfo.environment["ANNOUNCEMENT_DEMO"], pending == nil {
            pending = Announcement(
                id: "demo",
                title: "Update available!",
                message: "Hour Tracker 2.6 is out — smart pay projections, verified marks, and a live global leaderboard. Update now to get the latest.",
                kind: demo == "info" ? "info" : "update",
                buttonTitle: demo == "info" ? "Got it" : "Update Now"
            )
            return
        }
        guard Auth.auth().currentUser != nil, !isFetching, pending == nil else { return }
        isFetching = true
        Task { [weak self] in
            defer { self?.isFetching = false }
            guard let self else { return }
            do {
                let snap = try await db.collection("announcements").document("current").getDocument()
                guard let data = snap.data(),
                      let id = data["id"] as? String, !id.isEmpty,
                      let title = data["title"] as? String,
                      let message = data["message"] as? String else { return }
                guard id != UserDefaults.standard.string(forKey: Self.seenKey) else { return }
                pending = Announcement(
                    id: id,
                    title: title,
                    message: message,
                    kind: data["kind"] as? String ?? "info",
                    buttonTitle: data["buttonTitle"] as? String ?? "Got it"
                )
            } catch {
                // Silent: an unreachable announcement doc should never surface
                // an error in the app. The next open retries.
            }
        }
    }

    /// Marks the current announcement handled — shown at most once per id.
    func markSeen() {
        if let pending {
            UserDefaults.standard.set(pending.id, forKey: Self.seenKey)
        }
        pending = nil
    }
}
