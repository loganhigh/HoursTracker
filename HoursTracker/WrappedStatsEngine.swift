import Foundation

// MARK: - WrappedStatsEngine
//
// Pure calculation layer for Hour Tracker Wrapped. Takes already-loaded
// entries in, returns one WrappedYearStats out. No Firebase reads, no
// Firestore writes, no new yearly snapshot system — this is intentionally
// just a year-scoped re-run of the same math HoursStore/AchievementBadges
// already trust (`WorkEntry.paidHours`, Monday-start weeks, calendar-year
// boundaries), so Wrapped can never disagree with the rest of the app about
// what "42.5 hours" or "worked every day this week" means.
//
//     existing data (HoursStore.entries + .yearArchives)
//       -> WrappedStatsEngine.yearScopedEntries(...)   [year-scoping step]
//       -> WrappedStatsEngine.compute(...)              [pure aggregation]
//       -> WrappedYearStats
//
// EXCLUDED FROM V1 (do not add without a trustworthy data source first):
//   - XP earned / levels gained / prestiges this year — totalXP/level/prestige
//     are lifetime-cumulative, can be admin-corrected (`adminXPOffset`), and
//     prestige events aren't timestamped. There is no way to attribute a
//     slice of that lifetime number to a specific calendar year today.
//   - Leaderboard/ranking history — only a live snapshot + "yesterday's"
//     diff exist anywhere in the app; there's no rank-over-time series to
//     draw "your best rank this year" from.
enum WrappedStatsEngine {

    // MARK: - Year scoping

    /// Every worked entry (`!isOffDay`) that falls in `year`, sourced from
    /// whichever of `activeEntries` / `yearArchives` actually holds it.
    ///
    /// This is the single most important correctness rule for Wrapped: by
    /// the time someone opens "2025 Wrapped" in 2026, HoursStore has almost
    /// certainly already run `archivePriorYearsIfNeeded()` and moved every
    /// 2025 entry out of `entries` and into `yearArchives`. Reading only
    /// `activeEntries` (the mistake `AchievementBadges.BadgeStats` makes,
    /// documented there as scoped to the *current* year only) would silently
    /// return near-zero stats for any completed year. This function checks
    /// both sources and merges, so it's correct regardless of whether the
    /// year in question has been archived yet, is still live, or (in a
    /// defensive edge case) has entries split across both.
    static func yearScopedEntries(
        year: Int,
        activeEntries: [WorkEntry],
        yearArchives: [YearArchive],
        calendar: Calendar = .current
    ) -> [WorkEntry] {
        var byId: [UUID: WorkEntry] = [:]

        for archive in yearArchives where archive.year == year {
            for entry in archive.entries {
                byId[entry.id] = entry
            }
        }
        for entry in activeEntries where calendar.component(.year, from: entry.date) == year {
            byId[entry.id] = entry
        }

        return byId.values.filter { !$0.isOffDay }.sorted { $0.date < $1.date }
    }

    // MARK: - Compute

