import Foundation

// MARK: - Overtime Type

/// How overtime is calculated for weekday shifts.
/// Saturday and Sunday always use their own separate rate multipliers regardless of this setting.
enum OvertimeType: String, Codable, CaseIterable, Equatable {
    /// OT triggered when a single shift exceeds the daily threshold (e.g. > 8h/day). Most trades.
    case daily = "daily"
    /// OT triggered when the weekly total exceeds the weekly cap (e.g. > 40h/week). Office workers.
    case weekly = "weekly"
    /// Both rules apply simultaneously. Daily OT counted first; weekly OT only adds hours
    /// not already counted as daily OT, preventing double-counting.
    case dailyAndWeekly = "dailyAndWeekly"

    /// Options shown in Settings — legacy `dailyAndWeekly` is migrated to `.daily` on load.
    static var settingsCases: [OvertimeType] { [.daily, .weekly] }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .dailyAndWeekly: return "Daily + Weekly"
        }
    }

    var description: String {
        switch self {
        case .daily: return "Overtime kicks in when a single shift exceeds your daily threshold."
        case .weekly: return "Overtime kicks in when your weekly total exceeds the weekly cap."
        case .dailyAndWeekly: return "Both rules apply. Daily OT is counted first; weekly OT only catches hours not already flagged as daily OT."
        }
    }
}

// MARK: - Overtime Rules (pure logic, testable)

struct OvertimeRules {

    struct Breakout {
        let regularHours: Double
        let overtimeHoursAt1_5: Double
        let overtimeHoursAt2_0: Double
        let pay: Double
        var totalHours: Double { regularHours + overtimeHoursAt1_5 + overtimeHoursAt2_0 }
    }

    // MARK: Per-shift breakdown (daily only, or Saturday/Sunday rules)

    /// Pure function for per-shift overtime. Used for daily-only mode and Sat/Sun day types.
    static func breakdown(
        weekday: Int,
        rawHours: Double,
        wage: Double,
        saturdayThreshold: Double,
        saturdayMultiplier: Double,
        sundayMultiplier: Double,
        weekdayOTAfterHours: Double,
        weekdayOTMultiplier: Double,
        weekdayDoubleTimeAfterHours: Double? = nil,
        doubleTimeMultiplier: Double = 2.0
    ) -> Breakout {
        let r = max(0, rawHours)
        let reg: Double
        let ot15: Double
        let ot20: Double

        switch weekday {
        case 7: // Saturday: first threshold at 1.0x, rest at 1.5x
            reg = min(r, saturdayThreshold)
            ot15 = max(0, r - saturdayThreshold)
            ot20 = 0
        case 1: // Sunday: all at 2.0x
            reg = 0
            ot15 = 0
            ot20 = r
        default: // Weekday: regular → overtime → double time
            reg = min(r, weekdayOTAfterHours)
            let dtAfter = max(weekdayOTAfterHours, weekdayDoubleTimeAfterHours ?? .infinity)
            ot20 = max(0, r - dtAfter)
            ot15 = max(0, r - reg - ot20)
        }

        let pay: Double
        if weekday == 7 {
            pay = (reg * wage) + (ot15 * wage * saturdayMultiplier)
        } else if weekday == 1 {
            pay = ot20 * wage * sundayMultiplier
        } else {
            pay = (reg * wage) + (ot15 * wage * weekdayOTMultiplier) + (ot20 * wage * doubleTimeMultiplier)
        }

        return Breakout(regularHours: reg, overtimeHoursAt1_5: ot15, overtimeHoursAt2_0: ot20, pay: pay)
    }

    // MARK: Weekly-only breakdown

    /// Returns (regular, overtime) for one entry under weekly-only mode.
    /// `weekEntries` = all non-off-day entries for the same week, sorted oldest-first.
    static func weeklyBreakdown(
        entry: WorkEntry,
        weekEntries: [WorkEntry],
        weeklyCap: Double
    ) -> (regular: Double, overtime: Double) {
        let b = weeklyBreakdown(entry: entry, weekEntries: weekEntries, weeklyCap: weeklyCap, doubleTimeCap: nil)
        return (b.regular, b.overtime)
    }

    /// Weekly mode with an optional double-time threshold: the week's hours
    /// are spent oldest-first — regular up to `weeklyCap`, overtime up to
    /// `doubleTimeCap`, double time beyond it. So on a 44-hour week with
    /// double time after 52, Monday–Friday's 40h and Saturday's first 4h
    /// are regular, the next 8h are overtime, and anything after is 2×.
    static func weeklyBreakdown(
        entry: WorkEntry,
        weekEntries: [WorkEntry],
        weeklyCap: Double,
        doubleTimeCap: Double?
    ) -> (regular: Double, overtime: Double, doubleTime: Double) {
        let otCap = max(weeklyCap, doubleTimeCap ?? .infinity)
        var spent: Double = 0
        var result: (Double, Double, Double) = (0, 0, 0)
        for e in weekEntries {
            let h = max(0, e.paidHours)
            let reg = max(0, min(h, weeklyCap - spent))
            let ot = max(0, min(h - reg, otCap - spent - reg))
            let dt = max(0, h - reg - ot)
            spent += h
            if e.id == entry.id {
                result = (reg, ot, dt)
            }
        }
        return result
    }

    // MARK: Daily + Weekly combined breakdown (no double-counting)

    /// Returns (regularHours, dailyOT, weeklyOT) for one entry in daily+weekly mode.
    ///
    /// Algorithm (prevents double-counting):
    /// 1. Each day's daily-regular = min(rawHours, dailyThreshold). Daily OT = the rest.
    /// 2. Weekly pool = sum of daily-regular hours across the week.
    /// 3. If weekly pool > weeklyCap, the excess becomes weekly OT, distributed from the
    ///    last day forward (first-in regular, last-in OT).
    /// 4. An hour already counted as daily OT is never re-counted as weekly OT.
    static func dailyAndWeeklyBreakdown(
        entry: WorkEntry,
        weekEntries: [WorkEntry],
        dailyThreshold: Double,
        weeklyCap: Double
    ) -> (regular: Double, dailyOT: Double, weeklyOT: Double) {
        // Step 1: compute each day's daily regular / daily OT
        struct DaySlice {
            let id: UUID
            let dailyRegular: Double
            let dailyOT: Double
        }
        let slices = weekEntries.map { e -> DaySlice in
            let r = max(0, e.paidHours)
            let dailyReg = min(r, dailyThreshold)
            let dailyOT = r - dailyReg
            return DaySlice(id: e.id, dailyRegular: dailyReg, dailyOT: dailyOT)
        }

        // Step 2: run weekly cap over daily-regular amounts (oldest first = first regular)
        var weeklyRemaining = weeklyCap
        struct WeeklyAlloc {
            let id: UUID
            let weeklyRegular: Double
            let weeklyOT: Double
        }
        let allocs = slices.map { s -> WeeklyAlloc in
            let wReg = min(s.dailyRegular, max(0, weeklyRemaining))
            let wOT = s.dailyRegular - wReg
            weeklyRemaining -= wReg
            return WeeklyAlloc(id: s.id, weeklyRegular: wReg, weeklyOT: wOT)
        }

        // Step 3: find this entry's result
        guard let idx = allocs.firstIndex(where: { $0.id == entry.id }) else {
            return (0, 0, 0)
        }
        let alloc = allocs[idx]
        let slice = slices[idx]
        return (alloc.weeklyRegular, slice.dailyOT, alloc.weeklyOT)
    }
}
