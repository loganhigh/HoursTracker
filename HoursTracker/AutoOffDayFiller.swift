import Foundation

/// Fills every calendar day the user didn't open the app (and has no entry for) as an "Off" day.
/// Runs on each app open; marks all days from the user's first entry up to yesterday.
enum AutoOffDayFiller {
    /// Scope used while signed out. Markers are keyed per account so one
    /// account's progress can't hide another account's unfilled days on the
    /// same phone.
    static let localScope = "local"

    private static let lastProcessedDayKeyPrefix = "auto_off_last_processed_day"
    private static let firstEntryDayKeyPrefix = "auto_off_first_entry_day"
    /// Key written by builds that kept a single device-wide marker.
    private static let legacyLastProcessedDayKey = "auto_off_last_processed_day"

    static func makeOffDayEntries(
        entries: [WorkEntry],
        now: Date = Date(),
        calendar: Calendar = .current,
        accountScope: String = localScope,
        defaults: UserDefaults = .standard
    ) -> [WorkEntry] {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }

        // No entries yet — nothing to fill
        guard !entries.isEmpty else { return [] }

        // Only fill days on or after the user's very first logged entry
        let firstEntryDay = entries.map { calendar.startOfDay(for: $0.date) }.min() ?? today
        var scanStart = firstEntryDay

        let markerKey = key(lastProcessedDayKeyPrefix, scope: accountScope)
        let firstDayKey = key(firstEntryDayKeyPrefix, scope: accountScope)

        // Resume from where we left off last time the app was opened. The
        // marker only vouches for days it actually scanned: if entries now
        // reach EARLIER than any previous run saw (shifts backfilled for dates
        // before the first launch), the days between the new first entry and
        // the old one were never covered — rescan from the new start instead
        // of trusting the marker, or those gaps are never filled on this phone.
        let storedMarker = (defaults.object(forKey: markerKey) as? Date)
            ?? (defaults.object(forKey: legacyLastProcessedDayKey) as? Date)
        if let lastProcessed = storedMarker {
            let lastDay = calendar.startOfDay(for: lastProcessed)
            let previousFirst = (defaults.object(forKey: firstDayKey) as? Date)
                .map { calendar.startOfDay(for: $0) }
            let backfilled = previousFirst.map { firstEntryDay < $0 } ?? false
            if !backfilled,
               let dayAfter = calendar.date(byAdding: .day, value: 1, to: lastDay),
               dayAfter > scanStart {
                scanStart = dayAfter
            }
        }

        // Nothing new to process
        guard scanStart <= yesterday else {
            markProcessed(through: yesterday, firstEntryDay: firstEntryDay,
                          markerKey: markerKey, firstDayKey: firstDayKey,
                          calendar: calendar, defaults: defaults)
            return []
        }

        let loggedDays = daysCovered(by: entries, calendar: calendar)

        var newEntries: [WorkEntry] = []
        var cursor = scanStart
        while cursor <= yesterday {
            if !loggedDays.contains(cursor) {
                newEntries.append(offDayEntry(for: cursor))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        markProcessed(through: yesterday, firstEntryDay: firstEntryDay,
                      markerKey: markerKey, firstDayKey: firstDayKey,
                      calendar: calendar, defaults: defaults)
        return newEntries
    }

    /// Forget every account's markers (account deletion wipes the device).
    static func clearMarkers(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(lastProcessedDayKeyPrefix) || key.hasPrefix(firstEntryDayKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Every calendar day an entry touches. An overnight shift (end clock time
    /// before start, e.g. Sat 2pm–6am) spills into the next day, so that day
    /// counts as worked too — it must not be auto-filled as "Off".
    static func daysCovered(by entries: [WorkEntry], calendar: Calendar) -> Set<Date> {
        var days = Set<Date>()
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            days.insert(day)
            if !entry.isOffDay,
               entry.end.timeIntervalSince(entry.start) < 0,
               let next = calendar.date(byAdding: .day, value: 1, to: day) {
                days.insert(next)
            }
        }
        return days
    }

    private static func key(_ prefix: String, scope: String) -> String {
        "\(prefix)_\(scope)"
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

    private static func markProcessed(
        through day: Date,
        firstEntryDay: Date,
        markerKey: String,
        firstDayKey: String,
        calendar: Calendar,
        defaults: UserDefaults
    ) {
        defaults.set(calendar.startOfDay(for: day), forKey: markerKey)
        defaults.set(calendar.startOfDay(for: firstEntryDay), forKey: firstDayKey)
    }
}
