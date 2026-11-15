import XCTest
import UserNotifications
@testable import HoursTracker

/// Catch-up sheet: which skipped usual workdays get offered, and with what times.
final class CatchUpPlannerTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    /// 2026-03-02 is a Monday.
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d))! }

    private func shift(_ d: Int, start: Int = 7, hours: Double = 10, breakMin: Int = 30, off: Bool = false) -> WorkEntry {
        let date = day(d)
        let s = cal.date(bySettingHour: start, minute: 0, second: 0, of: date)!
        var e = WorkEntry(date: date, start: s, end: s.addingTimeInterval(hours * 3600), breakMinutes: breakMin, notes: "")
        e.isOffDay = off
        return e
    }

    /// Mon–Fri for four weeks: Mar 2–27.
    private var monToFri: [WorkEntry] {
        (0..<4).flatMap { w in (0..<5).map { shift(2 + w * 7 + $0) } }
    }

    private func at(_ d: Int, _ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: day(d))! }

    func testOffersSkippedWeekdaysAfterLastLog() {
        // Last log Fri Mar 27; now Thu Apr 2 at 8pm -> Mon 30, Tue 31, Wed 1, Thu 2.
        let missed = CatchUpPlanner.missedShifts(entries: monToFri, now: at(33, 20), calendar: cal)
        XCTAssertEqual(missed.map { cal.component(.day, from: $0.date) }, [30, 31, 1, 2])
        let first = missed[0]
        XCTAssertEqual(cal.component(.hour, from: first.start), 7)
        XCTAssertEqual(first.end.timeIntervalSince(first.start), 10 * 3600)
        XCTAssertEqual(first.breakMinutes, 30)
    }

    func testTodayWaitsUntilShiftIsOver() {
        // Thu Apr 2 at noon: today's 7–5 isn't over yet.
        let missed = CatchUpPlanner.missedShifts(entries: monToFri, now: at(33, 12), calendar: cal)
        XCTAssertEqual(missed.count, 3)
        let running = CatchUpPlanner.missedShifts(entries: monToFri, liveShiftRunning: true, now: at(33, 20), calendar: cal)
        XCTAssertEqual(running.count, 3)
    }

    func testNothingWithoutEnoughHistory() {
        let few = Array(monToFri.suffix(4))
        XCTAssertTrue(CatchUpPlanner.missedShifts(entries: few, now: at(33, 20), calendar: cal).isEmpty)
    }

    func testDismissedDaysAreNotAskedAgain() {
        let keys: Set<String> = [CatchUpPlanner.dayKey(day(30), calendar: cal)]
        let missed = CatchUpPlanner.missedShifts(entries: monToFri, dismissedDayKeys: keys, now: at(33, 20), calendar: cal)
        XCTAssertFalse(missed.contains { cal.component(.day, from: $0.date) == 30 })
    }

    func testOffDayEndsTheGap() {
        // An off day logged Mon Mar 30 means they're up to date through Monday.
        let entries = monToFri + [shift(30, off: true)]
        let missed = CatchUpPlanner.missedShifts(entries: entries, now: at(32, 20), calendar: cal)
        XCTAssertEqual(missed.map { cal.component(.day, from: $0.date) }, [31, 1])
    }

    func testCapsAtTwoWeeks() {
        let missed = CatchUpPlanner.missedShifts(entries: monToFri, now: at(27 + 30, 20), calendar: cal)
        XCTAssertFalse(missed.isEmpty)
        XCTAssertLessThanOrEqual(missed.count, 11)
    }

    func testFirstShiftNudgeSkipsOvernight() {
        let late = SmartNotifier.firstShiftNudgeDate(now: at(2, 21), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: late), 3)
        XCTAssertEqual(cal.component(.hour, from: late), 10)
        let afternoon = SmartNotifier.firstShiftNudgeDate(now: at(2, 14), calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: afternoon), 17)
    }

    // MARK: Crew "Text your boss"

    func testTextBossOnlyForTodaysWorkShift() {
        let now = at(18, 17)
        func offer(_ e: [WorkEntry], enabled: Bool = true, on: Bool = true, phone: String = "555-0100") -> Bool {
            CrewTextBoss.shouldOffer(for: e, enabled: enabled, on: on, phone: phone, now: now, calendar: cal)
        }
        XCTAssertTrue(offer([shift(18)]))
        XCTAssertFalse(offer([shift(17)]), "back-filled shift")
        XCTAssertFalse(offer([shift(18, off: true)]), "day off")
        XCTAssertFalse(offer([shift(18)], enabled: false), "not switched on by admin")
        XCTAssertFalse(offer([shift(18)], on: false), "user turned it off")
        XCTAssertFalse(offer([shift(18)], phone: " "), "no boss picked")
    }

    func testNotificationAskOnlyWhenOffAndNotRecent() {
        let now = Date()
        typealias P = NotificationAskPolicy
        XCTAssertTrue(P.shouldAsk(status: .denied, lastAskAt: nil, now: now))
        XCTAssertTrue(P.shouldAsk(status: .notDetermined, lastAskAt: now.addingTimeInterval(-15 * 86_400), now: now))
        XCTAssertFalse(P.shouldAsk(status: .denied, lastAskAt: now.addingTimeInterval(-3 * 86_400), now: now), "asked recently")
        XCTAssertFalse(P.shouldAsk(status: .authorized, lastAskAt: nil, now: now), "already on")
        XCTAssertFalse(P.shouldAsk(status: .provisional, lastAskAt: nil, now: now), "quiet delivery counts as on")
    }
}

/// Home's "Log 3 days this week" card for new accounts.
final class FirstWeekGoalTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Edmonton")!
        return c
    }()

    private func day(_ d: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    func testCountsDistinctLoggedDaysInFirstWeekOnly() throws {
        let created = day(10, hour: 22)
        let shifts = [day(9), day(10, hour: 7), day(10, hour: 15), day(12), day(17)]
        let p = try XCTUnwrap(FirstWeekGoal.progress(accountCreated: created, shiftDates: shifts, now: day(12, hour: 18), calendar: cal))
        XCTAssertEqual(p.days.count, 7)
        XCTAssertEqual(p.todayIndex, 2)
        XCTAssertEqual(p.loggedCount, 2, "Nov 10 counted once, Nov 9 (before signup) and Nov 17 (after week) ignored")
        XCTAssertFalse(p.isComplete)
        XCTAssertEqual(p.daysLeft, 5)
    }

    func testCompleteAtThreeDaysAndHiddenAfterWeek() throws {
        let created = day(10)
        let p = try XCTUnwrap(FirstWeekGoal.progress(accountCreated: created, shiftDates: [day(10), day(11), day(13)], now: day(13), calendar: cal))
        XCTAssertTrue(p.isComplete)
        XCTAssertNotNil(FirstWeekGoal.progress(accountCreated: created, shiftDates: [], now: day(16, hour: 23), calendar: cal))
        XCTAssertNil(FirstWeekGoal.progress(accountCreated: created, shiftDates: [], now: day(17), calendar: cal))
        XCTAssertNil(FirstWeekGoal.progress(accountCreated: created, shiftDates: [], now: day(9), calendar: cal))
    }
}
