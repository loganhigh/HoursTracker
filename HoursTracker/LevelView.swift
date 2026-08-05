import SwiftUI

// MARK: - LevelView (dedicated Level screen)
//
// Pushed from the Home XP strip. Flat, quiet translation of the level
// concept: hexagon emblem hero tinted by the user's prestige tier, a
// substantial XP progress block (seeded read-only from XPStripCache like
// ProfileXPCapsule), three MetricDisplay tiles, the next rank milestone,
// recent badge unlocks, and a truthful "how to earn XP" card. Tokens +
// DesignComponents only — no glows (Home owns the app's single hero glow),
// no metallic/3D chrome. Companion file: LevelSections.swift.

struct LevelView: View {
    @ObservedObject var store: HoursStore
    // Server stats drive displayedGamificationProfile(); observe so the
    // screen re-renders the moment they arrive.
    @ObservedObject private var statsListener = StatsListenerService.shared

    // MARK: - Data

    private var profile: GamificationProfile { store.displayedGamificationProfile() }

    /// Emblem/accent tint — the prestige tier color, matching HomeXPStrip.
    private var tierColor: Color {
        profile.prestige == 0 ? AppColors.accent : PrestigeTheme.color(for: profile.prestige)
    }

    private var rankTitle: String {
        GamificationLevelCalculator.rankTitle(forLevel: profile.level, prestige: profile.prestige)
    }

    /// Server-preferred total XP so the number matches the displayed (server)
    /// level; falls back to the local engine total when offline.
    private var totalXPDisplay: Int {
        if let serverXP = statsListener.lifetimeStats?.totalXP, serverXP > 0 {
            return serverXP
        }
        return profile.totalXP
    }

    /// Server-preferred lifetime hours, same preference order as CareerView.
    private var hoursLogged: Double {
        if let serverTotal = statsListener.lifetimeStats?.totalHours, serverTotal > 0 {
            return serverTotal
        }
        return store.allEntriesIncludingArchive()
            .filter { !$0.isOffDay }
            .reduce(0) { $0 + $1.paidHours }
    }

    /// Earned badges (factory order), shared with AchievementsView's row.
    private var earnedBadges: [AchievementBadge] {
        BadgeFactory.makeBadges(stats: BadgeStats(from: store))
            .filter(\.isUnlocked)
            .sorted { $0.order < $1.order }
    }

