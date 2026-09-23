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
        let full = (1...6).map { tracker("u\($0)", rank: $0, hours: Double(100 - $0)) }
        // Live top-3 arrives with u2 and u1 swapped.
        let live = [tracker("u2", rank: 1, hours: 99), tracker("u1", rank: 2, hours: 98), tracker("u3", rank: 3, hours: 97)]
        let merged = TopTrackersService.mergeLiveSlice(live, into: full, liveCoversFullSlice: true)
        XCTAssertEqual(merged.map(\.uid), ["u2", "u1", "u3", "u4", "u5", "u6"])
        XCTAssertEqual(merged.map(\.rank), [1, 2, 3, 4, 5, 6])
    }

    func testLiveSliceKeepsRowThatFellOutOfIt() {
        let full = (1...6).map { tracker("u\($0)", rank: $0, hours: Double(100 - $0)) }
        // u5 climbs into the top 3; u3 falls out of the live slice. u3 is
        // still ranked — it now sits just below the slice, above u4.
        let live = [tracker("u1", rank: 1, hours: 99), tracker("u5", rank: 2, hours: 98.5), tracker("u2", rank: 3, hours: 98)]
        let merged = TopTrackersService.mergeLiveSlice(live, into: full, liveCoversFullSlice: true)
        XCTAssertEqual(merged.map(\.uid), ["u1", "u5", "u2", "u3", "u4", "u6"])
        XCTAssertEqual(merged.map(\.rank), [1, 2, 3, 4, 5, 6])
    }

    // Regression: a full 100-document slice can parse to fewer rows (opted-out
    // profiles are filtered client-side). That is NOT the query exhausting the
    // collection — the deeper rows must survive (observed live: 106 → 99).
    func testLiveSliceShortByFilteringStillKeepsDeeperRows() {
        // Raw top-3 was u1, x (opted out, filtered), u3 → parsed live has 2 rows.
        let live = [tracker("u1", rank: 1, hours: 99), tracker("u3", rank: 2, hours: 97)]
        let full = [
            tracker("u1", rank: 1, hours: 99), tracker("u3", rank: 2, hours: 97),
            tracker("u4", rank: 3, hours: 96), tracker("u5", rank: 4, hours: 95), tracker("u6", rank: 5, hours: 94),
        ]
        let merged = TopTrackersService.mergeLiveSlice(live, into: full, liveCoversFullSlice: true)
        XCTAssertEqual(merged.map(\.uid), ["u1", "u3", "u4", "u5", "u6"])
        XCTAssertEqual(merged.map(\.rank), [1, 2, 3, 4, 5])
    }

    func testLiveSliceIsAuthoritativeWhenNoDeeperRowsExist() {
        let live = [tracker("a", rank: 1), tracker("b", rank: 2)]
        XCTAssertEqual(TopTrackersService.mergeLiveSlice(live, into: [], liveCoversFullSlice: true).map(\.uid), ["a", "b"])
        // A raw query that didn't fill its limit exhausted the collection —
        // the existing longer list is stale, so replace it.
        let stale = (1...5).map { tracker("s\($0)", rank: $0) }
        XCTAssertEqual(TopTrackersService.mergeLiveSlice(live, into: stale, liveCoversFullSlice: false).map(\.uid), ["a", "b"])
    }
}
