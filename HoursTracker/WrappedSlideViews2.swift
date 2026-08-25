import SwiftUI

// MARK: - Wrapped slides, part 2 (Long Shift Breakdown through Final Summary)
//
// Same rules as part 1: read-only from WrappedYearStats, no recomputation,
// motion driven by WrappedSlideAppearance with Reduce Motion handled inside
// the shared primitives.

struct WrappedLongShiftBreakdownSlide: View {
    let stats: WrappedYearStats

    /// Thresholds ordered light → heavy. Each step up gets a hotter tint and
    /// a stronger fill, so "over 14h" visibly outranks "over 8h" instead of
    /// four identical rows.
    private var thresholds: [(label: String, count: Int, tint: Color, intensity: Double)] {
        [
            ("Over 8 Hours", stats.shiftsOver8Hours, Color(hex: 0x7FC8F8), 0.18),
            ("Over 10 Hours", stats.shiftsOver10Hours, Color(hex: 0xF5C518), 0.26),
            ("Over 12 Hours", stats.shiftsOver12Hours, Color(hex: 0xE0932B), 0.34),
            ("Over 14 Hours", stats.shiftsOver14Hours, Color(hex: 0xE0563B), 0.44),
        ]
    }

    var body: some View {
        ZStack {
            WrappedBackdrop(tint: Color(hex: 0xE0932B))
            WrappedSlideAppearance { appeared, _ in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "The Long Ones")
                        .wrappedReveal(appeared, index: 0)

                    VStack(spacing: 10) {
                        ForEach(Array(thresholds.enumerated()), id: \.element.label) { index, threshold in
                            WrappedThresholdRow(
                                label: threshold.label,
                                count: threshold.count,
                                tint: threshold.tint,
                                intensity: threshold.intensity
                            )
                            .wrappedReveal(appeared, index: index + 1, yOffset: 16)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

private struct WrappedThresholdRow: View {
    let label: String
    let count: Int
    let tint: Color
    let intensity: Double

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(WrappedPalette.primaryText.opacity(0.9))
            Spacer()
            Text("\(count)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(intensity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(intensity + 0.2), lineWidth: 1)
        )
    }
}

struct WrappedBiggestWeekSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        if let busiestWeek = stats.busiestWeek {
            ZStack {
                WrappedBackdrop()
                WrappedSlideAppearance(
                    countTarget: busiestWeek.hours,
                    countDelay: 0.2,
                    haptic: .light
                ) { appeared, count in
                    WrappedSlideScaffold {
                        WrappedEyebrow(text: "Your Biggest Week")
                            .wrappedReveal(appeared, index: 0)

                        WrappedCountingText(
                            value: count,
                            font: .system(size: 64, weight: .black, design: .rounded),
                            format: { "\(WrappedFormat.compactHours($0))h" }
                        )
                        .wrappedReveal(appeared, index: 1, yOffset: 0, scaleFrom: 0.7)

                        Text(WrappedFormat.weekOfLabel(busiestWeek.weekStart))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(WrappedPalette.secondaryText)
                            .wrappedReveal(appeared, index: 2)

                        // Mon→Sun breakdown of that exact week, bars rising
                        // in sequence with the heaviest day picked out.
                        WrappedWeekChart(
                            dailyTotals: stats.busiestWeekDailyTotals,
                            isActive: appeared
                        )
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.22), value: appeared)
                    }
                }
            }
        }
    }
}

struct WrappedWeekendVsWeekdaySlide: View {
    let stats: WrappedYearStats

