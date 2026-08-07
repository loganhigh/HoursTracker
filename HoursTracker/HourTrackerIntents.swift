import AppIntents
import Foundation

// MARK: - Siri / Shortcuts (Hour Tracker Pro)
//
// `AddShiftIntent` is the headline voice flow — "Hey Siri, add a shift today
// from 8am to 4pm" logs the entry outright, no app UI. It runs without
// opening the app (`openAppWhenRun = false`) so the whole interaction stays
// in Siri; it still needs the live `HoursStore` (see `HoursStore.current`)
// so the save goes through the same path as a manually-entered shift, which
// means the app must have been launched at least once since boot.

private let needsProDialog: IntentDialog =
    "Siri Shortcuts need Hour Tracker Pro. Open Hour Tracker to upgrade."

private let needsLaunchDialog: IntentDialog =
    "Open Hour Tracker once, then try again."

struct AddShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Shift"
    static var description = IntentDescription("Logs a shift in Hour Tracker for a given day and time range.")
    /// Stays in Siri — the point is to log a shift without touching the app.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Start Time")
    var startTime: DateComponents

    @Parameter(title: "End Time")
    var endTime: DateComponents

    @Parameter(title: "Date")
    var date: DateComponents?

    static var parameterSummary: some ParameterSummary {
        Summary("Add a shift on \(\.$date) from \(\.$startTime) to \(\.$endTime)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PremiumManager.shared.isPremium else {
            return .result(dialog: needsProDialog)
        }
        guard let store = HoursStore.current else {
            return .result(dialog: needsLaunchDialog)
        }

        let cal = Calendar.current
        let day = cal.startOfDay(for: date.flatMap { cal.date(from: $0) } ?? Date())
        guard let start = merge(day: day, time: startTime, calendar: cal),
              let end = merge(day: day, time: endTime, calendar: cal) else {
            return .result(dialog: "I couldn't read those times.")
        }

        let entry = WorkEntry(
            date: day,
            start: start,
            end: end,
            breakMinutes: 0,
            notes: "",
            isOffDay: false,
            offDayReason: "",
            isHoliday: false
        )
        // Same validation the entry editor and live-shift engine apply.
        guard entry.paidHours > 0, entry.paidHours <= 48 else {
            return .result(dialog: "That shift length doesn't look right — check the start and end times.")
        }

        store.add(entry)

        let dayText = cal.isDateInToday(day)
            ? "today"
            : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return .result(dialog: "Added \(AppTheme.Format.hours(entry.paidHours)) for \(dayText).")
    }

    /// The day's date component carrying the spoken time's hour/minute,
    /// seconds zeroed — matches how the entry editor builds its dates, so an
    /// overnight range (end < start) resolves through `WorkEntry.paidHours`'
    /// +24h wrap exactly as a hand-logged shift does.
    private func merge(day: Date, time: DateComponents, calendar cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = time.hour
        comps.minute = time.minute ?? 0
        comps.second = 0
        return cal.date(from: comps)
    }
}

struct HoursThisWeekIntent: AppIntent {
    static var title: LocalizedStringResource = "Hours This Week"
    static var description = IntentDescription("Reads back your total hours worked this week from Hour Tracker.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PremiumManager.shared.isPremium else {
            return .result(dialog: needsProDialog)
        }
        guard let store = HoursStore.current else {
            return .result(dialog: needsLaunchDialog)
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
            intent: AddShiftIntent(),
            phrases: [
                "Add a shift to \(.applicationName)",
                "Add a shift in \(.applicationName)",
                "Log a shift in \(.applicationName)",
                "Log hours in \(.applicationName)"
            ],
            shortTitle: "Add a Shift",
            systemImageName: "plus.circle.fill"
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
