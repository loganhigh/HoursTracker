import Foundation

// MARK: - Missing-shift detector (Data Completion)
//
// Pure logic, no UI and no store access: given the user's entries it learns
// which weekdays they normally work and flags recent usual workdays that
// nothing accounts for. It only ever SUGGESTS a day — it never invents hours.
//
// "Accounted for" means a worked shift touches the day (overnight spill
// included), the user logged an off day for it themselves, or they dismissed
// the suggestion. The app's own auto-filled "Off" placeholders
// (AutoOffDayFiller) do NOT count: they are written for every unlogged day on
// app open, so counting them would hide exactly the gaps this looks for.

enum MissingShiftDetector {
    struct Config: Equatable {
        /// Weeks of history the usual-weekday pattern is learned from.
        var lookbackWeeks = 8
        /// A weekday is "usual" when worked in at least this share of active weeks.
        var usualThreshold = 0.75
        /// Weeks with at least one worked shift required before anything is suggested.
        var minActiveWeeks = 4
        /// Days before today that are checked for gaps (today itself never is).
        var recentDays = 21
    }

    struct Suggestion: Identifiable, Equatable {
        /// Start of the day that looks unlogged.
        let day: Date
        /// Calendar weekday of `day` (1 = Sunday … 7 = Saturday).
        let weekday: Int
        var id: Date { day }
    }

    struct Report: Equatable {
        /// Newest first.
        let suggestions: [Suggestion]
        /// Usual workdays inside the recent window.
        let expectedDays: Int
        /// Of those, days a shift, a user-logged off day, or a dismissal covers.
        let accountedDays: Int
        /// Weekdays (1 = Sunday … 7 = Saturday) the user normally works.
        let usualWeekdays: Set<Int>

        /// 0…1 share of usual days accounted for.
        var score: Double {
            expectedDays > 0 ? Double(accountedDays) / Double(expectedDays) : 1
        }

        var isComplete: Bool { suggestions.isEmpty && accountedDays >= expectedDays }
    }

    /// Returns nil when there isn't enough history to know the user's pattern.
    static func analyze(
        entries: [WorkEntry],
        dismissedDayKeys: Set<String> = [],
        weekStartWeekday: Int? = nil,
        now: Date = Date(),
        calendar baseCalendar: Calendar = .current,
        config: Config = Config()
    ) -> Report? {
        var cal = baseCalendar
        // Weeks follow the "Week starts on" setting, else the app's Monday convention.
        cal.firstWeekday = weekStartWeekday.flatMap { (1...7).contains($0) ? $0 : nil } ?? 2

        let today = cal.startOfDay(for: now)
        let firstDay = entries
            .filter { !isAutoPlaceholder($0, calendar: cal) }
            .map { cal.startOfDay(for: $0.date) }
            .min()
        guard let firstDay, firstDay < today else { return nil }

        let worked = entries.filter { !$0.isOffDay }
        guard !worked.isEmpty else { return nil }

        // MARK: Learn the usual weekdays from complete weeks before this one.
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstWeekStart = cal.dateInterval(of: .weekOfYear, for: firstDay)?.start
        else { return nil }

        var workedWeekdaysByWeek: [Date: Set<Int>] = [:]
        for entry in worked {
            let day = cal.startOfDay(for: entry.date)
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: day)?.start,
                  weekStart < currentWeekStart else { continue }
            workedWeekdaysByWeek[weekStart, default: []].insert(cal.component(.weekday, from: day))
        }

        var activeWeeks = 0
        var weeksWorkedByWeekday: [Int: Int] = [:]
        for back in 1...max(1, config.lookbackWeeks) {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -back, to: currentWeekStart),
                  weekStart >= firstWeekStart else { break }
            guard let weekdays = workedWeekdaysByWeek[weekStart], !weekdays.isEmpty else { continue }
            activeWeeks += 1
            for weekday in weekdays { weeksWorkedByWeekday[weekday, default: 0] += 1 }
        }
        guard activeWeeks >= max(1, config.minActiveWeeks) else { return nil }

        let needed = config.usualThreshold * Double(activeWeeks)
        let usual = Set(weeksWorkedByWeekday.filter { Double($0.value) >= needed - 1e-9 }.keys)
        guard !usual.isEmpty else { return nil }

        // MARK: Check the recent window.
        let workedDays = AutoOffDayFiller.daysCovered(by: worked, calendar: cal)
        let confirmedOffDays = Set(entries
            .filter { $0.isOffDay && !isAutoPlaceholder($0, calendar: cal) }
            .map { cal.startOfDay(for: $0.date) })

        var expected = 0
        var accounted = 0
        var suggestions: [Suggestion] = []
        for back in 1...max(1, config.recentDays) {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            guard day >= firstDay else { break }
            let weekday = cal.component(.weekday, from: day)
            guard usual.contains(weekday) else { continue }
            expected += 1
            if workedDays.contains(day)
                || confirmedOffDays.contains(day)
                || dismissedDayKeys.contains(dayKey(day, calendar: cal)) {
                accounted += 1
            } else {
                suggestions.append(Suggestion(day: day, weekday: weekday))
            }
        }

        return Report(
            suggestions: suggestions,
            expectedDays: expected,
            accountedDays: accounted,
            usualWeekdays: usual
        )
    }

    /// An "Off" day the app wrote on its own (AutoOffDayFiller), as opposed to
    /// one the user logged. Auto-fills are appended without going through
    /// `HoursStore.add/update`, so they carry no `modifiedAt` stamp, and they
    /// are created on a LATER day than the one they fill. The Home "log off
    /// day" button writes the same "Off" reason but goes through `add`
    /// (stamped), as does confirming a placeholder via `update`.
    static func isAutoPlaceholder(_ entry: WorkEntry, calendar: Calendar = .current) -> Bool {
        guard entry.isOffDay,
              entry.offDayReason == "Off",
              entry.modifiedAt == nil,
              entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        guard let created = entry.createdAt else { return true }
        return calendar.startOfDay(for: created) > calendar.startOfDay(for: entry.date)
    }

    /// Stable `yyyy-MM-dd` key for a calendar day (dismissal storage).
    static func dayKey(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
