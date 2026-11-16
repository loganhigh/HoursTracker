import SwiftUI

/// Career sections embedded directly on the You screen (the standalone
/// Career page is retired): personal bests, company tenure, and tracking
/// history. The old hero and "Career stats" grid are gone — You's Lifetime
/// grid already carries those numbers.
struct CareerSections: View {
    @ObservedObject var store: HoursStore

    @ObservedObject private var statsListener = StatsListenerService.shared

    // MARK: - Source data

    /// Lifetime stats span the year archive and are cached by the store —
    /// one pass over history, not one full scan per stat per re-render.
    private var lifetime: LifetimeWorkStats { store.lifetimeWorkStats() }

    private var totalHours: Double {
        // Prefer server-computed total so Career and Leaderboard always match.
        // Falls back to local sum when offline or not signed in.
        if let serverTotal = statsListener.lifetimeStats?.totalHours, serverTotal > 0 {
            return serverTotal
        }
        return lifetime.localTotalHours
    }

    private var longestShiftHours: Double { lifetime.longestShiftHours }
    private var daysWorked: Int { lifetime.daysWorked }
    private var monthsTracked: Int { lifetime.monthsTracked }
    private var firstEntryDate: Date? { lifetime.firstEntryDate }

    private var yearsTracked: Double {
        guard let first = firstEntryDate else { return 0 }
        return Date().timeIntervalSince(first) / (60 * 60 * 24 * 365.25)
    }

    private var bestMonthEntry: (label: String, hours: Double)? {
        guard let best = lifetime.bestMonth else { return nil }
        return (FriendProfileFormat.companyStartedString(from: best.start), best.hours)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
                // Every job in the same card, main first.
                JobCareerCards(store: store, soleJobHours: totalHours)

                SectionCard(
                    title: "Personal bests",
                    subtitle: "The records to beat",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 10) {
                        FriendRecordRow(
                            icon: "trophy.fill",
                            title: "Longest Shift",
                            value: AppTheme.Format.hours(longestShiftHours),
                            tint: AppColors.gold
                        )
                        FriendRecordRow(
                            icon: "flame.fill",
                            title: "Best Streak",
                            value: FriendProfileFormat.streakValueString(store.gamificationProfile.bestStreak),
                            tint: AppColors.streak
                        )
                        FriendRecordRow(
                            icon: "flame",
                            title: "Current Streak",
                            value: FriendProfileFormat.streakValueString(store.gamificationProfile.currentStreak),
                            tint: AppColors.accent
                        )
                        if let best = bestMonthEntry {
                            FriendRecordRow(
                                icon: "calendar.badge.checkmark",
                                title: "Best Month",
                                value: AppTheme.Format.hours(best.hours),
                                detail: best.label,
                                tint: AppColors.positive
                            )
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

                SectionCard(
                    title: "Tracking history",
                    subtitle: "How long you've been logging",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 10) {
                        FriendRecordRow(
                            icon: "hourglass",
                            title: "Tracking Since",
                            value: trackingSinceString,
                            tint: AppColors.accent
                        )
                        FriendRecordRow(
                            icon: "calendar.circle.fill",
                            title: "Months Tracked",
                            value: "\(monthsTracked)",
                            tint: AppColors.accent2
                        )
                        if yearsTracked >= 0.1 {
                            FriendRecordRow(
                                icon: "star.fill",
                                title: "Years Tracking",
                                value: String(format: "%.1f", yearsTracked),
                                tint: AppColors.gold
                            )
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

        }
    }

    // MARK: - Formatting

    private var trackingSinceString: String {
        guard let first = firstEntryDate else { return "—" }
        return FriendProfileFormat.companyStartedString(from: first)
    }
}
