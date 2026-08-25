import XCTest
@testable import HoursTracker

/// Covers story navigation bounds — that forward/back can never index out of
/// the available slide list, which is what would otherwise crash at the end
/// of a Wrapped story or on a low-data year with very few slides.
final class WrappedNavigatorTests: XCTestCase {

    private let threeSlides: [WrappedSlideType] = [.intro, .totalHours, .finalSummary]

    func testStartsOnFirstSlide() {
        let nav = WrappedNavigator(slides: threeSlides)
        XCTAssertEqual(nav.index, 0)
        XCTAssertEqual(nav.currentSlide, .intro)
        XCTAssertTrue(nav.isFirst)
        XCTAssertFalse(nav.isLast)
    }

    func testForwardStopsAtLastSlideAndReportsIt() {
        var nav = WrappedNavigator(slides: threeSlides)
        XCTAssertTrue(nav.goNext())  // -> totalHours
        XCTAssertTrue(nav.goNext())  // -> finalSummary
        XCTAssertTrue(nav.isLast)

        // Past the end: no movement, and returns false so the view knows to
        // dismiss rather than sitting on a dead tap.
        XCTAssertFalse(nav.goNext())
        XCTAssertEqual(nav.index, 2)
        XCTAssertEqual(nav.currentSlide, .finalSummary)

        // Repeated over-taps stay in bounds.
        for _ in 0..<10 { _ = nav.goNext() }
        XCTAssertEqual(nav.index, 2)
    }

    func testBackStopsAtFirstSlide() {
        var nav = WrappedNavigator(slides: threeSlides)
        XCTAssertFalse(nav.goPrevious())
        XCTAssertEqual(nav.index, 0)

        for _ in 0..<10 { _ = nav.goPrevious() }
        XCTAssertEqual(nav.index, 0)
        XCTAssertEqual(nav.currentSlide, .intro)
    }

    func testRoundTripForwardAndBack() {
        var nav = WrappedNavigator(slides: threeSlides)
        _ = nav.goNext()
        _ = nav.goNext()
        _ = nav.goPrevious()
        XCTAssertEqual(nav.index, 1)
        XCTAssertEqual(nav.currentSlide, .totalHours)
    }

    func testMinimalTwoSlideStoryStillNavigatesSafely() {
        // The empty-year shape: intro + summary only.
        var nav = WrappedNavigator(slides: [.intro, .finalSummary])
        XCTAssertEqual(nav.slideCount, 2)
        XCTAssertTrue(nav.goNext())
        XCTAssertTrue(nav.isLast)
        XCTAssertFalse(nav.goNext())
        XCTAssertEqual(nav.currentSlide, .finalSummary)
    }

    func testOutOfRangeStartingIndexIsClamped() {
        let tooHigh = WrappedNavigator(slides: threeSlides, index: 99)
        XCTAssertEqual(tooHigh.index, 2)
        XCTAssertEqual(tooHigh.currentSlide, .finalSummary)

        let negative = WrappedNavigator(slides: threeSlides, index: -5)
        XCTAssertEqual(negative.index, 0)
        XCTAssertEqual(negative.currentSlide, .intro)
    }

    func testEmptySlideListDoesNotCrash() {
        // Not producible by availableSlides(for:) — intro and summary always
        // exist — but the navigator must not trap if it ever happens.
        var nav = WrappedNavigator(slides: [])
        XCTAssertNil(nav.currentSlide)
        XCTAssertEqual(nav.slideCount, 0)
        XCTAssertFalse(nav.goNext())
        XCTAssertFalse(nav.goPrevious())
        XCTAssertEqual(nav.index, 0)
    }

    // MARK: - Integration with real slide availability

    func testNavigationCoversEverySlideOfARealStatsObject() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2

        let entries: [WorkEntry] = (1...15).map { day in
            var startComps = DateComponents(year: 2026, month: 6, day: day, hour: 5)
            startComps.timeZone = cal.timeZone
            var endComps = DateComponents(year: 2026, month: 6, day: day, hour: 20)
            endComps.timeZone = cal.timeZone
            var dateComps = DateComponents(year: 2026, month: 6, day: day)
            dateComps.timeZone = cal.timeZone
            return WorkEntry(
                date: cal.date(from: dateComps)!,
                start: cal.date(from: startComps)!,
                end: cal.date(from: endComps)!,
                breakMinutes: 0,
                notes: ""
            )
        }

        let stats = WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
        let slides = WrappedSlideType.availableSlides(for: stats)
        var nav = WrappedNavigator(slides: slides)

        var visited: [WrappedSlideType] = []
        visited.append(nav.currentSlide!)
        while nav.goNext() {
            visited.append(nav.currentSlide!)
        }

        XCTAssertEqual(visited, slides, "Walking forward should visit every available slide exactly once, in order")
        XCTAssertTrue(nav.isLast)
    }
}
