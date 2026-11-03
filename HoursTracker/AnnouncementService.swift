import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Announcements
//
// The admin publishes one live announcement (`announcements/current`, written
// only by the adminPublishAnnouncement callable). Each client checks the doc
// on app open and shows it ONCE per announcement id — an "update now" prompt
// that meets every out-of-date user the next time they use the app, then
// stays out of the way (see Announcement.isRelevant for who is skipped). Dismissing and updating both count as seen; re-publishing with a fresh
// id re-prompts everyone.

struct Announcement: Equatable {
    let id: String
    let title: String
    let message: String
    /// "update" routes the primary button to the App Store listing.
    let kind: String
    let buttonTitle: String

    var isUpdatePrompt: Bool { kind == "update" }

    /// Who an announcement is for. An update prompt names the version it
    /// asks for, so anyone already on it (or newer) is skipped. And an
    /// account created after the announcement went out never sees it: it
    /// signed up on a current build and the news is old. This is what keeps
    /// a brand-new user from landing on a pop-up the moment they sign up.
    static func isRelevant(
        kind: String,
        targetVersion: String?,
        publishedAt: Date?,
        installedVersion: String,
        accountCreatedAt: Date?
    ) -> Bool {
        if let publishedAt, let accountCreatedAt, accountCreatedAt >= publishedAt {
            return false
        }
        if kind == "update", let targetVersion, !targetVersion.isEmpty,
           !isVersion(installedVersion, olderThan: targetVersion) {
            return false
        }
        return true
    }

    /// Numeric dotted-version compare ("3.4" < "3.10"); missing parts are 0.
    static func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// The admin composes one message for everyone; `{name}` (or `{username}`,
    /// any case) is filled in per device with the user's own username so it
    /// can read "Hey logan, …". Falls back to "there" for an account that
    /// hasn't claimed a username yet, so the copy never shows a raw brace.
    static func personalized(_ text: String, name rawName: String?) -> String {
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filled = name.isEmpty ? "there" : name
        return text.replacingOccurrences(
            of: #"\{\s*(name|username)\s*\}"#,
            with: filled,
            options: [.regularExpression, .caseInsensitive]
        )
    }
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
                let kind = data["kind"] as? String ?? "info"
                let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                guard Announcement.isRelevant(
                    kind: kind,
                    targetVersion: data["version"] as? String,
                    publishedAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                    installedVersion: installed,
                    accountCreatedAt: Auth.auth().currentUser?.metadata.creationDate
                ) else {
                    // Not for this user — record it so it's never re-checked.
                    UserDefaults.standard.set(id, forKey: Self.seenKey)
                    return
                }
                // Same key the profile snapshot publishes as the user's name —
                // it holds the claimed username on every build since usernames.
                let name = UserDefaults.standard.string(forKey: "profile_display_name")
                pending = Announcement(
                    id: id,
                    title: Announcement.personalized(title, name: name),
                    message: Announcement.personalized(message, name: name),
                    kind: kind,
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
