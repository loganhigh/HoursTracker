import XCTest
@testable import HoursTracker

/// Double time thresholds (daily and weekly), and stat holiday pay rules.
final class OvertimeDoubleTimeTests: XCTestCase {

    private func entry(_ day: Int, hours: Double) -> WorkEntry {
        // A week in Sept 2026: Mon 14 … Sun 20.
        var comps = DateComponents(year: 2026, month: 9, day: day, hour: 7)
        comps.calendar = .current
        let start = comps.date!
        let end = start.addingTimeInterval(hours * 3600)
        return WorkEntry(date: Calendar.current.startOfDay(for: start), start: start, end: end, breakMinutes: 0, notes: "")
    }

    func testDailyDoubleTimeAfterTwelve() {
        let b = OvertimeRules.breakdown(
            weekday: 3, rawHours: 14, wage: 10,
            saturdayThreshold: 4, saturdayMultiplier: 1.5, sundayMultiplier: 2,
            weekdayOTAfterHours: 8, weekdayOTMultiplier: 1.5,
            weekdayDoubleTimeAfterHours: 12
        )
        XCTAssertEqual(b.regularHours, 8, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 4, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 2, accuracy: 1e-6)
        XCTAssertEqual(b.pay, 80 + 60 + 40, accuracy: 1e-6)
    }

    func testDailyDoubleTimeBelowOvertimeThresholdIsIgnored() {
        // A double-time threshold under the OT threshold can't come first.
        let b = OvertimeRules.breakdown(
            weekday: 3, rawHours: 10, wage: 10,
            saturdayThreshold: 4, saturdayMultiplier: 1.5, sundayMultiplier: 2,
            weekdayOTAfterHours: 8, weekdayOTMultiplier: 1.5,
            weekdayDoubleTimeAfterHours: 6
        )
        XCTAssertEqual(b.regularHours, 8, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 2, accuracy: 1e-6)
    }

    /// 44-hour week: Mon–Fri 8h each is regular, Saturday's first 4h regular,
    /// the rest overtime, and past 52 double time.
    func testFortyFourHourWeekSaturdaySplits() {
        let week = [14, 15, 16, 17, 18].map { entry($0, hours: 8) } + [entry(19, hours: 14)]
        let saturday = week[5]
        let b = OvertimeRules.weeklyBreakdown(entry: saturday, weekEntries: week, weeklyCap: 44, doubleTimeCap: 52)
        XCTAssertEqual(b.regular, 4, accuracy: 1e-6)
        XCTAssertEqual(b.overtime, 8, accuracy: 1e-6)
        XCTAssertEqual(b.doubleTime, 2, accuracy: 1e-6)

        let friday = week[4]
        let f = OvertimeRules.weeklyBreakdown(entry: friday, weekEntries: week, weeklyCap: 44, doubleTimeCap: 52)
        XCTAssertEqual(f.regular, 8, accuracy: 1e-6)
        XCTAssertEqual(f.overtime, 0, accuracy: 1e-6)
    }

    func testWeeklyWithoutDoubleTimeMatchesLegacyShape() {
        let week = [14, 15, 16, 17, 18].map { entry($0, hours: 9) }
        let legacy = OvertimeRules.weeklyBreakdown(entry: week[4], weekEntries: week, weeklyCap: 40)
        XCTAssertEqual(legacy.regular, 4, accuracy: 1e-6)
        XCTAssertEqual(legacy.overtime, 5, accuracy: 1e-6)
    }

    func testHolidayPayEquivalents() {
        XCTAssertEqual(HolidayPayRule.statPayOnly.paidHourEquivalent(workedHours: 0, statHours: 8), 8)
        XCTAssertEqual(HolidayPayRule.workedRegular.paidHourEquivalent(workedHours: 10, statHours: 8), 10)
        XCTAssertEqual(HolidayPayRule.workedTimeAndHalf.paidHourEquivalent(workedHours: 10, statHours: 8), 15)
        XCTAssertEqual(HolidayPayRule.workedDoubleTime.paidHourEquivalent(workedHours: 10, statHours: 8), 20)
        XCTAssertEqual(HolidayPayRule.workedDoubleTimePlusStat.paidHourEquivalent(workedHours: 10, statHours: 8), 28)
        XCTAssertFalse(HolidayPayRule.statPayOnly.isWorked)
    }

    func testHolidayRuleRoundTripsThroughCodable() throws {
        var e = entry(21, hours: 10)
        e.isHoliday = true
        e.holidayPayRule = .workedDoubleTimePlusStat
        e.statPayHours = 8
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(WorkEntry.self, from: data)
        XCTAssertEqual(back.holidayPayRule, .workedDoubleTimePlusStat)
        XCTAssertEqual(back.statPayHours, 8)

        // Entries from builds before the field decode with no rule.
        let legacy = #"{"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","date":0,"start":0,"end":36000,"breakMinutes":0,"notes":"","isOffDay":true,"offDayReason":"Holiday"}"#
        let old = try JSONDecoder().decode(WorkEntry.self, from: Data(legacy.utf8))
        XCTAssertNil(old.holidayPayRule)
        XCTAssertEqual(old.statPayHours, 0)
    }
}
