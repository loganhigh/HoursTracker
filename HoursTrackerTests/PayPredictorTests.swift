import XCTest
@testable import HoursTracker

final class PayPredictorTests: XCTestCase {

    private func cheque(_ daysAgo: Int, hours: Double, payout: Double) -> AdvancedPayPredictor.PastCheque {
        AdvancedPayPredictor.PastCheque(
            start: Date(timeIntervalSinceNow: -Double(daysAgo) * 86400),
            hours: hours,
            payout: payout
        )
    }

    // MARK: Guard rails

    func testFewerThanTwoRecordsReturnsNil() {
        XCTAssertNil(AdvancedPayPredictor.predict(currentHours: 40, past: []))
        XCTAssertNil(AdvancedPayPredictor.predict(currentHours: 40, past: [cheque(14, hours: 80, payout: 2000)]))
    }

    func testZeroHourAndZeroPayoutRecordsAreSkippedNotCrashedOn() {
        let past = [
            cheque(42, hours: 0, payout: 1500),   // would divide by zero
            cheque(28, hours: 80, payout: 0),     // meaningless payout
            cheque(14, hours: 80, payout: 2000),
        ]
        // Only one usable record remains, so no prediction.
        XCTAssertNil(AdvancedPayPredictor.predict(currentHours: 40, past: past))
    }

    func testZeroCurrentHoursReturnsNil() {
        let past = [cheque(28, hours: 80, payout: 2000), cheque(14, hours: 80, payout: 2000)]
        XCTAssertNil(AdvancedPayPredictor.predict(currentHours: 0, past: past))
    }

    // MARK: Weighted moving average

    func testStableRateProjectsLinearly() {
        // $25/h net across the board: 40h should project ~$1000.
        let past = [cheque(28, hours: 80, payout: 2000), cheque(14, hours: 80, payout: 2000)]
        let p = AdvancedPayPredictor.predict(currentHours: 40, past: past)
        XCTAssertEqual(p?.amount ?? 0, 1000, accuracy: 0.01)
        XCTAssertEqual(p?.netRate ?? 0, 25, accuracy: 0.001)
    }

    func testRecentRaiseOutweighsOldRate() {
        // Old cheques at $20/h, the two most recent at $30/h after a raise.
        let past = [
            cheque(56, hours: 80, payout: 1600),
            cheque(42, hours: 80, payout: 1600),
            cheque(28, hours: 80, payout: 2400),
            cheque(14, hours: 80, payout: 2400),
        ]
        let p = AdvancedPayPredictor.predict(currentHours: 80, past: past)!
        // Plain average would say $25/h. Linear recency weights (1,2,3,4) put
        // the learned rate at $27/h — the raise dominates.
        XCTAssertEqual(p.netRate, 27, accuracy: 0.001)
        XCTAssertGreaterThan(p.amount, 25 * 80)
    }

    func testChronologyIsSortedNotTrusted() {
        // Same cheques handed over newest-first must produce the same answer.
        let past = [
            cheque(14, hours: 80, payout: 2400),
            cheque(28, hours: 80, payout: 2400),
            cheque(42, hours: 80, payout: 1600),
            cheque(56, hours: 80, payout: 1600),
        ]
        let p = AdvancedPayPredictor.predict(currentHours: 80, past: past)!
        XCTAssertEqual(p.netRate, 27, accuracy: 0.001)
    }

    // MARK: Volume / overtime scaling

    func testHeavyPeriodScalesRateUpButIsCapped() {
        let past = [
            cheque(42, hours: 80, payout: 2000),
            cheque(28, hours: 80, payout: 2000),
            cheque(14, hours: 80, payout: 2000),
        ]
        let normal = AdvancedPayPredictor.predict(currentHours: 80, past: past)!
        XCTAssertFalse(normal.volumeAdjusted)
        XCTAssertEqual(normal.netRate, 25, accuracy: 0.001)

        let heavy = AdvancedPayPredictor.predict(currentHours: 120, past: past)!
        XCTAssertTrue(heavy.volumeAdjusted)
        XCTAssertGreaterThan(heavy.netRate, 25)
        // Cap: never more than +8% on the learned rate.
        XCTAssertLessThanOrEqual(heavy.netRate, 25 * 1.08 + 0.001)

        let slightlyOver = AdvancedPayPredictor.predict(currentHours: 85, past: past)!
        // 85h vs median 80h is inside the 15% threshold — no adjustment.
        XCTAssertFalse(slightlyOver.volumeAdjusted)
    }

    // MARK: Confidence tiers

    func testConfidenceTracksSampleDepth() {
        func predict(withSamples n: Int) -> AdvancedPayPredictor.Prediction? {
            let past = (0..<n).map { cheque(14 * ($0 + 1), hours: 80, payout: 2000) }
            return AdvancedPayPredictor.predict(currentHours: 40, past: past)
        }
        XCTAssertEqual(predict(withSamples: 2)?.confidence, .low)
        XCTAssertEqual(predict(withSamples: 4)?.confidence, .low)
        XCTAssertEqual(predict(withSamples: 5)?.confidence, .medium)
        XCTAssertEqual(predict(withSamples: 9)?.confidence, .medium)
        XCTAssertEqual(predict(withSamples: 10)?.confidence, .high)
    }
}
