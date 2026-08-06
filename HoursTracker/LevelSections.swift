import SwiftUI

// MARK: - Level screen sections (companion to LevelView.swift)
//
// The flat hexagon emblem shape, next-milestone card, recent-unlocks row,
// and the "how to earn XP" card. Quiet-card language throughout: flat
// fills, hairline strokes, tokens only, zero glows. The earn-XP copy states
// only mechanics GamificationEngine actually pays out (xpPerHour 100,
// shiftLogXP 50, overtimeXPPerHour 150, streakDayXP 200, longShiftXP 300,
// weeklyCompletionXP 500) — badges/milestones grant no XP, so they are not
// promised here.

// MARK: - Hexagon emblem shape

/// Flat, pointy-top hexagon with softly rounded corners — the Level screen's
/// emblem motif. Pure fill/stroke shape; no gradients or bevels.
struct LevelHexagon: Shape {
    var cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.75),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25)
        ]
        var path = Path()
        for index in 0..<points.count {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let previous = points[(index + points.count - 1) % points.count]
            let fromPrevious = unitVector(from: current, to: previous)
            let toNext = unitVector(from: current, to: next)
            let start = CGPoint(
                x: current.x + fromPrevious.dx * cornerRadius,
                y: current.y + fromPrevious.dy * cornerRadius
            )
            let end = CGPoint(
                x: current.x + toNext.dx * cornerRadius,
                y: current.y + toNext.dy * cornerRadius
            )
            if index == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }
            path.addQuadCurve(to: end, control: current)
        }
        path.closeSubpath()
        return path
    }

    private func unitVector(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

// MARK: - Next milestone

/// The next rank title (or prestige tier) and where it unlocks.
struct LevelMilestone {
    let title: String
    let detail: String
    /// Tier icon for prestige milestones; nil renders the level number.
    let icon: String?
    let levelNumber: Int?
    let tint: Color
}

struct LevelMilestoneCard: View {
    let milestone: LevelMilestone

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Next milestone")

            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    LevelHexagon(cornerRadius: 6)
                        .fill(milestone.tint.opacity(0.12))
                    LevelHexagon(cornerRadius: 6)
                        .stroke(milestone.tint.opacity(0.45), lineWidth: 1)
                    if let icon = milestone.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(milestone.tint)
                    } else if let level = milestone.levelNumber {
                        Text("\(level)")
                            .font(AppTypography.headline.monospacedDigit())
                            .foregroundStyle(milestone.tint)
                    }
                }
                .frame(width: 44, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(milestone.detail)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next milestone: \(milestone.title), \(milestone.detail)")
    }
}

// MARK: - Recent unlocks

/// Horizontal scroll of earned badges (shared AchievementBadgeCircle look)
/// with a View All push into the full badges screen. Callers hide this
/// section entirely when no badges are earned.
struct LevelRecentUnlocksSection: View {
    @ObservedObject var store: HoursStore
    let badges: [AchievementBadge]

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Recent unlocks")

            EarnedBadgesRow(badges: badges)

            NavigationLink {
                AchievementsView(store: store)
            } label: {
                Text("View All")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(AppColors.accent.opacity(0.1))
                    )
            }
            .buttonStyle(PremiumPressStyle())
        }
    }
}

// MARK: - How to earn XP

/// Four compact tiles naming the real XP mechanics — values mirror
/// GamificationEngine's constants (see file header).
struct LevelEarnXPCard: View {
    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("How to earn XP")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: AppSpacing.sm),
                GridItem(.flexible(), spacing: AppSpacing.sm)
            ], spacing: AppSpacing.sm) {
                LevelEarnXPTile(
                    icon: "clock.fill",
                    tint: AppColors.accent,
                    title: "Log hours",
                    detail: "+100 XP per hour worked"
                )
                LevelEarnXPTile(
                    icon: "bolt.fill",
                    tint: AppColors.warning,
                    title: "Work overtime",
                    detail: "+150 XP per overtime hour"
                )
                LevelEarnXPTile(
                    icon: "flame.fill",
                    tint: AppColors.streak,
                    title: "Keep your streak",
                    detail: "+200 XP per day worked"
                )
                LevelEarnXPTile(
                    icon: "hourglass",
                    tint: AppColors.accent2,
                    title: "Go long",
                    detail: "+300 XP per 12h+ shift"
                )
            }
        }
    }
}

struct LevelEarnXPTile: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .appText(.metricLabel)
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(detail)
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(detail)")
    }
}
