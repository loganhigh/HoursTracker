import SwiftUI

/// Drill-in profile for a friend — tap from Friends list.
struct FriendProfileDetailView: View {
    let friendUid: String
    @ObservedObject var friendsService: FriendsService
    var onRemoveFriend: ((FriendProfile) async -> Bool)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveConfirm = false
    @State private var isRemoving = false
    @State private var showFullPhoto = false
    @State private var showAllBadges = false

    private var friend: FriendProfile? {
        friendsService.friends.first { $0.uid == friendUid }
    }

    var body: some View {
        Group {
            if let friend {
                profileContent(friend: friend)
            } else {
                SoftLoadingIndicator(title: "Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.Colors.bg.ignoresSafeArea())
            }
        }
        .navigationTitle(friend?.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                if friend == nil {
                    await friendsService.fetchProfileDirectly(uid: friendUid)
                }
                await friendsService.refreshFriendProfiles()
            }
        }
        .refreshable {
            await friendsService.refreshFriendProfiles()
        }
        .alert("Remove friend?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                Task { await performRemove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let friend {
                Text("Remove \(friend.displayName) from your friends list? They will also stop seeing your stats.")
            }
        }
    }

    @ViewBuilder
    private func profileContent(friend: FriendProfile) -> some View {
        let tier = friend.prestigeTier

        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                identityHeader(friend: friend, tier: tier)

                if friend.hasCompanyInfo {
                    companyCard(friend: friend)
                }

                personalBestsCard(friend: friend)

                if friend.privacy.shareHours {
                    careerStatsCard(friend: friend)
                    if friend.hasChequeDetail {
                        chequeDetailCard(friend: friend, tier: tier)
                    }
                } else {
                    hiddenHoursCard
                }

                if friend.privacy.shareBadges, friend.hasBadgeDetail {
                    badgesCard(friend: friend, tier: tier)
                }

                if onRemoveFriend != nil {
                    removeFriendButton(friend: friend)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
    }

    // MARK: - Identity

    private func identityHeader(friend: FriendProfile, tier: PrestigeTheme.Tier) -> some View {
        VStack(spacing: 10) {
            ProfileAvatarView(
                name: friend.displayName,
                size: 72,
                photoURL: friend.profilePhotoURL,
                uid: friend.uid,
                showsAccentRing: true
            )
            .onTapGesture {
                if friend.profilePhotoURL != nil {
                    showFullPhoto = true
                }
            }
            .fullScreenCover(isPresented: $showFullPhoto) {
                ExpandedPhotoView(
                    name: friend.displayName,
                    photoURL: friend.profilePhotoURL,
                    uid: friend.uid
                )
            }

            Text(friend.rankTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tier.primary)

            Text(friend.levelDisplayLine)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)

            if friend.prestige > 0 {
                HStack(spacing: 6) {
                    Image(systemName: tier.icon)
                        .font(.system(size: 12, weight: .bold))
                    Text("Prestige \(friend.prestige)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(tier.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(tier.primary.opacity(0.14))
                        .overlay(Capsule().stroke(tier.primary.opacity(0.45), lineWidth: 1))
                )
            }

            if !friend.equippedTitle.isEmpty, friend.privacy.shareBadges {
                Text(friend.equippedTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tier.highlight.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Company

    private func companyCard(friend: FriendProfile) -> some View {
        SectionCard(
            title: companyTitle(for: friend),
            subtitle: companySubtitle(for: friend),
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                if let start = friend.companyStartDate {
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
                    let years = yearsAtCompany(from: start)
                    if years >= 0.1 {
                        recordRow(
                            icon: "star.circle.fill",
                            title: "Years worked",
                            value: String(format: "%.1f", years),
                            tint: .yellow
                        )
                    }
                    if let anniversary = nextWorkAnniversary(from: start) {
                        recordRow(
                            icon: "gift.fill",
                            title: "Next anniversary",
                            value: anniversaryCountdownString(to: anniversary),
                            detail: anniversaryDateString(anniversary),
                            tint: .pink
                        )
                    }
                }

                if friend.privacy.shareHours {
                    recordRow(
                        icon: "clock.fill",
                        title: "Hours logged",
                        value: hoursDisplay(friend.companyHoursLogged),
                        detail: friend.companyStartDate == nil ? "All shared shifts" : "Since start date",
                        tint: .orange
                    )
                    recordRow(
                        icon: "calendar",
                        title: "Days worked",
                        value: "\(friend.companyDaysWorked)",
                        tint: .blue
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func companyTitle(for friend: FriendProfile) -> String {
        let company = friend.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return company.isEmpty ? "Work" : company
    }

    private func companySubtitle(for friend: FriendProfile) -> String {
        let role = friend.companyOccupation.trimmingCharacters(in: .whitespacesAndNewlines)
        return role.isEmpty ? "Company details they've shared" : role
    }

    // MARK: - Career-style sections

    private func lifetimeHero(friend: FriendProfile) -> some View {
        let tier = friend.prestigeTier
        return VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: tier.gradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text(hoursDisplay(friend.totalHours))
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
            Text("Lifetime hours logged")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tier.primary.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func careerStatsCard(friend: FriendProfile) -> some View {
        let tier = friend.prestigeTier
        return SectionCard(
            title: "Career stats",
            subtitle: "Long-term totals from shared data",
            trailing: nil,
            centerHeader: true
        ) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                FriendCareerStatTile(label: "All-Time Hours", value: hoursDisplay(friend.totalHours), icon: "clock.fill", tint: tier.primary)
                FriendCareerStatTile(label: "This Cheque", value: hoursDisplay(friend.chequeHours), icon: "calendar", tint: tier.primary)
                FriendCareerStatTile(label: "Shifts This Week", value: "\(friend.weeklyShiftsLogged)", icon: "plus.circle.fill", tint: tier.primary)
                FriendCareerStatTile(label: "Days This Week", value: "\(friend.weeklyDaysLogged)", icon: "chart.bar.fill", tint: tier.primary)
            }
            .padding(.vertical, 8)
        }
    }

    private func personalBestsCard(friend: FriendProfile) -> some View {
        let tier = friend.prestigeTier
        return SectionCard(
            title: "Personal bests",
            subtitle: "Streaks and milestones",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                recordRow(icon: "flame.fill", title: "Best Streak", value: streakValueString(friend.bestStreak), tint: .red)
                recordRow(icon: "flame", title: "Current Streak", value: streakValueString(friend.currentStreak), tint: tier.primary)
                if let since = friend.friendsSince {
                    recordRow(icon: "person.2.fill", title: "Friends since", value: friendsSinceString(since), tint: tier.accent2)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func badgesCard(friend: FriendProfile, tier: PrestigeTheme.Tier) -> some View {
        let earned = friend.unlockedBadgeSummaries.filter { !$0.isLegend }
        let legend = friend.unlockedBadgeSummaries.filter(\.isLegend)
        let displayCount = earned.isEmpty ? friend.badgeCount : earned.count

        return SectionCard(
            title: "Badges",
            subtitle: "\(displayCount) badges unlocked",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 16) {
                if friend.unlockedBadgeSummaries.isEmpty {
                    Text("Badge details will appear after \(friend.displayName) opens the app.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    if !earned.isEmpty {
                        let visible = showAllBadges ? earned : Array(earned.prefix(9))
                        friendBadgesGrid(badges: visible, tier: tier)
                        if earned.count > 9 && !showAllBadges {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showAllBadges = true
                                }
                            } label: {
                                Text("See all \(earned.count) badges")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AppTheme.Colors.accent.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !legend.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Legend")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            friendBadgesGrid(badges: legend, tier: tier)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func friendBadgesGrid(badges: [SharedBadgeSummary], tier: PrestigeTheme.Tier) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(badges) { badge in
                FriendBadgeTile(badge: badge, tier: tier)
            }
        }
    }

    // MARK: - Cheque Detail

    private func chequeDetailCard(friend: FriendProfile, tier: PrestigeTheme.Tier) -> some View {
        let entries = chequeDays(for: friend)
        let loggedEntries = entries.filter { $0.hours > 0 || $0.shifts > 0 }
        let maxHours = loggedEntries.map(\.hours).max() ?? 1
        let subtitle = chequeWindowSubtitle(start: friend.chequeWindowStart, cutoff: friend.chequeWindowCutoff)
        let totalHours = entries.reduce(0.0) { $0 + $1.hours }
        let totalShifts = entries.reduce(0) { $0 + $1.shifts }

        return SectionCard(
            title: "This Cheque",
            subtitle: subtitle,
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 8) {
                if entries.isEmpty {
                    Text("Shift details will appear after \(friend.displayName) opens the app.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    HStack {
                        Text("\(loggedEntries.count) days • \(totalShifts) shifts • \(hoursDisplay(totalHours))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.subtext)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(entries) { entry in
                        chequeDayRow(entry: entry, maxHours: maxHours, tint: tier.primary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// Builds a full day-by-day list for the friend's cheque window, filling
    /// in zero-hour days so the viewer sees the entire period to date.
    private func chequeDays(for friend: FriendProfile) -> [FriendDailyEntry] {
        let iso = FriendDailyEntry.isoFormatter
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        guard
            let start = iso.date(from: friend.chequeWindowStart),
            let cutoff = iso.date(from: friend.chequeWindowCutoff)
        else {
            return friend.chequeDailySummary.sorted { $0.date < $1.date }
        }

        let hoursByDate = Dictionary(uniqueKeysWithValues: friend.chequeDailySummary.map { ($0.date, $0) })
        var days: [FriendDailyEntry] = []
        var cursor = cal.startOfDay(for: start)
        let lastIncluded = min(cal.startOfDay(for: cutoff), today)

        while cursor <= lastIncluded {
            let key = iso.string(from: cursor)
            if let existing = hoursByDate[key] {
                days.append(existing)
            } else {
                days.append(FriendDailyEntry(date: key, hours: 0, shifts: 0))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return days
    }

    private func chequeDayRow(entry: FriendDailyEntry, maxHours: Double, tint: Color) -> some View {
        let hasShift = entry.hours > 0 || entry.shifts > 0
        return HStack(spacing: 10) {
            // Day label
            Group {
                if let date = entry.calendarDate {
                    VStack(alignment: .center, spacing: 1) {
                        Text(dayAbbrev(date))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(hasShift ? AppTheme.Colors.subtext : AppTheme.Colors.faint)
                        Text(dayNum(date))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(hasShift ? AppTheme.Colors.text : AppTheme.Colors.faint)
                    }
                } else {
                    Text(entry.date)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .frame(width: 32)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(hasShift ? 0.12 : 0.05))
                        .frame(height: 22)
                    if hasShift {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.9), tint.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(8, geo.size.width * CGFloat(min(1, entry.hours / max(maxHours, 0.01)))),
                                height: 22
                            )
                    }
                }
            }
            .frame(height: 22)

            // Hours + shift count
            VStack(alignment: .trailing, spacing: 1) {
                Text(hasShift ? hoursDisplay(entry.hours) : "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(hasShift ? AppTheme.Colors.text : AppTheme.Colors.faint)
                    .monospacedDigit()
                if entry.shifts > 1 {
                    Text("\(entry.shifts) shifts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .opacity(hasShift ? 1 : 0.55)
    }

    private func chequeWindowSubtitle(start: String, cutoff: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        guard
            let s = f.date(from: start),
            let e = f.date(from: cutoff)
        else { return "Current pay period" }
        return "\(display.string(from: s)) – \(display.string(from: e))"
    }

    private func dayAbbrev(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNum(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var hiddenHoursCard: some View {
        SectionCard(
            title: "Hours hidden",
            subtitle: "This friend has chosen not to share work stats",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.subtext)
                Text("Rank and level are still visible, but hour totals stay private.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func removeFriendButton(friend: FriendProfile) -> some View {
        Button(role: .destructive) {
            showRemoveConfirm = true
        } label: {
            HStack(spacing: 10) {
                if isRemoving {
                    ProgressView()
                        .tint(.red)
                } else {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Remove Friend")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isRemoving)
        .padding(.top, 4)
    }

    // MARK: - Rows

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
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
    }

    // MARK: - Actions

    private func performRemove() async {
        guard let friend, let onRemoveFriend else { return }
        isRemoving = true
        defer { isRemoving = false }
        let removed = await onRemoveFriend(friend)
        if removed {
            dismiss()
        }
    }

    // MARK: - Formatting

    private func hoursDisplay(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value) + "h"
        }
        return AppTheme.Format.hours(value)
    }

    private func streakValueString(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func companyStartedString(from start: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return df.string(from: start)
    }

    private func yearsAtCompany(from start: Date) -> Double {
        max(0, Date().timeIntervalSince(start) / (60 * 60 * 24 * 365.25))
    }

    private func nextWorkAnniversary(from start: Date) -> Date? {
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

    private func tenureAtCompanyString(from start: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: start, to: Date())
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        if years == 0 && months == 0 { return "Less than a month" }
        if years == 0 { return months == 1 ? "1 month" : "\(months) months" }
        if months == 0 { return years == 1 ? "1 year" : "\(years) years" }
        let yearPart = years == 1 ? "1 year" : "\(years) years"
        let monthPart = months == 1 ? "1 month" : "\(months) months"
        return "\(yearPart), \(monthPart)"
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

    private func friendsSinceString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }
}

// MARK: - Stat tile (matches CareerView)

private struct FriendBadgeTile: View {
    let badge: SharedBadgeSummary
    let tier: PrestigeTheme.Tier

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: tier.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: tier.primary.opacity(0.35), radius: 8, y: 2)

                Image(systemName: badge.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 60)

            VStack(spacing: 2) {
                Text(badge.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(height: 28, alignment: .top)

                Text(badge.detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(height: 24, alignment: .top)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }
}

private struct FriendCareerStatTile: View {
    let label: String
    let value: String
    let icon: String
    var tint: Color = AppTheme.Colors.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
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

private struct ExpandedPhotoView: View {
    let name: String
    let photoURL: String?
    let uid: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                }
                Spacer()
                ProfileAvatarView(
                    name: name,
                    size: 280,
                    photoURL: photoURL,
                    uid: uid,
                    showsAccentRing: false
                )
                Text(name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                Spacer()
            }
        }
    }
}
