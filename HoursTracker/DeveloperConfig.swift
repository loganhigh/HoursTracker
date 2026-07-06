import Foundation

/// Developer-only configuration. Used to award the "Developer" achievement to the app author
/// and to display special titles for the app owner.
/// Safe for App Store: no hardcoded emails, uses stable identifiers only.
enum DeveloperConfig {
    /// Firebase UIDs that receive the special "Developer" badge.
    /// Add a UID after first sign-in:
    /// 1. Run the app in DEBUG mode and sign in with Apple
    /// 2. Look for "Firebase uid: <your_id>" in the Xcode console
    /// 3. Add your UID to the set below
    static let developerUserIDs: Set<String> = [
        "msUcdbAbaAaS4HDj52CMs0Vzw8j2"
    ]

    /// Firebase UIDs that should display the "CEO of Hour Tracker" title in place of
    /// the default "Member since YYYY" subtitle.
    static let ceoUserIDs: Set<String> = [
        "msUcdbAbaAaS4HDj52CMs0Vzw8j2"
    ]

    /// Returns true when the given Firebase UID is recognized as the app owner.
    static func isCEO(uid: String?) -> Bool {
        guard let uid else { return false }
        return ceoUserIDs.contains(uid)
    }
}
