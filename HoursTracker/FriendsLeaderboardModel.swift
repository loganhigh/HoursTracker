import SwiftUI

// MARK: - Friends leaderboard model
//
// The board ranks on hours logged in the current pay period, not a fixed
// Mon–Sun week: someone paid bi-weekly should see a bi-weekly board. Types
// here are shared by FriendsPodiumSections and FriendsLeaderboardSections.

// MARK: - Entry

/// One row on the board. Built for the signed-in user and every friend, so the
/// user ranks among their friends rather than sitting outside the list.
struct LeaderboardEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let isMe: Bool
    let level: Int
    let prestige: Int
    let streak: Int
    /// Hours in this person's current pay period.
    ///
    /// Each friend publishes their own cheque window, so a friend on a weekly
    /// cycle contributes a week while a bi-weekly viewer sees a fortnight. That
    /// is the honest limit of what friends broadcast — their raw shifts are
    /// never shared, only the aggregate — and it beats the previous behavior of
    /// forcing a Mon–Sun week on everyone regardless of how they are paid.
    let payPeriodHours: Double
    /// Lifetime hours, used only for the verified-tracker milestone. Ranking
    /// still runs on `payPeriodHours`; this is 0 for anyone hiding hours, so
    /// they simply go unbadged.
    /// Earns the verified badge beside the name.
    var hasReviewedApp: Bool = false
    let photoURL: String?
    /// Friend opted out of sharing hours; their figure is not real.
    let hoursHidden: Bool

    var rank: Int = 0
    /// Places gained (+) or lost (−) since the last day this board was opened.
    /// `nil` when there is no earlier snapshot to compare against.
    var movement: Int?

    var levelLine: String {
        prestige > 0 ? "Level \(level) • P\(prestige)" : "Level \(level)"
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

// MARK: - Rank movement memory

/// Remembers yesterday's ranking so rows can show movement.
///
/// Snapshots are taken at most once per calendar day. Comparing against the
/// live board instead would make every row read "—", since the baseline would
/// update in the same breath as the value it is compared to.
enum LeaderboardRankMemory {
    private static let defaults = UserDefaults.standard
    private static let ranksKey = "leaderboard_ranks_payPeriod"
    private static let dayKey = "leaderboard_ranks_day_payPeriod"

    /// Applies movement to `entries` and rolls the stored snapshot forward
    /// once the calendar day changes.
    static func annotate(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        let stored = defaults.dictionary(forKey: ranksKey) as? [String: Int] ?? [:]
        let storedDay = defaults.string(forKey: dayKey)
        let today = todayStamp()

        var annotated = entries
        if !stored.isEmpty {
            for index in annotated.indices {
                guard let previous = stored[annotated[index].id] else { continue }
                annotated[index].movement = previous - annotated[index].rank
            }
        }

        if storedDay != today {
            let snapshot = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.rank) })
            defaults.set(snapshot, forKey: ranksKey)
            defaults.set(today, forKey: dayKey)
        }
        return annotated
    }

    private static func todayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// MARK: - Board construction

extension LeaderboardEntry {
    /// Builds the ranked board: the signed-in user plus every friend.
    ///
    /// The user is a row like anyone else rather than a separate card — where
    /// they place among their friends is the point of the screen. Their figure
    /// comes from the local store rather than their own published profile, so
    /// the board is correct the moment they log a shift instead of after a
    /// server recompute.
    static func board(
        myUid: String?,
        myName: String,
        myProfile: GamificationProfile,
        myPayPeriodHours: Double,
        myPhotoURL: String?,
        friends: [FriendProfile]
    ) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = [
            LeaderboardEntry(
                id: myUid ?? "me",
                name: myName,
                isMe: true,
                level: myProfile.level,
                prestige: myProfile.prestige,
                streak: myProfile.currentStreak,
                payPeriodHours: myPayPeriodHours,
                hasReviewedApp: VerifiedTracker.isSelfVerified,
                photoURL: myPhotoURL,
                hoursHidden: false
            )
        ]

        entries += friends.map { friend in
            LeaderboardEntry(
                id: friend.uid,
                name: friend.displayName,
                isMe: false,
                level: friend.level,
                prestige: friend.prestige,
                streak: friend.currentStreak,
                // A friend who hides hours publishes 0. Ranking that as a real
                // zero is the only honest position for a value the app is not
                // allowed to see, but the row renders "—" rather than "0h".
                payPeriodHours: friend.privacy.shareHours ? friend.chequeHours : 0,
                hasReviewedApp: friend.hasReviewedApp,
                photoURL: friend.profilePhotoURL,
                hoursHidden: !friend.privacy.shareHours
            )
        }

        let sorted = entries.sorted { lhs, rhs in
            // Stable tiebreak, so equal values don't reshuffle between renders
            // and make the movement arrows lie.
            lhs.payPeriodHours == rhs.payPeriodHours
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.payPeriodHours > rhs.payPeriodHours
        }
        var ranked = sorted
        for index in ranked.indices { ranked[index].rank = index + 1 }
        return LeaderboardRankMemory.annotate(ranked)
    }
}
