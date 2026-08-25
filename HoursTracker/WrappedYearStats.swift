import Foundation

// MARK: - Wrapped (year-in-review) value types
//
// Pure data — no Firebase, no HoursStore reference. Produced by
// WrappedStatsEngine.compute(...) and consumed by (future) Wrapped UI.

/// A single day's total, used for "busiest day."
struct WrappedDayTotal: Equatable {
    /// Start-of-day (`Calendar.startOfDay`), not a specific shift's date/time.
    let day: Date
    let hours: Double
}

/// A single week's total, used for "busiest week." Weeks are Monday-start,
/// matching `HoursStore`'s week convention (`firstWeekday = 2`) rather than
/// `AchievementBadges.BadgeStats`'s Sunday-start convention — see the
/// implementation summary for why these differ in the existing codebase.
struct WrappedWeekTotal: Equatable {
    let weekStart: Date
    let hours: Double
}

/// A single month's total, used for "busiest month" and monthly averages.
struct WrappedMonthTotal: Equatable {
    /// First day of the month.
    let monthStart: Date
    let hours: Double
}

/// One completed calendar year's Wrapped stats, computed entirely from
/// `WorkEntry` history (live + archived). See `WrappedStatsEngine` for how
/// each field is derived and `WORKED_ENTRIES` conventions (off-days excluded
/// throughout).
struct WrappedYearStats: Equatable {
    let year: Int

    // MARK: Volume
    let totalHours: Double
    /// Worked shifts only (`!isOffDay`) — matches `BadgeStats.totalDays`'s
    /// convention of counting entries, not distinct days.
    let totalShifts: Int
    let averageShiftLengthHours: Double

    // MARK: Extremes
    let longestShiftHours: Double
    /// Start-of-day of the longest shift, nil only if there were no worked shifts.
    let longestShiftDate: Date?
    /// The actual `start` Date (date + time) of the shift with the earliest
    /// clock-in time-of-day this year.
    let earliestShiftStart: Date?
    /// The actual `end` Date (date + time) of the shift with the latest
    /// clock-out time-of-day this year, using the after-midnight rollover
    /// convention documented on `WrappedStatsEngine.lateNightAdjustedMinutes`.
    let latestShiftEnd: Date?

    // MARK: Long-day thresholds (shift count, not distinct days — same
    // convention as BadgeStats.longDaysOver12/14)
    let shiftsOver8Hours: Int
    let shiftsOver10Hours: Int
    let shiftsOver12Hours: Int
    let shiftsOver14Hours: Int

    // MARK: Busiest windows
    let busiestDay: WrappedDayTotal?
    let busiestWeek: WrappedWeekTotal?
    let busiestMonth: WrappedMonthTotal?

    // MARK: Chart series
    //
    // Pre-built so slides can draw complete charts without ever touching
    // WorkEntry again — the whole point of the engine being the single
    // statistics source.

    /// All 12 months of `year` in calendar order (January → December),
    /// including months with no shifts (0 hours). Always exactly 12
    /// elements, even for an empty year, so a chart can render a full
    /// Jan–Dec axis without padding it itself.
    let monthlyTotals: [WrappedMonthTotal]

    /// The seven days of `busiestWeek`, Monday → Sunday, including days with
    /// no shift (0 hours). Exactly 7 elements when `busiestWeek != nil`;
    /// empty when there's no busiest week (an empty year).
    let busiestWeekDailyTotals: [WrappedDayTotal]

    // MARK: Weekday / weekend split
    let weekdayHours: Double
    let weekendHours: Double
    let saturdayHours: Double
    let sundayHours: Double
    /// Shifts whose `date` falls on a Saturday or Sunday.
    let weekendShiftCount: Int

    // MARK: Averages
    /// totalHours / weeksWithActivity (not / 52) — see engine doc comment.
    let averageWeeklyHours: Double
    /// totalHours / monthsWithActivity (not / 12).
    let averageMonthlyHours: Double

    // MARK: Consistency
    /// Longest run of consecutive calendar days worked, computed strictly
    /// within this year (a streak spanning Dec 31 → Jan 1 is NOT carried
    /// across the year boundary — see engine doc comment for why).
    let longestStreakDays: Int
    let monthsWithActivity: Int

    // MARK: Bookends
    let firstShiftOfYear: WorkEntry?
    let lastShiftOfYear: WorkEntry?

    // MARK: Personality
    let personality: WorkerPersonalityResult

    // MARK: Trust / diagnostics metadata
    /// Worked shifts actually included in this computation (== totalShifts;
    /// kept as a separate field so a future diagnostic pass can compare it
    /// against an independently-sourced count without recomputing).
    let includedEntryCount: Int
    /// True if any of this year's entries came from `yearArchives` rather
    /// than the live `entries` array — expected for any completed prior year.
    let sourcedFromArchive: Bool
}