    /// The next rank title above the current level, or the next prestige
    /// tier when the current run has no further title changes.
    private var nextMilestone: LevelMilestone? {
        let p = profile
        let maxLevel = GamificationLevelCalculator.maxLevelForPrestige(p.prestige)
        let current = GamificationLevelCalculator.rankTitle(forLevel: p.level, prestige: p.prestige)
        if p.level < maxLevel {
            for lvl in (p.level + 1)...maxLevel {
                let title = GamificationLevelCalculator.rankTitle(forLevel: lvl, prestige: p.prestige)
                if title != current {
                    return LevelMilestone(
                        title: title,
                        detail: "Unlocked at Level \(lvl)",
                        icon: nil,
                        levelNumber: lvl,
                        tint: tierColor
                    )
                }
            }
        }
        if p.prestige < 10 {
            let next = PrestigeTheme.tier(for: p.prestige + 1)
            return LevelMilestone(
                title: "Prestige \(p.prestige + 1) — \(next.name)",
                detail: "Unlocked at Level \(maxLevel)",
                icon: next.icon,
                levelNumber: nil,
                tint: next.primary
            )
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                emblemHero

                LevelXPCard(profile: profile, tint: tierColor)

                metricTiles

                if let milestone = nextMilestone {
                    LevelMilestoneCard(milestone: milestone)
                }

                let earned = earnedBadges
                if !earned.isEmpty {
                    LevelRecentUnlocksSection(store: store, badges: earned)
                }

                LevelEarnXPCard()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, 10)
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("My Level")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Level/XP must match the server-published numbers — make sure
            // the server-stats listener is attached (same recovery hook as
            // CareerView / the You tab).
            StatsListenerService.shared.ensureListening()
        }
    }

    // MARK: - Emblem hero

    private var emblemHero: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                LevelHexagon(cornerRadius: 14)
                    .fill(tierColor.opacity(0.12))
                LevelHexagon(cornerRadius: 14)
                    .stroke(tierColor.opacity(0.45), lineWidth: 1.5)
                VStack(spacing: 0) {
                    Text("Level")
                        .appText(.eyebrow)
                        .foregroundStyle(tierColor)
                    Text("\(profile.level)")
                        .font(AppTypography.heroNumber)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, AppSpacing.lg)
                }
            }
            .frame(width: 150, height: 166)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(profile.level), \(rankTitle)")

            VStack(spacing: 2) {
                Text(rankTitle)
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                if profile.prestige > 0 {
                    Text("Prestige \(profile.prestige) • \(PrestigeTheme.tier(for: profile.prestige).name)")
                        .appText(.caption)
                        .foregroundStyle(tierColor)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Metric tiles

    private var metricTiles: some View {
        HStack(spacing: AppSpacing.sm) {
            MetricDisplay(
                icon: "flame.fill",
                label: "Streak",
                value: FriendProfileFormat.streakValueString(profile.currentStreak),
                tint: AppColors.streak
            )
            MetricDisplay(
                icon: "sparkles",
                label: "Total XP",
                value: totalXPDisplay.formatted()
            )
            MetricDisplay(
                icon: "clock.fill",
                label: "Hours",
                value: FriendProfileFormat.hoursDisplay(hoursLogged)
            )
        }
    }
}

// MARK: - XP progress card

/// The substantial XP block: "x,xxx / y,yyy XP", a 12pt progress capsule
/// (animated on appear, seeded read-only from the shared XPStripCache so a
/// cold push starts at the last displayed fill — HomeXPStrip owns the
/// writes), right-aligned percent, and a "N XP to Level M" caption. At max
/// level it renders the prestige-ready state instead.
struct LevelXPCard: View {
    let profile: GamificationProfile
    let tint: Color

    @AppStorage(XPStripCache.progressKey) private var cachedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress: Double = 0
    @State private var seeded = false

    private var isMaxLevel: Bool {
        profile.level >= GamificationLevelCalculator.maxLevelForPrestige(profile.prestige)
    }

    private var liveProgress: Double {
        guard profile.xpForNextLevel > 0 else { return 0 }
        return min(max(Double(profile.xpIntoCurrentLevel) / Double(profile.xpForNextLevel), 0), 1)
    }

    private var percent: Int {
        Int((min(max(displayedProgress, 0), 1) * 100).rounded())
    }

    private var xpRemaining: Int {
        max(profile.xpForNextLevel - profile.xpIntoCurrentLevel, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(profile.xpIntoCurrentLevel.formatted()) / \(profile.xpForNextLevel.formatted()) XP")
                    .font(AppTypography.headline.monospacedDigit())
                    .foregroundStyle(AppColors.text)
                Spacer()
                Text("\(percent)%")
                    .appText(.metricValue)
                    .foregroundStyle(tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.stroke.opacity(0.6))
                    if displayedProgress > 0 {
                        Capsule()
                            .fill(AppColors.accentGradient)
                            .frame(width: max(12, geo.size.width * displayedProgress))
                    }
                }
            }
            .frame(height: 12)

            if isMaxLevel {
                Label("Level \(profile.level) reached — ready to Prestige", systemImage: "sparkles")
                    .appText(.caption)
                    .foregroundStyle(tint)
            } else {
                Text("\(xpRemaining.formatted()) XP to Level \(profile.level + 1)")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isMaxLevel
            ? "Level \(profile.level) reached, ready to prestige"
            : "\(profile.xpIntoCurrentLevel) of \(profile.xpForNextLevel) experience points, \(xpRemaining) to level \(profile.level + 1)"
        )
        .onAppear { seedAndAnimate() }
        .onChange(of: liveProgress) { _, _ in animateToLive() }
    }

    private func seedAndAnimate() {
        if !seeded {
            seeded = true
            displayedProgress = cachedProgress
        }
        animateToLive()
    }

    private func animateToLive() {
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            displayedProgress = liveProgress
        }
    }
}
