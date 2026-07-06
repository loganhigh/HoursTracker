import Foundation

/// Fills every calendar day the user didn't open the app (and has no entry for) as an "Off" day.
/// Runs on each app open; marks all days from the user's first entry up to yesterday.
enum AutoOffDayFiller {
    private static let lastProcessedDayKey = "auto_off_last_processed_day"

    static func makeOffDayEntries(
        entries: [WorkEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkEntry] {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }

        // No entries yet — nothing to fill
        guard !entries.isEmpty else { return [] }

        // Only fill days on or after the user's very first logged entry
        let firstEntryDay = entries.map { calendar.startOfDay(for: $0.date) }.min() ?? today
        var scanStart = firstEntryDay

        // Resume from where we left off last time the app was opened
        if let lastProcessed = UserDefaults.standard.object(forKey: lastProcessedDayKey) as? Date {
            let lastDay = calendar.startOfDay(for: lastProcessed)
            if let dayAfter = calendar.date(byAdding: .day, value: 1, to: lastDay),
               dayAfter > scanStart {
                scanStart = dayAfter
            }
        }

        // Nothing new to process
        guard scanStart <= yesterday else {
            markProcessed(through: yesterday, calendar: calendar)
            return []
        }

        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.date) })

        var newEntries: [WorkEntry] = []
        var cursor = scanStart
        while cursor <= yesterday {
            if !loggedDays.contains(cursor) {
                newEntries.append(offDayEntry(for: cursor))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        markProcessed(through: yesterday, calendar: calendar)
        return newEntries
    }

    private static func offDayEntry(for day: Date) -> WorkEntry {
        WorkEntry(
            date: day,
            start: day,
            end: day,
            breakMinutes: 0,
            notes: "",
            isOffDay: true,
            offDayReason: "Off"
        )
    }

    private static func markProcessed(through day: Date, calendar: Calendar) {
        UserDefaults.standard.set(calendar.startOfDay(for: day), forKey: lastProcessedDayKey)
    }
}
