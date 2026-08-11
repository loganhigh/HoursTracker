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
        ZStack(alignment: .topTrailing) {
            // The globe bleeds off the card's trailing edge, so it is drawn
            // first and clipped by the card shape below.
            GlobalGlobeArt()
                .frame(width: 260, height: 260)
                .offset(x: 78, y: -46)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Text("Your global rank")
                    .appText(.eyebrow)
                    .foregroundStyle(AppColors.accent)

                HStack(alignment: .center, spacing: AppSpacing.xs) {
                    Text(rank.map { "#\($0)" } ?? "—")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.rankGold)
                    }
                }
                .padding(.top, 6)

                Text("All time hours")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
                    .padding(.top, 10)

                Text(GlobalHoursFormat.hours(hours))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
        }
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
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

// MARK: - Globe artwork

/// A wireframe globe drawn from plain shapes — no image asset, and it retints
/// with the user's prestige accent like the rest of the card.
struct GlobalGlobeArt: View {
    /// Latitudes as a fraction of the radius, north to south.
    private let latitudes: [CGFloat] = [-0.72, -0.42, -0.14, 0.14, 0.42, 0.72]
    /// Longitudes as a fraction of the full width.
    private let longitudes: [CGFloat] = [0.22, 0.55, 0.85]

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppColors.accent.opacity(0.45),
                                AppColors.accent.opacity(0.10),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.36, y: 0.30),
                            startRadius: 0,
                            endRadius: radius * 1.15
                        )
                    )

                Circle()
                    .stroke(AppColors.accent.opacity(0.55), lineWidth: 1.5)

                // Parallels: a horizontal slice of a sphere at height y has
                // half-width sqrt(r² - y²), which is what keeps these reading
                // as a globe rather than a stack of equal rings.
                ForEach(latitudes, id: \.self) { fraction in
                    let y = radius * fraction
                    let width = 2 * sqrt(max(radius * radius - y * y, 0))
                    Ellipse()
                        .stroke(AppColors.accent.opacity(0.30), lineWidth: 1)
                        .frame(width: width, height: max(8, width * 0.20))
                        .offset(y: y)
                }

                // Meridians: nested ellipses of full height, narrowing toward
                // the sphere's edge.
                ForEach(longitudes, id: \.self) { fraction in
                    Ellipse()
                        .stroke(AppColors.accent.opacity(0.30), lineWidth: 1)
                        .frame(width: radius * 2 * fraction, height: radius * 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
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
