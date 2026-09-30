import Foundation

// MARK: - Stat holiday pay
//
// How a statutory holiday is paid. Chosen when the shift is logged and stored
// on the entry, so a later change to the settings never rewrites an old day.
//
// A holiday that was NOT worked stays an off day (`isOffDay`, reason
// "Holiday") — streaks, XP and the leaderboard don't count it as work — but
// it carries `statPayHours` at the regular rate so cheques and the earnings
// card include the stat pay. A holiday that WAS worked is a normal work
// entry (`isHoliday`) paid at the rule's multiplier; its hours don't count
// toward the weekly overtime threshold.

enum HolidayPayRule: String, Codable, CaseIterable, Equatable {
    /// Regular stat pay for the day off (e.g. 8 hours) — nothing worked.
    case statPayOnly
    /// Worked the holiday, paid at the regular rate.
    case workedRegular
    /// Worked the holiday at time and a half.
    case workedTimeAndHalf
    /// Worked the holiday at double time.
    case workedDoubleTime
    /// Worked at double time AND received the day's stat pay on top.
    case workedDoubleTimePlusStat

    var isWorked: Bool { self != .statPayOnly }

    /// Multiplier applied to the hours actually worked.
    var workedMultiplier: Double {
        switch self {
        case .statPayOnly, .workedRegular: return 1.0
        case .workedTimeAndHalf: return 1.5
        case .workedDoubleTime, .workedDoubleTimePlusStat: return 2.0
        }
    }

    /// Whether the day's stat pay (regular rate × stat hours) is added.
    var includesStatPay: Bool {
        self == .statPayOnly || self == .workedDoubleTimePlusStat
    }

    var title: String {
        switch self {
        case .statPayOnly: return "Stat Holiday – paid, not worked"
        case .workedRegular: return "Worked – Regular Time"
        case .workedTimeAndHalf: return "Worked – Time & ½"
        case .workedDoubleTime: return "Worked – Double Time"
        case .workedDoubleTimePlusStat: return "Worked + Stat Holiday Pay"
        }
    }

    /// Short form for chips, cheque rows and the earnings card.
    var shortTitle: String {
        switch self {
        case .statPayOnly: return "Stat pay"
        case .workedRegular: return "Stat · 1×"
        case .workedTimeAndHalf: return "Stat · 1.5×"
        case .workedDoubleTime: return "Stat · 2×"
        case .workedDoubleTimePlusStat: return "Stat · 2× + stat pay"
        }
    }

    func detail(statHours: Double) -> String {
        let stat = HolidayPayRule.hoursText(statHours)
        switch self {
        case .statPayOnly:
            return "You get your regular \(stat) of stat pay even though you didn't work."
        case .workedRegular:
            return "You worked the holiday and are paid regular time for those hours."
        case .workedTimeAndHalf:
            return "You worked the holiday and receive time and a half."
        case .workedDoubleTime:
            return "You worked the holiday and receive double time."
        case .workedDoubleTimePlusStat:
            return "Double time for the hours worked, plus your \(stat) of stat pay."
        }
    }

    var icon: String {
        switch self {
        case .statPayOnly: return "star.circle"
        case .workedRegular: return "clock"
        case .workedTimeAndHalf: return "clock.badge"
        case .workedDoubleTime: return "clock.badge.fill"
        case .workedDoubleTimePlusStat: return "star.circle.fill"
        }
    }

    /// Hours paid for the day at the regular rate — what "the day was worth".
    /// e.g. 10h worked at 2× plus 8h stat pay = 28 paid hours.
    func paidHourEquivalent(workedHours: Double, statHours: Double) -> Double {
        (isWorked ? workedHours * workedMultiplier : 0) + (includesStatPay ? statHours : 0)
    }

    /// e.g. "10h × 2 + 8h stat pay = 28h paid".
    func formula(workedHours: Double, statHours: Double) -> String {
        let total = HolidayPayRule.hoursText(paidHourEquivalent(workedHours: workedHours, statHours: statHours))
        switch self {
        case .statPayOnly:
            return "\(HolidayPayRule.hoursText(statHours)) stat pay at your regular rate"
        case .workedRegular:
            return "\(HolidayPayRule.hoursText(workedHours)) at regular rate"
        case .workedTimeAndHalf, .workedDoubleTime:
            return "\(HolidayPayRule.hoursText(workedHours)) × \(HolidayPayRule.multText(workedMultiplier)) = \(total) paid"
        case .workedDoubleTimePlusStat:
            return "\(HolidayPayRule.hoursText(workedHours)) × 2 + \(HolidayPayRule.hoursText(statHours)) stat = \(total) paid"
        }
    }

    static func hoursText(_ h: Double) -> String {
        let rounded = (h * 100).rounded() / 100
        return rounded == rounded.rounded(.towardZero) ? "\(Int(rounded))h" : String(format: "%.2fh", rounded)
    }

    static func multText(_ m: Double) -> String {
        m == m.rounded(.towardZero) ? "\(Int(m))" : String(format: "%.1f", m)
    }
}

extension WorkEntry {
    /// Stat pay on top of any worked hours, in regular-rate dollars.
    func statPay(wage: Double) -> Double { max(0, statPayHours) * wage }
}
