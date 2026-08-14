import SwiftUI

// MARK: - Global leaderboard: header, hero rank card, stats strip
//
// The upper half of the global board. The podium and ranked rows live in
// GlobalPodiumSections.swift; the screen that composes them is
// GlobalLeaderboardView.swift. Presentation only — every figure is passed in.

// MARK: - Shared formatting

enum GlobalHoursFormat {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// "12,842h". Grouped separators because lifetime totals run to five
    /// figures, where an ungrouped run of digits stops being readable at a
    /// glance. Sub-1000 values keep one decimal so a new tracker's board
    /// position still moves visibly.
    static func hours(_ value: Double) -> String {
        guard value.isFinite else { return "0h" }
        let clamped = max(0, value)
        if clamped < 1000 {
            return String(format: "%.1fh", clamped)
        }
        let number = NSNumber(value: clamped.rounded())
        return (grouped.string(from: number) ?? "\(Int(clamped))") + "h"
    }
}

// MARK: - Header

struct GlobalLeaderboardHeader: View {
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Button {
                Haptics.lightTap()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(AppColors.card.opacity(0.7))
                            .overlay(Circle().stroke(AppColors.stroke, lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Hero rank card

struct GlobalRankHeroCard: View {
    /// `nil` when the signed-in user isn't on the board yet.
    let rank: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text("Your global rank")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.accent)

            HStack(alignment: .center, spacing: AppSpacing.xs) {
                Text(rank.map { "#\($0)" } ?? "—")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if rank == 1 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppColors.rankGold)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(AppColors.card2)
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.accent.opacity(0.14),
                                Color.clear,
                                AppColors.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppColors.accent.opacity(0.4),
                            AppColors.accent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Live pulse dot

/// A small "live" indicator: a solid dot with a ring expanding and fading out
/// behind it, on a loop. The SwiftUI equivalent of the reference component's
/// `animate-ping` span. Holds still under Reduce Motion.
struct LivePulseDot: View {
    var color: Color = AppColors.positive
    var size: CGFloat = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pinging = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(pinging ? 2.6 : 1)
                .opacity(pinging ? 0 : 0.75)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pinging = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Stats strip

struct GlobalStatsStrip: View {
    let trackerCount: Int
    let totalHours: Double
    /// Signed-in users on the app right now, from PresenceService's
    /// aggregation count. `nil` until the first count resolves.
    let activeNow: Int?

    var body: some View {
        HStack(spacing: 0) {
            tile(
                icon: "person.2.fill",
                value: "\(trackerCount)",
                label: "Total Trackers"
            )
            divider
            tile(
                icon: "clock.fill",
                value: GlobalHoursFormat.hours(totalHours),
                label: "Total Hours"
            )
            divider
            activeUsersTile
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 0.5)
                )
        )
    }

    /// Live-counter treatment: a pulsing dot in place of the icon square, and
    /// a count that rolls its digits when a refreshed count lands.
    private var activeUsersTile: some View {
        HStack(spacing: 8) {
            LivePulseDot()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let activeNow {
                        Text(activeNow, format: .number.grouping(.automatic))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: activeNow)
                    } else {
                        Text("—")
                    }
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text("Active Users")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activeNow.map { "\($0) active users" } ?? "Active users loading")
    }

    private var divider: some View {
        Rectangle()
            .fill(AppColors.stroke)
            .frame(width: 0.5, height: 34)
    }

    private func tile(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                        .fill(AppColors.accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

// MARK: - Verified review note

/// The line between the rank card and the stats strip explaining how the
/// verified mark is earned. Tapping it opens the proof sheet — the mark is
/// granted by hand from an emailed screenshot, see `VerifiedTracker`.
struct VerifiedReviewNote: View {
    let isVerified: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                VerifiedBadgeView(variant: isVerified ? .shimmer : .static, size: 13)
                VStack(spacing: 1) {
                    Text(isVerified
                         ? "Thanks for reviewing — your verified mark is live!"
                         : "(Users who review the app receive a verified mark beside their name!)")
                    if !isVerified {
                        Text("Tap to send us proof")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.accent)
                    }
                }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
            .padding(.horizontal, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Nothing left to earn once it's granted, so the row goes read-only.
        .disabled(isVerified)
        .accessibilityHint(isVerified ? "" : "Opens the App Store to write a review")
    }
}
