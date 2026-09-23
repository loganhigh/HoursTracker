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
