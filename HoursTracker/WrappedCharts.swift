import SwiftUI

// MARK: - Wrapped charts
//
// Hand-rolled SwiftUI bar charts rather than the Swift Charts framework.
// Both are "native", but Swift Charts animates a series as one unit — it
// has no clean per-mark entrance delay, which is exactly what the
// sequential bar-rise these slides are built around needs. Plain shapes
// also composite more cheaply (no plot-area layout pass, no axis
// machinery) on a screen that's already animating text.
//
// Both charts take pre-computed series off WrappedYearStats. Neither
// touches WorkEntry, and neither recomputes a total.

/// One bar in a Wrapped chart.
private struct WrappedBar: View {
    let heightFraction: Double   // 0...1 of the track height
    let isHighlighted: Bool
    let isActive: Bool           // has the entrance animation been triggered
    let delay: Double
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height
            // A hair of height even at zero so an empty month/day still reads
            // as a slot on the axis rather than a gap in the chart.
            let target = max(full * heightFraction, 2)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isHighlighted ? WrappedPalette.accentGradient : WrappedPalette.barGradient)
                .frame(height: isActive || reduceMotion ? target : 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : WrappedMotion.reveal.delay(delay),
                    value: isActive
                )
        }
    }
}

// MARK: - 12-month chart

/// January → December bar chart over `WrappedYearStats.monthlyTotals`.
/// Labels stay sparse (single initials, busiest month called out separately)
/// so it reads as a shape with a story rather than a dashboard.
struct WrappedMonthlyChart: View {
    let monthlyTotals: [WrappedMonthTotal]
    let busiestMonthStart: Date?
    let isActive: Bool

    private var maxHours: Double {
        max(monthlyTotals.map(\.hours).max() ?? 0, 0.0001) // avoid /0 on an empty year
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(monthlyTotals.enumerated()), id: \.element.monthStart) { index, month in
                    WrappedBar(
                        heightFraction: month.hours / maxHours,
                        isHighlighted: month.monthStart == busiestMonthStart,
                        isActive: isActive,
                        delay: WrappedMotion.barStagger(index),
                        cornerRadius: 3
                    )
                }
            }
            .frame(height: 120)

            // Single-letter month initials: enough to orient Jan→Dec without
            // 12 rotated labels turning this into an analytics screen.
            HStack(spacing: 5) {
                ForEach(Array(monthlyTotals.enumerated()), id: \.element.monthStart) { _, month in
                    Text(WrappedFormat.monthInitial(month.monthStart))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            month.monthStart == busiestMonthStart
                                ? WrappedPalette.accent
                                : WrappedPalette.secondaryText.opacity(0.7)
                        )
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - 7-day week chart

/// Monday → Sunday bar chart over `WrappedYearStats.busiestWeekDailyTotals`,
/// with the heaviest day of that week highlighted and labelled.
struct WrappedWeekChart: View {
    let dailyTotals: [WrappedDayTotal]
    let isActive: Bool

    private var maxHours: Double {
        max(dailyTotals.map(\.hours).max() ?? 0, 0.0001)
    }

    /// The heaviest day within this week. Ties resolve to the earliest day,
    /// matching how the engine breaks ties for busiest day/week/month.
    private var peakDay: Date? {
        dailyTotals
            .filter { $0.hours > 0 }
            .max { ($0.hours, $1.day) < ($1.hours, $0.day) }?
            .day
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(dailyTotals.enumerated()), id: \.element.day) { index, day in
                    VStack(spacing: 6) {
                        // Hours label rides above its bar, fading in after it.
                        Text(day.hours > 0 ? WrappedFormat.compactHours(day.hours) : "–")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                day.day == peakDay
                                    ? WrappedPalette.accent
                                    : WrappedPalette.secondaryText
                            )
                            .opacity(isActive ? 1 : 0)
                            .animation(
                                WrappedMotion.reveal.delay(WrappedMotion.barStagger(index, step: 0.07) + 0.18),
                                value: isActive
                            )

                        WrappedBar(
                            heightFraction: day.hours / maxHours,
                            isHighlighted: day.day == peakDay,
                            isActive: isActive,
                            delay: WrappedMotion.barStagger(index, step: 0.07),
                            cornerRadius: 5
                        )
                        .frame(height: 110)

                        Text(WrappedFormat.weekdayInitial(day.day))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                day.day == peakDay
                                    ? WrappedPalette.accent
                                    : WrappedPalette.secondaryText.opacity(0.7)
                            )
                    }
                }
            }
        }
    }
}

// MARK: - Proportional comparison bar

/// A single split bar showing two proportional segments — used for the
/// weekday/weekend comparison, where a proportional shape communicates the
/// split faster than two numbers do.
struct WrappedProportionBar: View {
    let leadingValue: Double
    let trailingValue: Double
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leadingFraction: Double {
        let total = leadingValue + trailingValue
        guard total > 0 else { return 0.5 }
        return leadingValue / total
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WrappedPalette.barGradient)
                    .frame(width: max((isActive || reduceMotion ? leadingFraction : 0.5) * width - 2, 0))

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WrappedPalette.accentGradient)
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : WrappedMotion.reveal.delay(0.2),
                value: isActive
            )
        }
        .frame(height: 26)
    }
}
