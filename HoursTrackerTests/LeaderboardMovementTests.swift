import XCTest
@testable import HoursTracker

/// The client half of live leaderboard movement: diffing one authoritative
/// ordering against the next. The server half (notification decisions) is
/// covered by functions/test/rankMoves.test.js.
final class LeaderboardMovementTests: XCTestCase {

    private func tracker(_ uid: String, rank: Int, hours: Double = 100) -> TopTracker {
        TopTracker(uid: uid, name: uid, hours: hours, countryCode: "", rank: rank)
    }

    // Initial load is baseline, never movement (Section 20).
    func testEmptyPreviousProducesNoMovements() {
        let current = [tracker("a", rank: 1), tracker("b", rank: 2)]
        XCTAssertTrue(TopTrackersService.rankMovements(previous: [], current: current).isEmpty)
    }

    func testUnchangedOrderProducesNoMovements() {
        let board = [tracker("a", rank: 1), tracker("b", rank: 2), tracker("c", rank: 3)]
        XCTAssertTrue(TopTrackersService.rankMovements(previous: board, current: board).isEmpty)
    }

    // Single overtake: symmetric ±1, untouched rows silent (Sections 1, 25).
    func testSingleOvertakeIsSymmetric() {
        let previous = [tracker("joey", rank: 4), tracker("ethan", rank: 5), tracker("dallas", rank: 6)]
        let current = [tracker("ethan", rank: 4), tracker("joey", rank: 5), tracker("dallas", rank: 6)]
        let moves = TopTrackersService.rankMovements(previous: previous, current: current)
        XCTAssertEqual(moves, ["ethan": 1, "joey": -1])
    }

    // A jump reports the full delta — the chip reads "↑ 3", not three hops.
    func testMultiPositionJump() {
        let previous = (1...5).map { tracker("u\($0)", rank: $0) }
        var current = previous
        current.removeAll { $0.uid == "u5" }
        current.insert(tracker("u5", rank: 2), at: 1)
        current = current.enumerated().map { tracker($1.uid, rank: $0 + 1) }
        let moves = TopTrackersService.rankMovements(previous: previous, current: current)
        XCTAssertEqual(moves["u5"], 3)
        XCTAssertEqual(moves["u2"], -1)
        XCTAssertEqual(moves["u4"], -1)
        XCTAssertNil(moves["u1"]) // untouched leader stays silent
    }

    // Appearing on the board is not climbing — no chip for the entrant,
    // real chips for the rows they displaced.
    func testNewEntrantHasNoMovement() {
        let previous = [tracker("a", rank: 1), tracker("b", rank: 2)]
        let current = [tracker("a", rank: 1), tracker("new", rank: 2), tracker("b", rank: 3)]
        let moves = TopTrackersService.rankMovements(previous: previous, current: current)
        XCTAssertNil(moves["new"])
        XCTAssertEqual(moves["b"], -1)
    }
}
