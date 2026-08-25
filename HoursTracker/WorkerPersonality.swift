import Foundation

// MARK: - Worker Personality (Wrapped)
//
// A deterministic, threshold-based classifier over year-scoped shift
// signals. Pure math — no Firebase, no HoursStore dependency — so it can be
// unit tested and re-tuned without touching WrappedStatsEngine's shift math.
//
// All thresholds/weights live in `WorkerPersonalityScoring.Tuning` so this
// can be re-balanced later without touching the scoring logic itself.

enum WorkerPersonalityType: String, CaseIterable, Equatable {
    case machine = "The Machine"
    case grinder = "The Grinder"
    case earlyBird = "The Early Bird"
    case nightOwl = "The Night Owl"
    case weekendWarrior = "The Weekend Warrior"
    case overtimeAddict = "The Overtime Addict"
    case consistentOne = "The Consistent One"
    case workhorse = "The Workhorse"

    /// Display copy only — not part of scoring. Safe for the Wrapped UI to
    /// read directly rather than hardcoding its own copy per type.
    var tagline: String {
        switch self {
        case .machine: return "High hours, high shift count — you just don't stop."
        case .grinder: return "Long shifts, back to back. You do the heavy ones."
        case .earlyBird: return "Up before everyone else, clocked in and going."
        case .nightOwl: return "Your shifts run late — the after-hours crew."
        case .weekendWarrior: return "Saturdays and Sundays are just more workdays to you."
        case .overtimeAddict: return "Marathon shifts are your normal, not your exception."
        case .consistentOne: return "Steady, week after week — reliability is your edge."
        case .workhorse: return "You show up and put in the work, plain and simple."
        }
    }
}

/// Inputs to the classifier. Deliberately narrow — every field here must be
/// derivable from `WorkEntry` history alone (see `WrappedStatsEngine`), no
/// pay-rate or server-owned data, so the signals stay as trustworthy as the
/// shift log itself.
struct WorkerPersonalitySignals: Equatable {
    let totalHours: Double
    let totalShifts: Int
    let averageShiftLengthHours: Double
    /// Shifts >= 12h, as a fraction of total shifts (0...1).
    let over12hShiftFraction: Double
    /// Fraction of shifts starting at/before `Tuning.earlyStartHour` (0...1).
    let earlyStartFraction: Double
    /// Fraction of shifts ending at/after `Tuning.lateFinishHour`, using the
    /// same after-midnight rollover convention as `WrappedStatsEngine`'s
    /// latest-end calculation (0...1).
    let lateFinishFraction: Double
    /// Fraction of total hours worked on Saturday/Sunday (0...1).
    let weekendHoursFraction: Double
    /// Proxy for "overtime-heavy" behavior: fraction of shifts at/above
    /// `Tuning.overtimeProxyShiftHours` length. This is a shift-length proxy,
    /// not a payroll overtime calculation — the engine has no pay-rate data
    /// to compute real OT dollars, and inventing one here would violate the
    /// "don't invent unproven numbers" rule that also excluded XP/leaderboard
    /// stats from v1.
    let overtimeProxyFraction: Double
    /// How steadily the year was worked: weeks with >=1 shift divided by the
    /// number of weeks spanned between the first and last shift of the year
    /// (0...1). 1.0 means every week in that span had at least one shift.
    let weeklyConsistency: Double
}

struct WorkerPersonalityResult: Equatable {
    let type: WorkerPersonalityType
    /// The winning type's raw score, for debugging/tuning — not shown to users.
    let winningScore: Double
    /// Every type's score, same purpose.
    let allScores: [WorkerPersonalityType: Double]
}

enum WorkerPersonalityScoring {

    /// Every tunable knob in one place. Change these, not the scoring
    /// functions, to rebalance which persona wins in edge cases.
    struct Tuning {
        // Day-boundary conventions (shared meaning with WrappedStatsEngine,
        // which reads these same values when building raw signals — do not
        // hardcode a different number there, or tuning here stops doing
        // anything).
        var earlyStartHour = 6
        var lateFinishHour = 21
        /// Deliberately higher than the "long shift" bar (12h, see
        /// `WrappedYearStats.shiftsOver12Hours`) so Overtime Addict means
        /// "shifts that run *especially* long," not just "any shift a
        /// Grinder would also rack up." Without this separation the two
        /// personas' signals are nearly identical and Overtime Addict wins
        /// almost any long-shift pattern by default, which defeats having
        /// two distinct personas at all.
        var overtimeProxyShiftHours = 14.0

