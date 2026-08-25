import Foundation

// MARK: - Wrapped slide list
//
// The single source of truth for "which slides exist for this user's
// stats." WrappedView never hardcodes a slide count or index — it always
// asks `availableSlides(for:)` and renders whatever comes back, so a slide
// that would show bogus/empty data for a low-activity year is simply
// omitted rather than rendered blank.

enum WrappedSlideType: CaseIterable {
    case intro
    case totalHours
    case totalShifts
    case biggestMonth
    case longestShift
    case workSchedule
    case longShiftBreakdown
    case biggestWeek
    case weekendVsWeekday
    case workStreak
    case workerPersonality
    case finalSummary

    /// The ordered list of slides worth showing for `stats`. Each condition
    /// mirrors what that slide actually displays — if the underlying field
    /// is nil/zero, the slide would either be blank or misleading, so it's
    /// left out rather than rendered.
    static func availableSlides(for stats: WrappedYearStats) -> [WrappedSlideType] {
        var slides: [WrappedSlideType] = [.intro]

        if stats.totalHours > 0 {
            slides.append(.totalHours)
        }
        if stats.totalShifts > 0 {
            slides.append(.totalShifts)
        }
        if stats.busiestMonth != nil {
            slides.append(.biggestMonth)
        }
        if stats.longestShiftHours > 0, stats.longestShiftDate != nil {
            slides.append(.longestShift)
        }
        if stats.earliestShiftStart != nil, stats.latestShiftEnd != nil {
            slides.append(.workSchedule)
        }
        if stats.shiftsOver8Hours > 0 {
            slides.append(.longShiftBreakdown)
        }
        if stats.busiestWeek != nil {
            slides.append(.biggestWeek)
        }
        if stats.totalHours > 0 {
            slides.append(.weekendVsWeekday)
        }
        // "Only show if meaningful" — a 1-2 day streak isn't worth a slide
        // of its own; it reads as padding rather than an insight.
        if stats.longestStreakDays >= 3 {
            slides.append(.workStreak)
        }
        if stats.totalShifts > 0 {
            slides.append(.workerPersonality)
        }

        // Final summary always shows, even for a near-empty year — it's the
        // "here's what we've got" close, not a data-dependent insight.
        slides.append(.finalSummary)

        return slides
    }
}
