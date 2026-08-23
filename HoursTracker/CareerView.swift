import SwiftUI

/// Career sections embedded directly on the You screen (the standalone
/// Career page is retired): personal bests, company tenure, and tracking
/// history. The old hero and "Career stats" grid are gone — You's Lifetime
/// grid already carries those numbers.
struct CareerSections: View {
    @ObservedObject var store: HoursStore
    @AppStorage("company_name") private var companyName: String = ""
    @AppStorage("company_start_date_ts") private var companyStartDateTS: Double = 0
    @AppStorage("company_occupation") private var companyOccupation: String = ""

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

    private var trimmedCompanyName: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCompanyInfo: Bool {
        !trimmedCompanyName.isEmpty
    }

    private var companyStartDate: Date? {
        guard companyStartDateTS > 0 else { return nil }
        return Date(timeIntervalSince1970: companyStartDateTS)
    }

    private var yearsAtCompany: Double {
        guard let start = companyStartDate else { return 0 }
        return FriendProfileFormat.yearsAtCompany(from: start)
    }

    private var companyHoursLogged: Double {
        guard let start = companyStartDate else { return totalHours }
        return lifetime.hours(since: start)
    }

    private var companyDaysWorked: Int {
        guard let start = companyStartDate else { return daysWorked }
        return lifetime.daysWorked(since: start)
    }

    private var bestMonthEntry: (label: String, hours: Double)? {
        guard let best = lifetime.bestMonth else { return nil }
        return (FriendProfileFormat.companyStartedString(from: best.start), best.hours)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
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

                companyCard

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

    // MARK: - Company

    @ViewBuilder
    private var companyCard: some View {
        if hasCompanyInfo {
            companyCardFilled
        } else {
            companyCardEmpty
        }
    }

    private var companyCardEmpty: some View {
        SectionCard(
            title: "Company",
            subtitle: "Track tenure, anniversaries, and hours at work",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "building.2.fill")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppColors.accent.opacity(0.85))

                Text("Add your company to see start date, tenure, and work anniversaries here.")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xs)

                NavigationLink {
                    CompanyProfileView(store: store)
                } label: {
                    Label("Set up company profile", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private var companyCardFilled: some View {
        SectionCard(
            title: trimmedCompanyName,
            subtitle: companyCardSubtitle,
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                if let start = companyStartDate {
                    FriendRecordRow(
                        icon: "building.2.fill",
                        title: "Started",
                        value: FriendProfileFormat.companyStartedString(from: start),
                        tint: AppColors.accent
                    )
                    FriendRecordRow(
                        icon: "briefcase.fill",
                        title: "Time at company",
                        value: FriendProfileFormat.tenureAtCompanyString(from: start),
                        tint: AppColors.accent2
                    )
                    if yearsAtCompany >= 0.1 {
                        FriendRecordRow(
                            icon: "star.circle.fill",
                            title: "Years worked",
                            value: String(format: "%.1f", yearsAtCompany),
                            tint: AppColors.gold
                        )
                    }
                    if let anniversary = FriendProfileFormat.nextWorkAnniversary(from: start) {
                        FriendRecordRow(
                            icon: "gift.fill",
                            title: "Next anniversary",
                            value: FriendProfileFormat.anniversaryCountdownString(to: anniversary),
                            detail: FriendProfileFormat.anniversaryDateString(anniversary),
                            tint: AppColors.accentHighlight
                        )
                    }
                }
                FriendRecordRow(
                    icon: "clock.fill",
                    title: "Hours logged",
                    value: FriendProfileFormat.hoursDisplay(companyHoursLogged),
                    detail: companyStartDate == nil ? "All shifts in app" : "Since start date",
                    tint: AppColors.streak
                )
                FriendRecordRow(
                    icon: "calendar",
                    title: "Days worked",
                    value: "\(companyDaysWorked)",
                    tint: AppColors.accent
                )

                NavigationLink {
                    CompanyProfileView(store: store)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.callout.weight(.semibold))
                        Text("Edit company profile")
                            .appText(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.faint)
                    }
                    .foregroundStyle(AppColors.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, AppSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .fill(AppColors.accent.opacity(0.1))
                    )
                }
                .buttonStyle(PremiumPressStyle())
                .padding(.top, AppSpacing.xxs)
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }

    private var companyCardSubtitle: String {
        let occupation = companyOccupation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !occupation.isEmpty { return occupation }
        return "Your workplace"
    }

    // MARK: - Formatting

    private var trackingSinceString: String {
        guard let first = firstEntryDate else { return "—" }
        return FriendProfileFormat.companyStartedString(from: first)
    }
}
