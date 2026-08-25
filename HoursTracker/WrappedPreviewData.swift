#if DEBUG
import SwiftUI

// MARK: - Wrapped previews (DEBUG only)
//
// Wrapped normally lives behind sign-in, which makes it slow to eyeball
// during development. These previews build realistic WrappedYearStats
// through the real WrappedStatsEngine — no hand-written stat values — so
// what the canvas shows is what the app computes.
//
// The whole file compiles out of Release.

enum WrappedPreviewData {

    private static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday, matching HoursStore
        return cal
    }

    private static func entry(
        year: Int, month: Int, day: Int,
        startHour: Int, endHour: Int
    ) -> WorkEntry {
        let cal = calendar
        var start = DateComponents(year: year, month: month, day: day, hour: startHour)
        var end = DateComponents(year: year, month: month, day: day, hour: endHour)
        var date = DateComponents(year: year, month: month, day: day)
        start.timeZone = cal.timeZone
        end.timeZone = cal.timeZone
        date.timeZone = cal.timeZone
        return WorkEntry(
            date: cal.date(from: date)!,
            start: cal.date(from: start)!,
            end: cal.date(from: end)!,
            breakMinutes: 0,
            notes: ""
        )
    }

    /// A full, varied year — every slide qualifies. Roughly a heavy-trades
    /// schedule: ~18 shifts a month, a brutal June streak, a heavier July,
    /// some weekend work, an early start and a late finish.
    static var busyYear: WrappedYearStats {
        let year = Calendar.current.component(.year, from: Date())
        var entries: [WorkEntry] = []

        for month in 1...12 {
            let extraDays = (month == 7) ? 6 : 0
            for day in 1...(18 + extraDays) {
                entries.append(entry(year: year, month: month, day: day,
                                     startHour: 7, endHour: month == 7 ? 19 : 16))
            }
        }
        // A 13-day June run of 14h days: drives the streak + long-shift slides.
        for day in 10...22 {
            entries.append(entry(year: year, month: 6, day: day, startHour: 5, endHour: 19))
        }
        // One very early start and one very late finish for the schedule slide.
        entries.append(entry(year: year, month: 3, day: 24, startHour: 4, endHour: 12))
        entries.append(entry(year: year, month: 9, day: 12, startHour: 14, endHour: 23))

        return WrappedStatsEngine.compute(
            year: year,
            entries: entries,
            calendar: calendar,
            sourcedFromArchive: true
        )
    }

    /// A light year — several slides are skipped, so the progress bar has
    /// fewer segments. Useful for checking the low-data path.
    static var quietYear: WrappedYearStats {
        let year = Calendar.current.component(.year, from: Date())
        let entries = [
            entry(year: year, month: 4, day: 8, startHour: 9, endHour: 13),
            entry(year: year, month: 4, day: 9, startHour: 9, endHour: 14),
        ]
        return WrappedStatsEngine.compute(
            year: year, entries: entries, calendar: calendar, sourcedFromArchive: false
        )
    }

    /// A year with no shifts at all — should show intro + summary only.
    static var emptyYear: WrappedYearStats {
        WrappedStatsEngine.compute(
            year: Calendar.current.component(.year, from: Date()),
            entries: [],
            calendar: calendar,
            sourcedFromArchive: false
        )
    }
}

// MARK: - Whole-story previews
//
// Use the canvas in Live/interactive mode: tap the right side to advance,
// the left side to go back, exactly as in the app.

#Preview("Wrapped — full year") {
    WrappedView(stats: WrappedPreviewData.busyYear, username: "logan")
}

#Preview("Wrapped — quiet year (slides skipped)") {
    WrappedView(stats: WrappedPreviewData.quietYear, username: "logan")
}

#Preview("Wrapped — empty year") {
    WrappedView(stats: WrappedPreviewData.emptyYear, username: "logan")
}

// MARK: - Individual slide previews
//
// Faster than tapping through the story when iterating on one slide.

#Preview("Slide — Total Hours") {
    WrappedTotalHoursSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Total Shifts") {
    WrappedTotalShiftsSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Biggest Month") {
    WrappedBiggestMonthSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Longest Shift") {
    WrappedLongestShiftSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Work Schedule") {
    WrappedWorkScheduleSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Long Shift Breakdown") {
    WrappedLongShiftBreakdownSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Biggest Week") {
    WrappedBiggestWeekSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Weekend vs Weekday") {
    WrappedWeekendVsWeekdaySlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Work Streak") {
    WrappedWorkStreakSlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Worker Personality") {
    WrappedWorkerPersonalitySlide(stats: WrappedPreviewData.busyYear)
}

#Preview("Slide — Final Summary") {
    WrappedFinalSummarySlide(stats: WrappedPreviewData.busyYear, username: "logan")
}
#endif