    /// Computes one year's Wrapped stats from already year-scoped, already
    /// worked-only entries (i.e. the output of `yearScopedEntries`). Kept as
    /// a separate entry point from `yearScopedEntries` so callers that
    /// already have the right slice (e.g. a unit test) don't have to
    /// round-trip through HoursStore's live/archive split.
    static func compute(
        year: Int,
        entries: [WorkEntry],
        calendar: Calendar = .current,
        sourcedFromArchive: Bool
    ) -> WrappedYearStats {
        var cal = calendar
        cal.firstWeekday = 2 // Monday — matches HoursStore's week convention.

        let sorted = entries.sorted { $0.date < $1.date }

        guard !sorted.isEmpty else {
            return emptyStats(year: year, sourcedFromArchive: sourcedFromArchive, calendar: cal)
        }

        // MARK: Volume
        let totalHours = sorted.reduce(0) { $0 + $1.paidHours }
        let totalShifts = sorted.count
        let averageShiftLengthHours = totalHours / Double(totalShifts)

        // MARK: Extremes
        let longestShift = sorted.max { $0.paidHours < $1.paidHours }
        let earliestShift = sorted.min { timeOfDayMinutes($0.start, calendar: cal) < timeOfDayMinutes($1.start, calendar: cal) }
        let latestShift = sorted.max { lateNightAdjustedMinutes($0.end, calendar: cal) < lateNightAdjustedMinutes($1.end, calendar: cal) }

        // MARK: Long-day thresholds
        let shiftsOver8 = sorted.filter { $0.paidHours >= 8 }.count
        let shiftsOver10 = sorted.filter { $0.paidHours >= 10 }.count
        let shiftsOver12 = sorted.filter { $0.paidHours >= 12 }.count
        let shiftsOver14 = sorted.filter { $0.paidHours >= 14 }.count

        // MARK: Busiest day / week / month
        var dayTotals: [Date: Double] = [:]
        var weekTotals: [Date: Double] = [:]
        var monthTotals: [Date: Double] = [:]
        for entry in sorted {
            let day = cal.startOfDay(for: entry.date)
            dayTotals[day, default: 0] += entry.paidHours

            if let weekStart = cal.dateInterval(of: .weekOfYear, for: entry.date)?.start {
                weekTotals[weekStart, default: 0] += entry.paidHours
            }

            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: entry.date)) ?? entry.date
            monthTotals[monthStart, default: 0] += entry.paidHours
        }

        // `max(by:)` on a dictionary is order-unstable across equal values,
        // so ties are broken by earliest date to keep results deterministic
        // run to run (a Wrapped that changes its "biggest month" between
        // launches on tied data would look broken).
        let busiestDay = dayTotals
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
            .map { WrappedDayTotal(day: $0.key, hours: $0.value) }
        let busiestWeek = weekTotals
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
            .map { WrappedWeekTotal(weekStart: $0.key, hours: $0.value) }
        let busiestMonth = monthTotals
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
            .map { WrappedMonthTotal(monthStart: $0.key, hours: $0.value) }

        // MARK: Chart series
        let monthlyTotals = Self.buildMonthlyTotals(year: year, monthTotals: monthTotals, calendar: cal)
        let busiestWeekDailyTotals = Self.buildBusiestWeekDailyTotals(
            busiestWeek: busiestWeek,
            dayTotals: dayTotals,
            calendar: cal
        )

        // MARK: Weekday / weekend split
        var weekdayHours = 0.0
        var weekendHours = 0.0
        var saturdayHours = 0.0
        var sundayHours = 0.0
        var weekendShiftCount = 0
        for entry in sorted {
            let weekday = cal.component(.weekday, from: entry.date) // 1 = Sunday, 7 = Saturday
            switch weekday {
            case 7:
                saturdayHours += entry.paidHours
                weekendHours += entry.paidHours
                weekendShiftCount += 1
            case 1:
                sundayHours += entry.paidHours
                weekendHours += entry.paidHours
                weekendShiftCount += 1
            default:
                weekdayHours += entry.paidHours
            }
        }

        // MARK: Averages (against weeks/months that actually had activity,
        // not a fixed /52 or /12 — a partial year of data, or a year with
        // gaps, shouldn't be diluted by weeks/months with zero shifts).
        let weeksWithActivity = weekTotals.keys.count
        let monthsWithActivity = monthTotals.keys.count
        let averageWeeklyHours = weeksWithActivity > 0 ? totalHours / Double(weeksWithActivity) : 0
        let averageMonthlyHours = monthsWithActivity > 0 ? totalHours / Double(monthsWithActivity) : 0

        // MARK: Consistency
        // Same consecutive-day-streak algorithm as
        // AchievementBadges.BadgeStats.computeBestStreak, but deliberately
        // NOT reused across the year boundary: a streak that started Dec 28
        // and continued into January is real, but attributing it to "2025"
        // vs "2026" is ambiguous, and mixing years back in would reintroduce
        // exactly the cross-year contamination this engine exists to avoid.
        // So longestStreakDays is the longest run found strictly within the
        // entries passed in (i.e. strictly within `year`).
        let workedDays = Array(Set(sorted.map { cal.startOfDay(for: $0.date) })).sorted()
        let longestStreakDays = Self.longestConsecutiveDayStreak(sortedDistinctDays: workedDays, calendar: cal)

        // MARK: Bookends
        let firstShiftOfYear = sorted.first
        let lastShiftOfYear = sorted.last

        // MARK: Personality
        // Reads its thresholds from WorkerPersonalityScoring.Tuning rather
        // than hardcoding its own copies — otherwise re-tuning that struct
        // later wouldn't actually change anything, since these raw signals
        // would still be built off stale literals.
        let personalityTuning = WorkerPersonalityScoring.Tuning()
        let earlyStartCount = sorted.filter { cal.component(.hour, from: $0.start) <= personalityTuning.earlyStartHour }.count
        let lateFinishCount = sorted.filter { lateNightAdjustedMinutes($0.end, calendar: cal) >= personalityTuning.lateFinishHour * 60 }.count
        let overtimeProxyCount = sorted.filter { $0.paidHours >= personalityTuning.overtimeProxyShiftHours }.count
        let signals = WorkerPersonalitySignals(
            totalHours: totalHours,
            totalShifts: totalShifts,
            averageShiftLengthHours: averageShiftLengthHours,
            over12hShiftFraction: Double(shiftsOver12) / Double(totalShifts),
            earlyStartFraction: Double(earlyStartCount) / Double(totalShifts),
            lateFinishFraction: Double(lateFinishCount) / Double(totalShifts),
            weekendHoursFraction: totalHours > 0 ? weekendHours / totalHours : 0,
            overtimeProxyFraction: Double(overtimeProxyCount) / Double(totalShifts),
            weeklyConsistency: weeklyConsistency(sortedEntries: sorted, calendar: cal)
        )
        let personality = WorkerPersonalityScoring.classify(signals: signals)

        return WrappedYearStats(
            year: year,
            totalHours: totalHours,
            totalShifts: totalShifts,
            averageShiftLengthHours: averageShiftLengthHours,
            longestShiftHours: longestShift?.paidHours ?? 0,
            longestShiftDate: longestShift.map { cal.startOfDay(for: $0.date) },
            earliestShiftStart: earliestShift?.start,
            latestShiftEnd: latestShift?.end,
            shiftsOver8Hours: shiftsOver8,
            shiftsOver10Hours: shiftsOver10,
            shiftsOver12Hours: shiftsOver12,
            shiftsOver14Hours: shiftsOver14,
            busiestDay: busiestDay,
            busiestWeek: busiestWeek,
            busiestMonth: busiestMonth,
            monthlyTotals: monthlyTotals,
            busiestWeekDailyTotals: busiestWeekDailyTotals,
            weekdayHours: weekdayHours,
            weekendHours: weekendHours,
            saturdayHours: saturdayHours,
            sundayHours: sundayHours,
            weekendShiftCount: weekendShiftCount,
            averageWeeklyHours: averageWeeklyHours,
            averageMonthlyHours: averageMonthlyHours,
            longestStreakDays: longestStreakDays,
            monthsWithActivity: monthsWithActivity,
            firstShiftOfYear: firstShiftOfYear,
            lastShiftOfYear: lastShiftOfYear,
            personality: personality,
            includedEntryCount: totalShifts,
            sourcedFromArchive: sourcedFromArchive
        )
    }

    /// Convenience overload: scopes and computes in one call.
    static func compute(
        year: Int,
        activeEntries: [WorkEntry],
        yearArchives: [YearArchive],
        calendar: Calendar = .current
    ) -> WrappedYearStats {
        let scoped = yearScopedEntries(year: year, activeEntries: activeEntries, yearArchives: yearArchives, calendar: calendar)
        let sourcedFromArchive = yearArchives.contains { $0.year == year && !$0.entries.isEmpty }
        return compute(year: year, entries: scoped, calendar: calendar, sourcedFromArchive: sourcedFromArchive)
    }

    // MARK: - Helpers

    /// Minutes since midnight, unadjusted. Used for "earliest start" — a
    /// literal earliest clock-in time never needs the after-midnight
    /// rollover below (an "early" shift starting at 3 AM already sorts
    /// before a 6 AM start with plain minutes-since-midnight).
    private static func timeOfDayMinutes(_ date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Minutes since midnight, with hours before 5 AM rolled forward by 24h
    /// so a 2:00 AM clock-out ranks *after* an 11:00 PM clock-out instead of
    /// before it. Without this, "latest shift end" would nonsensically pick
    /// an early-evening finish over a shift that ran past midnight. The 5 AM
    /// cutoff matches the existing graveyard/night-shift hour buckets in
    /// `AchievementBadges.BadgeStats` (hour < 3 / < 4), just widened slightly
    /// since this is about ranking "how late," not classifying shift type.
    private static func lateNightAdjustedMinutes(_ date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        var minutes = hour * 60 + (comps.minute ?? 0)
        if hour < 5 { minutes += 24 * 60 }
        return minutes
    }

    /// All 12 months of `year` in calendar order, filling months with no
    /// shifts as 0 rather than omitting them — a Jan–Dec chart needs a slot
    /// per month, and making the UI pad a sparse dictionary would push
    /// calendar logic into the view layer.
    private static func buildMonthlyTotals(
        year: Int,
        monthTotals: [Date: Double],
        calendar: Calendar
    ) -> [WrappedMonthTotal] {
        (1...12).compactMap { month in
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let monthStart = calendar.date(from: components) else { return nil }
            return WrappedMonthTotal(monthStart: monthStart, hours: monthTotals[monthStart] ?? 0)
        }
    }

    /// The seven days of the busiest week, Monday → Sunday, with unworked
    /// days as 0. `busiestWeek.weekStart` already comes from a Monday-start
    /// `dateInterval(of: .weekOfYear)` (the calendar passed in has
    /// `firstWeekday = 2`), so walking +0...+6 days from it yields Mon→Sun
    /// directly. Empty when there is no busiest week.
    private static func buildBusiestWeekDailyTotals(
        busiestWeek: WrappedWeekTotal?,
        dayTotals: [Date: Double],
        calendar: Calendar
    ) -> [WrappedDayTotal] {
        guard let busiestWeek else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: busiestWeek.weekStart) else { return nil }
            let dayStart = calendar.startOfDay(for: day)
            return WrappedDayTotal(day: dayStart, hours: dayTotals[dayStart] ?? 0)
        }
    }

    /// Same algorithm as `AchievementBadges.BadgeStats.computeBestStreak`,
    /// duplicated rather than shared because that one is `private static`
    /// and scoped to `BadgeStats`'s init — kept identical on purpose so the
    /// two never quietly drift apart.
    private static func longestConsecutiveDayStreak(sortedDistinctDays: [Date], calendar: Calendar) -> Int {
        guard !sortedDistinctDays.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for i in 1..<sortedDistinctDays.count {
            let daysDiff = calendar.dateComponents([.day], from: sortedDistinctDays[i - 1], to: sortedDistinctDays[i]).day ?? 0
            if daysDiff == 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    /// Fraction of weeks between the first and last shift of the year (Mon
    /// start, inclusive) that had at least one shift. 1.0 = worked every
    /// week spanned; lower = gaps. Intentionally scoped to the span between
    /// first and last shift (not the full 52-week year) so a year that
    /// genuinely only had activity in, say, its final 3 months isn't scored
    /// as "inconsistent" for the 9 months before tracking began.
    private static func weeklyConsistency(sortedEntries: [WorkEntry], calendar: Calendar) -> Double {
        guard let first = sortedEntries.first?.date, let last = sortedEntries.last?.date,
              let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
              let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: last)?.start
        else { return 0 }

        let weeksSpanned = (calendar.dateComponents([.weekOfYear], from: firstWeekStart, to: lastWeekStart).weekOfYear ?? 0) + 1
        guard weeksSpanned > 0 else { return 1 }

        let weeksWithActivity = Set(sortedEntries.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start }).count
        return min(1, Double(weeksWithActivity) / Double(weeksSpanned))
    }

    private static func emptyStats(
        year: Int,
        sourcedFromArchive: Bool,
        calendar: Calendar = .current
    ) -> WrappedYearStats {
        let emptySignals = WorkerPersonalitySignals(
            totalHours: 0, totalShifts: 0, averageShiftLengthHours: 0,
            over12hShiftFraction: 0, earlyStartFraction: 0, lateFinishFraction: 0,
            weekendHoursFraction: 0, overtimeProxyFraction: 0, weeklyConsistency: 0
        )
        return WrappedYearStats(
            year: year,
            totalHours: 0,
            totalShifts: 0,
            averageShiftLengthHours: 0,
            longestShiftHours: 0,
            longestShiftDate: nil,
            earliestShiftStart: nil,
            latestShiftEnd: nil,
            shiftsOver8Hours: 0,
            shiftsOver10Hours: 0,
            shiftsOver12Hours: 0,
            shiftsOver14Hours: 0,
            busiestDay: nil,
            busiestWeek: nil,
            busiestMonth: nil,
            // Still a full Jan–Dec series (all zeroes) so a chart renders an
            // empty year as a flat 12-month axis rather than nothing at all.
            monthlyTotals: buildMonthlyTotals(year: year, monthTotals: [:], calendar: calendar),
            // No busiest week exists, so there are no seven days to describe.
            busiestWeekDailyTotals: [],
            weekdayHours: 0,
            weekendHours: 0,
            saturdayHours: 0,
            sundayHours: 0,
            weekendShiftCount: 0,
            averageWeeklyHours: 0,
            averageMonthlyHours: 0,
            longestStreakDays: 0,
            monthsWithActivity: 0,
            firstShiftOfYear: nil,
            lastShiftOfYear: nil,
            personality: WorkerPersonalityScoring.classify(signals: emptySignals),
            includedEntryCount: 0,
            sourcedFromArchive: sourcedFromArchive
        )
    }
}

