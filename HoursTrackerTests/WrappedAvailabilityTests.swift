import XCTest
@testable import HoursTracker

/// Covers when Wrapped is offered. The season rules decide whether users see
/// the feature at all, so an off-by-one here means either a Wrapped that
/// never appears or one that shows mid-year with incomplete numbers.
final class WrappedAvailabilityTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var comps = DateComponents(year: year, month: month, day: day, hour: hour)
        comps.timeZone = cal.timeZone
        return cal.date(from: comps)!
    }

    /// Isolated defaults so dismissal tests can't leak into each other or
    /// into the real app's stored state.
    private func freshDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "WrappedAvailabilityTests-\(UUID().uuidString)")!
        return suite
    }

    private func stats(shifts: Int, hoursPerShift: Double, year: Int = 2026) -> WrappedYearStats {
        var c = cal
        c.firstWeekday = 2
        let entries: [WorkEntry] = (0..<shifts).map { index in
            let day = (index % 27) + 1
            let month = (index / 27) + 1
            var s = DateComponents(year: year, month: month, day: day, hour: 8)
            var e = DateComponents(year: year, month: month, day: day, hour: 8 + Int(hoursPerShift))
            var d = DateComponents(year: year, month: month, day: day)
            s.timeZone = c.timeZone; e.timeZone = c.timeZone; d.timeZone = c.timeZone
            return WorkEntry(date: c.date(from: d)!, start: c.date(from: s)!,
                             end: c.date(from: e)!, breakMinutes: 0, notes: "")
        }
        return WrappedStatsEngine.compute(year: year, entries: entries, calendar: c, sourcedFromArchive: true)
    }

    // MARK: - Season window

    func testJanuaryOffersThePreviousYear() {
        XCTAssertEqual(WrappedAvailability.offeredYear(asOf: date(2027, 1, 1), calendar: cal), 2026)
        XCTAssertEqual(WrappedAvailability.offeredYear(asOf: date(2027, 1, 15), calendar: cal), 2026)
        XCTAssertEqual(WrappedAvailability.offeredYear(asOf: date(2027, 1, 31), calendar: cal), 2026)
    }

    func testEveryOtherMonthOffersNothing() {
        for month in 2...12 {
            XCTAssertNil(
                WrappedAvailability.offeredYear(asOf: date(2027, month, 15), calendar: cal),
                "Month \(month) must not offer Wrapped"
            )
        }
    }

    func testSeasonBoundariesAreExact() {
        // Dec 31 = closed, Jan 1 = open, Feb 1 = closed again.
        XCTAssertFalse(WrappedAvailability.isInSeason(date(2026, 12, 31, hour: 23), calendar: cal))
        XCTAssertTrue(WrappedAvailability.isInSeason(date(2027, 1, 1, hour: 0), calendar: cal))
        XCTAssertFalse(WrappedAvailability.isInSeason(date(2027, 2, 1, hour: 0), calendar: cal))
    }

    // MARK: - Data threshold

    func testThresholdMetByShiftCountAlone() {
        // 20 short shifts: under the hours bar, over the shift bar.
        let s = stats(shifts: 20, hoursPerShift: 2)
        XCTAssertLessThan(s.totalHours, WrappedAvailability.Rules.minimumHours)
        XCTAssertTrue(WrappedAvailability.meetsDataThreshold(s))
    }

    func testThresholdMetByHoursAlone() {
        // 10 very long shifts: under the shift bar, over the hours bar.
        let s = stats(shifts: 10, hoursPerShift: 12)
        XCTAssertLessThan(s.totalShifts, WrappedAvailability.Rules.minimumShifts)
        XCTAssertTrue(WrappedAvailability.meetsDataThreshold(s))
    }

    func testSparseYearFailsThreshold() {
        XCTAssertFalse(WrappedAvailability.meetsDataThreshold(stats(shifts: 3, hoursPerShift: 4)))
    }

    func testEmptyYearFailsThreshold() {
        let empty = WrappedStatsEngine.compute(year: 2026, entries: [], calendar: cal, sourcedFromArchive: false)
        XCTAssertFalse(WrappedAvailability.meetsDataThreshold(empty))
    }

    // MARK: - Home card decision

    func testHomeCardShowsInJanuaryForAQualifyingYear() {
        let defaults = freshDefaults()
        XCTAssertTrue(WrappedAvailability.shouldShowHomeCard(
            stats: stats(shifts: 40, hoursPerShift: 8),
            asOf: date(2027, 1, 5), calendar: cal, defaults: defaults
        ))
    }

    func testHomeCardHiddenOutsideJanuary() {
        let defaults = freshDefaults()
        XCTAssertFalse(WrappedAvailability.shouldShowHomeCard(
            stats: stats(shifts: 40, hoursPerShift: 8),
            asOf: date(2027, 6, 5), calendar: cal, defaults: defaults
        ))
    }

    func testHomeCardHiddenForSparseYear() {
        let defaults = freshDefaults()
        XCTAssertFalse(WrappedAvailability.shouldShowHomeCard(
            stats: stats(shifts: 2, hoursPerShift: 3),
            asOf: date(2027, 1, 5), calendar: cal, defaults: defaults
        ))
    }

    func testHomeCardHiddenForMismatchedYear() {
        // Stats for 2025 must not satisfy January 2027's 2026 slot.
        let defaults = freshDefaults()
        XCTAssertFalse(WrappedAvailability.shouldShowHomeCard(
            stats: stats(shifts: 40, hoursPerShift: 8, year: 2025),
            asOf: date(2027, 1, 5), calendar: cal, defaults: defaults
        ))
    }

    func testDismissalIsRememberedPerYearOnly() {
        let defaults = freshDefaults()
        let s = stats(shifts: 40, hoursPerShift: 8)

        WrappedAvailability.markHomeCardDismissed(year: 2026, defaults: defaults)
        XCTAssertFalse(WrappedAvailability.shouldShowHomeCard(
            stats: s, asOf: date(2027, 1, 5), calendar: cal, defaults: defaults
        ))

        // Next year's Wrapped is unaffected by this year's dismissal.
        XCTAssertFalse(WrappedAvailability.hasDismissedHomeCard(year: 2027, defaults: defaults))
    }

    // MARK: - App-launch floor (Hour Tracker shipped early 2026)

    func testNothingIsOfferedForYearsBeforeTheAppExisted() {
        // January 2026 would nominally offer 2025 — but the app barely
        // existed then, so nothing should be offered.
        XCTAssertNil(WrappedAvailability.offeredYear(asOf: date(2026, 1, 15), calendar: cal))
        XCTAssertFalse(WrappedAvailability.isInSeason(date(2026, 1, 15), calendar: cal))
        XCTAssertFalse(WrappedAvailability.isEligibleYear(2025))
        XCTAssertFalse(WrappedAvailability.isEligibleYear(2024))
    }

    func testFirstRealWrappedIsTwentyTwentySixInJanuaryTwentyTwentySeven() {
        XCTAssertTrue(WrappedAvailability.isEligibleYear(2026))
        XCTAssertEqual(WrappedAvailability.offeredYear(asOf: date(2027, 1, 1), calendar: cal), 2026)
    }

    /// The exact ship-tonight scenario: released Aug 2026, nothing may appear
    /// anywhere until January.
    func testShippingBeforeJanuaryShowsNothingEvenWithAFullPriorYear() {
        let defaults = freshDefaults()

        // Home card: out of season anyway.
        XCTAssertFalse(WrappedAvailability.shouldShowHomeCard(
            stats: stats(shifts: 200, hoursPerShift: 8, year: 2025),
            asOf: date(2026, 8, 24), calendar: cal, defaults: defaults
        ))

        // You-tab entry: 2025 is below the floor, so it must stay hidden even
        // though the data would otherwise qualify.
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2026, 8, 24), calendar: cal
        ) { year in
            stats(shifts: 200, hoursPerShift: 8, year: year)
        }
        XCTAssertNil(found, "Nothing may surface before the first eligible year")
    }

    func testYouEntryAppearsOnceTwentyTwentySixIsComplete() {
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2027, 1, 1), calendar: cal
        ) { year in
            stats(shifts: 40, hoursPerShift: 8, year: year)
        }
        XCTAssertEqual(found?.year, 2026)
    }

    func testYouEntryPersistsAfterJanuaryEnds() {
        // The whole point of the You entry: still reachable in June.
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2027, 6, 15), calendar: cal
        ) { year in
            stats(shifts: 40, hoursPerShift: 8, year: year)
        }
        XCTAssertEqual(found?.year, 2026)
    }

    // MARK: - Permanent You-tab entry

    func testYouEntryPicksMostRecentCompletedQualifyingYear() {
        // Asked in 2029: 2028, 2027 and 2026 all qualify — newest must win.
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2029, 5, 4), calendar: cal
        ) { year in
            stats(shifts: 40, hoursPerShift: 8, year: year)
        }
        XCTAssertEqual(found?.year, 2028, "Should offer the most recent completed year")
    }

    func testYouEntryNeverOffersTheInProgressYear() {
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2029, 5, 4), calendar: cal
        ) { year in
            stats(shifts: 40, hoursPerShift: 8, year: year)
        }
        XCTAssertNotEqual(found?.year, 2029)
        XCTAssertLessThan(found?.year ?? .max, 2029)
    }

    func testYouEntrySkipsGapYearsAndFindsAnOlderQualifyingOne() {
        // Only 2026 is solid; the years since are sparse.
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2029, 5, 4), calendar: cal
        ) { year in
            year == 2026
                ? stats(shifts: 40, hoursPerShift: 8, year: year)
                : stats(shifts: 1, hoursPerShift: 2, year: year)
        }
        XCTAssertEqual(found?.year, 2026)
    }

    func testYouEntryReturnsNilWhenNoYearQualifies() {
        let found = WrappedAvailability.mostRecentEligibleYear(
            asOf: date(2029, 5, 4), calendar: cal
        ) { year in
            stats(shifts: 1, hoursPerShift: 1, year: year)
        }
        XCTAssertNil(found)
    }

    func testYouEntryLookbackIsBounded() {
        // A year far outside the lookback window must not be reached, so a
        // long-time user doesn't pay for an unbounded scan.
        var yearsChecked: [Int] = []
        _ = WrappedAvailability.mostRecentEligibleYear(asOf: date(2026, 8, 24), calendar: cal) { year in
            yearsChecked.append(year)
            return stats(shifts: 1, hoursPerShift: 1, year: year)
        }
        // In Aug 2026 the floor (2026) is above the last completed year
        // (2025), so nothing is even worth checking.
        XCTAssertTrue(yearsChecked.isEmpty, "Must not scan years below the floor")

        // Far enough in the future, the scan is bounded and walks backwards.
        var laterChecked: [Int] = []
        _ = WrappedAvailability.mostRecentEligibleYear(asOf: date(2035, 8, 24), calendar: cal) { year in
            laterChecked.append(year)
            return stats(shifts: 1, hoursPerShift: 1, year: year)
        }
        XCTAssertLessThanOrEqual(laterChecked.count, 5)
        XCTAssertEqual(laterChecked.first, 2034, "Should start at the most recent completed year")
        XCTAssertEqual(laterChecked, laterChecked.sorted(by: >), "Should walk backwards")
    }

    // MARK: - Notification timing

    func testNotificationFiresAt10amOnNewYearsDay() {
        let fire = WrappedAvailability.notificationDate(forYear: 2026, calendar: cal)
        XCTAssertNotNil(fire)
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: fire!)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, WrappedAvailability.Rules.notificationHour)
    }

    func testNotificationLandsInsideTheSeasonItAdvertises() {
        // The push must not arrive when the card wouldn't be there.
        let fire = WrappedAvailability.notificationDate(forYear: 2026, calendar: cal)!
        XCTAssertEqual(WrappedAvailability.offeredYear(asOf: fire, calendar: cal), 2026)
    }
}
