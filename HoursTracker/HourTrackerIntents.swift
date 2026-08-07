import AppIntents
import Foundation

// MARK: - Siri / Shortcuts (Hour Tracker Pro)
//
// All three intents open the app before running (`openAppWhenRun = true`).
// Clock in/out mutate real app state (`LiveShiftManager`, `HoursStore`) and
// need to run in-process against the live singletons rather than a
// freshly-constructed, un-synced store — see `HoursStore.current`.

private let needsProDialog: IntentDialog =
    "Siri Shortcuts need Hour Tracker Pro. Open Hour Tracker to upgrade."

struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock In"
    static var description = IntentDescription("Starts a live shift in Hour Tracker.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PremiumManager.shared.isPremium else {
            return .result(dialog: needsProDialog)
        }
        guard LiveShiftManager.shared.activeShift == nil else {
            return .result(dialog: "You're already clocked in.")
        }
        LiveShiftManager.shared.clockIn()
        return .result(dialog: "Clocked in.")
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock Out"
    static var description = IntentDescription("Ends your live shift in Hour Tracker and saves it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PremiumManager.shared.isPremium else {
            return .result(dialog: needsProDialog)
        }
        guard let store = HoursStore.current else {
            return .result(dialog: "Open Hour Tracker once, then try again.")
        }
        guard let entry = LiveShiftManager.shared.clockOut(into: store) else {
            return .result(dialog: "You're not clocked in.")
        }
        return .result(dialog: "Clocked out. Logged \(AppTheme.Format.hours(entry.paidHours)).")
    }
}

struct HoursThisWeekIntent: AppIntent {
    static var title: LocalizedStringResource = "Hours This Week"
    static var description = IntentDescription("Reads back your total hours worked this week from Hour Tracker.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PremiumManager.shared.isPremium else {
            return .result(dialog: needsProDialog)
        }
        guard let store = HoursStore.current else {
            return .result(dialog: "Open Hour Tracker once, then try again.")
        }
        guard let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else {
            return .result(dialog: "Couldn't figure out this week's range.")
        }
        var total: Double = 0
        for entry in store.entries where entry.date >= weekInterval.start && entry.date < weekInterval.end {
            total += entry.paidHours
        }
        return .result(dialog: "You've worked \(AppTheme.Format.hours(total)) this week.")
    }
}

// MARK: - App Shortcuts (auto-discoverable in Siri + the Shortcuts app)

struct HourTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Clock into \(.applicationName)"
            ],
            shortTitle: "Clock In",
            systemImageName: "clock.badge.checkmark.fill"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out with \(.applicationName)",
                "Clock out of \(.applicationName)"
            ],
            shortTitle: "Clock Out",
            systemImageName: "clock.badge.xmark.fill"
        )
        AppShortcut(
            intent: HoursThisWeekIntent(),
            phrases: [
                "How many hours have I worked this week in \(.applicationName)",
                "Check my hours in \(.applicationName)"
            ],
            shortTitle: "Hours This Week",
            systemImageName: "chart.bar.fill"
        )
    }
}
