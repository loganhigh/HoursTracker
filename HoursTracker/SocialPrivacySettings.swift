import Foundation
import SwiftUI
import Combine

/// User-controlled privacy switches that govern what friends can see and what
/// invitations the user is willing to receive. Persisted locally via
/// `@AppStorage` and mirrored to the user's Firestore profile snapshot so the
/// friends-listening side can honor each flag without a separate fetch.
///
/// All flags default to ON — the social features are opt-out, but every toggle
/// is surfaced clearly in Settings so the user can clamp the experience down to
/// a minimal stats-only mode at any time.
struct SocialPrivacyFlags: Equatable, Hashable {
    var shareHours: Bool
    var shareBadges: Bool
    var shareActivity: Bool
    var acceptInvites: Bool

    static let `default` = SocialPrivacyFlags(
        shareHours: true,
        shareBadges: true,
        shareActivity: true,
        acceptInvites: true
    )

    static let restrictive = SocialPrivacyFlags(
        shareHours: false,
        shareBadges: false,
        shareActivity: false,
        acceptInvites: false
    )

    /// Serializes to the Firestore payload nested under `privacy` on a user doc.
    var firestorePayload: [String: Any] {
        [
            "shareHours": shareHours,
            "shareBadges": shareBadges,
            "shareActivity": shareActivity,
            "acceptInvites": acceptInvites
        ]
    }

    /// Parses a Firestore `privacy` dictionary, falling back to defaults for
    /// any missing keys (so older profile snapshots stay friendly).
    static func from(firestore data: [String: Any]?) -> SocialPrivacyFlags {
        guard let data else { return .default }
        return SocialPrivacyFlags(
            shareHours: data["shareHours"] as? Bool ?? true,
            shareBadges: data["shareBadges"] as? Bool ?? true,
            shareActivity: data["shareActivity"] as? Bool ?? true,
            acceptInvites: data["acceptInvites"] as? Bool ?? true
        )
    }
}

/// `@MainActor` ObservableObject that bridges `@AppStorage` flags to the
/// rest of the app. UI binds to its `@Published` properties; any change is
/// persisted automatically and announced via `objectWillChange` so dependent
/// services (CloudSync) can push a refreshed profile snapshot.
@MainActor
final class SocialPrivacyStore: ObservableObject {
    static let shared = SocialPrivacyStore()

    // Storage keys are namespaced under `social_privacy_*` so they can never
    // collide with existing PaySettings or generic preference keys.
    @AppStorage("social_privacy_share_hours")    private var storedShareHours: Bool = true
    @AppStorage("social_privacy_share_badges")   private var storedShareBadges: Bool = true
    @AppStorage("social_privacy_share_activity") private var storedShareActivity: Bool = true
    @AppStorage("social_privacy_accept_invites") private var storedAcceptInvites: Bool = true

    @Published var flags: SocialPrivacyFlags

    private init() {
        // Seed the in-memory flags from persisted storage. The @AppStorage values
        // are read here once; subsequent writes go through `update(...)`.
        flags = SocialPrivacyFlags(
            shareHours: UserDefaults.standard.object(forKey: "social_privacy_share_hours") as? Bool ?? true,
            shareBadges: UserDefaults.standard.object(forKey: "social_privacy_share_badges") as? Bool ?? true,
            shareActivity: UserDefaults.standard.object(forKey: "social_privacy_share_activity") as? Bool ?? true,
            acceptInvites: UserDefaults.standard.object(forKey: "social_privacy_accept_invites") as? Bool ?? true
        )
    }

    /// Mutates a single flag, persists it, and broadcasts the change so any
    /// observer (CloudSyncManager profile pusher, FriendsView, etc.) can react.
    func update(_ mutation: (inout SocialPrivacyFlags) -> Void) {
        var next = flags
        mutation(&next)
        guard next != flags else { return }
        flags = next
        storedShareHours = next.shareHours
        storedShareBadges = next.shareBadges
        storedShareActivity = next.shareActivity
        storedAcceptInvites = next.acceptInvites
    }
}