// MARK: - Diagnostics (temporary — cross-checks Wrapped's numbers against
// HoursStore's own trusted query methods for the same period; not intended
// as permanent product surface).

struct WrappedDiagnosticReport {
    let year: Int
    let engineEntryCount: Int
    let engineTotalHours: Double
    /// month-start -> (engine hours, HoursStore.monthTotalHours), only for
    /// months that fall within the CURRENT calendar year (HoursStore's
    /// `monthTotalHours` only has visibility into `entries`, not
    /// `yearArchives`, so archived years can't be cross-checked this way —
    /// see `mismatchSummary` for how that's handled).
    let monthComparisons: [(monthStart: Date, engineHours: Double, storeHours: Double?)]
    let allMonthsMatch: Bool

    var mismatchSummary: String {
        let mismatches = monthComparisons.filter { comparison in
            guard let storeHours = comparison.storeHours else { return false }
            return abs(comparison.engineHours - storeHours) > 0.01
        }
        if mismatches.isEmpty {
            return "OK — \(engineEntryCount) entries, \(String(format: "%.2f", engineTotalHours))h total, all \(monthComparisons.count) comparable months match HoursStore."
        }
        let lines = mismatches.map { "\($0.monthStart): engine=\(String(format: "%.2f", $0.engineHours))h store=\(String(format: "%.2f", $0.storeHours ?? -1))h" }
        return "MISMATCH — \(mismatches.count) month(s) disagree with HoursStore:\n" + lines.joined(separator: "\n")
    }
}

