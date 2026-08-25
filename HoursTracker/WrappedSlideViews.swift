import SwiftUI

// MARK: - Wrapped slides, part 1 (Intro through Work Schedule)
//
// Every slide reads only from an already-computed WrappedYearStats — none
// of these views touch WorkEntry, HoursStore, or recompute a statistic. A
// slide is only ever shown when WrappedSlideType.availableSlides(for:)
// confirmed its underlying data is meaningful.
//
// Motion convention: each slide wraps its content in WrappedSlideAppearance,
// which supplies one `appeared` flag (drives every staggered entrance) and
// one animated `count` value (drives the hero number). Reduce Motion is
// handled inside those primitives — content always appears, it just stops
// travelling and counting.

struct WrappedIntroSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        ZStack {
            WrappedBackdrop()
            WrappedSlideAppearance { appeared, _ in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "Your \(String(stats.year))")
                        .wrappedReveal(appeared, index: 0)

                    WrappedHero(text: "IN HOURS", size: 52)
                        .wrappedReveal(appeared, index: 1, yOffset: 30, scaleFrom: 0.86)

                    WrappedSupportingLine(text: "Tap to begin")
                        .wrappedReveal(appeared, index: 3)
                        .padding(.top, 12)
                }
            }
        }
    }
}

struct WrappedTotalHoursSlide: View {
    let stats: WrappedYearStats

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstFired = false
    @State private var burstFinished = false

    private var burstAsset: WrappedRiveAsset { .wrappedFinale }

    /// The burst only exists between the count landing and the animation
    /// finishing — outside that window the view tree is exactly the native
    /// slide it was before.
    private var showsBurst: Bool {
        burstFired && !burstFinished && !reduceMotion && burstAsset.isPlayable
    }

    var body: some View {
        ZStack {
            WrappedBackdrop()
            // The hero count is the whole slide here, so it gets the medium
            // haptic as it lands and the largest type in the story.
            WrappedSlideAppearance(
                countTarget: stats.totalHours,
                countDelay: 0.25,
                haptic: .medium,
                // Fires on the exact frame the number reaches its final
                // value, so the burst lands on the beat rather than on a
                // hardcoded guess at the count's duration.
                onCountSettled: { burstFired = true }
            ) { appeared, count in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "You worked")
                        .wrappedReveal(appeared, index: 0)

                    WrappedCountingText.wholeNumber(
                        value: count,
                        font: .system(size: 88, weight: .black, design: .rounded)
                    )
                    .wrappedReveal(appeared, index: 1, yOffset: 0, scaleFrom: 0.62)

                    WrappedEyebrow(text: "Hours", color: WrappedPalette.accent)
                        .wrappedReveal(appeared, index: 2)

                    WrappedSupportingLine(
                        text: "Across \(WrappedFormat.groupedInt(stats.totalShifts)) shifts."
                    )
                    .wrappedReveal(appeared, index: 4)
                    .padding(.top, 10)
                }
            }

            // Decorative burst on the beat the number lands. Never
            // interactive, so a tap to advance still passes through it.
            if showsBurst {
                WrappedRiveView(
                    asset: burstAsset,
                    onFinished: { burstFinished = true }
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}

struct WrappedTotalShiftsSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        ZStack {
            WrappedBackdrop(tint: Color(hex: 0x5B8DEF))
            WrappedSlideAppearance(countTarget: Double(stats.totalShifts), countDelay: 0.2) { appeared, count in
                WrappedSlideScaffold {
                    WrappedEyebrow(text: "You clocked")
                        .wrappedReveal(appeared, index: 0)

                    WrappedCountingText.wholeNumber(
                        value: count,
                        font: .system(size: 76, weight: .black, design: .rounded)
                    )
                    .wrappedReveal(appeared, index: 1, yOffset: 0, scaleFrom: 0.7)

                    WrappedEyebrow(text: "Shifts", color: WrappedPalette.accent)
                        .wrappedReveal(appeared, index: 2)

                    // Deliberately staggered well after the count so the two
                    // figures read as separate beats, not one block of text.
                    VStack(spacing: 4) {
                        WrappedEyebrow(text: "Average shift")
                        Text(WrappedFormat.hoursAndMinutes(stats.averageShiftLengthHours))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(WrappedPalette.primaryText)
                    }
                    .wrappedReveal(appeared, index: 6, yOffset: 18)
                    .padding(.top, 22)
                }
            }
        }
    }
}

