import Foundation

// MARK: - Advanced pay predictor
//
// Learns what a cheque is actually worth from the totals users type in after
// getting paid, then projects the live cheque from its hours. The recorded
// total bakes in everything the in-app estimate can't see — taxes, tips,
// bonuses, employer rounding — so the learned net rate ($ actually received
// per hour logged) beats rate × hours the moment there's history to learn
// from.
//
// Pure math, no I/O: callers assemble past cheques from wherever actuals are
// stored (HoursStore.actualPayout(for:)) and hand them in. That keeps every
// rule here unit-testable — see PayPredictorTests.

struct AdvancedPayPredictor {

    /// One completed cheque the user recorded a real total for.
    struct PastCheque {
        let start: Date
        /// Paid hours logged inside that period.
        let hours: Double
        /// What the cheque actually paid, as typed by the user.
        let payout: Double
    }

    struct Prediction {
        /// Projected take-home for the hours logged so far.
        let amount: Double
        /// The learned net rate ($/h) after weighting and volume scaling.
        let netRate: Double
        /// How many recorded cheques the estimate stands on.
        let sampleCount: Int
        let confidence: Confidence
        /// True when the current period's volume tripped the overtime scaling.
        let volumeAdjusted: Bool
    }

    enum Confidence {
        case low, medium, high

        init(sampleCount: Int) {
            switch sampleCount {
            case ..<5: self = .low
            case ..<10: self = .medium
            default: self = .high
            }
        }

        var label: String {
            switch self {
            case .low: return "Low confidence"
            case .medium: return "Medium confidence"
            case .high: return "High confidence"
            }
        }

        /// 1–3, for a dots-style indicator.
        var level: Int {
            switch self {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            }
        }
    }

    /// If the live period's hours exceed the historical median by this factor,
    /// the projected rate starts scaling up — heavy periods land dispropor-
    /// tionately in overtime, which the flat learned rate under-counts.
    private static let volumeThreshold = 1.15
    /// How much of the excess-hours ratio converts into rate uplift.
    private static let volumeSlope = 0.15
    /// Ceiling on the uplift: at +8% the OT effect is priced without letting
    /// one monster period double a prediction.
    private static let volumeCap = 1.08

    /// Nil until there are at least two usable recorded cheques — one cheque
    /// is an anecdote, not a rate. Zero-hour or zero-payout records are
    /// skipped rather than crashing the averages they'd divide by.
    static func predict(currentHours: Double, past: [PastCheque]) -> Prediction? {
        let usable = past
            .filter { $0.hours > 0 && $0.payout > 0 && $0.payout.isFinite && $0.hours.isFinite }
            .sorted { $0.start < $1.start }
        guard usable.count >= 2, currentHours > 0, currentHours.isFinite else { return nil }

        // Weighted moving average of the net rate: weights rise linearly with
        // recency (oldest = 1, newest = n), so a raise or a seasonal tip
        // spike three cheques ago outweighs how things looked last winter.
        var weightedRate = 0.0
        var totalWeight = 0.0
        for (index, cheque) in usable.enumerated() {
            let weight = Double(index + 1)
            weightedRate += (cheque.payout / cheque.hours) * weight
            totalWeight += weight
        }
        let baseRate = weightedRate / totalWeight

        // Volume scaling against the median (not mean — one outlier period
        // shouldn't move the yardstick everything is compared to).
        let sortedHours = usable.map(\.hours).sorted()
        let median = sortedHours.count.isMultiple(of: 2)
            ? (sortedHours[sortedHours.count / 2 - 1] + sortedHours[sortedHours.count / 2]) / 2
            : sortedHours[sortedHours.count / 2]

        var rate = baseRate
        var volumeAdjusted = false
        if median > 0, currentHours > median * volumeThreshold {
            let ratio = currentHours / median
            rate = baseRate * min(volumeCap, 1 + (ratio - 1) * volumeSlope)
            volumeAdjusted = true
        }

        return Prediction(
            amount: rate * currentHours,
            netRate: rate,
            sampleCount: usable.count,
            confidence: Confidence(sampleCount: usable.count),
            volumeAdjusted: volumeAdjusted
        )
    }
}
