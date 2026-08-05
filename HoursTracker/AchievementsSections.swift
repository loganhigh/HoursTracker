import SwiftUI

// MARK: - Achievements sections (Phase 8)
//
// Section building blocks for AchievementsView: summary strip, Next-Up
// spotlight, horizontal earned row, and grouped collection rows. Flat badge
// language throughout — SF symbol in an accent-ring circle, quiet cards
// (radius 20, card.opacity(0.55)), hairline strokes, zero glows. Legend and
// special badges use the fixed AppColors.gold ring; everything else stays
// prestige-accent. No motion is added, so Reduce Motion needs no extra gating.

// MARK: - Badge circle

/// The one flat badge mark: earned = accent-gradient fill + white symbol,
/// earned legend = gold ring + gold symbol on a quiet fill,
/// locked = quiet fill + lock.
struct AchievementBadgeCircle: View {
    let badge: AchievementBadge
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    badge.isUnlocked && !badge.isLegend
                    ? AnyShapeStyle(AppColors.accentGradient)
                    : AnyShapeStyle(AppColors.card2)
                )
            Circle()
                .stroke(ringColor, lineWidth: ringWidth)
            Image(systemName: badge.isUnlocked ? badge.icon : "lock.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var ringColor: Color {
        if !badge.isUnlocked { return AppColors.stroke }
        return badge.isLegend ? AppColors.gold.opacity(0.8) : AppColors.textOnAccent.opacity(0.25)
    }

    private var ringWidth: CGFloat {
        badge.isUnlocked && badge.isLegend ? 1.5 : (badge.isUnlocked ? 1 : 0.5)
    }

    private var iconColor: Color {
        if !badge.isUnlocked { return AppColors.subtext }
        return badge.isLegend ? AppColors.gold : AppColors.textOnAccent
    }
}

// MARK: - Thin progress capsule

struct ThinProgressCapsule: View {
    let progress: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.stroke.opacity(0.6))
                Capsule()
                    .fill(AppColors.accentGradient)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Summary strip

/// Quiet top card: "N of M earned" with an accent numeral and a thin
/// progress capsule. Counts only badges visible to this user (Owner /
/// Developer specials are excluded upstream).
struct AchievementsSummaryCard: View {
    let earned: Int
    let total: Int

    private var fraction: Double {
        total > 0 ? Double(earned) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(earned)")
                    .appText(.heroNumber)
                    .foregroundStyle(AppColors.accent)
                Text("of \(total) earned")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
            }
            ThinProgressCapsule(progress: fraction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.strokeStrong, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of \(total) badges earned")
    }
}

// MARK: - Next-Up spotlight

/// The single closest-to-completion locked badge, chosen upstream from the
/// factory's existing progress values. Shows the badge's real requirement
/// text — the model carries no raw value/target pair, so no "X of Y" counts
/// are fabricated.
struct NextUpBadgeCard: View {
    let badge: AchievementBadge

    private var percent: Int {
        Int((min(max(badge.progress, 0), 1) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Next up")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.subtext)
            HStack(spacing: AppSpacing.sm) {
                AchievementBadgeCircle(badge: badge, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(badge.name)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(badge.detail)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(2)
                }
                Spacer(minLength: AppSpacing.xs)
                Text("\(percent)%")
                    .appText(.metricValue)
                    .foregroundStyle(AppColors.accent)
            }
            ThinProgressCapsule(progress: badge.progress)
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.strokeStrong, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next up: \(badge.name), \(badge.detail), \(percent) percent complete")
    }
}

// MARK: - Earned row

/// Horizontal scroll of earned badges in their existing factory order.
/// The badge model carries no earned dates, so none are shown or invented.
struct EarnedBadgesRow: View {
    let badges: [AchievementBadge]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                ForEach(badges) { badge in
                    VStack(spacing: 6) {
                        AchievementBadgeCircle(badge: badge, size: 56)
                        Text(badge.name)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .frame(height: 28, alignment: .top)
                    }
                    .frame(width: 76)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(badge.name), earned")
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Collection group

/// One grouped card of collection rows with a leading header. Groups mirror
/// the real sections the badge data supports (Owner / Developer / Earned /
/// Locked / Legend) — the model has no category field to group by.
struct BadgeCollectionGroup: View {
    let title: String
    let badges: [AchievementBadge]
    /// When set (Legend), the header shows "earned of total".
    var earnedCount: Int? = nil

    private var countText: String {
        if let earnedCount { return "\(earnedCount) of \(badges.count)" }
        return "\(badges.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Spacer()
                Text(countText)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            .padding(.horizontal, AppSpacing.xxs)

            LazyVStack(spacing: 0) {
                ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                    BadgeCollectionRow(badge: badge)
                    if index < badges.count - 1 {
                        Rectangle()
                            .fill(AppColors.stroke.opacity(0.6))
                            .frame(height: 0.5)
                            .padding(.leading, AppSpacing.md + 40 + AppSpacing.sm)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Collection row

/// Badge circle + name + requirement text; right side is a small progress
/// ring with percent when locked, a subtle filled check when earned.
struct BadgeCollectionRow: View {
    let badge: AchievementBadge

    private var percent: Int {
        Int((min(max(badge.progress, 0), 1) * 100).rounded())
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            AchievementBadgeCircle(badge: badge, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(badge.name)
                    .appText(.subheadline)
                    .foregroundStyle(badge.isUnlocked ? AppColors.text : AppColors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(badge.detail)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: AppSpacing.xs)

            if badge.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(badge.isLegend ? AppColors.gold : AppColors.accent)
                    .opacity(0.9)
            } else {
                ZStack {
                    AppProgressRing(progress: badge.progress, lineWidth: 3)
                    Text("\(percent)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppColors.subtext)
                }
                .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            badge.isUnlocked
            ? "\(badge.name), \(badge.detail), earned"
            : "\(badge.name), \(badge.detail), \(percent) percent complete"
        )
    }
}
