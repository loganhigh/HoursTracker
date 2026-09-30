import AppIntents
import Foundation

// MARK: - Siri: clock in / clock out
//
// The live shift is driven by voice: "Hey Siri, clock in to Hour Tracker"
// starts it (Dynamic Island + Lock Screen card take over from there), and
// "Hey Siri, just finished work in Hour Tracker" clocks out and logs the
// shift through the same path as a hand-entered one. Neither opens the app.
// Apple requires the app name in every phrase; `INAlternativeAppNames`
// lets people say "Hours" or "Tracker" instead.

private let needsLaunchDialog: IntentDialog = "Open Hour Tracker once, then try again."

/// `LiveActivityIntent`: without it ActivityKit refuses to start an
/// activity from a Siri/Shortcuts run while the app is in the background.
struct ClockInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Starts a live shift in Hour Tracker right now.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard HoursStore.current != nil else { return .result(dialog: needsLaunchDialog) }
        let live = LiveShiftManager.shared
        if let shift = live.activeShift {
            return .result(dialog: "You're already clocked in — since \(shift.startDate.formatted(date: .omitted, time: .shortened)).")
        }
        let now = Date()
        live.clockIn(at: now)
        return .result(dialog: "Clocked in at \(now.formatted(date: .omitted, time: .shortened)). Have a good one.")
    }
}

struct ClockOutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("Ends the live shift in Hour Tracker and logs it.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = HoursStore.current else { return .result(dialog: needsLaunchDialog) }
        let live = LiveShiftManager.shared
        guard let shift = live.activeShift else {
            return .result(dialog: "You're not clocked in right now.")
        }
        let now = Date()
        guard let entry = live.clockOut(at: now, into: store) else {
            let worked = shift.elapsedWorked(at: now)
            return .result(dialog: worked > 24 * 3600
                ? "That shift is over 24 hours, so I couldn't save it. Open Hour Tracker to sort it out."
                : "That shift is too short to save yet.")
        }
        var dialog = "Shift logged: \(AppTheme.Format.hours(entry.paidHours))"
        if store.paySettings.hourlyRateSet, store.paySettings.hourlyWage > 0 {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = store.paySettings.currencyCode
            if let money = f.string(from: NSNumber(value: store.payBreakdown(for: entry).pay)) {
                dialog += ", about \(money) before deductions"
            }
        }
        return .result(dialog: "\(dialog). Nice work.")
    }
}

struct ShiftStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Am I Clocked In?"
    static var description = IntentDescription("Reads back how long the live shift has been running.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let shift = LiveShiftManager.shared.activeShift else {
            return .result(dialog: "You're not clocked in.")
        }
        let worked = shift.elapsedWorked(at: Date()) / 3600
        let since = shift.startDate.formatted(date: .omitted, time: .shortened)
        return .result(dialog: shift.isOnBreak
            ? "You're on break. \(AppTheme.Format.hours(worked)) worked since \(since)."
            : "You've been clocked in since \(since) — \(AppTheme.Format.hours(worked)) so far.")
    }
}
