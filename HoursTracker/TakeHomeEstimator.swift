import Foundation

// MARK: - Take-home estimate
//
// The app knows gross pay exactly (rate, overtime rules, vacation pay) but has
// no tax tables. What it does have is the real total users type in after each
// payday. Dividing what a cheque actually paid by what the app computed as
// gross for the same period gives the user's own deduction ratio — tax, CPP,
// EI, union dues, benefits, all of it — without the app guessing any of them.
//
// Until there are at least two recorded cheques, the estimate falls back to a
// flat assumption and says so, rather than presenting a guess as learned.
//
// Pure math, no I/O — see TakeHomeEstimatorTests.

enum TakeHomeEstimator {

    /// Used until the user has recorded enough cheques to learn from.
    static let assumedDeductionRate = 0.25

    /// Only the most recent cheques count: raises, tax-bracket changes and
    /// new benefits make old ratios stale.
    static let maxSamples = 6

    /// A ratio outside this band is a data-entry problem (a typo'd payout,
    /// a cheque recorded against the wrong period), not a real tax rate.
    static let plausibleRatio: ClosedRange<Double> = 0.35...1.0

    struct Sample {
        /// Gross the app computed for the pay period.
        let gross: Double
        /// What the cheque actually paid, as recorded by the user.
        let payout: Double
    }

    enum Source: Equatable {
        /// Learned from this many recorded cheques.
        case learned(cheques: Int)
        /// Not enough history — the flat assumption was used.
        case assumed
    }

    struct Ratio: Equatable {
        /// Take-home ÷ gross.
        let value: Double
        let source: Source
    }

    /// The user's own take-home ratio from recorded cheques, most recent
    /// first. nil with fewer than two usable cheques.
    static func learnedRatio(_ samplesNewestFirst: [Sample]) -> Ratio? {
        let usable = samplesNewestFirst
            .filter { $0.gross > 0 && $0.payout > 0 && $0.gross.isFinite && $0.payout.isFinite }
            .prefix(maxSamples)
        guard usable.count >= 2 else { return nil }
        let gross = usable.reduce(0) { $0 + $1.gross }
        let payout = usable.reduce(0) { $0 + $1.payout }
        let raw = payout / gross
        let clamped = min(max(raw, plausibleRatio.lowerBound), plausibleRatio.upperBound)
        return Ratio(value: clamped, source: .learned(cheques: usable.count))
    }

    /// The ratio to apply: learned when available, otherwise the assumption.
    static func ratio(learned: Ratio?) -> Ratio {
        learned ?? Ratio(value: 1 - assumedDeductionRate, source: .assumed)
    }
}
