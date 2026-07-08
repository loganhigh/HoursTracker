import Foundation

/// Shared level/prestige math used by local gamification and friend profile display.
enum GamificationLevelCalculator {
    static func maxLevelForPrestige(_ prestige: Int) -> Int { 25 }

    static func xpRequiredForLevel(_ level: Int) -> Int {
        let clamped = max(level, 1)
        return Int(900 + (Double(clamped - 1) * 180) + (pow(Double(clamped - 1), 1.22) * 18))
    }

    static func levelState(
        for totalXP: Int,
        prestige: Int,
        snapshots: [Int] = []
    ) -> (level: Int, xpIntoLevel: Int, xpForNext: Int, canPrestige: Bool) {
        var xpPool = max(0, totalXP)
        let clampedPrestige = min(max(prestige, 0), 10)

        for p in 0..<clampedPrestige {
            let cap = maxLevelForPrestige(p)
            let fullRunXP = (1...cap).reduce(0) { $0 + xpRequiredForLevel($1) }
            let runXP: Int
            if p < snapshots.count {
                // A snapshot records the user's ENTIRE XP at prestige time, which
                // can exceed the standard run cost when they banked XP sitting at
                // max level before pressing Prestige. Deduct at most the standard
                // cost so the banked surplus carries into the next run instead of
                // being confiscated (matches the pre-2.0 math users levelled under).
                runXP = min(snapshots[p] - (p > 0 ? snapshots[p - 1] : 0), fullRunXP)
            } else {
                runXP = fullRunXP
            }
            xpPool = max(0, xpPool - runXP)
        }

        let maxLevel = maxLevelForPrestige(clampedPrestige)
        let xpPerRun = (1...maxLevel).reduce(0) { $0 + xpRequiredForLevel($1) }
        let cappedRunXP = min(xpPool, xpPerRun)
        var remaining = cappedRunXP
        var level = 1
        while level < maxLevel {
            let needed = xpRequiredForLevel(level)
            if remaining >= needed {
                remaining -= needed
                level += 1
            } else {
                break
            }
        }
        let xpForNext = xpRequiredForLevel(level)
        let isMaxed = level == maxLevel && remaining >= xpForNext
        let xpIntoLevel = isMaxed ? xpForNext : remaining
        let canPrestige = level >= maxLevel && prestige < 10
        return (level, xpIntoLevel, xpForNext, canPrestige)
    }

    /// Derives the display level for a friend's cloud profile snapshot.
    static func displayLevel(
        totalXP: Int?,
        storedLevel: Int,
        prestige: Int,
        snapshots: [Int]
    ) -> Int {
        guard let totalXP else { return max(storedLevel, 1) }
        return levelState(for: totalXP, prestige: prestige, snapshots: snapshots).level
    }

    static func displayLevelLine(level: Int, prestige: Int) -> String {
        if prestige > 0 { return "Level \(level) • P\(prestige)" }
        return "Level \(level)"
    }

    /// Cumulative XP at the start of `targetLevel` within the current prestige run.
    static func totalXPAtLevelStart(
        _ targetLevel: Int,
        prestige: Int,
        snapshots: [Int] = []
    ) -> Int {
        let clampedLevel = min(max(targetLevel, 1), maxLevelForPrestige(prestige))
        let clampedPrestige = min(max(prestige, 0), 10)
        var total = 0
        for p in 0..<clampedPrestige {
            let fullRunXP = (1...maxLevelForPrestige(p)).reduce(0) { $0 + xpRequiredForLevel($1) }
            if p < snapshots.count {
                let snap = snapshots[p]
                let prev = p > 0 ? snapshots[p - 1] : 0
                // Same cap as levelState: banked XP beyond the standard run cost
                // is not part of the run's cost.
                total += min(snap - prev, fullRunXP)
            } else {
                total += fullRunXP
            }
        }
        for level in 1..<clampedLevel {
            total += xpRequiredForLevel(level)
        }
        return total
    }

    /// Cumulative total XP snapshots after each completed prestige run (0..<prestige).
    static func buildSnapshotsForPrestige(_ prestige: Int) -> [Int] {
        let clamped = min(max(prestige, 0), 10)
        guard clamped > 0 else { return [] }
        let runXP = (1...maxLevelForPrestige(0)).reduce(0) { $0 + xpRequiredForLevel($1) }
        var cumulative = 0
        return (0..<clamped).map { _ in
            cumulative += runXP
            return cumulative
        }
    }

    static func rankTitle(forLevel level: Int, prestige: Int = 0) -> String {
        let names = [
            "Rookie",              // 1
            "Shift Starter",       // 2
            "Clock Puncher",       // 3
            "Hour Hustler",        // 4
            "Time Tracker",        // 5
            "Early Bird",          // 6
            "Daily Grinder",       // 7
            "Break Boss",          // 8
            "Shift Regular",       // 9
            "Week Warrior",        // 10
            "Paycheck Hunter",     // 11
            "Schedule Pro",        // 12
            "Hard Charger",        // 13
            "Time Keeper",         // 14
            "Shift Captain",       // 15
            "Hours Hero",          // 16
            "Work Warrior",        // 17
            "Clock Commander",     // 18
            "Elite Grinder",       // 19
            "Hour Machine",        // 20
            "Shift Legend",        // 21
            "Time Titan",          // 22
            "Overtime Ace",        // 23
            "OT King",             // 24
            "Prestige Ready"       // 25
        ]
        let maxLevel = maxLevelForPrestige(prestige)
        let clamped = min(max(level, 1), maxLevel)
        let base = names[min(clamped - 1, names.count - 1)]
        guard prestige > 0, let tier = PrestigeTheme.tiers.first(where: { $0.prestige == prestige }) else {
            return base
        }
        return "\(tier.name) \(base)"
    }
}
