import XCTest
@testable import HoursTracker

/// Year-end summary: pure roll-up of already-computed pay breakdowns by
/// year, job and month, plus the default-year rule for the picker.
final class YearEndSummaryTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Edmonton")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func shift(_ date: Date, job: String = "primary", hours: Double, reg: Double? = nil, ot: Double = 0,
                       dt: Double = 0, pay: Double, offDay: Bool = false, stat: Bool = false,
                       statHours: Double = 0) -> YearEndSummary.Shift {
        YearEndSummary.Shift(date: date, jobID: job, isOffDay: offDay, isStatHoliday: stat, workedHours: hours,
                             regularHours: reg ?? hours, overtimeHours: ot, doubleTimeHours: dt,
                             statPayHours: statHours, pay: pay)
    }

    func testTotalsSplitHoursByKindAndExcludeOtherYears() {
        let shifts = [
            shift(day(2025, 3, 4), hours: 10, reg: 8, ot: 2, pay: 330),
            shift(day(2025, 3, 4), hours: 2, pay: 60),                // same day, second shift
            shift(day(2025, 7, 9), hours: 14, reg: 8, ot: 4, dt: 2, pay: 540),
            // Stat holiday worked at 1.5×: own bucket, not regular/OT.
            shift(day(2025, 7, 1), hours: 8, reg: 0, ot: 8, pay: 360 + 240, stat: true, statHours: 8),
            // Stat holiday not worked: stat pay only.
            shift(day(2025, 12, 25), hours: 0, reg: 0, pay: 240, offDay: true, stat: true, statHours: 8),
            // Plain day off: no hours, no day worked.
            shift(day(2025, 8, 2), hours: 0, reg: 0, pay: 0, offDay: true),
            // Other years are ignored (archived prior year / current year).
            shift(day(2024, 12, 31), hours: 9, pay: 270),
            shift(day(2026, 1, 1), hours: 9, pay: 270),
        ]
        let s = YearEndSummary(year: 2025, shifts: shifts, jobs: [("primary", "Paving")], calendar: cal)
        let t = s.totals

        XCTAssertEqual(t.totalHours, 34, accuracy: 0.001)
        XCTAssertEqual(t.regularHours, 18, accuracy: 0.001)
        XCTAssertEqual(t.overtimeHours, 6, accuracy: 0.001)
        XCTAssertEqual(t.doubleTimeHours, 2, accuracy: 0.001)
        XCTAssertEqual(t.statHolidayHours, 8, accuracy: 0.001)
        XCTAssertEqual(t.regularHours + t.overtimeHours + t.doubleTimeHours + t.statHolidayHours, t.totalHours, accuracy: 0.001)
        XCTAssertEqual(t.statPayHours, 16, accuracy: 0.001)
        XCTAssertEqual(t.statHolidayPay, 840, accuracy: 0.001)
        XCTAssertEqual(t.grossPay, 330 + 60 + 540 + 600 + 240, accuracy: 0.001)
        XCTAssertEqual(t.daysWorked, 3)
        XCTAssertEqual(t.shiftCount, 4)
    }

    func testMonthsAlwaysTwelveAndSumToTotals() {
        let shifts = [
            shift(day(2025, 1, 15), hours: 8, pay: 240),
            shift(day(2025, 1, 16), hours: 8, pay: 240),
            shift(day(2025, 11, 3), hours: 6, pay: 180),
        ]
        let s = YearEndSummary(year: 2025, shifts: shifts, jobs: [("primary", "Main job")], calendar: cal)

        XCTAssertEqual(s.months.map(\.month), Array(1...12))
        XCTAssertEqual(s.months[0].totals.totalHours, 16, accuracy: 0.001)
        XCTAssertEqual(s.months[0].totals.daysWorked, 2)
        XCTAssertEqual(s.months[10].totals.grossPay, 180, accuracy: 0.001)
        XCTAssertEqual(s.months[5].totals.shiftCount, 0)
        XCTAssertEqual(s.months[5].totals.grossPay, 0)
        XCTAssertEqual(s.months.reduce(0) { $0 + $1.totals.totalHours }, s.totals.totalHours, accuracy: 0.001)
        XCTAssertEqual(s.months.reduce(0) { $0 + $1.totals.grossPay }, s.totals.grossPay, accuracy: 0.001)
    }

    func testPerJobBreakdownFollowsJobOrderAndKeepsUnknownJobs() {
        let shifts = [
            shift(day(2025, 5, 1), job: "bar", hours: 5, pay: 100),
            shift(day(2025, 5, 1), job: "primary", hours: 8, pay: 240),
            shift(day(2025, 5, 2), job: "primary", hours: 10, reg: 8, ot: 2, pay: 330),
            shift(day(2025, 5, 3), job: "zzz-orphan", hours: 1, pay: 20),
        ]
        let s = YearEndSummary(year: 2025, shifts: shifts,
                               jobs: [("primary", "Paving"), ("bar", "Bar"), ("unused", "Unused")], calendar: cal)

        XCTAssertEqual(s.jobs.map(\.name), ["Paving", "Bar", "zzz-orphan"])
        XCTAssertEqual(s.jobs[0].totals.totalHours, 18, accuracy: 0.001)
        XCTAssertEqual(s.jobs[0].totals.overtimeHours, 2, accuracy: 0.001)
        XCTAssertEqual(s.jobs[0].totals.daysWorked, 2)
        XCTAssertEqual(s.jobs[1].totals.grossPay, 100, accuracy: 0.001)
        // Same calendar day worked at two jobs counts once overall.
        XCTAssertEqual(s.totals.daysWorked, 3)
        XCTAssertEqual(s.jobs.reduce(0) { $0 + $1.totals.grossPay }, s.totals.grossPay, accuracy: 0.001)
    }

    func testEmptyYear() {
        let s = YearEndSummary(year: 2023, shifts: [shift(day(2025, 1, 1), hours: 8, pay: 240)],
                               jobs: [("primary", "Main job")], calendar: cal)
        XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(s.jobs.isEmpty)
        XCTAssertEqual(s.months.count, 12)
    }

    func testDefaultYear() {
        let years = [2026, 2025, 2023]
        // Tax season (Jan–Mar): last year when it has data.
        XCTAssertEqual(YearEndSummary.defaultYear(available: years, today: day(2026, 2, 10), calendar: cal), 2025)
        XCTAssertEqual(YearEndSummary.defaultYear(available: years, today: day(2026, 3, 31), calendar: cal), 2025)
        // Rest of the year: most recent year with data.
        XCTAssertEqual(YearEndSummary.defaultYear(available: years, today: day(2026, 4, 1), calendar: cal), 2026)
        XCTAssertEqual(YearEndSummary.defaultYear(available: [2023], today: day(2026, 11, 15), calendar: cal), 2023)
        // Tax season but nothing last year: newest with data.
        XCTAssertEqual(YearEndSummary.defaultYear(available: [2026, 2023], today: day(2026, 1, 5), calendar: cal), 2026)
        // No data at all.
        XCTAssertEqual(YearEndSummary.defaultYear(available: [], today: day(2026, 2, 1), calendar: cal), 2025)
        XCTAssertEqual(YearEndSummary.defaultYear(available: [], today: day(2026, 8, 1), calendar: cal), 2026)
    }

    func testAvailableYearsNewestFirst() {
        let dates = [day(2024, 6, 1), day(2026, 1, 2), day(2024, 7, 1), day(2025, 12, 31)]
        XCTAssertEqual(YearEndSummary.availableYears(in: dates, calendar: cal), [2026, 2025, 2024])
    }

    /// Archived prior-year entries reach the summary through the store and
    /// are paid by the store's own `payBreakdown`.
    @MainActor
    func testStoreSummaryIncludesArchivedYear() {
        let store = HoursStore()
        Self.retained.append(store)
        var settings = PaySettings()
        settings.hourlyRate = 30
        settings.hourlyRateSet = true
        settings.overtimeType = .daily
        settings.weekdayOvertimeAfterHours = 8
        settings.weekendPremiumsEnabled = false
        store.paySettings = settings

        let c = Calendar.current
        // Wednesday 2014-03-12 (a year no real device data uses), 10 hours: 8 regular + 2 overtime.
        let date = c.date(from: DateComponents(year: 2014, month: 3, day: 12))!
        let start = c.date(bySettingHour: 7, minute: 0, second: 0, of: date)!
        let entry = WorkEntry(date: date, start: start, end: start.addingTimeInterval(10 * 3600), breakMinutes: 0, notes: "")
        store.entries = []
        store.yearArchives = [YearArchive(year: 2014, entries: [entry])]

        let s = YearEndSummary.make(year: 2014, store: store)
        XCTAssertEqual(s.totals.totalHours, 10, accuracy: 0.001)
        XCTAssertEqual(s.totals.grossPay, store.payBreakdown(for: entry).pay, accuracy: 0.001)
        XCTAssertEqual(s.totals.regularHours + s.totals.overtimeHours + s.totals.doubleTimeHours, 10, accuracy: 0.001)
        XCTAssertTrue(YearEndSummary.availableYears(store: store).contains(2014))
    }

    /// The PDF renders and spills onto a second page (12-month table).
    func testPDFRendersMultiplePages() throws {
        let shifts = (1...12).map { shift(day(2025, $0, 10), hours: 9, reg: 8, ot: 1, pay: 285) }
            + [shift(day(2025, 6, 11), job: "bar", hours: 4, pay: 80)]
        let summary = YearEndSummary(year: 2025, shifts: shifts, jobs: [("primary", "Paving"), ("bar", "Bar")], calendar: cal)
        let doc = YearEndSummaryDocument(summary: summary, employee: "tester", company: "Acme Paving",
                                         companyLogo: nil, currencyCode: "CAD", showPay: true)
        let url = try doc.writePDF()
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertGreaterThanOrEqual(pdf.numberOfPages, 2)
    }

    private static var retained: [HoursStore] = []
}
