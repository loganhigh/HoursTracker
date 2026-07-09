import SwiftUI

/// Leaderboard with weekly hours and company-focused categories.
struct FriendsLeaderboardView: View {

    @ObservedObject var store: HoursStore
    @ObservedObject var friendsService: FriendsService
    // `store.displayedLevel` (my row) prefers the server-computed level from
    // StatsListenerService — observe it so my level re-renders when the
    // server snapshot lands (HoursStore itself doesn't republish on it).
    @ObservedObject private var statsListener = StatsListenerService.shared
    @EnvironmentObject private var authService: AuthService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.semanticColors) private var theme

    // MARK: - Category

    enum Category: String, CaseIterable, Identifiable {
        case hours = "Most Hours"
        case tenure = "Time at Company"
        case companyHours = "Company Hours"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .hours:        return "Hours logged Mon–Sun this week"
            case .tenure:       return "Time at current company"
            case .companyHours: return "Hours logged since company start"
            }
        }

        var icon: String {
            switch self {
            case .hours:        return "clock.fill"
            case .tenure:       return "building.2.fill"
            case .companyHours: return "briefcase.fill"
            }
        }
    }

    @State private var selected: Category = .hours
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    categoryPicker
                    if rows.isEmpty {
                        emptyState
                    } else {
                        if rows.count >= 3 { podium }
                        leaderboardList
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.md)
            }
            .refreshable {
                store.syncProfileSnapshotToCloud()
                await friendsService.refreshFriendProfiles()
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Same recovery hook as CareerView: guarantees the server-stats
                // listeners are attached whenever a level-displaying screen appears.
                StatsListenerService.shared.ensureListening()
                store.syncProfileSnapshotToCloud()
                Task { await friendsService.refreshFriendProfiles() }
            }
        }
    }

    // MARK: - Subviews

    private var categoryPicker: some View {
        HStack(spacing: 8) {
            ForEach(Category.allCases) { category in
                MotionSegmentChip(
                    title: category.rawValue,
                    systemImage: category.icon,
                    isSelected: selected == category
                ) {
                    selected = category
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var podium: some View {
        // Reorder so 2nd is on the left, 1st in the middle, 3rd on the right —
        // the standard podium layout. Use first three rows.
        let top3 = Array(rows.prefix(3))
        HStack(alignment: .bottom, spacing: 10) {
            podiumColumn(row: top3[safe: 1], height: 110, rank: 2)
                .podiumRise(delay: 0.08)
            podiumColumn(row: top3[safe: 0], height: 140, rank: 1)
                .podiumRise(delay: 0)
            podiumColumn(row: top3[safe: 2], height: 96,  rank: 3)
                .podiumRise(delay: 0.14)
        }
        .padding(.top, 4)
        .id(selected)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: selected)
    }

    private func podiumColumn(row: LeaderboardRow?, height: CGFloat, rank: Int) -> some View {
        let highlight = (rank == 1)
        return VStack(spacing: 8) {
            avatar(row: row, size: rank == 1 ? 56 : 48, accentHalo: highlight)
                .overlay(
                    Image(systemName: rank == 1 ? "crown.fill" : "")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.yellow)
                        .shadow(color: .yellow.opacity(0.6), radius: 4)
                        .offset(y: -28)
                )
            Text(row?.displayName ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            if let levelLine = row?.levelDisplayLine {
                Text(levelLine)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Text(row?.primaryDisplay ?? "—")
                .font(AppDesignSystem.Typography.heroNumerals(size: rank == 1 ? 18 : 16, weight: .bold))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: highlight
                            ? theme.accentGradientColors
                            : [theme.cardSecondary, theme.cardSecondary.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: height)
                .overlay(
                    Text("\(rank)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(highlight ? .white : theme.textSecondary)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var leaderboardList: some View {
        SectionCard(
            title: "Standings",
            subtitle: selected.subtitle,
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    leaderboardRow(row: row, position: index + 1)
                    if index < rows.count - 1 {
                        Divider().opacity(0.25)
                    }
                }
            }
            .animation(nil, value: rows.map { "\($0.id)-\($0.primaryValue)" })
        }
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: selected)
    }

    private func leaderboardRow(row: LeaderboardRow, position: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 22, alignment: .leading)
                .monospacedDigit()

            avatar(row: row, size: 36, accentHalo: row.isMe)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if row.isMe {
                        Text("YOU")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(theme.accent.opacity(0.22)))
                            .foregroundStyle(theme.accent)
                            .fixedSize()
                    }
                }
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: 8)

            Text(row.primaryDisplay)
                .font(AppDesignSystem.Typography.heroNumerals(size: 17, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 10)
    }

    private func avatar(row: LeaderboardRow?, size: CGFloat, accentHalo: Bool) -> some View {
        ProfileAvatarView(
            name: row?.displayName ?? "—",
            size: size,
            photoURL: row?.profilePhotoURL,
            uid: row?.id,
            showsAccentRing: accentHalo
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("No friends to rank yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Add a friend with their code to see weekly standings together.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                .stroke(theme.border, lineWidth: 0.5)
        )
        .gentleFadeIn()
    }

    // MARK: - Rows

    /// View-model row consumed by both the podium and the standings list.
    private struct LeaderboardRow: Identifiable, Equatable {
        let id: String
        let displayName: String
        let isMe: Bool
        let levelDisplayLine: String
        let primaryValue: Double
        let primaryDisplay: String
        let subtitle: String
        let profilePhotoURL: String?
    }

    private var rows: [LeaderboardRow] {
        let myRow = makeRow(forSelf: true)
        // All three categories depend on hours-derived data (weeklyHours,
        // weeklyShiftsLogged, daysLogged, currentStreak). When a friend has opted
        // out of `shareHours` those fields are zeroed at write time AND we
        // skip them in the leaderboard so they don't appear with a misleading
        // "0" rank — privacy + UX both stay clean.
        let friendRows: [LeaderboardRow] = {
            switch selected {
            case .hours:
                return friendsService.friends
                    .filter { $0.privacy.shareHours }
                    .map { makeRow(forFriend: $0) }
            case .tenure, .companyHours:
                return friendsService.friends
                    .filter { $0.hasCompanyInfo || $0.privacy.shareHours }
                    .map { makeRow(forFriend: $0) }
            }
        }()
        var all = [myRow] + friendRows
        // Sort descending on the category metric; tiebreaker = display name
        // for stable visual ordering.
        all.sort { lhs, rhs in
            if lhs.primaryValue != rhs.primaryValue { return lhs.primaryValue > rhs.primaryValue }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return all
    }

    private func makeRow(forSelf: Bool) -> LeaderboardRow {
        let name = UserDefaults.standard.string(forKey: "profile_display_name") ?? "You"
        let profile = store.gamificationProfile
        let weekly = WeeklyStatsCalculator.weeklyHours(store.entries)
        let companyStartTS = UserDefaults.standard.double(forKey: "company_start_date_ts")
        let companyStartDate = companyStartTS > 0 ? Date(timeIntervalSince1970: companyStartTS) : nil
        let companyEntries = store.allEntriesIncludingArchive().filter { !$0.isOffDay }
        let companyHoursLogged: Double = {
            guard let start = companyStartDate else { return companyEntries.reduce(0) { $0 + $1.paidHours } }
            let startDay = Calendar.current.startOfDay(for: start)
            return companyEntries
                .filter { Calendar.current.startOfDay(for: $0.date) >= startDay }
                .reduce(0) { $0 + $1.paidHours }
        }()
        return makeRow(
            id: authService.user?.uid ?? "self",
            name: name,
            isMe: true,
            levelDisplayLine: GamificationLevelCalculator.displayLevelLine(
                level: store.displayedLevel,
                prestige: profile.prestige
            ),
            weeklyHours: weekly,
            companyStartDate: companyStartDate,
            companyHoursLogged: companyHoursLogged,
            companyName: UserDefaults.standard.string(forKey: "company_name") ?? "",
            profilePhotoURL: ProfilePhotoManager.shared.remotePhotoURL
        )
    }

    private func makeRow(forFriend friend: FriendProfile) -> LeaderboardRow {
        makeRow(
            id: friend.uid,
            name: friend.displayName,
            isMe: false,
            levelDisplayLine: friend.levelDisplayLine,
            weeklyHours: friend.weeklyHours,
            companyStartDate: friend.companyStartDate,
            companyHoursLogged: friend.companyHoursLogged,
            companyName: friend.companyName,
            profilePhotoURL: friend.profilePhotoURL
        )
    }

    private func makeRow(
        id: String,
        name: String,
        isMe: Bool,
        levelDisplayLine: String,
        weeklyHours: Double,
        companyStartDate: Date?,
        companyHoursLogged: Double,
        companyName: String,
        profilePhotoURL: String?
    ) -> LeaderboardRow {
        let primaryValue: Double
        let primaryDisplay: String
        let detail: String
        switch selected {
        case .hours:
            primaryValue = weeklyHours
            primaryDisplay = AppTheme.Format.hours(weeklyHours)
            detail = ""
        case .tenure:
            let days = companyStartDate.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0 } ?? 0
            primaryValue = Double(days)
            primaryDisplay = Self.formatTenure(days: days)
            detail = companyName.isEmpty ? "" : companyName
        case .companyHours:
            primaryValue = companyHoursLogged
            primaryDisplay = AppTheme.Format.hours(companyHoursLogged)
            detail = companyName.isEmpty ? "" : companyName
        }
        let subtitle = detail.isEmpty ? levelDisplayLine : "\(levelDisplayLine) • \(detail)"
        return LeaderboardRow(
            id: id,
            displayName: name,
            isMe: isMe,
            levelDisplayLine: levelDisplayLine,
            primaryValue: primaryValue,
            primaryDisplay: primaryDisplay,
            subtitle: subtitle,
            profilePhotoURL: profilePhotoURL
        )
    }

    private static func formatTenure(days: Int) -> String {
        if days <= 0 { return "—" }
        let years = days / 365
        let months = (days % 365) / 30
        if years > 0 && months > 0 {
            return "\(years)y \(months)m"
        } else if years > 0 {
            return years == 1 ? "1 year" : "\(years) years"
        } else if months > 0 {
            return months == 1 ? "1 month" : "\(months) months"
        } else {
            return days == 1 ? "1 day" : "\(days) days"
        }
    }
}

// MARK: - Safe indexing

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
