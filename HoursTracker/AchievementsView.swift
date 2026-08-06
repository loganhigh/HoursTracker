import SwiftUI

/// Lightweight badge payload synced to Firestore for friend profile display.
struct SharedBadgeSummary: Identifiable, Equatable, Hashable {
    var id: String { name }
    let icon: String
    let name: String
    let detail: String
    let isLegend: Bool
    let order: Int
}

// MARK: - AchievementsView (Phase 8 redesign)
//
// Summary strip ("N of M earned") + Next-Up spotlight (closest locked badge
// by the factory's existing progress values) + horizontal Earned row +
// grouped collection rows. Badge model/factory live in AchievementBadges.swift
// (definitions unchanged); section views live in AchievementsSections.swift.
//
// Grouping note: `AchievementBadge` carries no category field and factory
// `order` bands overlap across the factory's comment groups, so rows fall
// back to the real, data-supported sections: Owner / Developer / Earned /
// Locked / Legend. No categories are invented.

struct AchievementsView: View {
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    /// When true, renders only the achievements content (no ScrollView, nav, toolbar). Use when embedding in ProfileView.
    var embedded: Bool = false

    /// Owner / CEO status — strictly gated by Firebase UID via `DeveloperConfig`.
    /// Email-based gating was removed to avoid shipping a personal address in the
    /// binary and to prevent collisions if any user enters that email in pay
    /// settings.
    private var isOwner: Bool {
        DeveloperConfig.isCEO(uid: authService.user?.uid)
    }

    /// Developer badge: only awarded when Apple user ID is in DeveloperConfig.developerUserIDs.
    private var isDeveloper: Bool {
        guard let id = authService.user?.uid else { return false }
        return DeveloperConfig.developerUserIDs.contains(id)
    }

    // MARK: - Stats derived from entries
    private var stats: BadgeStats { BadgeStats(from: store) }

    private var ceoBadge: AchievementBadge? {
        if isOwner {
            return AchievementBadge(
                icon: "crown.fill",
                name: "CEO",
                detail: "Owner Status",
                isUnlocked: true,
                isLegend: true,
                progress: 1.0,
                order: 0
            )
        }
        return nil
    }

    /// Developer badge: only shown when the current user's Firebase UID is in
    /// `DeveloperConfig.developerUserIDs`. Rendered in its own dedicated section.
    private var developerBadge: AchievementBadge? {
        guard isDeveloper else { return nil }
        return AchievementBadge(
            icon: "hammer.fill",
            name: "Developer",
            detail: "Built Hour Tracker",
            isUnlocked: true,
            isLegend: true,
            progress: 1.0,
            order: 5
        )
    }

    private var achievementsContent: some View {
        // Build BadgeStats and the badge list exactly once per render (the
        // factory walks the user's entire shift history).
        let allBadges = BadgeFactory.makeBadges(stats: stats)
        let earnedBadges = allBadges.filter { $0.isUnlocked && !$0.isLegend }.sorted { $0.order < $1.order }
        let lockedBadges = allBadges.filter { !$0.isUnlocked && !$0.isLegend }.sorted { $0.order < $1.order }
        let legendBadges = allBadges.filter { $0.isLegend }.sorted { $0.order < $1.order }

        // Summary counts only what this user can see from the factory —
        // Owner/Developer special badges are gated and excluded.
        let earnedCount = allBadges.filter(\.isUnlocked).count
        let totalCount = allBadges.count

        // Next-Up spotlight: the single closest-to-completion locked badge,
        // ranked by the factory's existing progress values (ties -> factory
        // order). Hidden when nothing is meaningfully in progress.
        let nextUp = allBadges
            .filter { !$0.isUnlocked && $0.progress > 0 }
            .sorted { $0.progress != $1.progress ? $0.progress > $1.progress : $0.order < $1.order }
            .first

        return VStack(spacing: AppSpacing.xl) {
            AchievementsSummaryCard(earned: earnedCount, total: totalCount)

            if let nextUp {
                NextUpBadgeCard(badge: nextUp)
            }

            if earnedBadges.isEmpty && ceoBadge == nil && developerBadge == nil {
                AppEmptyState(
                    icon: "rosette",
                    title: "No badges yet — keep going!",
                    message: "Log shifts to unlock your first badge."
                )
            }

            if !earnedBadges.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    SectionEyebrow("Earned")
                    EarnedBadgesRow(badges: earnedBadges)
                }
            }

            // Collection — grouped rows over the real sections the data
            // supports (no invented categories).
            VStack(spacing: AppSpacing.lg) {
                if let ceo = ceoBadge {
                    BadgeCollectionGroup(title: "Owner", badges: [ceo])
                }
                if let dev = developerBadge {
                    BadgeCollectionGroup(title: "Developer", badges: [dev])
                }
                if !earnedBadges.isEmpty {
                    BadgeCollectionGroup(title: "Earned", badges: earnedBadges)
                }
                if !lockedBadges.isEmpty {
                    BadgeCollectionGroup(title: "Locked", badges: lockedBadges)
                }
                if !legendBadges.isEmpty {
                    BadgeCollectionGroup(
                        title: "Legend",
                        badges: legendBadges,
                        earnedCount: legendBadges.filter(\.isUnlocked).count
                    )
                }
            }

            Text("Badges unlock automatically from your hours & patterns.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, AppSpacing.xs)
                .padding(.horizontal, AppSpacing.md)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, embedded ? 0 : 10)
        .padding(.bottom, embedded ? 24 : 32)
    }

    var body: some View {
        Group {
            if embedded {
                achievementsContent
            } else {
                ScrollView {
                    achievementsContent
                }
                .background(AppColors.bg.ignoresSafeArea())
                .navigationTitle("Badges")
            }
        }
    }

    /// Public helper so other views can show the earned badge count without
    /// duplicating the BadgeStats/BadgeFactory computation.
    static func earnedBadgeCount(for store: HoursStore) -> Int {
        earnedBadgesForSharing(from: store).filter { !$0.isLegend }.count
    }

    /// Earned + total (non-legend) badge counts for "N of M" summary rows.
    static func badgeCollectionCounts(for store: HoursStore) -> (earned: Int, total: Int) {
        let badges = BadgeFactory.makeBadges(stats: BadgeStats(from: store))
            .filter { !$0.isLegend }
        return (badges.filter(\.isUnlocked).count, badges.count)
    }

    /// Earned badges serialized for the public profile doc so friends can
    /// see which badges someone has unlocked.
    static func earnedBadgesForSharing(from store: HoursStore) -> [SharedBadgeSummary] {
        let stats = BadgeStats(from: store)
        return BadgeFactory.makeBadges(stats: stats)
            .filter(\.isUnlocked)
            .sorted { $0.order < $1.order }
            .map {
                SharedBadgeSummary(
                    icon: $0.icon,
                    name: $0.name,
                    detail: $0.detail,
                    isLegend: $0.isLegend,
                    order: $0.order
                )
            }
    }
}
