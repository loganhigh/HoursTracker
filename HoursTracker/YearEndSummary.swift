import Foundation

/// One calendar year of the user's own entries rolled up
/// for tax time: hours by kind, stat holidays, gross pay, per job and per
/// month. Pure aggregation over `Shift` values so it's unit-testable; the
/// pay figures on each `Shift` come from `HoursStore.payBreakdown(for:)`
/// (see `YearEndSummary.make(year:store:)`), never from a separate engine.
struct YearEndSummary: Equatable {
    /// One entry's already-computed pay breakdown.
    struct Shift: Equatable {
        let date: Date
        let jobID: String
        let isOffDay: Bool
        /// Carries a stat holiday rule (worked or paid-not-worked).
        let isStatHoliday: Bool
        /// Hours worked (0 for off days and stat-pay-only days).
        let workedHours: Double
        let regularHours: Double
        let overtimeHours: Double
        let doubleTimeHours: Double
        /// Stat pay hours at the regular rate, on top of any hours worked.
        let statPayHours: Double
        let pay: Double
    }

    struct Bucket: Equatable {
        var totalHours: Double = 0
        /// Regular / overtime / double time exclude stat holiday shifts,
        /// which are paid by their own rule and counted in `statHolidayHours`,
        /// so regular + overtime + double time + stat holiday = total.
        var regularHours: Double = 0
        var overtimeHours: Double = 0
        var doubleTimeHours: Double = 0
        /// Hours worked on stat holidays.
        var statHolidayHours: Double = 0
        var statPayHours: Double = 0
        /// Everything paid on stat holiday days (worked premium + stat pay).
        var statHolidayPay: Double = 0
        var grossPay: Double = 0
        var daysWorked: Int = 0
        var shiftCount: Int = 0
    }

    struct JobLine: Equatable, Identifiable {
        let id: String
        let name: String
        let totals: Bucket
    }

    struct MonthLine: Equatable, Identifiable {
        /// 1 = January … 12 = December.
        let month: Int
        let totals: Bucket
        var id: Int { month }
    }

    let year: Int
    let totals: Bucket
    /// Jobs with any activity this year, in the app's job order.
    let jobs: [JobLine]
    /// Always twelve lines, January first (empty months are zero).
    let months: [MonthLine]

    var isEmpty: Bool { totals.shiftCount == 0 && totals.statPayHours == 0 && totals.grossPay == 0 }

    /// Rolls up `shifts` that fall in `year`. `jobs` gives display order and
    /// names; a shift whose job isn't listed is grouped under its raw id.
    init(year: Int, shifts: [Shift], jobs: [(id: String, name: String)], calendar: Calendar = .current) {
        self.year = year
        let inYear = shifts.filter { calendar.component(.year, from: $0.date) == year }

        totals = Self.bucket(inYear, calendar: calendar)

        let byJob = Dictionary(grouping: inYear, by: \.jobID)
        var order = jobs.map(\.id).filter { byJob[$0] != nil }
        order += byJob.keys.filter { !order.contains($0) }.sorted()
        let names = Dictionary(jobs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.jobs = order.map { id in
            JobLine(id: id, name: names[id] ?? id, totals: Self.bucket(byJob[id] ?? [], calendar: calendar))
        }

        let byMonth = Dictionary(grouping: inYear) { calendar.component(.month, from: $0.date) }
        months = (1...12).map { MonthLine(month: $0, totals: Self.bucket(byMonth[$0] ?? [], calendar: calendar)) }
    }

    private static func bucket(_ shifts: [Shift], calendar: Calendar) -> Bucket {
        var b = Bucket()
        var days = Set<Date>()
        for s in shifts {
            b.grossPay += s.pay
            b.statPayHours += s.statPayHours
            if s.isStatHoliday {
                b.statHolidayPay += s.pay
                b.statHolidayHours += s.workedHours
            }
            guard !s.isOffDay else { continue }
            b.shiftCount += 1
            b.totalHours += s.workedHours
            if !s.isStatHoliday {
                b.regularHours += s.regularHours
                b.overtimeHours += s.overtimeHours
                b.doubleTimeHours += s.doubleTimeHours
            }
            if s.workedHours > 0 { days.insert(calendar.startOfDay(for: s.date)) }
        }
        b.daysWorked = days.count
        return b
    }

    // MARK: Year choice

    /// Years with at least one entry, newest first.
    static func availableYears(in dates: [Date], calendar: Calendar = .current) -> [Int] {
        Set(dates.map { calendar.component(.year, from: $0) }).sorted(by: >)
    }

    /// The year the picker opens on: last year in January–March (tax season)
    /// when it has data, otherwise the most recent year with data, otherwise
    /// the current year (last year in Jan–Mar).
    static func defaultYear(available: [Int], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let current = calendar.component(.year, from: today)
        let taxSeason = calendar.component(.month, from: today) <= 3
        if taxSeason, available.contains(current - 1) { return current - 1 }
        if let newest = available.filter({ $0 <= current }).max() ?? available.max() { return newest }
        return taxSeason ? current - 1 : current
    }
}

// MARK: - From the store

extension YearEndSummary {
    /// Every entry for `year` — live and archived — paid by the same
    /// `payBreakdown` the cheque screens use (each shift by its own job).
    @MainActor
    static func make(year: Int, store: HoursStore, calendar: Calendar = .current) -> YearEndSummary {
        let shifts = store.allEntriesIncludingArchive()
            .filter { calendar.component(.year, from: $0.date) == year }
            .map { entry -> Shift in
                let b = store.payBreakdown(for: entry)
                return Shift(
                    date: entry.date,
                    jobID: store.jobID(of: entry),
                    isOffDay: entry.isOffDay,
                    isStatHoliday: entry.holidayPayRule != nil,
                    workedHours: entry.holidayPayRule != nil ? b.rawHours : entry.paidHours,
                    regularHours: b.regularHours,
                    overtimeHours: b.overtimeHoursAt1_5,
                    doubleTimeHours: b.overtimeHoursAt2_0,
                    statPayHours: b.statPayHours,
                    pay: b.pay
                )
            }
        return YearEndSummary(year: year, shifts: shifts, jobs: store.jobs.map { ($0.id, $0.name) }, calendar: calendar)
    }

    @MainActor
    static func availableYears(store: HoursStore, calendar: Calendar = .current) -> [Int] {
        availableYears(in: store.allEntriesIncludingArchive().map(\.date), calendar: calendar)
    }
}
