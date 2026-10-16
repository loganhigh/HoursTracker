import Foundation

// MARK: - OwlLines
//
// What Otto says. Pure functions over values a screen already has, so no
// new data or stores. Rules: one line, at most `maxLength` characters,
// hours before money, and a line stays the same for the whole day (picked
// by a day seed) so it never flickers on re-render.

enum OwlLines {
    static let maxLength = 40

    /// Home companion pose, matching `home(…)`'s line.
    static func homePose(todayHours: Double, isDayOff: Bool, streakDays: Int) -> OwlPose {
        if isDayOff { return .sleep }
        if todayHours > 0 { return .cheer }
        if streakDays >= 3 { return .streak }
        return .coffee
    }

    /// Home companion line, keyed off today's shift.
    static func home(todayHours: Double, isDayOff: Bool, streakDays: Int, hasAnyShifts: Bool = true, daySeed: Int) -> String {
        if !hasAnyShifts {
            return "Log your first shift below."
        }
        if isDayOff {
            return pick(["Day off. Rest up.", "No shift today. Enjoy it.", "Recharge day. You earned it."], seed: daySeed)
        }
        if todayHours >= 10 {
            return "\(hours(todayHours)) today. Big one!"
        }
        if todayHours > 0 {
            return pick(["\(hours(todayHours)) today. Nice shift.", "\(hours(todayHours)) logged today.", "\(hours(todayHours)) today. Solid work."], seed: daySeed)
        }
        if streakDays >= 3 {
            return "\(streakDays)-day streak. Keep it going."
        }
        return pick(["Log today's shift when you're done.", "Ready when you are.", "Clock out, then log it here."], seed: daySeed)
    }

    /// History tab: unlogged workdays come first, then the live cheque.
    static func history(currentChequeHours: Double, missingDays: Int) -> (pose: OwlPose, line: String) {
        if missingDays == 1 { return (.search, "One workday looks unlogged.") }
        if missingDays > 1 { return (.search, "\(missingDays) workdays look unlogged.") }
        if currentChequeHours > 0 { return (.clipboard, "\(hours(currentChequeHours)) on this cheque so far.") }
        return (.clipboard, "Fresh cheque. Let's fill it up.")
    }

    /// Friends hub: where you sit on this cheque's board.
    static func friends(myRank: Int, total: Int) -> (pose: OwlPose, line: String) {
        switch myRank {
        case 1: return (.trophy, "You're #1 among your friends.")
        case 2, 3: return (.trophy, "#\(myRank) this cheque. On the podium!")
        case let rank where rank > 3: return (.buddies, "#\(rank) of \(total). Time to climb.")
        default: return (.buddies, "Your friends' hours, this cheque.")
        }
    }

    /// Global board: your worldwide rank, or how to get onto the board.
    static func globalRank(_ rank: Int?) -> (pose: OwlPose, line: String) {
        guard let rank else { return (.search, "Log a shift to join the board.") }
        switch rank {
        case 1: return (.crown, "#1 in the world. Wow.")
        case 2...10: return (.trophy, "Top 10 worldwide. Huge.")
        default: return (.trophy, "#\(rank) worldwide. Keep climbing.")
        }
    }

    /// You tab, over the lifetime grid: a finished run first, then a big
    /// lifetime, then a day-stable pick of hours, days or the next level.
    static func you(
        allTimeHours: Double,
        daysWorked: Int,
        level: Int,
        xpToNextLevel: Int,
        canPrestige: Bool,
        daySeed: Int
    ) -> (pose: OwlPose, line: String) {
        if allTimeHours <= 0 { return (.wave, "Your story starts with one shift.") }
        if canPrestige { return (.crown, "Max level. Prestige when you're ready.") }
        let lifetime = allTimeHours >= 1000 ? "\(Int(allTimeHours.rounded()))h" : hours(allTimeHours)
        if allTimeHours >= 1000 { return (.trophy, "\(lifetime) all time. Legendary.") }
        var options = [
            "\(lifetime) logged all time.",
            daysWorked == 1 ? "First day logged. Proud of you." : "\(daysWorked) days worked. Proud of you.",
        ]
        if xpToNextLevel > 0 {
            options.append("\(xpToNextLevel.formatted()) XP to Level \(level + 1).")
        }
        return (.idle, pick(options, seed: daySeed))
    }

    /// Badges screen, over the "N of M" card. No badges at all is the empty
    /// state's job.
    static func badges(earned: Int, total: Int) -> (pose: OwlPose, line: String) {
        if total > 0, earned >= total { return (.crown, "Every badge earned. Legend.") }
        if total > 0, earned * 2 >= total { return (.trophy, "Over halfway there. Keep going!") }
        return (.trophy, "\(earned) of \(total) badges. Keep going.")
    }

    /// A savings goal's detail sheet.
    static func goal(fraction: Double, isComplete: Bool) -> (pose: OwlPose, line: String) {
        if isComplete { return (.cheer, "Goal reached. Treat yourself!") }
        if fraction <= 0 { return (.point, "Add your first savings below.") }
        if fraction >= 0.75 { return (.cheer, "Almost there. So close!") }
        if fraction >= 0.5 { return (.idle, "Over halfway. Keep going!") }
        return (.idle, "\(Int((fraction * 100).rounded(.down)))% saved. Every bit counts.")
    }

    /// Where a cheque stands, for its detail screen.
    enum ChequeState {
        case inProgress, pending, awaitingTotal, recorded
    }

    static func cheque(_ state: ChequeState, hours worked: Double) -> (pose: OwlPose, line: String) {
        switch state {
        case .inProgress:
            return worked > 0
                ? (.clipboard, "\(hours(worked)) logged so far.")
                : (.clipboard, "Fresh cheque. Let's fill it up.")
        case .pending: return (.calendar, "Payday's on the way.")
        case .awaitingTotal: return (.point, "Got paid? Add the total below.")
        case .recorded: return (.cheer, "Paid and recorded. Nice work.")
        }
    }

    /// Live shift: what the owl does while the timer runs.
    static func liveShift(isOnBreak: Bool, isStale: Bool) -> (pose: OwlPose, line: String) {
        if isStale { return (.oops, "Still on the clock?") }
        if isOnBreak { return (.sleep, "Enjoy your break.") }
        return (.coffee, "Clocked in. I'll keep the time.")
    }

    /// Stable index for "today" so a line doesn't change between renders.
    static func daySeed(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let origin = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func hours(_ value: Double) -> String {
        AppTheme.Format.hours(value)
    }

    static func pick(_ options: [String], seed: Int) -> String {
        guard !options.isEmpty else { return "" }
        let index = ((seed % options.count) + options.count) % options.count
        return options[index]
    }
}
