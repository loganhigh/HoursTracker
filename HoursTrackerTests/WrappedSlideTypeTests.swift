import XCTest
@testable import HoursTracker

/// Covers slide availability — the logic that decides which slides exist for
/// a given year's stats. This is what keeps the progress bar segment count,
/// the navigation bounds, and the rendered slide in agreement, so a
/// regression here would either show a blank slide or let navigation run
/// past the end.
final class WrappedSlideTypeTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
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

    // MARK: - Empty / low-data years

    func testEmptyYearShowsOnlyIntroAndSummaryNoBogusStatSlides() {
        let slides = WrappedSlideType.availableSlides(for: stats([]))
        XCTAssertEqual(slides, [.intro, .finalSummary])
        // Specifically: no "longest shift" or "busiest month" slide for a
        // year with no data at all.
        XCTAssertFalse(slides.contains(.longestShift))
        XCTAssertFalse(slides.contains(.biggestMonth))
        XCTAssertFalse(slides.contains(.workStreak))
    }

    func testSingleShortShiftSkipsLongShiftAndStreakSlides() {
        // One 4h shift: real data, but nothing over 8h and no multi-day streak.
        let slides = WrappedSlideType.availableSlides(for: stats([
            entry(year: 2026, month: 5, day: 4, startHour: 9, endHour: 13)
        ]))

        XCTAssertTrue(slides.contains(.totalHours))
        XCTAssertTrue(slides.contains(.totalShifts))
        XCTAssertTrue(slides.contains(.biggestMonth))
        XCTAssertFalse(slides.contains(.longShiftBreakdown), "No shift reached 8h")
        XCTAssertFalse(slides.contains(.workStreak), "A 1-day streak isn't worth a slide")
    }

    func testTwoDayStreakStillSkipsStreakSlideButThreeDaysShowsIt() {
        let twoDays = WrappedSlideType.availableSlides(for: stats([
            entry(year: 2026, month: 5, day: 4, startHour: 9, endHour: 17),
            entry(year: 2026, month: 5, day: 5, startHour: 9, endHour: 17),
        ]))
        XCTAssertFalse(twoDays.contains(.workStreak))

        let threeDays = WrappedSlideType.availableSlides(for: stats([
            entry(year: 2026, month: 5, day: 4, startHour: 9, endHour: 17),
            entry(year: 2026, month: 5, day: 5, startHour: 9, endHour: 17),
            entry(year: 2026, month: 5, day: 6, startHour: 9, endHour: 17),
        ]))
        XCTAssertTrue(threeDays.contains(.workStreak))
    }

    // MARK: - Full-data year

    func testRichYearShowsEverySlideInOrder() {
        var entries: [WorkEntry] = []
        // 20 consecutive long days -> hits every threshold + a long streak.
        for day in 1...20 {
            entries.append(entry(year: 2026, month: 6, day: day, startHour: 5, endHour: 20)) // 15h
        }
        // A weekend shift so the weekend split is non-zero.
        entries.append(entry(year: 2026, month: 7, day: 4, startHour: 9, endHour: 17)) // Sat

        let slides = WrappedSlideType.availableSlides(for: stats(entries))

        XCTAssertEqual(slides, [
            .intro, .totalHours, .totalShifts, .biggestMonth, .longestShift,
            .workSchedule, .longShiftBreakdown, .biggestWeek, .weekendVsWeekday,
            .workStreak, .workerPersonality, .finalSummary,
        ])
    }

    // MARK: - Invariants that protect navigation

    func testIntroIsAlwaysFirstAndSummaryAlwaysLast() {
        let cases: [[WorkEntry]] = [
            [],
            [entry(year: 2026, month: 1, day: 2, startHour: 9, endHour: 13)],
            (1...10).map { entry(year: 2026, month: 3, day: $0, startHour: 6, endHour: 20) },
        ]
        for entries in cases {
            let slides = WrappedSlideType.availableSlides(for: stats(entries))
            XCTAssertEqual(slides.first, .intro)
            XCTAssertEqual(slides.last, .finalSummary)
            XCTAssertGreaterThanOrEqual(slides.count, 2)
        }
    }

    func testNoDuplicateSlidesForAnyDataShape() {
        let entries = (1...12).map { entry(year: 2026, month: 2, day: $0, startHour: 4, endHour: 22) }
        let slides = WrappedSlideType.availableSlides(for: stats(entries))
        XCTAssertEqual(Set(slides).count, slides.count, "A duplicated slide would desync the progress bar")
    }
}
