import XCTest
@testable import HoursTracker

/// When the app asks for an App Store review.
final class ReviewAskPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    func testPrestigeAsksUnlessReviewWrittenThisYear() {
        XCTAssertTrue(ReviewAskPolicy.shouldAskAfterPrestige(wroteAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAfterPrestige(wroteAt: daysAgo(30), now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldAskAfterPrestige(wroteAt: daysAgo(400), now: now))
    }

    func testMilestoneOnlyOnceAtThirtyShifts() {
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 29, alreadyAsked: false, wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 30, alreadyAsked: false, wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 80, alreadyAsked: true, wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 30, alreadyAsked: false, wroteAt: nil, lastAskAt: daysAgo(2), now: now))
    }

    func testStarSheetNeedsShiftsAndCooldown() {
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 9, lastStarAt: nil, wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldShowStarSheet(workShifts: 10, lastStarAt: nil, wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: daysAgo(60), wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: daysAgo(121), wroteAt: nil, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: nil, wroteAt: daysAgo(10), lastAskAt: nil, now: now))
    }
}
