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
