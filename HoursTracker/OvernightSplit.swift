import Foundation

// MARK: - Overnight shift splitting
//
// Pure calculation for the Add Shift wizard's "split at midnight" option:
// one overnight shift (e.g. Sat 2 PM → Sun 6 AM) becomes two entries — the
// pre-midnight portion on the start day and the post-midnight portion on the
// next day — so day-based pay rules (Sunday premium, Saturday OT) apply to
// the hours actually worked on each day, matching payrolls that split at
// midnight rather than attributing the whole shift to its start day.

enum OvernightSplit {

    struct Portion: Equatable {
        /// Start-of-day the portion belongs to (what `WorkEntry.date` stores).
        let date: Date
        let start: Date
        let end: Date
        let breakMinutes: Int
    }

    /// Splits an overnight shift into its two same-day portions, or returns
    /// nil when there is nothing to split:
    /// - the shift doesn't cross midnight (end after start), or
    /// - it ends exactly at midnight (the "second day" would be 0 hours).
    ///
    /// `start`/`end` follow the wizard's convention: both anchored to the
    /// selected day, with an end time-of-day at or before the start meaning
    /// "ends tomorrow" (the same convention `WorkEntry.paidHours` wraps).
    ///
    /// The break is attributed to the longer portion — a single unpaid break
    /// usually falls mid-shift, which lies inside whichever side of midnight
    /// is bigger. It is also capped so a break can never exceed the portion
    /// holding it (which would zero out that day's hours).
    static func split(
        date: Date,
        start: Date,
        end: Date,
        breakMinutes: Int,
        calendar: Calendar = .current
    ) -> (first: Portion, second: Portion)? {
        let day = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }

        // Anchor the wizard's time-of-day values onto the entry's actual days.
        let anchoredStart = merge(day: day, timeOf: start, calendar: calendar)
        let anchoredEnd = merge(day: nextDay, timeOf: end, calendar: calendar)

        // Not overnight (or zero-length second day): nothing to split.
        let secondSeconds = anchoredEnd.timeIntervalSince(nextDay)
        let firstSeconds = nextDay.timeIntervalSince(anchoredStart)
        guard merge(day: day, timeOf: end, calendar: calendar) <= anchoredStart, // crosses midnight
              secondSeconds > 0, firstSeconds > 0
        else { return nil }

        // Break rides the longer portion, capped below that portion's length
        // so the entry can never compute to zero/negative paid hours.
        let firstIsLonger = firstSeconds >= secondSeconds
        let cappedBreak = min(
            max(0, breakMinutes),
            Int((firstIsLonger ? firstSeconds : secondSeconds) / 60) - 1
        )
        let safeBreak = max(0, cappedBreak)

        // First portion ends at midnight. Stored as 12:00 AM on the same day
        // — WorkEntry's overnight wrap (+24h on a negative span) turns that
        // into the correct duration, and it displays as "… – 12:00 AM".
        let first = Portion(
            date: day,
            start: anchoredStart,
            end: day, // 12:00 AM, same-day anchor per the wizard convention
            breakMinutes: firstIsLonger ? safeBreak : 0
        )
        let second = Portion(
            date: nextDay,
            start: nextDay, // 12:00 AM on the next day
            end: anchoredEnd,
            breakMinutes: firstIsLonger ? 0 : safeBreak
        )
        return (first, second)
    }

    private static func merge(day: Date, timeOf time: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }
}
