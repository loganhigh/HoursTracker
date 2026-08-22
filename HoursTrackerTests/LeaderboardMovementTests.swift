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

    // MARK: - Live slice merge (regression: top-100 snapshot truncated the 500-row board)

    func testLiveSliceKeepsDeeperRowsAndRenumbers() {
        let limit = 3
        let full = (1...6).map { tracker("u\($0)", rank: $0) }
        // Live top-3 arrives with u2 and u1 swapped.
        let live = [tracker("u2", rank: 1), tracker("u1", rank: 2), tracker("u3", rank: 3)]
        let merged = TopTrackersService.mergeLiveSlice(live, into: full, liveLimit: limit)
        XCTAssertEqual(merged.map(\.uid), ["u2", "u1", "u3", "u4", "u5", "u6"])
        XCTAssertEqual(merged.map(\.rank), [1, 2, 3, 4, 5, 6])
    }

    func testLiveSliceDropsRowThatClimbedIntoIt() {
        let limit = 3
        let full = (1...6).map { tracker("u\($0)", rank: $0) }
        // u5 climbs into the top 3; u3 falls out of the live slice.
        let live = [tracker("u1", rank: 1), tracker("u5", rank: 2), tracker("u2", rank: 3)]
        let merged = TopTrackersService.mergeLiveSlice(live, into: full, liveLimit: limit)
        XCTAssertEqual(merged.map(\.uid), ["u1", "u5", "u2", "u4", "u6"])
        XCTAssertEqual(merged.map(\.rank), [1, 2, 3, 4, 5])
    }

    func testLiveSliceIsAuthoritativeWhenNoDeeperRowsExist() {
        let live = [tracker("a", rank: 1), tracker("b", rank: 2)]
        XCTAssertEqual(TopTrackersService.mergeLiveSlice(live, into: [], liveLimit: 100).map(\.uid), ["a", "b"])
        // A short live list (fewer than the limit) means the query exhausted
        // the collection — the existing longer list is stale, so replace it.
        let stale = (1...5).map { tracker("s\($0)", rank: $0) }
        XCTAssertEqual(TopTrackersService.mergeLiveSlice(live, into: stale, liveLimit: 100).map(\.uid), ["a", "b"])
    }
}
