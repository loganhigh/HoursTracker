import Foundation

// MARK: - Leaderboard, Board Chat and messages on the watch
//
// Same pattern as clock-in: the watch asks, the phone answers from the board
// and chat it already has (and sends through the same callables, so the word
// filter, blocks and rate limit all apply). Replies carry one of these as
// JSON under `WatchKeys.payload`.

struct WatchBoardRow: Codable, Equatable, Identifiable, Hashable {
    var id: String { uid }
    var uid: String
    var rank: Int
    var username: String
    var hours: Double
    var hoursHidden: Bool
    var prestige: Int
    var isMe: Bool
}

struct WatchBoard: Codable, Equatable {
    var myRank: Int?
    var myHours: Double
    var totalRanked: Int
    /// The top ten, then a gap, then the people just around you.
    var top: [WatchBoardRow]
    var aroundMe: [WatchBoardRow]
}

struct WatchChatLine: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var uid: String
    var username: String
    var text: String
    var createdAt: Date
    var isMine: Bool
    var mentionsMe: Bool
}

struct WatchChat: Codable, Equatable {
    /// Oldest first.
    var lines: [WatchChatLine]
    var myUsername: String?
    var unreadMessages: Int
}

struct WatchThreadSummary: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var otherUid: String
    var otherUsername: String
    var lastText: String
    var lastAt: Date
    var unread: Int
}

struct WatchThreadMessages: Codable, Equatable {
    var threadId: String
    /// Oldest first; `uid` is the sender, compared with `myUid`.
    var lines: [WatchChatLine]
}

/// One-tap replies offered under every composer.
enum WatchQuickReplies {
    static let all = ["Let's go 💪", "Great work!", "Congrats 🎉", "Keep it up 🔥", "Thanks!", "On my way"]
}
