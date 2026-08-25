import XCTest
@testable import HoursTracker

/// Covers the pre-built chart series (`monthlyTotals`, `busiestWeekDailyTotals`)
/// that let Wrapped slides draw complete charts without re-querying WorkEntry.
/// The invariants here — fixed element counts, calendar ordering, zero-filled
/// gaps, and sums agreeing with the headline totals — are what a chart's axis
/// and bar heights depend on.
final class WrappedChartSeriesTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday, matching HoursStore's week convention
        return c
    }

    private func entry(
        year: Int, month: Int, day: Int,
        startHour: Int, endHour: Int, endDayOffset: Int = 0
    ) -> WorkEntry {
        var startComps = DateComponents(year: year, month: month, day: day, hour: startHour)
        startComps.timeZone = cal.timeZone
        var endComps = DateComponents(year: year, month: month, day: day + endDayOffset, hour: endHour)
        endComps.timeZone = cal.timeZone
        var dateComps = DateComponents(year: year, month: month, day: day)
        dateComps.timeZone = cal.timeZone
        return WorkEntry(
            date: cal.date(from: dateComps)!,
            start: cal.date(from: startComps)!,
            end: cal.date(from: endComps)!,
            breakMinutes: 0,
            notes: ""
        )
    }

    private func stats(_ entries: [WorkEntry], year: Int = 2026) -> WrappedYearStats {
        WrappedStatsEngine.compute(year: year, entries: entries, calendar: cal, sourcedFromArchive: false)
    }

    // MARK: - monthlyTotals

    func testMonthlyTotalsAlwaysHasExactlyTwelveEntries() {
        // Sparse data (two months), an empty year, and a dense year all
        // produce the same fixed-length series.
        let sparse = stats([
            entry(year: 2026, month: 2, day: 3, startHour: 9, endHour: 17),
            entry(year: 2026, month: 9, day: 8, startHour: 9, endHour: 17),
        ])
        XCTAssertEqual(sparse.monthlyTotals.count, 12)

        XCTAssertEqual(stats([]).monthlyTotals.count, 12)

        let dense = stats((1...12).map { entry(year: 2026, month: $0, day: 5, startHour: 9, endHour: 17) })
        XCTAssertEqual(dense.monthlyTotals.count, 12)
    }

    func testMonthlyTotalsAreJanuaryThroughDecemberInOrder() {
        let result = stats([entry(year: 2026, month: 6, day: 1, startHour: 9, endHour: 17)])

        for (index, monthTotal) in result.monthlyTotals.enumerated() {
            let comps = cal.dateComponents([.year, .month, .day], from: monthTotal.monthStart)
            XCTAssertEqual(comps.year, 2026)
            XCTAssertEqual(comps.month, index + 1, "Element \(index) should be month \(index + 1)")
            XCTAssertEqual(comps.day, 1, "Each entry should be the first of its month")
        }

        // Explicitly ascending — a chart's x-axis depends on this.
        let dates = result.monthlyTotals.map(\.monthStart)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testEmptyMonthsReturnZeroHours() {
        // Only March has data.
        let result = stats([entry(year: 2026, month: 3, day: 10, startHour: 9, endHour: 17)]) // 8h

        XCTAssertEqual(result.monthlyTotals[2].hours, 8, accuracy: 0.001, "March should hold the 8h")
        for (index, monthTotal) in result.monthlyTotals.enumerated() where index != 2 {
            XCTAssertEqual(monthTotal.hours, 0, accuracy: 0.001, "Month \(index + 1) had no shifts")
        }
    }

    func testMonthlyTotalsSumEqualsTotalHours() {
        let result = stats([
            entry(year: 2026, month: 1, day: 5, startHour: 9, endHour: 17),   // 8h
            entry(year: 2026, month: 1, day: 6, startHour: 9, endHour: 13),   // 4h
            entry(year: 2026, month: 7, day: 20, startHour: 6, endHour: 20),  // 14h
            entry(year: 2026, month: 12, day: 31, startHour: 22, endHour: 6, endDayOffset: 1), // 8h overnight
        ])

        let seriesSum = result.monthlyTotals.reduce(0) { $0 + $1.hours }
        XCTAssertEqual(seriesSum, result.totalHours, accuracy: 0.001)
        XCTAssertEqual(seriesSum, 34, accuracy: 0.001)
    }

    func testEmptyYearMonthlyTotalsAreTwelveZeroMonths() {
        let result = stats([])
        XCTAssertEqual(result.monthlyTotals.count, 12)
        XCTAssertTrue(result.monthlyTotals.allSatisfy { $0.hours == 0 })
        XCTAssertEqual(result.monthlyTotals.reduce(0) { $0 + $1.hours }, result.totalHours, accuracy: 0.001)
    }

    // MARK: - busiestWeekDailyTotals

    func testBusiestWeekDailyTotalsHasExactlySevenEntriesWhenAWeekExists() {
        let result = stats([entry(year: 2026, month: 6, day: 3, startHour: 9, endHour: 17)])
        XCTAssertNotNil(result.busiestWeek)
        XCTAssertEqual(result.busiestWeekDailyTotals.count, 7)
    }

    func testBusiestWeekDailyTotalsRunMondayThroughSunday() {
        // 2026-06-03 is a Wednesday; its Monday-start week begins 2026-06-01.
        let result = stats([entry(year: 2026, month: 6, day: 3, startHour: 9, endHour: 17)])
        let days = result.busiestWeekDailyTotals.map(\.day)

        // Weekday numbering: 2 = Monday ... 1 = Sunday.
        let expectedWeekdays = [2, 3, 4, 5, 6, 7, 1]
        for (index, day) in days.enumerated() {
            XCTAssertEqual(
                cal.component(.weekday, from: day),
                expectedWeekdays[index],
                "Element \(index) should be weekday \(expectedWeekdays[index])"
            )
        }

        // Consecutive and ascending.
        XCTAssertEqual(days, days.sorted())
        for index in 1..<days.count {
            let gap = cal.dateComponents([.day], from: days[index - 1], to: days[index]).day
            XCTAssertEqual(gap, 1)
        }

        XCTAssertEqual(days.first, result.busiestWeek?.weekStart)
    }

    func testMissingDaysInBusiestWeekReturnZeroHours() {
        // Mon 2026-06-01 and Thu 2026-06-04 only; the other five are gaps.
        let result = stats([
            entry(year: 2026, month: 6, day: 1, startHour: 9, endHour: 17),  // 8h Mon
            entry(year: 2026, month: 6, day: 4, startHour: 9, endHour: 15),  // 6h Thu
        ])

        let hours = result.busiestWeekDailyTotals.map(\.hours)
        XCTAssertEqual(hours.count, 7)
        XCTAssertEqual(hours[0], 8, accuracy: 0.001)  // Monday
        XCTAssertEqual(hours[1], 0, accuracy: 0.001)  // Tuesday — no shift
        XCTAssertEqual(hours[2], 0, accuracy: 0.001)  // Wednesday — no shift
        XCTAssertEqual(hours[3], 6, accuracy: 0.001)  // Thursday
        XCTAssertEqual(hours[4], 0, accuracy: 0.001)
        XCTAssertEqual(hours[5], 0, accuracy: 0.001)
        XCTAssertEqual(hours[6], 0, accuracy: 0.001)
    }

    func testBusiestWeekDailyTotalsSumEqualsBusiestWeekHours() {
        // A heavy week plus a lighter week elsewhere, so the busiest week is
        // unambiguous and the series must match its headline total.
        var entries: [WorkEntry] = []
        for day in 1...5 {
            entries.append(entry(year: 2026, month: 6, day: day, startHour: 6, endHour: 18)) // 12h x5 = 60h
        }
        entries.append(entry(year: 2026, month: 7, day: 6, startHour: 9, endHour: 13))       // 4h, other week

        let result = stats(entries)
        let dailySum = result.busiestWeekDailyTotals.reduce(0) { $0 + $1.hours }

        XCTAssertEqual(result.busiestWeek?.hours ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(dailySum, result.busiestWeek?.hours ?? -1, accuracy: 0.001)
    }

    func testMultipleShiftsOnOneDayAggregateIntoThatDaysTotal() {
        // Two shifts on the same Monday must sum into a single day bucket,
        // not appear as two entries or overwrite each other.
        let result = stats([
            entry(year: 2026, month: 6, day: 1, startHour: 6, endHour: 10),  // 4h
            entry(year: 2026, month: 6, day: 1, startHour: 14, endHour: 19), // 5h
        ])

        XCTAssertEqual(result.busiestWeekDailyTotals.count, 7)
        XCTAssertEqual(result.busiestWeekDailyTotals[0].hours, 9, accuracy: 0.001)
        XCTAssertEqual(result.busiestWeekDailyTotals.reduce(0) { $0 + $1.hours }, 9, accuracy: 0.001)
    }

    func testEmptyYearBusiestWeekDailyTotalsIsEmptyNotSevenZeroes() {
        // With no busiest week there are no seven days to describe — an
        // empty series is honest, whereas seven zeroed days would imply a
        // real week that happened to be idle.
        let result = stats([])
        XCTAssertNil(result.busiestWeek)
        XCTAssertTrue(result.busiestWeekDailyTotals.isEmpty)
    }

    // MARK: - Determinism

    func testTiedBusiestPeriodsResolveDeterministically() {
        // Two months with identical totals: the winner must be stable across
        // repeated computations (dictionary iteration order is not).
        let entries = [
            entry(year: 2026, month: 4, day: 6, startHour: 9, endHour: 17),  // 8h April
            entry(year: 2026, month: 8, day: 3, startHour: 9, endHour: 17),  // 8h August
        ]

        let first = stats(entries)
        for _ in 0..<25 {
            let repeated = stats(entries)
            XCTAssertEqual(repeated.busiestMonth?.monthStart, first.busiestMonth?.monthStart)
            XCTAssertEqual(repeated.busiestWeek?.weekStart, first.busiestWeek?.weekStart)
            XCTAssertEqual(repeated.busiestDay?.day, first.busiestDay?.day)
        }

        // Ties resolve to the earliest period.
        XCTAssertEqual(cal.component(.month, from: first.busiestMonth!.monthStart), 4)
    }
}
