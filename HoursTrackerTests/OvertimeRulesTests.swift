import XCTest
@testable import HoursTracker

/// Unit tests for Saturday overtime rule: first 4h at regular, remaining at 1.5x.
final class OvertimeRulesTests: XCTestCase {

    let wage: Double = 10.0
    let satThreshold: Double = 4.0
    let satMult: Double = 1.5
    let sunMult: Double = 2.0
    let wdAfter: Double = 8.0
    let wdMult: Double = 1.5

    func testSaturday_3h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 3.0,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 3.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.pay, 3.0 * wage, accuracy: 1e-6)
    }

    func testSaturday_4h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 4.0,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 4.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.pay, 4.0 * wage, accuracy: 1e-6)
    }

    func testSaturday_6_5h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 6.5,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 4.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 2.5, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        let expectedPay = (4.0 * wage) + (2.5 * wage * 1.5)
        XCTAssertEqual(b.pay, expectedPay, accuracy: 1e-6)
    }

    func testSaturday_12h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 12.0,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 4.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 8.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        let expectedPay = (4.0 * wage) + (8.0 * wage * 1.5)
        XCTAssertEqual(b.pay, expectedPay, accuracy: 1e-6)
    }
}

// MARK: - Pay cycle schedule

final class PayCycleScheduleTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Edmonton")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func biWeekly(payday: Date, cutoff: Date? = nil) -> PaySettings {
        var s = PaySettings()
        s.payPeriodType = .biWeekly
        s.nextPayday = payday
        if let cutoff {
            s.payPeriodUsesCutoff = true
            s.nextCutoff = cutoff
        }
        return s
    }

    func testIsPaydayMatchesTheSavedPaydayAndEveryPeriodAroundIt() {
        let s = biWeekly(payday: day(2026, 8, 28))
        XCTAssertTrue(PayCycleEngine.isPayday(day(2026, 8, 28), settings: s, calendar: cal))
        XCTAssertTrue(PayCycleEngine.isPayday(day(2026, 8, 14), settings: s, calendar: cal))
        XCTAssertTrue(PayCycleEngine.isPayday(day(2026, 9, 11), settings: s, calendar: cal))
        XCTAssertFalse(PayCycleEngine.isPayday(day(2026, 8, 27), settings: s, calendar: cal))
        XCTAssertFalse(PayCycleEngine.isPayday(day(2026, 9, 4), settings: s, calendar: cal))
    }

    func testIsPaydayStillTrueAfterNextPaydayHasRolledPastToday() {
        // What Home sees on payday morning: advanceNextPaydayIfNeeded already moved nextPayday forward.
        let s = biWeekly(payday: day(2026, 9, 11))
        XCTAssertTrue(PayCycleEngine.isPayday(day(2026, 8, 28), settings: s, calendar: cal))
    }

    func testPayDayMarkerRendersOnPayday() {
        let s = biWeekly(payday: day(2026, 8, 28))
        XCTAssertEqual(PayCycleEngine.periodDayMarkerLabels(for: day(2026, 8, 28), settings: s, calendar: cal), ["PayDay"])
        XCTAssertEqual(PayCycleEngine.periodDayMarkerLabels(for: day(2026, 8, 27), settings: s, calendar: cal), [])
    }

    func testCutoffWithPaydayAndCutoffMarkers() {
        let s = biWeekly(payday: day(2026, 8, 28), cutoff: day(2026, 8, 22))
        XCTAssertEqual(PayCycleEngine.periodDayMarkerLabels(for: day(2026, 8, 22), settings: s, calendar: cal), ["Cutoff"])
        XCTAssertEqual(PayCycleEngine.periodDayMarkerLabels(for: day(2026, 8, 28), settings: s, calendar: cal), ["PayDay"])
    }

    func testCutoffEnteredAfterNextPaydayKeepsARealLag() {
        // Onboarded Aug 24: "next payday Aug 28, next cutoff Sep 5" is a valid description.
        let s = biWeekly(payday: day(2026, 8, 28), cutoff: day(2026, 9, 5))
        XCTAssertEqual(PayCycleEngine.cutoffPaydayLagDays(settings: s, calendar: cal), 6)
        let current = PayCycleEngine.cycle(containing: day(2026, 8, 24), settings: s, calendar: cal)
        XCTAssertEqual(current.cutoff, day(2026, 9, 5))
        XCTAssertEqual(current.payday, day(2026, 9, 11))
        let previous = PayCycleEngine.previousCycle(before: current, settings: s, calendar: cal)
        XCTAssertEqual(previous.cutoff, day(2026, 8, 22))
        XCTAssertEqual(previous.payday, day(2026, 8, 28), "the cheque cut off Aug 22 is the one that pays on the user's stated Aug 28")
    }

    func testLongerThanOnePeriodLagIsPreserved() {
        let s = biWeekly(payday: day(2026, 9, 11), cutoff: day(2026, 8, 22))
        XCTAssertEqual(PayCycleEngine.cutoffPaydayLagDays(settings: s, calendar: cal), 20)
    }
}

// MARK: - Usual work days

final class WorkScheduleInferenceTests: XCTestCase {
    func testAutoFilledOffDaysDoNotMakeAWeekdayUsual() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 22))! // Saturday
        var entries: [WorkEntry] = []
        for back in 1...28 {
            let d = cal.date(byAdding: .day, value: -back, to: now)!
            let wd = cal.component(.weekday, from: d)
            if (2...6).contains(wd) {
                entries.append(WorkEntry(date: d, start: d, end: d.addingTimeInterval(8 * 3600), breakMinutes: 0, notes: ""))
            } else {
                entries.append(WorkEntry(date: d, start: d, end: d, breakMinutes: 0, notes: "", isOffDay: true, offDayReason: "Off"))
            }
        }
        let usual = WorkScheduleInference.usualWorkWeekdays(entries: entries, now: now, calendar: cal)
        XCTAssertEqual(usual, Set(2...6))
    }
}

// MARK: - Share-card trend

final class HoursAnalyticsTrendTests: XCTestCase {
    func testThisWeekTrendComparesAgainstTheSameDaysOfLastWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Edmonton")!
        func day(_ d: Int, hours: Double) -> WorkEntry {
            let start = cal.date(from: DateComponents(year: 2026, month: 8, day: d))!
            return WorkEntry(date: start, start: start, end: start.addingTimeInterval(hours * 3600), breakMinutes: 0, notes: "")
        }
        // Wednesday Aug 19 2026, 3pm.
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 15))!
        let entries = [
            day(10, hours: 8), day(11, hours: 8), day(12, hours: 8),      // last Mon–Wed = 24h
            day(14, hours: 10), day(15, hours: 10), day(16, hours: 10),   // last Fri–Sun = 30h (the OLD comparison window)
            day(17, hours: 12), day(18, hours: 12), day(19, hours: 12),   // this Mon–Wed = 36h
        ]
        let r = HoursAnalyticsCalculator.compute(entries: entries, range: .thisWeek, overtimeHours: { _ in 0 }, calendar: cal, now: now)
        XCTAssertEqual(r.totalHours, 36, accuracy: 0.01)
        // 36 vs last Mon–Wed's 24 = +50%. The old equal-length-window-before
        // comparison would have used last Fri–Sun's 30h and reported +20%.
        XCTAssertEqual(r.trendTotal, 50)
    }
}
