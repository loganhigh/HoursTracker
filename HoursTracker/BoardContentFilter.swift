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

    private static let blockedWords: Set<String> = [
        "fuck", "shit", "bitch", "asshole", "cunt", "nigger", "faggot", "retard"
    ]

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

        let lowered = trimmed.lowercased()
        for word in blockedWords where lowered.contains(word) {
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
