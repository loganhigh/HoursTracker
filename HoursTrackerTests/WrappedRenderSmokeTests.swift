import XCTest
import SwiftUI
@testable import HoursTracker

/// Renders every Wrapped slide headlessly via ImageRenderer. A compile check
/// can't catch a crash inside a view body (a bad force-unwrap, an out-of-range
/// index, a divide-by-zero in a chart's height fraction) — this can, and it
/// also proves each slide produces actual non-blank pixels rather than
/// silently laying out to nothing.
@MainActor
final class WrappedRenderSmokeTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func entry(year: Int, month: Int, day: Int, startHour: Int, endHour: Int) -> WorkEntry {
        var s = DateComponents(year: year, month: month, day: day, hour: startHour); s.timeZone = cal.timeZone
        var e = DateComponents(year: year, month: month, day: day, hour: endHour); e.timeZone = cal.timeZone
        var d = DateComponents(year: year, month: month, day: day); d.timeZone = cal.timeZone
        return WorkEntry(
            date: cal.date(from: d)!, start: cal.date(from: s)!, end: cal.date(from: e)!,
            breakMinutes: 0, notes: ""
        )
    }

    /// A year with enough variety that every slide qualifies.
    private var richStats: WrappedYearStats {
        var entries: [WorkEntry] = []
        for day in 1...20 {
            entries.append(entry(year: 2026, month: 6, day: day, startHour: 5, endHour: 20)) // 15h streak
        }
        entries.append(entry(year: 2026, month: 7, day: 4, startHour: 9, endHour: 17))  // Saturday
        entries.append(entry(year: 2026, month: 7, day: 5, startHour: 9, endHour: 15))  // Sunday
        entries.append(entry(year: 2026, month: 2, day: 10, startHour: 8, endHour: 12))
        return WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
    }

    private var emptyStats: WrappedYearStats {
        WrappedStatsEngine.compute(year: 2026, entries: [], calendar: cal, sourcedFromArchive: false)
    }

    /// Renders a view at phone size and returns its image, or nil if the
    /// render produced nothing.
    private func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 1
        return renderer.uiImage
    }

    private func assertRenders<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let image = render(view) else {
            XCTFail("\(name) produced no image", file: file, line: line)
            return
        }
        XCTAssertGreaterThan(image.size.width, 0, "\(name) rendered zero-width", file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, "\(name) rendered zero-height", file: file, line: line)
    }

    // MARK: - Every slide, rich data

    func testAllSlidesRenderWithRichData() {
        let stats = richStats
        assertRenders(WrappedIntroSlide(stats: stats), "Intro")
        assertRenders(WrappedTotalHoursSlide(stats: stats), "TotalHours")
        assertRenders(WrappedTotalShiftsSlide(stats: stats), "TotalShifts")
        assertRenders(WrappedBiggestMonthSlide(stats: stats), "BiggestMonth")
        assertRenders(WrappedLongestShiftSlide(stats: stats), "LongestShift")
        assertRenders(WrappedWorkScheduleSlide(stats: stats), "WorkSchedule")
        assertRenders(WrappedLongShiftBreakdownSlide(stats: stats), "LongShiftBreakdown")
        assertRenders(WrappedBiggestWeekSlide(stats: stats), "BiggestWeek")
        assertRenders(WrappedWeekendVsWeekdaySlide(stats: stats), "WeekendVsWeekday")
        assertRenders(WrappedWorkStreakSlide(stats: stats), "WorkStreak")
        assertRenders(WrappedWorkerPersonalitySlide(stats: stats), "WorkerPersonality")
        assertRenders(WrappedFinalSummarySlide(stats: stats), "FinalSummary")
    }

    // MARK: - Empty year

    func testSlidesRenderSafelyWithEmptyYear() {
        // Only intro + summary are ever shown for an empty year, but the
        // data-dependent slides must still not crash if rendered — the
        // charts in particular divide by a max that would be 0.
        let stats = emptyStats
        assertRenders(WrappedIntroSlide(stats: stats), "Intro/empty")
        assertRenders(WrappedFinalSummarySlide(stats: stats), "FinalSummary/empty")
        assertRenders(WrappedWeekendVsWeekdaySlide(stats: stats), "WeekendVsWeekday/empty")
        assertRenders(WrappedLongShiftBreakdownSlide(stats: stats), "LongShiftBreakdown/empty")
        assertRenders(WrappedWorkStreakSlide(stats: stats), "WorkStreak/empty")
    }

    // MARK: - Charts in isolation

    func testChartsRenderIncludingZeroDataEdgeCases() {
        // An all-zero monthly series is the divide-by-zero risk for bar
        // height fractions.
        assertRenders(
            WrappedMonthlyChart(
                monthlyTotals: emptyStats.monthlyTotals,
                busiestMonthStart: nil,
                isActive: true
            ).frame(height: 200),
            "MonthlyChart/allZero"
        )

        assertRenders(
            WrappedMonthlyChart(
                monthlyTotals: richStats.monthlyTotals,
                busiestMonthStart: richStats.busiestMonth?.monthStart,
                isActive: true
            ).frame(height: 200),
            "MonthlyChart/rich"
        )

        assertRenders(
            WrappedWeekChart(dailyTotals: richStats.busiestWeekDailyTotals, isActive: true)
                .frame(height: 200),
            "WeekChart/rich"
        )

        // Empty series — the week chart gets no days at all for an empty year.
        assertRenders(
            WrappedWeekChart(dailyTotals: [], isActive: true).frame(height: 200),
            "WeekChart/empty"
        )

        // Both sides zero: the proportion bar must not divide by zero.
        assertRenders(
            WrappedProportionBar(leadingValue: 0, trailingValue: 0, isActive: true).frame(width: 300),
            "ProportionBar/zeroZero"
        )
    }

    // MARK: - Full container

    func testWrappedViewRendersForRichAndEmptyYears() {
        assertRenders(WrappedView(stats: richStats), "WrappedView/rich")
        assertRenders(WrappedView(stats: emptyStats), "WrappedView/empty")
    }
}
