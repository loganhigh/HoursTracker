import XCTest
@testable import HoursTracker

/// "Week starts on" (weekStartWeekday) — periods align to the chosen weekday
/// while pay stays on the saved payday, with no explicit cutoff saved.
final class WeekStartCycleTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func settings(weekStart: Int?, payday: Date, type: PayPeriodType = .weekly) -> PaySettings {
        var s = PaySettings()
        s.payPeriodType = type
        s.nextPayday = payday
        s.weekStartWeekday = weekStart
        return s
    }

    // Rylee's case: paid Fridays, wants Sunday-start weeks.
    func testWeeklySundayStartWithFridayPayday() {
        // Friday Aug 28, 2026 is a payday.
        let s = settings(weekStart: 1, payday: date(2026, 8, 28))
        let cycle = PayCycleEngine.cycle(containing: date(2026, 8, 26), settings: s, calendar: cal)
        // Wed Aug 26 falls in Sun Aug 23 – Sat Aug 29.
        XCTAssertEqual(cycle.start, date(2026, 8, 23))
        XCTAssertEqual(cycle.cutoff, date(2026, 8, 29))
        XCTAssertEqual(cal.component(.weekday, from: cycle.start), 1)
        // Paid the Friday after the window closes.
        XCTAssertEqual(cycle.payday, date(2026, 9, 4))
    }

    func testWeeklyMondayStart() {
        let s = settings(weekStart: 2, payday: date(2026, 8, 28))
        let cycle = PayCycleEngine.cycle(containing: date(2026, 8, 26), settings: s, calendar: cal)
        // Mon Aug 24 – Sun Aug 30.
        XCTAssertEqual(cycle.start, date(2026, 8, 24))
        XCTAssertEqual(cycle.cutoff, date(2026, 8, 30))
        XCTAssertEqual(cal.component(.weekday, from: cycle.start), 2)
    }

    func testBiweeklyKeepsWeekdayAlignmentAcrossPeriods() {
        let s = settings(weekStart: 1, payday: date(2026, 8, 28), type: .biWeekly)
        let cycle = PayCycleEngine.cycle(containing: date(2026, 8, 26), settings: s, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: cycle.start), 1)
        XCTAssertEqual(cycle.spanDays, 14)
        let next = PayCycleEngine.nextCycle(after: cycle, settings: s, calendar: cal)
        XCTAssertEqual(next.start, cycle.end)
        XCTAssertEqual(cal.component(.weekday, from: next.start), 1)
        let prev = PayCycleEngine.previousCycle(before: cycle, settings: s, calendar: cal)
        XCTAssertEqual(prev.end, cycle.start)
    }

    func testNilWeekStartKeepsPaydayAnchoredBehavior() {
        let s = settings(weekStart: nil, payday: date(2026, 8, 28))
        let cycle = PayCycleEngine.cycle(containing: date(2026, 8, 26), settings: s, calendar: cal)
        // Legacy: period ends the day before payday (Fri Aug 21 – Thu Aug 27).
        XCTAssertEqual(cycle.start, date(2026, 8, 21))
        XCTAssertEqual(cycle.cutoff, date(2026, 8, 27))
        XCTAssertEqual(cycle.payday, date(2026, 8, 28))
    }

    func testSavedCutoffWinsOverWeekStart() {
        var s = settings(weekStart: 2, payday: date(2026, 8, 28))
        s.payPeriodUsesCutoff = true
        s.nextCutoff = date(2026, 8, 22) // Saturday
        let cycle = PayCycleEngine.cycle(containing: date(2026, 8, 20), settings: s, calendar: cal)
        // Anchored to the SAVED Saturday cutoff, not the Monday week start.
        XCTAssertEqual(cycle.cutoff, date(2026, 8, 22))
        XCTAssertEqual(cycle.start, date(2026, 8, 16))
    }
}
