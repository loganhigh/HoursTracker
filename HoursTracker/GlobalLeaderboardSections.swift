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
    let onGlobe: () -> Void

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

            VStack(alignment: .leading, spacing: 1) {
                Text("Global Leaderboard")
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("All time hours")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
            }

            Spacer(minLength: AppSpacing.xs)

            Button {
                Haptics.lightTap()
                onGlobe()
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textOnAccent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColors.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change your country flag")
        }
    }
}

// MARK: - Hero rank card

struct GlobalRankHeroCard: View {
    /// `nil` when the signed-in user isn't on the board yet.
    let rank: Int?
    let hours: Double

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

            Text(GlobalHoursFormat.hours(hours))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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

// MARK: - Stats strip

struct GlobalStatsStrip: View {
    let trackerCount: Int
    let totalHours: Double
    /// The viewer's standing as a percentile, e.g. 3 for "Top 3%".
    /// `nil` when they aren't ranked yet.
    let percentile: Int?

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
            tile(
                icon: "chart.line.uptrend.xyaxis",
                value: percentile.map { "Top \($0)%" } ?? "—",
                label: "Your standing"
            )
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
