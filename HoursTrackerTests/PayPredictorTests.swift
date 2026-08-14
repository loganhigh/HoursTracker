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

// MARK: - Hours-aware regression

extension PayPredictorTests {

    /// "I get 72h five times — the system knows 72h pays X."
    func testRepeatedIdenticalHoursPinTheirPayout() {
        let past = (1...5).map { cheque(14 * $0, hours: 72, payout: 1800) }
        let p = AdvancedPayPredictor.predict(currentHours: 72, past: past)!
        XCTAssertEqual(p.amount, 1800, accuracy: 0.01)
        XCTAssertEqual(p.confidence, .medium)
    }

    /// With spread in the history, higher hours ride the learned line —
    /// overtime slope included — not a flat rate.
    func testSpreadTeachesTheSlopeForUnseenHours() {
        // ~$25/h base with OT pushing marginal dollars above that:
        // 60h → $1500, 72h → $1900, 90h → $2500.
        let past = [
            cheque(56, hours: 60, payout: 1500),
            cheque(42, hours: 72, payout: 1900),
            cheque(28, hours: 72, payout: 1900),
            cheque(14, hours: 90, payout: 2500),
        ]
        let at72 = AdvancedPayPredictor.predict(currentHours: 72, past: past)!
        XCTAssertEqual(at72.amount, 1900, accuracy: 60) // near the observed 72h payout

        let at100 = AdvancedPayPredictor.predict(currentHours: 100, past: past)!
        // The line's marginal rate (~$33/h across the observed span) carries
        // past the highest observed hours; a flat $25/h would say ~$2500.
        XCTAssertGreaterThan(at100.amount, 2700)
        XCTAssertLessThan(at100.amount, 3600)
    }

    /// A nonsense negative slope (less pay for more hours) is not trusted —
    /// the flat-rate path answers instead.
    func testNegativeSlopeFallsBackToFlatRate() {
        let past = [
            cheque(42, hours: 60, payout: 2400),
            cheque(28, hours: 80, payout: 2000),
            cheque(14, hours: 100, payout: 1600),
        ]
        let p = AdvancedPayPredictor.predict(currentHours: 80, past: past)!
        // Fallback WMA rate is positive and sane; the line would have sloped
        // downward and been rejected.
        XCTAssertGreaterThan(p.amount, 0)
        XCTAssertEqual(p.netRate, (40.0 * 1 + 25.0 * 2 + 16.0 * 3) / 6.0, accuracy: 0.001)
    }
}
