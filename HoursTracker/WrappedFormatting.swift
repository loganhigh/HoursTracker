import Foundation

// MARK: - Wrapped display formatting
//
// Pure string formatting only — every value formatted here comes from an
// already-computed WrappedYearStats field. No stat is recalculated or
// re-derived from WorkEntry here; that would defeat the point of having a
// single trusted WrappedStatsEngine.

enum WrappedFormat {
    /// "9h 14m" — hours + minutes, for durations. Whole-hour durations drop
    /// the minutes ("8h" not "8h 0m").
    static func hoursAndMinutes(_ hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0h" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// A duration mid count-up toward `target`, in the shape the final
    /// value will have so the text never changes form while counting.
    /// Lands on exactly `hoursAndMinutes(target)`.
    ///
    /// Only the hours count; the minutes sit at their final value the whole
    /// time. Counting minutes made them spin 0→59 once per hour, which read
    /// as a glitchy number scramble next to the other slides' smooth counts.
    static func countingDuration(_ hours: Double, target: Double) -> String {
        let targetMinutes = Int((max(target, 0) * 60).rounded())
        let targetHours = targetMinutes / 60
        let minutes = targetMinutes % 60
        let shownHours = hours.isFinite ? min(max(Int(hours.rounded(.down)), 0), targetHours) : 0
        let finalHours = hours.isFinite && hours >= target ? targetHours : shownHours
        return minutes == 0 ? "\(finalHours)h" : "\(finalHours)h \(minutes)m"
    }

    /// "2,847" — grouped integer, for large whole-number stats like total
    /// shifts. Native SwiftUI/Foundation number formatting, not manual
    /// string math.
    static func groupedInt(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// "2,847" — grouped, rounded-to-whole-number hours for hero displays
    /// where a decimal would clutter a large headline number.
    static func groupedWholeHours(_ hours: Double) -> String {
        groupedInt(Int(hours.rounded()))
    }

    /// "327.5" — one decimal place, grouped, for hour totals shown at a
    /// smaller supporting scale (e.g. a monthly/weekly total) where the
    /// fractional hour is still worth showing.
    static func oneDecimalHours(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(1)).grouping(.automatic))
    }

    /// "4:47 AM" — time-of-day only, from a full Date.
    static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "Jul 12" — short month + day.
    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// "Jul 12, 2026" — short month + day + year.
    static func shortDateWithYear(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// "JULY" — full month name, uppercased, for hero-style month displays.
    static func fullMonthUppercased(_ monthStart: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM"
        return formatter.string(from: monthStart).uppercased()
    }

    /// "Week of Jul 7" — for a week-start date.
    static func weekOfLabel(_ weekStart: Date, calendar: Calendar = .current) -> String {
        "Week of \(shortDate(weekStart, calendar: calendar))"
    }

    /// "J", "F", "M"… — single-letter month initial for a compact 12-month
    /// chart axis.
    static func monthInitial(_ monthStart: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMMM" // narrow month symbol
        return formatter.string(from: monthStart)
    }

    /// "M", "T", "W"… — single-letter weekday initial for the seven-day chart.
    static func weekdayInitial(_ day: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEEE" // narrow weekday symbol
        return formatter.string(from: day)
    }

    /// "12" / "9.5" — shortest readable hour figure for a chart label, where
    /// a trailing ".0" is noise.
    static func compactHours(_ hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0" }
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(hours))"
        }
        return hours.formatted(.number.precision(.fractionLength(1)))
    }
}
