import SwiftUI

/// Leaderboard with weekly hours and company-focused categories.
/// Phase 7 redesign: quiet stepped podium with metal rank pips, a persistent
/// "You" summary row, and ranked standings with relative bars. Data flow
/// (FriendsService, category computation, privacy gating) is unchanged.
struct FriendsLeaderboardView: View {

    @ObservedObject var store: HoursStore
    @ObservedObject var friendsService: FriendsService
    // `store.displayedLevel` (my row) prefers the server-computed level from
    // StatsListenerService — observe it so my level re-renders when the
    // server snapshot lands (HoursStore itself doesn't republish on it).
    @ObservedObject private var statsListener = StatsListenerService.shared
    @EnvironmentObject private var authService: AuthService

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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    categoryPicker
                    if rows.isEmpty {
                        emptyState
                    } else {
                        if rows.count >= 3 { podium }
                        youSummary(proxy: proxy)
                        leaderboardList
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
        }
        .refreshable {
            store.syncProfileSnapshotToCloud()
            await friendsService.refreshFriendProfiles()
        }
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Same recovery hook as CareerView: guarantees the server-stats
            // listeners are attached whenever a level-displaying screen appears.
            StatsListenerService.shared.ensureListening()
            store.syncProfileSnapshotToCloud()
            Task { await friendsService.refreshFriendProfiles() }
        }
    }

    // MARK: - Subviews

    private var categoryPicker: some View {
        HStack(spacing: AppSpacing.xs) {
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

    // MARK: Podium

    @ViewBuilder
    private var podium: some View {
        // Reorder so 2nd is on the left, 1st in the middle, 3rd on the right —
        // the standard podium layout. Use first three rows.
        let top3 = Array(rows.prefix(3))
        HStack(alignment: .bottom, spacing: 10) {
            LeaderboardPodiumColumn(row: top3[safe: 1], height: 96, rank: 2)
                .podiumRise(delay: 0.08)
            LeaderboardPodiumColumn(row: top3[safe: 0], height: 122, rank: 1)
                .podiumRise(delay: 0)
            LeaderboardPodiumColumn(row: top3[safe: 2], height: 82, rank: 3)
                .podiumRise(delay: 0.14)
        }
        .padding(.top, AppSpacing.md)
        .id(selected)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: selected)
    }

    // MARK: "You" summary row

    /// Persistent summary directly under the podium — always shows your rank
    /// (even when you're on the podium). Tapping scrolls to your standings row.
    private func youSummary(proxy: ScrollViewProxy) -> some View {
        let myIndex = rows.firstIndex { $0.isMe }
        let me = myIndex.map { rows[$0] }
        return Button {
            Haptics.lightTap()
            guard let me else { return }
            withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                proxy.scrollTo("standing-\(me.id)", anchor: .center)
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                avatar(row: me, size: 36, accentHalo: false)
                Text(youSummaryLine(rank: (myIndex ?? 0) + 1, row: me))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressStyle())
        .accessibilityHint("Scrolls to your row in the standings")
    }

    private func youSummaryLine(rank: Int, row: FriendsLeaderboardRowModel?) -> String {
        guard let row else { return "You're unranked" }
        let base = "You're #\(rank)"
        guard row.primaryDisplay != "—" else { return base }
        switch selected {
        case .hours:        return "\(base) · \(row.primaryDisplay) this week"
        case .tenure:       return "\(base) · \(row.primaryDisplay) at company"
        case .companyHours: return "\(base) · \(row.primaryDisplay) at company"
        }
    }

    // MARK: Standings

    private var leaderboardList: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Standings", subtitle: selected.subtitle)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    leaderboardRow(row: row, position: index + 1)
                        .id("standing-\(row.id)")
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(AppColors.stroke)
                            .opacity(0.5)
                            .padding(.leading, 60)
                    }
                }
            }
            .padding(AppSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
            .animation(nil, value: rows.map { "\($0.id)-\($0.primaryValue)" })
        }
        .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: selected)
    }

    private func leaderboardRow(row: FriendsLeaderboardRowModel, position: Int) -> some View {
        let leaderValue = rows.first?.primaryValue ?? 0
        let fraction = leaderValue > 0 ? min(1, max(0, row.primaryValue / leaderValue)) : 0
        return HStack(spacing: AppSpacing.sm) {
            Text("\(position)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(position <= 3 ? LeaderboardRankStyle.color(position) : AppColors.subtext)
                .frame(width: 24, alignment: .center)

            avatar(row: row, size: 36, accentHalo: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if row.isMe {
                        Text("YOU")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.accent.opacity(0.12)))
                            .foregroundStyle(AppColors.accent)
                            .fixedSize()
                    }
                }
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: AppSpacing.xs)

            VStack(alignment: .trailing, spacing: 4) {
                Text(row.primaryDisplay)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: true, vertical: false)
                LeaderboardRelativeBar(fraction: fraction)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(row.isMe ? AppColors.accent.opacity(0.12) : Color.clear)
        )
    }

    private func avatar(row: FriendsLeaderboardRowModel?, size: CGFloat, accentHalo: Bool) -> some View {
        ProfileAvatarView(
            name: row?.displayName ?? "—",
            size: size,
            photoURL: row?.profilePhotoURL,
            uid: row?.id,
            showsAccentRing: accentHalo
        )
    }

    private var emptyState: some View {
        AppEmptyState(
            icon: "person.2.slash",
            title: "No friends to rank yet",
            message: "Add a friend with their code to see weekly standings together."
        )
        .padding(AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.stroke, lineWidth: 0.5)
        )
    }

    // MARK: - Rows (model lives in FriendsLeaderboardSections.swift)

    private var rows: [FriendsLeaderboardRowModel] {
        let myRow = makeRow(forSelf: true)
        // All three categories depend on hours-derived data (weeklyHours,
        // weeklyShiftsLogged, daysLogged, currentStreak). When a friend has opted
        // out of `shareHours` those fields are zeroed at write time AND we
        // skip them in the leaderboard so they don't appear with a misleading
        // "0" rank — privacy + UX both stay clean.
        let friendRows: [FriendsLeaderboardRowModel] = {
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

    private func makeRow(forSelf: Bool) -> FriendsLeaderboardRowModel {
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

    private func makeRow(forFriend friend: FriendProfile) -> FriendsLeaderboardRowModel {
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
    ) -> FriendsLeaderboardRowModel {
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
        return FriendsLeaderboardRowModel(
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
