import XCTest
@testable import HoursTracker

/// When the app asks for an App Store review.
final class ReviewAskPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    func testReviewedUsersAreNeverAskedAgain() {
        XCTAssertTrue(ReviewAskPolicy.shouldAskAfterPrestige(reviewed: false))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAfterPrestige(reviewed: true))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 30, alreadyAsked: false, reviewed: true, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: daysAgo(900), reviewed: true, lastAskAt: nil, now: now))
    }

    func testMilestoneOnlyOnceAtThirtyShifts() {
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 29, alreadyAsked: false, reviewed: false, lastAskAt: nil, now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 30, alreadyAsked: false, reviewed: false, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 80, alreadyAsked: true, reviewed: false, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldAskAtMilestone(workShifts: 30, alreadyAsked: false, reviewed: false, lastAskAt: daysAgo(2), now: now))
    }

    func testStarSheetNeedsShiftsAndCooldown() {
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 9, lastStarAt: nil, reviewed: false, lastAskAt: nil, now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldShowStarSheet(workShifts: 10, lastStarAt: nil, reviewed: false, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: daysAgo(60), reviewed: false, lastAskAt: nil, now: now))
        XCTAssertTrue(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: daysAgo(121), reviewed: false, lastAskAt: nil, now: now))
        XCTAssertFalse(ReviewAskPolicy.shouldShowStarSheet(workShifts: 50, lastStarAt: nil, reviewed: true, lastAskAt: nil, now: now))
    }
}