extension WrappedStatsEngine {
    /// Compares this engine's month-by-month totals against
    /// `HoursStore.monthTotalHours(monthDate:)` for every month of `year`
    /// that's still live in `store.entries` (i.e. the current calendar
    /// year — HoursStore has no equivalent query over `yearArchives`, so
    /// archived years can only be self-consistency-checked, not
    /// cross-checked against a second implementation). Takes a `HoursStore`
    /// only to read its already-loaded, already-in-memory data — no
    /// Firebase calls happen here.
    static func diagnosticReport(year: Int, store: HoursStore, calendar: Calendar = .current) -> WrappedDiagnosticReport {
        let stats = compute(
            year: year,
            activeEntries: store.entries,
            yearArchives: store.yearArchives,
            calendar: calendar
        )

        let currentYear = calendar.component(.year, from: Date())
        var comparisons: [(monthStart: Date, engineHours: Double, storeHours: Double?)] = []

        if year == currentYear {
            let scoped = yearScopedEntries(year: year, activeEntries: store.entries, yearArchives: store.yearArchives, calendar: calendar)
            var engineMonthTotals: [Date: Double] = [:]
            for entry in scoped {
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
                engineMonthTotals[monthStart, default: 0] += entry.paidHours
            }
            for (monthStart, engineHours) in engineMonthTotals.sorted(by: { $0.key < $1.key }) {
                let storeHours = store.monthTotalHours(monthDate: monthStart)
                comparisons.append((monthStart: monthStart, engineHours: engineHours, storeHours: storeHours))
            }
        }

        let allMatch = comparisons.allSatisfy { abs($0.engineHours - ($0.storeHours ?? $0.engineHours)) <= 0.01 }

        return WrappedDiagnosticReport(
            year: year,
            engineEntryCount: stats.includedEntryCount,
            engineTotalHours: stats.totalHours,
            monthComparisons: comparisons,
            allMonthsMatch: allMatch
        )
    }
}
