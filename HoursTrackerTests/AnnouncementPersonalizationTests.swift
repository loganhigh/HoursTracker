import XCTest
@testable import HoursTracker

final class AnnouncementPersonalizationTests: XCTestCase {
    func testNamePlaceholderIsFilledInAnyCaseAndSpacing() {
        XCTAssertEqual(Announcement.personalized("Hey {name}!", name: "logan"), "Hey logan!")
        XCTAssertEqual(Announcement.personalized("Hey {NAME}, {username}", name: "logan"), "Hey logan, logan")
        XCTAssertEqual(Announcement.personalized("Hey { name }", name: "logan"), "Hey logan")
    }

    func testMissingNameFallsBackToThere() {
        XCTAssertEqual(Announcement.personalized("Hey {name}", name: nil), "Hey there")
        XCTAssertEqual(Announcement.personalized("Hey {name}", name: "   "), "Hey there")
    }

    func testTextWithoutPlaceholderIsUntouched() {
        XCTAssertEqual(Announcement.personalized("Update now {soon}", name: "logan"), "Update now {soon}")
    }
}

/// Who sees the announcement: only out-of-date users for an update, and never
/// an account created after it was published.
final class AnnouncementTargetingTests: XCTestCase {
    private let published = Date(timeIntervalSince1970: 1_800_000_000)

    func testVersionCompareIsNumeric() {
        XCTAssertTrue(Announcement.isVersion("3.4", olderThan: "3.10"))
        XCTAssertTrue(Announcement.isVersion("3.4", olderThan: "3.4.1"))
        XCTAssertFalse(Announcement.isVersion("3.4.0", olderThan: "3.4"))
        XCTAssertFalse(Announcement.isVersion("3.5", olderThan: "3.4"))
    }

    func testUpdateSkipsUsersAlreadyOnTheVersion() {
        let old = published.addingTimeInterval(-86_400)
        XCTAssertTrue(Announcement.isRelevant(kind: "update", targetVersion: "3.4", publishedAt: published,
                                              installedVersion: "3.2", accountCreatedAt: old))
        XCTAssertFalse(Announcement.isRelevant(kind: "update", targetVersion: "3.4", publishedAt: published,
                                               installedVersion: "3.4", accountCreatedAt: old))
        XCTAssertFalse(Announcement.isRelevant(kind: "update", targetVersion: "3.4", publishedAt: published,
                                               installedVersion: "3.5", accountCreatedAt: old))
    }

    func testAccountsCreatedAfterPublishingNeverSeeIt() {
        let newer = published.addingTimeInterval(60)
        XCTAssertFalse(Announcement.isRelevant(kind: "update", targetVersion: nil, publishedAt: published,
                                               installedVersion: "3.2", accountCreatedAt: newer))
        XCTAssertFalse(Announcement.isRelevant(kind: "info", targetVersion: nil, publishedAt: published,
                                               installedVersion: "3.4", accountCreatedAt: newer))
    }

    func testLegacyDocWithoutVersionStillReachesExistingUsers() {
        XCTAssertTrue(Announcement.isRelevant(kind: "update", targetVersion: nil, publishedAt: published,
                                              installedVersion: "3.2",
                                              accountCreatedAt: published.addingTimeInterval(-60)))
    }
}
