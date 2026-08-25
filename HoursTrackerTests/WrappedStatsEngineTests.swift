import XCTest
@testable import HoursTracker

final class WrappedStatsEngineTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    /// Builds a worked shift on a given (year, month, day) with hour-of-day
    /// start/end. `endDayOffset: 1` produces an overnight shift.
    private func entry(
        year: Int, month: Int, day: Int,
        startHour: Int, startMinute: Int = 0,
        endHour: Int, endMinute: Int = 0,
        endDayOffset: Int = 0,
        breakMinutes: Int = 0
    ) -> WorkEntry {
        var startComps = DateComponents(year: year, month: month, day: day, hour: startHour, minute: startMinute)
        startComps.timeZone = cal.timeZone
        var endComps = DateComponents(year: year, month: month, day: day + endDayOffset, hour: endHour, minute: endMinute)
        endComps.timeZone = cal.timeZone
        let start = cal.date(from: startComps)!
        let end = cal.date(from: endComps)!
        var dateComps = DateComponents(year: year, month: month, day: day)
        dateComps.timeZone = cal.timeZone
        let date = cal.date(from: dateComps)!
        return WorkEntry(date: date, start: start, end: end, breakMinutes: breakMinutes, notes: "")
    }

    // MARK: - Year scoping

    func testYearScopedEntriesReadsFromArchiveNotJustActive() {
        // The defining requirement: a completed year's entries live in
        // yearArchives, NOT in the live `entries` array. This must not
        // silently return zero.
        let archived2025 = entry(year: 2025, month: 6, day: 1, startHour: 9, endHour: 17)
        let live2026 = entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 17)

        let scoped = WrappedStatsEngine.yearScopedEntries(
            year: 2025,
            activeEntries: [live2026],
            yearArchives: [YearArchive(year: 2025, entries: [archived2025])]
        )

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.id, archived2025.id)
    }

    func testYearScopedEntriesFallsBackToActiveForCurrentYear() {
        let live = entry(year: 2026, month: 3, day: 1, startHour: 9, endHour: 17)
        let scoped = WrappedStatsEngine.yearScopedEntries(year: 2026, activeEntries: [live], yearArchives: [])
        XCTAssertEqual(scoped.count, 1)
    }

    func testYearScopedEntriesExcludesOffDays() {
        var offDay = entry(year: 2026, month: 3, day: 1, startHour: 9, endHour: 17)
        offDay.isOffDay = true
        let worked = entry(year: 2026, month: 3, day: 2, startHour: 9, endHour: 17)
        let scoped = WrappedStatsEngine.yearScopedEntries(year: 2026, activeEntries: [offDay, worked], yearArchives: [])
        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.id, worked.id)
    }

    func testYearScopedEntriesDedupesIdPresentInBothActiveAndArchive() {
        // Defensive case: same id somehow present in both sources (e.g. a
        // sync race). Should not double-count.
        let e = entry(year: 2025, month: 6, day: 1, startHour: 9, endHour: 17)
        let scoped = WrappedStatsEngine.yearScopedEntries(
            year: 2025,
            activeEntries: [e],
            yearArchives: [YearArchive(year: 2025, entries: [e])]
        )
        XCTAssertEqual(scoped.count, 1)
    }

    // MARK: - Core aggregation

    func testTotalHoursAndShiftCount() {
        let entries = [
            entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 17),   // 8h
            entry(year: 2026, month: 1, day: 6, startHour: 9, endHour: 13),   // 4h
        ]
        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.totalHours, 12, accuracy: 0.001)
        XCTAssertEqual(stats.totalShifts, 2)
        XCTAssertEqual(stats.averageShiftLengthHours, 6, accuracy: 0.001)
    }

    func testOvernightShiftPaidHoursHandledViaWorkEntry() {
        // 10 PM -> 6 AM next day. WorkEntry.paidHours already wraps this
        // (raw negative -> +24), so the engine should just inherit 8h
        // without any special-casing of its own.
        let overnight = entry(year: 2026, month: 1, day: 5, startHour: 22, endHour: 6, endDayOffset: 1)
        let stats = WrappedStatsEngine.compute(year: 2026, entries: [overnight], calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.totalHours, 8, accuracy: 0.001)
        XCTAssertEqual(stats.longestShiftHours, 8, accuracy: 0.001)
    }

    func testLongestShiftAndDate() {
        let short = entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 13)
        let long = entry(year: 2026, month: 1, day: 10, startHour: 8, endHour: 20) // 12h
        let stats = WrappedStatsEngine.compute(year: 2026, entries: [short, long], calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.longestShiftHours, 12, accuracy: 0.001)
        XCTAssertEqual(stats.longestShiftDate, cal.startOfDay(for: long.date))
    }

    func testEarliestStartUsesTimeOfDayNotCalendarDate() {
        // A LATER calendar-date shift with an EARLIER clock-in time should win.
        let laterDateNormalStart = entry(year: 2026, month: 3, day: 1, startHour: 9, endHour: 17)
        let earlierDateEarlyStart = entry(year: 2026, month: 1, day: 1, startHour: 4, endHour: 12)
        let stats = WrappedStatsEngine.compute(
            year: 2026,
            entries: [laterDateNormalStart, earlierDateEarlyStart],
            calendar: cal,
            sourcedFromArchive: false
        )
        XCTAssertEqual(stats.earliestShiftStart, earlierDateEarlyStart.start)
    }

    func testLatestEndRollsOverPastMidnightCorrectly() {
        // An 11 PM finish should rank as "less late" than a 2 AM finish,
        // even though 2:00 < 23:00 in raw clock time.
        let eveningFinish = entry(year: 2026, month: 1, day: 5, startHour: 15, endHour: 23)
        let overnightFinish = entry(year: 2026, month: 1, day: 6, startHour: 18, endHour: 2, endDayOffset: 1)
        let stats = WrappedStatsEngine.compute(
            year: 2026,
            entries: [eveningFinish, overnightFinish],
            calendar: cal,
            sourcedFromArchive: false
        )
        XCTAssertEqual(stats.latestShiftEnd, overnightFinish.end)
    }

    func testLongDayThresholdsCountShiftsNotDistinctDays() {
        let entries = [
            entry(year: 2026, month: 1, day: 1, startHour: 6, endHour: 20),  // 14h
            entry(year: 2026, month: 1, day: 2, startHour: 6, endHour: 19),  // 13h
            entry(year: 2026, month: 1, day: 3, startHour: 6, endHour: 17),  // 11h
            entry(year: 2026, month: 1, day: 4, startHour: 6, endHour: 15),  // 9h
            entry(year: 2026, month: 1, day: 5, startHour: 6, endHour: 12),  // 6h
        ]
        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.shiftsOver8Hours, 4)
        XCTAssertEqual(stats.shiftsOver10Hours, 3)
        XCTAssertEqual(stats.shiftsOver12Hours, 2)
        XCTAssertEqual(stats.shiftsOver14Hours, 1)
    }

    func testWeekendSplitAndCounts() {
        // 2026-01-03 is a Saturday, 2026-01-04 is a Sunday (UTC gregorian).
        let saturday = entry(year: 2026, month: 1, day: 3, startHour: 9, endHour: 17)  // 8h
        let sunday = entry(year: 2026, month: 1, day: 4, startHour: 9, endHour: 13)    // 4h
        let monday = entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 17)    // 8h
        let stats = WrappedStatsEngine.compute(year: 2026, entries: [saturday, sunday, monday], calendar: cal, sourcedFromArchive: false)

        XCTAssertEqual(stats.saturdayHours, 8, accuracy: 0.001)
        XCTAssertEqual(stats.sundayHours, 4, accuracy: 0.001)
        XCTAssertEqual(stats.weekendHours, 12, accuracy: 0.001)
        XCTAssertEqual(stats.weekdayHours, 8, accuracy: 0.001)
        XCTAssertEqual(stats.weekendShiftCount, 2)
    }

    func testBusiestDayWeekMonth() {
        let entries = [
            entry(year: 2026, month: 1, day: 5, startHour: 6, endHour: 14),   // 8h, week of Jan 5
            entry(year: 2026, month: 1, day: 6, startHour: 6, endHour: 14),   // 8h, week of Jan 5
            entry(year: 2026, month: 2, day: 2, startHour: 6, endHour: 10),   // 4h, Feb — separate month/week
        ]
        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)

        XCTAssertEqual(stats.busiestDay?.hours ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(stats.busiestWeek?.hours ?? -1, 16, accuracy: 0.001) // Jan 5 + Jan 6 in the same Mon-start week
        XCTAssertEqual(stats.busiestMonth?.hours ?? -1, 16, accuracy: 0.001) // January's 16h beats February's 4h
    }

    func testAveragesDivideByActivePeriodsNotFixedFiftyTwoOrTwelve() {
        // Only 2 months touched (Jan, Mar) — averaging by 12 would understate.
        let entries = [
            entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 17),  // 8h
            entry(year: 2026, month: 3, day: 5, startHour: 9, endHour: 17),  // 8h
        ]
        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.monthsWithActivity, 2)
        XCTAssertEqual(stats.averageMonthlyHours, 8, accuracy: 0.001) // 16h / 2 months, not / 12
    }

    func testLongestStreakDoesNotCrossYearBoundary() {
        // Dec 30/31 (prior year, not passed in) + Jan 1/2 (this year).
        // Only entries actually passed in count — the engine has no
        // knowledge of "yesterday" outside what's in its input.
        let entries = [
            entry(year: 2026, month: 1, day: 1, startHour: 9, endHour: 17),
            entry(year: 2026, month: 1, day: 2, startHour: 9, endHour: 17),
            entry(year: 2026, month: 1, day: 3, startHour: 9, endHour: 17),
        ]
        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.longestStreakDays, 3)
    }

    func testFirstAndLastShiftOfYear() {
        let jan = entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 17)
        let dec = entry(year: 2026, month: 12, day: 20, startHour: 9, endHour: 17)
        let mid = entry(year: 2026, month: 6, day: 1, startHour: 9, endHour: 17)
        let stats = WrappedStatsEngine.compute(year: 2026, entries: [dec, jan, mid], calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.firstShiftOfYear?.id, jan.id)
        XCTAssertEqual(stats.lastShiftOfYear?.id, dec.id)
    }

    func testEmptyYearReturnsZeroedStatsNotCrash() {
        let stats = WrappedStatsEngine.compute(year: 2026, entries: [], calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats.totalHours, 0)
        XCTAssertEqual(stats.totalShifts, 0)
        XCTAssertNil(stats.busiestDay)
        XCTAssertNil(stats.firstShiftOfYear)
        XCTAssertEqual(stats.longestStreakDays, 0)
    }

    // MARK: - Worker Personality (architecture-level, not exact-output)

    func testPersonalityClassificationIsDeterministic() {
        let entries = (1...20).map { i in
            entry(year: 2026, month: 1, day: i, startHour: 5, endHour: 18) // 13h, early start
        }
        let stats1 = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        let stats2 = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        XCTAssertEqual(stats1.personality.type, stats2.personality.type)
        XCTAssertEqual(stats1.personality.winningScore, stats2.personality.winningScore, accuracy: 0.0001)
    }

    func testGrinderSignalsProduceGrinderOrMoreSpecificWin() {
        // Heavy 13h shifts starting/ending mid-day, so early-start and
        // late-finish signals stay at zero and don't compete with the
        // long-shift-length signal this test is actually exercising.
        let entries = (1...15).map { i in
            entry(year: 2026, month: 1, day: i, startHour: 7, endHour: 20) // 13h
        }
        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        XCTAssertTrue([.grinder, .machine].contains(stats.personality.type))
    }

    // MARK: - Diagnostic report structure (no HoursStore/Firebase needed for
    // this assertion — just checking the report shape is sane for an empty
    // comparison set).

    func testDiagnosticMismatchSummaryFormatsCleanlyWithNoComparisons() {
        let report = WrappedDiagnosticReport(
            year: 2025,
            engineEntryCount: 10,
            engineTotalHours: 80,
            monthComparisons: [],
            allMonthsMatch: true
        )
        XCTAssertTrue(report.mismatchSummary.contains("OK"))
        XCTAssertTrue(report.mismatchSummary.contains("10 entries"))
    }
}
