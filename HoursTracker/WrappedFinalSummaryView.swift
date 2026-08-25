import SwiftUI

// MARK: - Wrapped final summary
//
// Structure:
//   WrappedFinalSummarySlide
//     └─ native SwiftUI card (all real content — the source of truth)
//     └─ optional WrappedRiveView (decorative one-shot celebration)
//
// Every figure on this card is plain SwiftUI reading an already-computed
// WrappedYearStats. The Rive layer is purely decorative and entirely
// optional: with no `.riv` asset in the bundle (or with Reduce Motion on)
// this renders exactly the native card it renders today.

extension WrappedRiveAsset {
    /// The celebration Wrapped looks for: `wrapped_finale.riv`.
    ///
    /// Artboard and animation are intentionally left `nil` so the file's
    /// **default artboard and first animation** are used — that way a
    /// correctly-authored `.riv` plays on drop-in with no code change. Set
    /// `artboardName` / `animationName` / `stateMachineName` explicitly only
    /// if the file needs a specific one.
    ///
    /// No asset ships today, so this resolves to `isPlayable == false` and
    /// every host falls back to its native-only presentation.
    static let wrappedFinale = WrappedRiveAsset(
        fileName: "wrapped_finale",
        autoPlay: true,
        loops: false // one-shot: a permanently looping celebration would
                     // keep the render loop awake for the whole time the
                     // user sits on this slide.
    )
}

struct WrappedFinalSummarySlide: View {
    let stats: WrappedYearStats
    /// Shown as a handle above the year when the signed-in user has claimed
    /// one. Passed in rather than read from FriendsService here, so slides
    /// stay pure views over data handed to them.
    var username: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrationFinished = false

    private var celebrationAsset: WrappedRiveAsset { .wrappedFinale }

    /// Only mount the Rive layer when it could actually do something —
    /// keeps the view tree identical to today's when no asset is present.
    private var showsCelebration: Bool {
        !reduceMotion && !celebrationFinished && celebrationAsset.isPlayable
    }

    var body: some View {
        ZStack {
            WrappedBackdrop()

            WrappedSlideAppearance(haptic: .light) { appeared, _ in
                WrappedSlideScaffold {
                    summaryCard(appeared: appeared)
                }
            }

            // Decorative celebration layer, above the card but never
            // interactive — story navigation taps must pass straight
            // through it.
            if showsCelebration {
                WrappedRiveView(
                    asset: celebrationAsset,
                    onFinished: { celebrationFinished = true }
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Native content (unchanged, plus the username line)

    @ViewBuilder
    private func summaryCard(appeared: Bool) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                WrappedEyebrow(text: "Hour Tracker Wrapped")
                Text(String(stats.year))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(WrappedPalette.accent)
                if let username, !username.isEmpty {
                    Text(Username.display(username))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(WrappedPalette.secondaryText)
                }
            }
            .wrappedReveal(appeared, index: 0)

            HStack(spacing: 0) {
                WrappedSummaryMetric(
                    value: WrappedFormat.groupedWholeHours(stats.totalHours),
                    label: "Hours"
                )
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 38)

                WrappedSummaryMetric(
                    value: WrappedFormat.groupedInt(stats.totalShifts),
                    label: "Shifts"
                )
                .frame(maxWidth: .infinity)
            }
            .wrappedReveal(appeared, index: 1, yOffset: 16)

            VStack(spacing: 8) {
                if let busiestMonth = stats.busiestMonth {
                    WrappedSummaryLine(
                        label: "Biggest month",
                        value: WrappedFormat.fullMonthUppercased(busiestMonth.monthStart).capitalized
                    )
                    .wrappedReveal(appeared, index: 2, yOffset: 12)
                }
                if stats.longestShiftHours > 0 {
                    WrappedSummaryLine(
                        label: "Longest shift",
                        value: WrappedFormat.hoursAndMinutes(stats.longestShiftHours)
                    )
                    .wrappedReveal(appeared, index: 3, yOffset: 12)
                }
                if stats.longestStreakDays >= 3 {
                    WrappedSummaryLine(
                        label: "Longest streak",
                        value: "\(stats.longestStreakDays) days"
                    )
                    .wrappedReveal(appeared, index: 4, yOffset: 12)
                }
            }

            VStack(spacing: 4) {
                WrappedEyebrow(text: "Worker Type")
                Text(stats.personality.type.rawValue)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(WrappedPalette.primaryText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .wrappedReveal(appeared, index: 5, yOffset: 14)
            .padding(.top, 4)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(WrappedPalette.accent.opacity(0.30), lineWidth: 1)
        )
        .wrappedReveal(appeared, index: 0, yOffset: 26, scaleFrom: 0.92)
    }
}

struct WrappedSummaryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(WrappedPalette.primaryText)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            WrappedEyebrow(text: label)
        }
    }
}

struct WrappedSummaryLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(WrappedPalette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(WrappedPalette.primaryText)
        }
    }
}
