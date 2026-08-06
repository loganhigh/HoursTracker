import SwiftUI

/// Lifetime career overview: total hours, days worked, personal bests, level
/// progression. Phase 9 restyle: canonical tokens throughout, standard hero
/// anatomy without the glow (Home owns the app's single hero glow), and the
/// shared FriendRecordRow / FriendProfileFormat building blocks instead of
/// local duplicates. Structure (hero → stats → bests → company → history)
/// unchanged.
struct CareerView: View {
    @ObservedObject var store: HoursStore
    @AppStorage("company_name") private var companyName: String = ""
    @AppStorage("company_start_date_ts") private var companyStartDateTS: Double = 0
    @AppStorage("company_occupation") private var companyOccupation: String = ""

    @ObservedObject private var statsListener = StatsListenerService.shared

    // MARK: - Source data

    private var workEntries: [WorkEntry] {
        // Lifetime/all-time stats must span the year archive: archivePriorYearsIfNeeded
        // moves prior-year entries out of `store.entries`, so reading `entries` alone
        // silently drops every year before the current one after the Jan-1 rollover.
        store.allEntriesIncludingArchive().filter { !$0.isOffDay }
    }

    private var totalHours: Double {
        // Prefer server-computed total so Career and Leaderboard always match.
        // Falls back to local sum when offline or not signed in.
        if let serverTotal = statsListener.lifetimeStats?.totalHours, serverTotal > 0 {
            return serverTotal
        }
        return workEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var averageShiftHours: Double {
        guard !workEntries.isEmpty else { return 0 }
        return totalHours / Double(workEntries.count)
    }

    private var totalOvertimeHours: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).overtimeHours }
    }

    private var longestShiftHours: Double {
        workEntries.map(\.paidHours).max() ?? 0
    }

    private var daysWorked: Int {
        let cal = Calendar.current
        return Set(workEntries.map { cal.startOfDay(for: $0.date) }).count
    }

    private var monthsTracked: Int {
        let cal = Calendar.current
        let months = Set(workEntries.map { entry -> DateComponents in
            cal.dateComponents([.year, .month], from: entry.date)
        })
        return months.count
    }

    private var firstEntryDate: Date? {
        workEntries.map(\.date).min()
    }

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
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        return workEntries
            .filter { cal.startOfDay(for: $0.date) >= startDay }
            .reduce(0) { $0 + $1.paidHours }
    }

    private var companyDaysWorked: Int {
        guard let start = companyStartDate else { return daysWorked }
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let days = Set(
            workEntries
                .filter { cal.startOfDay(for: $0.date) >= startDay }
                .map { cal.startOfDay(for: $0.date) }
        )
        return days.count
    }

    private var bestMonthEntry: (label: String, hours: Double)? {
        guard !workEntries.isEmpty else { return nil }
        let cal = Calendar.current
        var byMonth: [DateComponents: Double] = [:]
        for entry in workEntries {
            let key = cal.dateComponents([.year, .month], from: entry.date)
            byMonth[key, default: 0] += entry.paidHours
        }
        guard let top = byMonth.max(by: { $0.value < $1.value }) else { return nil }
        var comps = DateComponents()
        comps.year = top.key.year
        comps.month = top.key.month
        comps.day = 1
        guard let date = cal.date(from: comps) else { return nil }
        return (FriendProfileFormat.companyStartedString(from: date), top.value)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                heroSummary

                SectionCard(
                    title: "Career stats",
                    subtitle: "Long-term totals from every shift",
                    trailing: nil,
                    centerHeader: true
                ) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: AppSpacing.sm),
                        GridItem(.flexible(), spacing: AppSpacing.sm)
                    ], spacing: AppSpacing.sm) {
                        MetricDisplay(icon: "clock.fill", label: "All-Time Hours", value: FriendProfileFormat.hoursDisplay(totalHours))
                        MetricDisplay(icon: "calendar", label: "Days Worked", value: "\(daysWorked)")
                        MetricDisplay(icon: "chart.bar.fill", label: "Avg Shift", value: AppTheme.Format.hours(averageShiftHours))
                        MetricDisplay(icon: "bolt.fill", label: "Overtime", value: AppTheme.Format.hours(totalOvertimeHours))
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

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
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, 10)
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Career")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Career's lifetime hours must always match the global leaderboard,
            // which is server-fed — make sure the server-stats listener is
            // attached even if the sign-in callback never started it.
            StatsListenerService.shared.ensureListening()
        }
    }

    // MARK: - Hero (standard anatomy, no glow — Home owns the only hero glow)

    private var heroSummary: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Career")

            AnimatedMetricText(value: totalHours) { FriendProfileFormat.hoursDisplay($0) }
                .font(AppTypography.heroNumber)
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("Lifetime hours logged")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
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
