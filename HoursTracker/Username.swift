import Foundation

/// The handle friends add each other by. Mirrors functions/src/social/usernames.js
/// exactly — one canonical form (lowercase, 3–20 characters, letter first, then
/// letters / digits / underscore). The client validates for instant feedback;
/// uniqueness is only ever decided by the `claimUsername` callable.
enum Username {
    static let minLength = 3
    static let maxLength = 20

    /// Same list as the server: handles that would impersonate the app or its staff.
    static let reserved: Set<String> = [
        "admin", "admins", "administrator", "administrators", "root", "system",
        "support", "help", "helpdesk", "staff", "team", "official", "moderator",
        "moderators", "mod", "mods", "dev", "devs", "developer", "developers",
        "hourtracker", "hour_tracker", "hourstracker", "hours_tracker", "tracker",
        "trackedhours", "tracked_hours", "apple", "google", "firebase",
        "null", "undefined", "anonymous", "deleted", "unknown", "me", "you",
    ]

    /// Canonical form of whatever was typed: trimmed, lowercased, no leading @.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasPrefix("@") { s.removeFirst() }
        return s
    }

    /// What a text field should keep as the user types: lowercase, allowed
    /// characters only, capped at the max length.
    static func filteredForTyping(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let kept = lowered.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        return String(kept.prefix(maxLength))
    }

    /// nil when `username` (canonical) is acceptable, else a user-facing reason.
    /// `moderation` defaults to the shared name filter so handles get the same
    /// slur / impersonation screening as display names.
    static func problem(with username: String, moderation: (String) -> Bool = { !BroadContentFilter.shared.validate($0).isAllowed }) -> String? {
        if username.isEmpty { return "Choose a username." }
        if username.count < minLength { return "Usernames need at least \(minLength) characters." }
        if username.count > maxLength { return "Usernames can be at most \(maxLength) characters." }
        guard let first = username.first, first.isASCII, first.isLetter else {
            return "Usernames must start with a letter."
        }
        let allowed = username.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        if !allowed { return "Use letters, numbers, and underscores only." }
        if reserved.contains(username) { return "That username is reserved." }
        if moderation(username) { return "That username isn't allowed." }
        return nil
    }

    /// A starting point derived from a display name ("Mike Thompson" → "mike_thompson",
    /// falling back to "worker" when nothing usable survives). Never returns a
    /// reserved handle; the caller still has to check availability.
    static func suggestion(from displayName: String) -> String {
        let folded = displayName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        var out = ""
        var lastWasSeparator = true
        for ch in folded {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                out.append("_")
                lastWasSeparator = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        while let f = out.first, !(f.isLetter) { out.removeFirst() }
        if out.count < minLength || reserved.contains(out) { out = "worker" }
        return String(out.prefix(maxLength))
    }

    /// "@mike_47" for display.
    static func display(_ username: String) -> String { "@" + username }
}
