import SwiftUI

/// Lifetime career overview: total hours, days worked, personal bests, level
/// progression. Pay-rate progression lives in PayHistoryView.
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
        return max(0, Date().timeIntervalSince(start) / (60 * 60 * 24 * 365.25))
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

    private var nextWorkAnniversary: Date? {
        guard let start = companyStartDate else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startParts = cal.dateComponents([.month, .day], from: start)
        guard let month = startParts.month, let day = startParts.day else { return nil }

        var thisYear = cal.dateComponents([.year], from: today)
        thisYear.month = month
        thisYear.day = day
        guard var anniversary = cal.date(from: thisYear) else { return nil }
        if cal.startOfDay(for: anniversary) < today {
            anniversary = cal.date(byAdding: .year, value: 1, to: anniversary) ?? anniversary
        }
        return anniversary
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
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return (df.string(from: date), top.value)
    }

    private var levelLabel: String {
        let level = store.displayedLevel
        let prestige = store.gamificationProfile.prestige
        if prestige > 0 {
            return "Lv \(level) • P\(prestige)"
        }
        return "Level \(level)"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                heroSummary

                SectionCard(
                    title: "Career stats",
                    subtitle: "Long-term totals from every shift",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 14) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            CareerStatTile(label: "All-Time Hours", value: hoursDisplay(totalHours), icon: "clock.fill")
                            CareerStatTile(label: "Days Worked", value: "\(daysWorked)", icon: "calendar")
                            CareerStatTile(label: "Avg Shift", value: AppTheme.Format.hours(averageShiftHours), icon: "chart.bar.fill")
                            CareerStatTile(label: "Overtime", value: AppTheme.Format.hours(totalOvertimeHours), icon: "bolt.fill")
                        }
                    }
                    .padding(.vertical, 8)
                }

                SectionCard(
                    title: "Personal bests",
                    subtitle: "The records to beat",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 10) {
                        recordRow(
                            icon: "trophy.fill",
                            title: "Longest Shift",
                            value: AppTheme.Format.hours(longestShiftHours),
                            tint: .orange
                        )
                        recordRow(
                            icon: "flame.fill",
                            title: "Best Streak",
                            value: streakValueString(store.gamificationProfile.bestStreak),
                            tint: .red
                        )
                        recordRow(
                            icon: "flame",
                            title: "Current Streak",
                            value: streakValueString(store.gamificationProfile.currentStreak),
                            tint: AppTheme.Colors.accent
                        )
                        if let best = bestMonthEntry {
                            recordRow(
                                icon: "calendar.badge.checkmark",
                                title: "Best Month",
                                value: "\(AppTheme.Format.hours(best.hours))",
                                detail: best.label,
                                tint: .green
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }

                companyCard

                SectionCard(
                    title: "Tracking history",
                    subtitle: "How long you've been logging",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 10) {
                        recordRow(
                            icon: "hourglass",
                            title: "Tracking Since",
                            value: trackingSinceString,
                            tint: AppTheme.Colors.accent
                        )
                        recordRow(
                            icon: "calendar.circle.fill",
                            title: "Months Tracked",
                            value: "\(monthsTracked)",
                            tint: .blue
                        )
                        if yearsTracked >= 0.1 {
                            recordRow(
                                icon: "star.fill",
                                title: "Years Tracking",
                                value: yearsTrackedString,
                                tint: .yellow
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }

            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Career")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var heroSummary: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accentGradient)
            Text(hoursDisplay(totalHours))
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
            Text("Lifetime hours logged")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
            HStack(spacing: 6) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(levelLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(AppTheme.Colors.accent.opacity(0.15))
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
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
            VStack(spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent.opacity(0.85))

                Text("Add your company to see start date, tenure, and work anniversaries here.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                NavigationLink {
                    CompanyProfileView(store: store)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Set up company profile")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Colors.accentGradient)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
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
                    recordRow(
                        icon: "building.2.fill",
                        title: "Started",
                        value: companyStartedString(from: start),
                        tint: AppTheme.Colors.accent
                    )
                    recordRow(
                        icon: "briefcase.fill",
                        title: "Time at company",
                        value: tenureAtCompanyString(from: start),
                        tint: .purple
                    )
                    if yearsAtCompany >= 0.1 {
                        recordRow(
                            icon: "star.circle.fill",
                            title: "Years worked",
                            value: String(format: "%.1f", yearsAtCompany),
                            tint: .yellow
                        )
                    }
                    if let anniversary = nextWorkAnniversary {
                        recordRow(
                            icon: "gift.fill",
                            title: "Next anniversary",
                            value: anniversaryCountdownString(to: anniversary),
                            detail: anniversaryDateString(anniversary),
                            tint: .pink
                        )
                    }
                }
                recordRow(
                    icon: "clock.fill",
                    title: "Hours logged",
                    value: hoursDisplay(companyHoursLogged),
                    detail: companyStartDate == nil ? "All shifts in app" : "Since start date",
                    tint: .orange
                )
                recordRow(
                    icon: "calendar",
                    title: "Days worked",
                    value: "\(companyDaysWorked)",
                    tint: .blue
                )

                NavigationLink {
                    CompanyProfileView(store: store)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Edit company profile")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.faint)
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Colors.accent.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
    }

    private var companyCardSubtitle: String {
        let occupation = companyOccupation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !occupation.isEmpty { return occupation }
        return "Your workplace"
    }

    // MARK: - Record row

    private func recordRow(
        icon: String,
        title: String,
        value: String,
        detail: String? = nil,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
    }

    // MARK: - Formatting helpers

    private func hoursDisplay(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value) + "h"
        }
        return AppTheme.Format.hours(value)
    }

    private func streakValueString(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private var trackingSinceString: String {
        guard let first = firstEntryDate else { return "—" }
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df.string(from: first)
    }

    private var yearsTrackedString: String {
        if yearsTracked < 1 {
            return String(format: "%.1f", yearsTracked)
        }
        return String(format: "%.1f", yearsTracked)
    }

    private func companyStartedString(from start: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df.string(from: start)
    }

    private func tenureAtCompanyString(from start: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: start, to: Date())
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        if years == 0 && months == 0 { return "Less than a month" }
        if years == 0 { return "\(months) mo" }
        if months == 0 { return "\(years) yr" }
        return "\(years) yr \(months) mo"
    }

    private func anniversaryDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }

    private func anniversaryCountdownString(to date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }
}

// MARK: - Career stat tile

private struct CareerStatTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
        )
    }
}
