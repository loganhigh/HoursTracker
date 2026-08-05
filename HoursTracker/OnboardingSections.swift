import SwiftUI

// MARK: - Onboarding sections (Phase 11)
//
// Native SwiftUI hero illustrations for the four onboarding screens plus the
// shared page indicator. Tokens + DesignComponents only — semantic colors,
// zero glows, Reduce Motion honored on every animation.

// MARK: - Page indicator

/// Four quiet dots; the active dot elongates into a capsule.
struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AppColors.accent : AppColors.stroke)
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .animation(AppMotion.Spring.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Screen 1 hero — floating weekday shift stack

/// A floating stack of seven weekday shift-block rows with soft depth
/// (offset opacity layers, no glow) and a gentle idle float loop.
struct OnboardingShiftStackHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    private struct DayRow: Identifiable {
        let id: String
        let time: String
        var blockWidth: CGFloat = 132
        var hasOvertime = false
        var isEmpty = false
    }

    private let rows: [DayRow] = [
        DayRow(id: "MON", time: "7:00 – 3:30", blockWidth: 128),
        DayRow(id: "TUE", time: "7:00 – 3:30", blockWidth: 128),
        DayRow(id: "WED", time: "8:00 – 4:30", blockWidth: 136),
        DayRow(id: "THU", time: "7:00 – 5:30", blockWidth: 128, hasOvertime: true),
        DayRow(id: "FRI", time: "7:00 – 3:30", blockWidth: 128),
        DayRow(id: "SAT", time: "9:00 – 1:00", blockWidth: 104),
        DayRow(id: "SUN", time: "", isEmpty: true)
    ]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows) { row in
                shiftRow(row)
            }
        }
        .padding(AppSpacing.md)
        .background(
            ZStack {
                depthLayer(offset: 22, scale: 0.90, opacity: 0.18)
                depthLayer(offset: 11, scale: 0.95, opacity: 0.38)
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 1)
                    )
            }
        )
        .offset(y: floating ? -4 : 4)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of a week of logged shifts")
    }

    private func depthLayer(offset: CGFloat, scale: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            .fill(AppColors.card2)
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(y: offset)
    }

    private func shiftRow(_ row: DayRow) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(row.id)
                .appText(.eyebrow)
                .foregroundStyle(row.isEmpty ? AppColors.faint : AppColors.subtext)
                .frame(width: 42, alignment: .leading)

            if row.isEmpty {
                Text("—")
                    .appText(.caption)
                    .foregroundStyle(AppColors.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 5) {
                    Text(row.time)
                        .appText(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, AppSpacing.xs)
                        .frame(width: row.blockWidth, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                .fill(AppColors.accent.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                        .stroke(AppColors.accent.opacity(0.28), lineWidth: 1)
                                )
                        )

                    if row.hasOvertime {
                        Text("OT")
                            .appText(.eyebrow)
                            .foregroundStyle(AppColors.accent2)
                            .frame(width: 34, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                    .fill(AppColors.accent2.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                            .stroke(AppColors.accent2.opacity(0.28), lineWidth: 1)
                                    )
                            )
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Screen 2 hero — level ring + XP capsule + streak / badge cluster

struct OnboardingProgressHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: Double = 0
    @State private var xpFill: CGFloat = 0

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                AppProgressRing(progress: ringProgress, lineWidth: 10)
                    .frame(width: 150, height: 150)
                VStack(spacing: 2) {
                    Text("LVL")
                        .appText(.eyebrow)
                        .foregroundStyle(AppColors.subtext)
                    Text("12")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.text)
                }
            }

            xpCapsule
                .frame(width: 230, height: 30)

            HStack(spacing: AppSpacing.sm) {
                streakChip
                badgeCircle
            }
        }
        .onAppear {
            if reduceMotion {
                ringProgress = 0.65
                xpFill = 0.62
            } else {
                withAnimation(AppMotion.Spring.smooth.delay(0.15)) {
                    ringProgress = 0.65
                    xpFill = 0.62
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of level progress, experience points, a streak, and a badge")
    }

    /// Static illustration twin of the You tab's ProfileXPCapsule.
    private var xpCapsule: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(AppColors.stroke.opacity(0.5))

            GeometryReader { geo in
                if xpFill > 0 {
                    Capsule()
                        .fill(AppColors.accent.opacity(0.3))
                        .frame(width: max(30, geo.size.width * xpFill))
                }
            }

            HStack(spacing: AppSpacing.xs) {
                Text("XP")
                    .appText(.eyebrow)
                    .foregroundStyle(AppColors.textOnAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppColors.accent))

                Spacer(minLength: AppSpacing.xs)

                Text("620 / 1,000")
                    .appText(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.subtext)
                    .padding(.trailing, AppSpacing.xs)
            }
            .padding(4)
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 0.5))
    }

    private var streakChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.streak)
            Text("6")
                .appText(.headline)
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppColors.card2)
                .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 1))
        )
    }

    private var badgeCircle: some View {
        Circle()
            .fill(AppColors.card2)
            .frame(width: 38, height: 38)
            .overlay(Circle().stroke(AppColors.accent.opacity(0.45), lineWidth: 1.5))
            .overlay(
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            )
    }
}

// MARK: - Screen 3 hero — quiet leaderboard card

struct OnboardingLeaderboardHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrowRisen = false

    var body: some View {
        VStack(spacing: 0) {
            leaderboardRow(rank: 1, nameWidth: 96, hours: "28.7h", highlighted: false)
            leaderboardRow(rank: 2, nameWidth: 78, hours: "24.3h", highlighted: true)
            leaderboardRow(rank: 3, nameWidth: 88, hours: "21.5h", highlighted: false)
        }
        .padding(AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
        .onAppear {
            if reduceMotion {
                arrowRisen = true
            } else {
                withAnimation(AppMotion.Spring.smooth.delay(0.35)) {
                    arrowRisen = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of a weekly friends leaderboard")
    }

    private func leaderboardRow(rank: Int, nameWidth: CGFloat, hours: String, highlighted: Bool) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(rank)")
                .appText(.headline)
                .monospacedDigit()
                .foregroundStyle(highlighted ? AppColors.accent : AppColors.subtext)
                .frame(width: 18)

            Circle()
                .fill(AppColors.card2)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(AppColors.stroke, lineWidth: 1))
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(highlighted ? AppColors.accent : AppColors.subtext)
                )

            Capsule()
                .fill(AppColors.stroke.opacity(0.6))
                .frame(width: nameWidth, height: 10)

            Spacer(minLength: AppSpacing.xs)

            if highlighted {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .opacity(arrowRisen ? 1 : 0)
                    .offset(y: arrowRisen ? 0 : 4)
            }

            Text(hours)
                .appText(.headline)
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(highlighted ? AppColors.accent.opacity(0.12) : Color.clear)
        )
    }
}