        // Scoring targets: signal value that yields a score of 1.0 for that
        // persona (scores are clamped to 1.5 above target so one dominant
        // signal can still win outright).
        var machineHoursTarget = 1800.0
        var machineShiftsTarget = 200.0
        var grinderOver12FractionTarget = 0.25
        var grinderAvgShiftTarget = 9.5
        var earlyBirdFractionTarget = 0.5
        var nightOwlFractionTarget = 0.35
        var weekendWarriorFractionTarget = 0.3
        var overtimeAddictFractionTarget = 0.3
        var consistentWeeklyConsistencyTarget = 0.8
        var workhorseHoursTarget = 900.0

        // Per-persona signal weights (must each sum to 1.0 across a
        // persona's own inputs; not required to sum to anything across
        // personas since scores aren't normalized against each other).
        var machineWeights = (hours: 0.5, shifts: 0.5)
        var grinderWeights = (over12hFraction: 0.6, avgShiftLength: 0.4)
        var consistentWeights = (weeklyConsistency: 0.7, moderateHours: 0.3)

        /// Break ties deterministically: earlier entries win on equal score.
        /// Ordered roughly most-specific/flashiest to most-generic so a
        /// generic high-hours year doesn't out-rank a clearly-defined
        /// pattern (e.g. an early-bird who also happens to work a lot of
        /// hours should read as "Early Bird," not "Machine").
        var priorityOrder: [WorkerPersonalityType] = [
            .machine, .grinder, .overtimeAddict, .nightOwl,
            .earlyBird, .weekendWarrior, .consistentOne, .workhorse,
        ]
    }

    static func classify(
        signals: WorkerPersonalitySignals,
        tuning: Tuning = Tuning()
    ) -> WorkerPersonalityResult {
        var scores: [WorkerPersonalityType: Double] = [:]

        scores[.machine] =
            tuning.machineWeights.hours * ratio(signals.totalHours, target: tuning.machineHoursTarget)
            + tuning.machineWeights.shifts * ratio(Double(signals.totalShifts), target: tuning.machineShiftsTarget)

        scores[.grinder] =
            tuning.grinderWeights.over12hFraction * ratio(signals.over12hShiftFraction, target: tuning.grinderOver12FractionTarget)
            + tuning.grinderWeights.avgShiftLength * ratio(signals.averageShiftLengthHours, target: tuning.grinderAvgShiftTarget)

        scores[.earlyBird] = ratio(signals.earlyStartFraction, target: tuning.earlyBirdFractionTarget)

        scores[.nightOwl] = ratio(signals.lateFinishFraction, target: tuning.nightOwlFractionTarget)

        scores[.weekendWarrior] = ratio(signals.weekendHoursFraction, target: tuning.weekendWarriorFractionTarget)

        scores[.overtimeAddict] = ratio(signals.overtimeProxyFraction, target: tuning.overtimeAddictFractionTarget)

        // "Consistent" rewards steady weekly presence at a moderate (not
        // extreme) hour total — a Machine-level grinder isn't what this
        // persona is meant to describe, even if they're also very steady.
        let moderateHoursScore = 1 - min(1, abs(signals.totalHours - tuning.workhorseHoursTarget) / tuning.workhorseHoursTarget)
        scores[.consistentOne] =
            tuning.consistentWeights.weeklyConsistency * ratio(signals.weeklyConsistency, target: tuning.consistentWeeklyConsistencyTarget)
            + tuning.consistentWeights.moderateHours * moderateHoursScore

        // Baseline/fallback persona: a straightforward hours score, capped
        // below Machine's ceiling so it only wins when nothing flashier
        // qualifies.
        scores[.workhorse] = min(1.0, ratio(signals.totalHours, target: tuning.workhorseHoursTarget))

        var winner = tuning.priorityOrder.first ?? .workhorse
        var winnerScore = scores[winner] ?? 0
        for type in tuning.priorityOrder.dropFirst() {
            let s = scores[type] ?? 0
            if s > winnerScore {
                winner = type
                winnerScore = s
            }
        }

        return WorkerPersonalityResult(type: winner, winningScore: winnerScore, allScores: scores)
    }

    /// `value / target`, clamped to [0, 1.5] so a signal well past its
    /// target still contributes but can't blow out the weighted sum.
    private static func ratio(_ value: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(1.5, max(0, value / target))
    }
}
