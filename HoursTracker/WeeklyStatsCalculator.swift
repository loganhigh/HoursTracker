import Foundation

/// Single source of truth for "this week" semantics across the social
/// surface (leaderboard, snapshot publish, activity feed). We use a
/// Monday-start week here intentionally — even though some legacy charts
/// inside RootView render Sunday-start columns, the consumer-facing
/// productivity week (and what every existing analytics helper already
/// uses, see `HoursAnalyticsCalculator` / `GamificationEngine.makeWeeklyChallenges`)
/// is Monday-aligned. Centralizing it here means we can change the
/// definition once and have leaderboards / feeds / privacy all stay in sync.
enum WeeklyStatsCalculator {

    /// Calendar with Monday set as the first weekday and ISO-style minimum
    /// days in first week. Use this any time you need a stable week interval.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    /// Returns the half-open `[start, end)` interval for the current week
    /// containing `now`. If for any reason the calendar fails to resolve the
    /// week, falls back to a 7-day window ending right now.
    static func currentWeekInterval(now: Date = Date()) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
            return interval
        }
        let end = now
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
        return DateInterval(start: start, end: end)
    }

    /// Sum of paid hours for `entries` that fall within the current Monday-aligned
    /// week, ignoring off-day entries (they don't contribute to "hours worked").
    static func weeklyHours(_ entries: [WorkEntry], now: Date = Date()) -> Double {
        let interval = currentWeekInterval(now: now)
        return entries
            .filter { !$0.isOffDay && interval.contains($0.date) }
            .reduce(0) { $0 + $1.paidHours }
    }

    /// Sum of overtime hours for `entries` in the current week, computed via
    /// the store's pay breakdown (so each entry's province / multiplier rules
    /// are honored). Off-day entries skip the breakdown call.
    static func weeklyOvertimeHours(
        _ entries: [WorkEntry],
        overtimeForEntry: (WorkEntry) -> Double,
        now: Date = Date()
    ) -> Double {
        let interval = currentWeekInterval(now: now)
        return entries
            .filter { !$0.isOffDay && interval.contains($0.date) }
            .reduce(0) { $0 + overtimeForEntry($1) }
    }

    /// Count of non-off-day shift entries logged in the current week.
    static func weeklyShiftsLogged(_ entries: [WorkEntry], now: Date = Date()) -> Int {
        let interval = currentWeekInterval(now: now)
        return entries.filter { !$0.isOffDay && interval.contains($0.date) }.count
    }

    /// Returns the number of distinct calendar days the user logged a non-off-day
    /// entry within the current week. Used as the "Consistency" leaderboard metric.
    static func weeklyDaysLogged(_ entries: [WorkEntry], now: Date = Date()) -> Int {
        let interval = currentWeekInterval(now: now)
        let cal = calendar
        let days = entries
            .filter { !$0.isOffDay && interval.contains($0.date) }
            .map { cal.startOfDay(for: $0.date) }
        return Set(days).count
    }
}
