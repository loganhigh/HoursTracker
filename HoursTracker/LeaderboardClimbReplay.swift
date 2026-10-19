import Foundation

// MARK: - Global board climb replay
//
// When the user opens the global board after climbing while it was closed,
// their row starts back at the rank they last saw and climbs up past each
// person they overtook, one step at a time, while a pill counts the people
// passed. This file holds the pure parts (step ranks, board order, copy) and
// the last-seen rank store; GlobalLeaderboardView drives the animation.

enum LeaderboardClimbReplay {
    /// Most steps a climb takes, so a 40-place jump still finishes in a
    /// couple of seconds (it moves several places per step instead).
    static let maxSteps = 12

    /// The ranks the row stops at on its way from `old` up to `new`, ending
    /// at `new`. Empty unless it's a climb (a smaller rank number).
    static func steps(from old: Int, to new: Int, maxSteps: Int = maxSteps) -> [Int] {
        let gained = old - new
        guard gained > 0, new >= 1, maxSteps > 0 else { return [] }
        let count = min(gained, maxSteps)
        return (1...count).map { i in
            old - Int((Double(gained) * Double(i) / Double(count)).rounded())
        }
    }

    /// Seconds between steps: slow enough to see each person go by, with
    /// the longest climbs finishing in about three seconds.
    static func stepInterval(stepCount: Int) -> Double {
        guard stepCount > 0 else { return 0 }
        return min(0.4, max(0.26, 3.0 / Double(stepCount)))
    }

    /// The board with `uid` placed at `rank` and everyone renumbered by
    /// position, so rank numbers roll as the row moves. Unchanged when the
    /// uid isn't on the board.
    static func order(_ trackers: [TopTracker], placing uid: String, atRank rank: Int) -> [TopTracker] {
        var rows = trackers
        guard let idx = rows.firstIndex(where: { $0.uid == uid }) else { return trackers }
        let mine = rows.remove(at: idx)
        let target = min(max(rank - 1, 0), rows.count)
        rows.insert(mine, at: target)
        return rows.enumerated().map { $0.element.withRank($0.offset + 1) }
    }

    /// "You passed 1 person" / "You passed 12 people".
    static func passedText(_ count: Int) -> String {
        count == 1 ? "You passed 1 person" : "You passed \(count) people"
    }

    // MARK: Last-seen rank

    static func lastSeenKey(uid: String) -> String { "global_last_seen_rank_\(uid)" }

    /// The rank the user last saw on the board, or nil if never recorded.
    static func lastSeenRank(uid: String, defaults: UserDefaults = .standard) -> Int? {
        let value = defaults.integer(forKey: lastSeenKey(uid: uid))
        return value > 0 ? value : nil
    }

    static func rememberRank(_ rank: Int, uid: String, defaults: UserDefaults = .standard) {
        guard rank > 0 else { return }
        defaults.set(rank, forKey: lastSeenKey(uid: uid))
    }

    /// Records a starting point the first time the user is seen on the
    /// board, even if they never open it, so their first climb after that
    /// can replay. Never overwrites an existing value.
    static func seedIfNeeded(rank: Int, uid: String, defaults: UserDefaults = .standard) {
        guard lastSeenRank(uid: uid, defaults: defaults) == nil else { return }
        rememberRank(rank, uid: uid, defaults: defaults)
    }
}

extension TopTracker {
    /// The same tracker at a different rank (used while replaying a climb).
    func withRank(_ newRank: Int) -> TopTracker {
        TopTracker(
            uid: uid,
            name: name,
            hours: hours,
            countryCode: countryCode,
            rank: newRank,
            photoURL: photoURL,
            level: level,
            prestige: prestige,
            streak: streak,
            hasReviewedApp: hasReviewedApp,
            occupation: occupation,
            hoursHidden: hoursHidden
        )
    }
}
