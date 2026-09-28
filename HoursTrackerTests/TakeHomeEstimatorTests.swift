import XCTest
@testable import HoursTracker

final class TakeHomeEstimatorTests: XCTestCase {
    private func sample(_ gross: Double, _ payout: Double) -> TakeHomeEstimator.Sample {
        .init(gross: gross, payout: payout)
    }

    func testNeedsTwoUsableChequesToLearn() {
        XCTAssertNil(TakeHomeEstimator.learnedRatio([]))
        XCTAssertNil(TakeHomeEstimator.learnedRatio([sample(2000, 1400)]))
        // Zero-gross and zero-payout records don't count toward the two.
        XCTAssertNil(TakeHomeEstimator.learnedRatio([sample(2000, 1400), sample(0, 900), sample(1500, 0)]))
    }

    func testRatioIsTotalPayoutOverTotalGross() {
        let r = TakeHomeEstimator.learnedRatio([sample(2000, 1300), sample(3000, 2000)])
        XCTAssertEqual(r?.value ?? 0, 3300.0 / 5000.0, accuracy: 1e-9)
        XCTAssertEqual(r?.source, .learned(cheques: 2))
    }

    func testOnlyTheMostRecentChequesCount() {
        // Newest first: six at 70%, then an old cheque at 50% that must be ignored.
        let recent = Array(repeating: sample(1000, 700), count: 6)
        let r = TakeHomeEstimator.learnedRatio(recent + [sample(1000, 500)])
        XCTAssertEqual(r?.value ?? 0, 0.70, accuracy: 1e-9)
        XCTAssertEqual(r?.source, .learned(cheques: 6))
    }

    func testImplausibleRatiosAreClamped() {
        // Tips pushing payout above gross → capped at 100%.
        XCTAssertEqual(TakeHomeEstimator.learnedRatio([sample(1000, 1200), sample(1000, 1100)])?.value, 1.0)
        // A typo'd tiny payout → floored, not reported as 90% tax.
        XCTAssertEqual(TakeHomeEstimator.learnedRatio([sample(1000, 100), sample(1000, 50)])?.value, 0.35)
    }

    func testFallsBackToTheAssumptionWithoutHistory() {
        let r = TakeHomeEstimator.ratio(learned: nil)
        XCTAssertEqual(r.value, 0.75, accuracy: 1e-9)
        XCTAssertEqual(r.source, .assumed)
    }

    func testUsersExampleNumbers() {
        // 14h shift, $652.50 gross, a learned 66% ratio → ~$431 and ~$30.79/h.
        let ratio = TakeHomeEstimator.learnedRatio([sample(1000, 660.5), sample(1000, 660.5)])!
        let takeHome = 652.50 * ratio.value
        XCTAssertEqual(takeHome, 431.0, accuracy: 0.1)
        XCTAssertEqual(takeHome / 14, 30.79, accuracy: 0.01)
    }
}
