import Foundation

/// Infers which weekdays the user usually logs from recent history.
enum WorkScheduleInference {
    /// Weekdays (1 = Sunday … 7 = Saturday) logged at least `minOccurrences` times in the lookback window.
    static func usualWorkWeekdays(
        entries: [WorkEntry],
        lookbackDays: Int = 28,
        minOccurrences: Int = 2,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<Int> {
        guard lookbackDays > 0, minOccurrences > 0 else { return [] }
        guard let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return [] }

        // Auto-filled "Off" days are entries too; counting them made every
        // weekday "usual" after a few weeks, so the "Did you work today?"
        // reminder fired on weekends and holidays.
        let recent = entries.filter { !$0.isOffDay && $0.date >= cutoff }
        var countByWeekday: [Int: Int] = (1...7).reduce(into: [:]) { $0[$1] = 0 }
        for entry in recent {
            let weekday = calendar.component(.weekday, from: entry.date)
            countByWeekday[weekday, default: 0] += 1
        }
        return Set(countByWeekday.filter { $0.value >= minOccurrences }.map(\.key))
    }
}