struct WrappedBiggestMonthSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        // WrappedSlideType only includes this slide when busiestMonth != nil.
        if let busiestMonth = stats.busiestMonth {
            ZStack {
                WrappedBackdrop()
                WrappedSlideAppearance(haptic: .light) { appeared, _ in
                    WrappedSlideScaffold {
                        WrappedEyebrow(text: "Your Biggest Month")
                            .wrappedReveal(appeared, index: 0)

                        WrappedHero(
                            text: WrappedFormat.fullMonthUppercased(busiestMonth.monthStart),
                            size: 54
                        )
                        .wrappedReveal(appeared, index: 1, yOffset: 20, scaleFrom: 0.8)

                        Text("\(WrappedFormat.oneDecimalHours(busiestMonth.hours)) hours")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(WrappedPalette.accent)
                            .wrappedReveal(appeared, index: 2)

                        // Full Jan–Dec context, bars rising in sequence.
                        WrappedMonthlyChart(
                            monthlyTotals: stats.monthlyTotals,
                            busiestMonthStart: busiestMonth.monthStart,
                            isActive: appeared
                        )
                        .padding(.top, 26)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.25), value: appeared)
                    }
                }
            }
        }
    }
}

struct WrappedLongestShiftSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        if let date = stats.longestShiftDate {
            ZStack {
                WrappedBackdrop(tint: Color(hex: 0xE0563B))
                WrappedSlideAppearance(
                    countTarget: stats.longestShiftHours,
                    countDelay: 0.22,
                    haptic: .medium
                ) { appeared, count in
                    WrappedSlideScaffold {
                        WrappedEyebrow(text: "Longest Shift")
                            .wrappedReveal(appeared, index: 0)

                        // Counts up in h/m form, so the minutes tick into
                        // place rather than the whole duration cross-fading.
                        WrappedCountingText(
                            value: count,
                            font: .system(size: 68, weight: .black, design: .rounded),
                            format: { WrappedFormat.hoursAndMinutes($0) }
                        )
                        .wrappedReveal(appeared, index: 1, yOffset: 0, scaleFrom: 0.68)

                        // Date stays deliberately quiet — it's context, not
                        // the headline.
                        Text(WrappedFormat.shortDateWithYear(date))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(WrappedPalette.secondaryText)
                            .wrappedReveal(appeared, index: 5)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }
}

struct WrappedWorkScheduleSlide: View {
    let stats: WrappedYearStats

    var body: some View {
        if let earliest = stats.earliestShiftStart, let latest = stats.latestShiftEnd {
            ZStack {
                WrappedBackdrop(tint: Color(hex: 0x7A5CE0))
                WrappedSlideAppearance { appeared, _ in
                    WrappedSlideScaffold {
                        WrappedEyebrow(text: "Your Hours")
                            .wrappedReveal(appeared, index: 0)

                        // Day → night band: a single gradient standing in for
                        // a 24-hour clock, with the two times marked on it.
                        WrappedDayNightBand(isActive: appeared)
                            .padding(.vertical, 24)
                            .wrappedReveal(appeared, index: 1, yOffset: 12)

                        // Two separate beats, sunrise first then sunset.
                        HStack(alignment: .top, spacing: 0) {
                            WrappedScheduleMarker(
                                icon: "sunrise.fill",
                                label: "Earliest Start",
                                value: WrappedFormat.timeOfDay(earliest),
                                tint: Color(hex: 0xFFB347)
                            )
                            .frame(maxWidth: .infinity)
                            .wrappedReveal(appeared, index: 3, yOffset: 18)

                            WrappedScheduleMarker(
                                icon: "moon.stars.fill",
                                label: "Latest Finish",
                                value: WrappedFormat.timeOfDay(latest),
                                tint: Color(hex: 0x9B8CFF)
                            )
                            .frame(maxWidth: .infinity)
                            .wrappedReveal(appeared, index: 5, yOffset: 18)
                        }
                    }
                }
            }
        }
    }
}

/// A 24-hour day→night gradient band. Static gradient, animated width —
/// cheap to composite and it only animates once on entrance.
private struct WrappedDayNightBand: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: 0x1B1B3A), // night
                        Color(hex: 0xFFB347), // dawn
                        Color(hex: 0x7FC8F8), // midday
                        Color(hex: 0xE0563B), // dusk
                        Color(hex: 0x1B1B3A), // night again
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 10)
            .scaleEffect(x: isActive || reduceMotion ? 1 : 0.1, anchor: .leading)
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : WrappedMotion.reveal.delay(0.15),
                value: isActive
            )
    }
}

private struct WrappedScheduleMarker: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
            WrappedEyebrow(text: label)
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(WrappedPalette.primaryText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}
