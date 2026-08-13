import Foundation

/// Lightweight client-side validation for the friends board. Firestore rules
/// enforce length and auth; this layer blocks empty/spammy content before writes.
enum BoardContentFilter {
    static let maxPostLength = 280
    static let maxCommentLength = 200
    static let allowedReactionEmojis: [String] = ["🔥", "💪", "😂", "😭", "🏆"]

    enum ValidationError: LocalizedError {
        case empty
        case tooLong(max: Int)
        case blockedContent
        case spam

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Write something before posting."
            case .tooLong(let max):
                return "Keep it under \(max) characters."
            case .blockedContent:
                return "That message can't be posted."
            case .spam:
                return "That looks like spam — try rephrasing."
            }
        }
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
        let joined = parts.joined().uppercased()
        if joined.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return joined
    }

    static func validatePost(_ text: String) throws -> String {
        try validate(text, maxLength: maxPostLength)
    }

    static func validateComment(_ text: String) throws -> String {
        try validate(text, maxLength: maxCommentLength)
    }

    private static func validate(_ text: String, maxLength: Int) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }
        guard trimmed.count <= maxLength else { throw ValidationError.tooLong(max: maxLength) }

        // Shared moderation — same categories as display names minus the
        // reserved-name tier (posts may say "admin"), and word-aware where
        // the old substring set here would have blocked real names embedded
        // in posts ("Ishita" contains "shit").
        if !BroadContentFilter.shared.validatePostText(trimmed).isAllowed {
            throw ValidationError.blockedContent
        }

        if isSpam(trimmed) {
            throw ValidationError.spam
        }
        return trimmed
    }

    private static func isSpam(_ text: String) -> Bool {
        let collapsed = text.replacingOccurrences(of: " ", with: "")
        if collapsed.count >= 8 {
            let unique = Set(collapsed.lowercased())
            if Double(unique.count) / Double(collapsed.count) < 0.2 {
                return true
            }
        }

        if text.filter({ $0 == "@" }).count >= 5 { return true }
        if text.filter({ $0 == "#" }).count >= 8 { return true }

        let urlPattern = #"https?://[^\s]+"#
        if text.range(of: urlPattern, options: .regularExpression) != nil,
           text.count < 40 {
            return true
        }
        return false
    }
}