    var body: some View {
        ZStack {
            WrappedBackdrop(tint: Color(hex: 0x5B8DEF))
            WrappedSlideAppearance { appeared, _ in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "Weekday vs Weekend")
                        .wrappedReveal(appeared, index: 0)

                    // Proportional split reads faster than two numbers.
                    WrappedProportionBar(
                        leadingValue: stats.weekdayHours,
                        trailingValue: stats.weekendHours,
                        isActive: appeared
                    )
                    .wrappedReveal(appeared, index: 1, yOffset: 10)
                    .padding(.top, 6)

                    HStack(alignment: .top, spacing: 0) {
                        WrappedSplitLegend(
                            label: "Weekday",
                            value: WrappedFormat.oneDecimalHours(stats.weekdayHours),
                            swatch: WrappedPalette.barGradient
                        )
                        .frame(maxWidth: .infinity)

                        WrappedSplitLegend(
                            label: "Weekend",
                            value: WrappedFormat.oneDecimalHours(stats.weekendHours),
                            swatch: WrappedPalette.accentGradient
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .wrappedReveal(appeared, index: 2, yOffset: 16)
                    .padding(.top, 4)

                    VStack(spacing: 8) {
                        WrappedStatRow(label: "Saturday", value: "\(WrappedFormat.oneDecimalHours(stats.saturdayHours))h")
                            .wrappedReveal(appeared, index: 4, yOffset: 14)
                        WrappedStatRow(label: "Sunday", value: "\(WrappedFormat.oneDecimalHours(stats.sundayHours))h")
                            .wrappedReveal(appeared, index: 5, yOffset: 14)
                        WrappedStatRow(label: "Weekend Shifts", value: "\(stats.weekendShiftCount)")
                            .wrappedReveal(appeared, index: 6, yOffset: 14)
                    }
                    .padding(.top, 20)
                }
            }
        }
    }
}

private struct WrappedSplitLegend: View {
    let label: String
    let value: String
    let swatch: LinearGradient

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatch)
                .frame(width: 26, height: 6)
            WrappedEyebrow(text: label)
            Text("\(value)h")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(WrappedPalette.primaryText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

struct WrappedWorkStreakSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        ZStack {
            WrappedBackdrop(tint: Color(hex: 0xE0563B))
            WrappedSlideAppearance(
                countTarget: Double(stats.longestStreakDays),
                countDelay: 0.2,
                haptic: .success
            ) { appeared, count in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "Longest Streak")
                        .wrappedReveal(appeared, index: 0)

                    WrappedStreakFlame(isActive: appeared)
                        .wrappedReveal(appeared, index: 1, yOffset: 0, scaleFrom: 0.5)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        WrappedCountingText.wholeNumber(
                            value: count,
                            font: .system(size: 76, weight: .black, design: .rounded)
                        )
                        Text("DAYS")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(WrappedPalette.accent)
                    }
                    .wrappedReveal(appeared, index: 2, yOffset: 0, scaleFrom: 0.72)

                    WrappedSupportingLine(text: "Worked back to back, no days off.")
                        .wrappedReveal(appeared, index: 5)
                        .padding(.top, 8)
                }
            }
        }
    }
}

/// Flame mark with a short, finite pulse. Deliberately not `repeatForever`:
/// an always-running animation on a screen the user may sit on keeps the
/// render loop awake for no real benefit. Three beats reads as "alive," then
/// it settles.
private struct WrappedStreakFlame: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 56, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: 0xFFD166), Color(hex: 0xE0563B)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .scaleEffect(pulse ? 1.08 : 1.0)
            .onChange(of: isActive) { _, active in
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct WrappedWorkerPersonalitySlide: View {
    let stats: WrappedYearStats

    var body: some View {
        ZStack {
            WrappedBackdrop(tint: Color(hex: 0x7A5CE0))
            // The biggest reveal in the story: the label holds alone for a
            // beat, then the type lands hard with a success haptic.
            WrappedSlideAppearance(countDelay: 0, haptic: .success) { appeared, _ in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "Your Worker Type")
                        .wrappedReveal(appeared, index: 0)

                    // Scoring is untouched — this only renders the existing
                    // deterministic WorkerPersonalityResult.
                    WrappedHero(text: stats.personality.type.rawValue.uppercased(), size: 44)
                        .wrappedReveal(appeared, index: 4, yOffset: 34, scaleFrom: 0.72)
                        .padding(.top, 8)

                    Rectangle()
                        .fill(WrappedPalette.accent)
                        .frame(width: 54, height: 3)
                        .wrappedReveal(appeared, index: 6, yOffset: 0, scaleFrom: 0.2)
                        .padding(.vertical, 6)

                    WrappedSupportingLine(text: stats.personality.type.tagline)
                        .wrappedReveal(appeared, index: 7)
                }
            }
        }
    }
}

// NOTE: WrappedFinalSummarySlide (plus WrappedSummaryMetric / WrappedSummaryLine)
// now lives in WrappedFinalSummaryView.swift, where it gained the optional
// Rive celebration layer.
