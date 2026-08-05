import SwiftUI

// MARK: - Home Sections, part 2 (Phase 3)
//
// Recent shifts, yearly overview chart, and the friends standings card —
// extracted from HoursHomeView with explicit dependencies.

// MARK: - Recent Shifts

struct RecentShiftsSection: View {
    @ObservedObject var store: HoursStore
    let hasAnyShifts: Bool
    let onSelect: (WorkEntry) -> Void
    let onViewAll: () -> Void
    let onAddShift: () -> Void
    /// Nil once the "How tracking works" hint has been dismissed.
    let onTrackingHint: (() -> Void)?

    private var recentEntries: [WorkEntry] {
        Array(store.entries.sorted { $0.date > $1.date }.prefix(5))
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Recent Shifts")

            if recentEntries.isEmpty {
                AppEmptyState(
                    icon: "calendar.badge.plus",
                    title: "No shifts logged yet",
                    message: "Log a shift to see your latest entries here.",
                    actionTitle: hasAnyShifts ? "Add Shift" : "Add First Shift",
                    action: onAddShift,
                    secondaryActionTitle: onTrackingHint == nil ? nil : "How tracking works",
                    secondaryAction: onTrackingHint
                )
                .padding(.vertical, AppSpacing.xs)
            } else {
                VStack(spacing: AppSpacing.xs + 2) {
                    ForEach(recentEntries) { entry in
                        Button {
                            Haptics.lightTap()
                            onSelect(entry)
                        } label: {
                            EntryRowView(
                                entry: entry,
                                breakdown: store.payBreakdown(for: entry),
                                currencyCode: store.paySettings.currencyCode,
                                showPay: store.paySettings.showPayCalculations,
                                paySettings: store.paySettings
                            )
                        }
                        .buttonStyle(PremiumPressStyle())
                    }

                    Button(action: onViewAll) {
                        Text("View all")
                            .appText(.headline)
                            .foregroundStyle(AppColors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm + 2, style: .continuous)
                                    .fill(AppColors.accent.opacity(0.1))
                            )
                    }
                    .buttonStyle(PremiumPressStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Yearly Overview (12-month bar chart)

struct YearlyOverviewSection: View {
    @ObservedObject var store: HoursStore

    // Hoisted out of the render path so the 12-month chart doesn't allocate a
    // DateFormatter on every body evaluation.
    private static let monthAbbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private var monthlyHoursByMonth: [(label: String, hours: Double)] {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        return (1...12).compactMap { month -> (String, Double)? in
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            guard let start = cal.date(from: comps) else { return nil }
            let hours = store.monthTotalHours(monthDate: start)
            let label = Self.monthAbbrevFormatter.string(from: start)
            return (label, hours)
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Yearly Overview")

            VStack(spacing: AppSpacing.md) {
                Text(verbatim: "\(Calendar.current.component(.year, from: Date()))")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .center)

                MonthlyOverviewChart(data: monthlyHoursByMonth)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Monthly Overview Bar Chart (moved from RootView)

struct MonthlyOverviewChart: View {
    let data: [(label: String, hours: Double)]
    @State private var appeared = false

    private var maxHours: Double {
        max(data.map(\.hours).max() ?? 8, 8)
    }

    /// Compact label above bars. Shows whole hours for values ≥ 10 so labels
    /// never truncate inside the narrow bar columns.
    private func compactHours(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0h" }
        if value >= 10 {
            return "\(Int(value.rounded()))h"
        }
        // Below 10h show one decimal to distinguish e.g. 4.5h from 4h
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded(.towardZero) ? "\(Int(tenths))h" : "\(tenths)h"
    }

    var body: some View {
        let chartHeight: CGFloat = 160
        let barSpacing: CGFloat = 4
        let labelReserve: CGFloat = 22

        VStack(spacing: AppSpacing.sm) {
            GeometryReader { geo in
                let barWidth = max(16, (geo.size.width - barSpacing * CGFloat(max(data.count - 1, 0))) / CGFloat(max(data.count, 1)))

                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 6) {
                            Text(item.hours > 0 ? compactHours(item.hours) : " ")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .opacity(item.hours > 0 ? 1 : 0)

                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.accent, AppColors.accent2],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(
                                    width: barWidth,
                                    height: appeared && item.hours > 0
                                        ? (maxHours > 0 ? max(4, CGFloat(item.hours / maxHours) * (chartHeight - labelReserve - 8)) : 4)
                                        : 0
                                )
                                .opacity(item.hours > 0 ? 1 : 0)
                                .animation(AppMotion.Spring.smooth.delay(Double(index) * 0.04), value: appeared)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: chartHeight)

            HStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    Text(item.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.subtext)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .onAppear { appeared = true }
    }
}

// MARK: - Friends standings card (top 3 this cheque)

struct HomeFriendsCard: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject var store: HoursStore
    @ObservedObject var authService: AuthService
    let onOpenFriends: () -> Void

    var body: some View {
        Button(action: onOpenFriends) {
            VStack(spacing: AppSpacing.sm) {
                SectionEyebrow("Friends")

                HomeFriendsCardContent(
                    friendsService: friendsService,
                    store: store,
                    authService: authService
                )
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColors.card.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(AppColors.stroke, lineWidth: 0.5)
                        )
                )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct HomeFriendsCardContent: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject var store: HoursStore
    @ObservedObject var authService: AuthService
    @ObservedObject private var statsListener = StatsListenerService.shared

    private struct StandingsRow: Identifiable {
        let id: String
        let name: String
        let hours: Double
        let levelLine: String
        let profilePhotoURL: String?
        let isMe: Bool
    }

    private var standings: [StandingsRow] {
        let myName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "You"
        let profile = store.gamificationProfile
        let currentCycle = store.currentPayCycle()
        let myHours = PayCycleEngine.entries(store.entries, in: currentCycle)
            .reduce(0.0) { $0 + $1.paidHours }
        let myLevelLine = GamificationLevelCalculator.displayLevelLine(
            level: store.displayedLevel,
            prestige: profile.prestige
        )
        var rows: [StandingsRow] = [
            StandingsRow(
                id: authService.user?.uid ?? "self",
                name: myName,
                hours: myHours,
                levelLine: myLevelLine,
                profilePhotoURL: ProfilePhotoManager.shared.remotePhotoURL,
                isMe: true
            )
        ]
        rows += friendsService.friends
            .filter { $0.privacy.shareHours }
            .map {
                StandingsRow(
                    id: $0.uid,
                    name: $0.displayName,
                    hours: $0.chequeHours,
                    levelLine: $0.levelDisplayLine,
                    profilePhotoURL: $0.profilePhotoURL,
                    isMe: false
                )
            }
        return rows
            .sorted {
                if $0.hours != $1.hours { return $0.hours > $1.hours }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(standings.prefix(3).enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().opacity(0.2)
                }
                standingsRow(row, rank: index + 1)
            }
        }
        .animation(nil, value: standings.map { "\($0.id)-\($0.hours)" })
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(nil, value: friendsService.friends.map { "\($0.uid):\($0.weeklyHours):\($0.totalHours):\($0.level)" })
        .onAppear {
            store.syncProfileSnapshotToCloud()
            Task { await friendsService.refreshFriendProfiles() }
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return AppColors.rankGold
        case 2: return AppColors.rankSilver
        case 3: return AppColors.rankBronze
        default: return AppColors.accent
        }
    }

    private func standingsRow(_ row: StandingsRow, rank: Int) -> some View {
        HStack(spacing: AppSpacing.xs + 2) {
            ZStack {
                Circle()
                    .fill(rankColor(rank).opacity(0.18))
                    .frame(width: 24, height: 24)
                Text("\(rank)")
                    .font(AppTypography.eyebrow.monospacedDigit())
                    .foregroundStyle(rankColor(rank))
            }

            ProfileAvatarView(
                name: row.name,
                size: 32,
                photoURL: row.profilePhotoURL,
                uid: row.id
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)

                    if row.isMe {
                        Text("YOU")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.accent.opacity(0.22)))
                            .foregroundStyle(AppColors.accent)
                    }
                }

                Text(row.levelLine)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }

            Spacer(minLength: AppSpacing.xs)

            Text(AppTheme.Format.hours(row.hours))
                .font(AppTypography.metricValue)
                .foregroundStyle(rank == 1 ? AppColors.accent : AppColors.text)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Hours-type chips (Regular / Overtime / Double-time, current week)

struct HoursTypeChipsRow: View {
    @ObservedObject var store: HoursStore

    /// Current-week (Mon–Sun) split summed from the same per-entry pay
    /// breakdown the pay engine uses — so daily, weekly and combined OT modes
    /// all report the exact hours the cheque math attributes to each rate.
    private var split: (regular: Double, overtime: Double, doubleTime: Double) {
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return (0, 0, 0) }
        var regular = 0.0
        var overtime = 0.0
        var doubleTime = 0.0
        for entry in store.entries where !entry.isOffDay && entry.date >= interval.start && entry.date < interval.end {
            let b = store.payBreakdown(for: entry)
            regular += b.regularHours
            overtime += b.overtimeHoursAt1_5
            doubleTime += b.overtimeHoursAt2_0
        }
        return (regular, overtime, doubleTime)
    }

    var body: some View {
        let s = split
        if s.regular + s.overtime + s.doubleTime > 0 {
            HStack(spacing: AppSpacing.xs) {
                chip(icon: "clock.fill", tint: AppColors.accent, label: "Regular", hours: s.regular)
                chip(icon: "clock.badge.exclamationmark", tint: AppColors.warning, label: "Overtime", hours: s.overtime)
                if s.doubleTime > 0 {
                    chip(icon: "bolt.fill", tint: AppColors.streak, label: "Double", hours: s.doubleTime)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func chip(icon: String, tint: Color, label: String, hours: Double) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(AppTheme.Format.hours(hours))
                .font(AppTypography.caption.monospacedDigit())
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(AppColors.card.opacity(0.55))
                .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 0.5))
        )
    }
}
