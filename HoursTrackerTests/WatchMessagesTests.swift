import XCTest
@testable import HoursTracker

/// The phone and watch share these types over WatchConnectivity, so the
/// math the watch shows has to match what the phone saves, and every
/// command has to survive the JSON round trip.
final class WatchMessagesTests: XCTestCase {

    func testDraftHoursSubtractBreakAndWrapPastMidnight() {
        let day = Date()
        XCTAssertEqual(WatchShiftDraft(day: day, startMinutes: 6 * 60, endMinutes: 18 * 60 + 30,
                                       breakMinutes: 30, locationName: "").paidHours, 12, accuracy: 0.001)
        // 10 PM → 6 AM is 8 hours, not -16.
        XCTAssertEqual(WatchShiftDraft(day: day, startMinutes: 22 * 60, endMinutes: 6 * 60,
                                       breakMinutes: 0, locationName: "").paidHours, 8, accuracy: 0.001)
        // A break longer than the shift never goes negative.
        XCTAssertEqual(WatchShiftDraft(day: day, startMinutes: 9 * 60, endMinutes: 9 * 60 + 30,
                                       breakMinutes: 60, locationName: "").paidHours, 0)
    }

    func testLiveShiftWorkedTimeExcludesBreaksIncludingOneInProgress() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let shift = WatchLiveShift(startDate: start, breaks: [
            WatchBreak(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(4500)),
            WatchBreak(start: start.addingTimeInterval(7200), end: nil),
        ])
        XCTAssertTrue(shift.isOnBreak)
        // 3h wall clock − 15 min finished break − 60 min running break = 1h45m.
        XCTAssertEqual(shift.workedSeconds(at: start.addingTimeInterval(3 * 3600)), 105 * 60, accuracy: 0.001)
    }

    func testCommandsRoundTripThroughJSON() throws {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let commands: [WatchCommand] = [
            .requestSnapshot, .clockIn(at: at), .startBreak(at: at), .endBreak(at: at), .clockOut(at: at),
            .addShift(WatchShiftDraft(day: at, startMinutes: 360, endMinutes: 1110, breakMinutes: 30,
                                      locationName: "Main Yard", templateID: "t1")),
            .requestMonth(at),
        ]
        for command in commands {
            let data = try XCTUnwrap(WatchCoding.encode(command))
            XCTAssertEqual(WatchCoding.decode(WatchCommand.self, from: data), command)
        }
    }
}
