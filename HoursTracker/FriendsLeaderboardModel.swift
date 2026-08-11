import SwiftUI

// MARK: - Friends leaderboard (redesign)
//
// The Friends hub as a competitive board: podium, metric switcher, ranked
// rows, crew summary. Everything here renders from data the app already
// publishes — weekly hours, level/prestige, streaks — so no card shows a
// number the app cannot actually source.

// MARK: - Metric

/// Which column the board ranks on. Each case has to supply its own units,
/// because the podium and the "you're N behind" line both read as nonsense if
/// hours phrasing is reused for levels or streak days.
enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case thisWeek
    case levels
    case streaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWeek: return "This Week"
        case .levels: return "Levels"
        case .streaks: return "Streaks"
        }
    }

    var icon: String {
        switch self {
        case .thisWeek: return "chart.bar.fill"
        case .levels: return "star.fill"
        case .streaks: return "flame.fill"
        }
    }

    func value(_ entry: LeaderboardEntry) -> Double {
        switch self {
        case .thisWeek: return entry.weeklyHours
        // Prestige dominates level, so a P1 L16 outranks a P0 L24 the same way
        // the profile header presents them.
        case .levels: return Double(entry.prestige * 1000 + entry.level)
        case .streaks: return Double(entry.streak)
        }
    }

    func display(_ entry: LeaderboardEntry) -> String {
        switch self {
        case .thisWeek: return AppTheme.Format.hours(entry.weeklyHours)
        case .levels: return "Lv \(entry.level)"
        case .streaks: return "\(entry.streak)d"
        }
    }

    /// Gap wording for the "you vs the person above you" line.
    func gapPhrase(_ gap: Double) -> String {
        switch self {
        case .thisWeek: return AppTheme.Format.hours(gap)
        case .levels: return gap == 1 ? "1 level" : "\(Int(gap)) levels"
        case .streaks: return Int(gap) == 1 ? "1 day" : "\(Int(gap)) days"
        }
    }
}

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
    let weeklyHours: Double
    let photoURL: String?
    /// Friend opted out of sharing hours; their weekly figure is not real.
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
/// Snapshots are taken at most once per calendar day, per metric. Comparing
/// against the live board instead would make every row read "—", since the
/// baseline would update in the same breath as the value it is compared to.
enum LeaderboardRankMemory {
    private static let defaults = UserDefaults.standard

    private static func key(_ metric: LeaderboardMetric) -> String {
        "leaderboard_ranks_\(metric.rawValue)"
    }

    private static func dayKey(_ metric: LeaderboardMetric) -> String {
        "leaderboard_ranks_day_\(metric.rawValue)"
    }

    /// Applies movement to `entries` and rolls the stored snapshot forward
    /// once the calendar day changes.
    static func annotate(_ entries: [LeaderboardEntry], metric: LeaderboardMetric) -> [LeaderboardEntry] {
        let stored = defaults.dictionary(forKey: key(metric)) as? [String: Int] ?? [:]
        let storedDay = defaults.string(forKey: dayKey(metric))
        let today = todayStamp()

        var annotated = entries
        if !stored.isEmpty {
            for index in annotated.indices {
                guard let previous = stored[annotated[index].id] else { continue }
                let delta = previous - annotated[index].rank
                annotated[index].movement = delta == 0 ? 0 : delta
            }
        }

        if storedDay != today {
            let snapshot = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.rank) })
            defaults.set(snapshot, forKey: key(metric))
            defaults.set(today, forKey: dayKey(metric))
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
    /// they place among their friends is the point of the screen. Their figures
    /// come from the local store rather than their own published profile, so
    /// the board is correct the moment they log a shift instead of after a
    /// server recompute.
    static func board(
        myUid: String?,
        myName: String,
        myProfile: GamificationProfile,
        myWeeklyHours: Double,
        myPhotoURL: String?,
        friends: [FriendProfile],
        metric: LeaderboardMetric
    ) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = [
            LeaderboardEntry(
                id: myUid ?? "me",
                name: myName,
                isMe: true,
                level: myProfile.level,
                prestige: myProfile.prestige,
                streak: myProfile.currentStreak,
                weeklyHours: myWeeklyHours,
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
                weeklyHours: friend.privacy.shareHours ? friend.weeklyHours : 0,
                photoURL: friend.profilePhotoURL,
                hoursHidden: !friend.privacy.shareHours
            )
        }

        let sorted = entries.sorted { lhs, rhs in
            let l = metric.value(lhs), r = metric.value(rhs)
            // Stable tiebreak, so equal values don't reshuffle between renders
            // and make the movement arrows lie.
            return l == r
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : l > r
        }
        var ranked = sorted
        for index in ranked.indices { ranked[index].rank = index + 1 }
        return LeaderboardRankMemory.annotate(ranked, metric: metric)
    }
}
