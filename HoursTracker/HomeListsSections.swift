import SwiftUI
import Combine

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                                // Ease-out growth from the baseline: fast
                                // launch, gentle landing — no spring wobble on
                                // a data chart. 40ms per month keeps the whole
                                // year under a second.
                                .animation(
                                    reduceMotion
                                        ? nil
                                        : .easeOut(duration: 0.55).delay(Double(index) * 0.04),
                                    value: appeared
                                )
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

// MARK: - Friends standings card (every friend, this cheque)

struct HomeFriendsCard: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject var store: HoursStore
    @ObservedObject var authService: AuthService
    let onOpenFriends: () -> Void

    @State private var showingFriendsPicker = false

    var body: some View {
        Button(action: onOpenFriends) {
            VStack(spacing: AppSpacing.sm) {
                SectionEyebrow("Friends")
                    // Trailing overlay so the eyebrow itself stays centered.
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Button {
                            Haptics.lightTap()
                            showingFriendsPicker = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.subtext)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose which friends show here")
                    }

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
        .sheet(isPresented: $showingFriendsPicker) {
            HomeFriendsPickerSheet(friendsService: friendsService)
        }
    }
}

struct HomeFriendsCardContent: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject var store: HoursStore
    @ObservedObject var authService: AuthService
    @ObservedObject private var statsListener = StatsListenerService.shared
    @ObservedObject private var filter = HomeFriendsFilter.shared

    private struct StandingsRow: Identifiable {
        let id: String
        let name: String
        let hours: Double
        let levelLine: String
        let profilePhotoURL: String?
        let isMe: Bool
        /// True for friends whose `privacy.shareHours` is off. They are still
        /// listed (so every friend is visible) but their hours stay hidden and
        /// they are never ranked against the sharing standings.
        var hoursHidden: Bool = false
        /// Verified badge, same rule as every other surface.
        var hasReviewedApp: Bool = false
    }

    /// Ranked standings: me plus every friend who shares hours. Sorted by
    /// cheque hours descending, then name — unchanged from the previous
    /// top-3 card, just uncapped.
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
                isMe: true,
                hasReviewedApp: VerifiedStatusService.shared.isVerified
            )
        ]
        rows += friendsService.friends
            .filter { $0.privacy.shareHours && filter.isVisible($0.uid) }
            .map {
                StandingsRow(
                    id: $0.uid,
                    name: $0.displayName,
                    hours: $0.chequeHours,
                    levelLine: $0.levelDisplayLine,
                    profilePhotoURL: $0.profilePhotoURL,
                    isMe: false,
                    hasReviewedApp: $0.hasReviewedApp
                )
            }
        return rows
            .sorted {
                if $0.hours != $1.hours { return $0.hours > $1.hours }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    /// Friends who keep their hours private. Listed after the ranked rows with
    /// the same "Hours hidden" treatment the Friends tab uses (`FriendStatsRow`).
    private var hiddenRows: [StandingsRow] {
        friendsService.friends
            .filter { !$0.privacy.shareHours && filter.isVisible($0.uid) }
            .map {
                StandingsRow(
                    id: $0.uid,
                    name: $0.displayName,
                    hours: 0,
                    levelLine: $0.levelDisplayLine,
                    profilePhotoURL: $0.profilePhotoURL,
                    isMe: false,
                    hoursHidden: true,
                    hasReviewedApp: $0.hasReviewedApp
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let ranked = standings
        let hidden = hiddenRows

        return VStack(spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().opacity(0.2)
                    }
                    standingsRow(row, rank: index + 1)
                }

                ForEach(hidden) { row in
                    Divider().opacity(0.2)
                    standingsRow(row, rank: nil)
                }
            }

        }
        .animation(nil, value: ranked.map { "\($0.id)-\($0.hours)" })
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

    /// `rank` is nil for private friends — they get a lock pip instead of a
    /// number because they are not ranked against the sharing standings.
    private func standingsRow(_ row: StandingsRow, rank: Int?) -> some View {
        HStack(spacing: AppSpacing.xs + 2) {
            ZStack {
                Circle()
                    .fill((rank.map(rankColor) ?? AppColors.subtext).opacity(0.18))
                    .frame(width: 24, height: 24)
                if let rank {
                    Text("\(rank)")
                        .font(AppTypography.eyebrow.monospacedDigit())
                        .foregroundStyle(rankColor(rank))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColors.subtext)
                }
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

                    if VerifiedTracker.isVerified(reviewed: row.hasReviewedApp) {
                        // Static: this card lists every friend on Home.
                        VerifiedBadgeView(variant: .static, size: 12)
                    }

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

            if row.hoursHidden {
                Text("Hours hidden")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
            } else {
                Text(AppTheme.Format.hours(row.hours))
                    .font(AppTypography.metricValue)
                    .foregroundStyle(rank == 1 ? AppColors.accent : AppColors.text)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}


// MARK: - Admin console entry

/// Home's way into the admin console, shown only to the CEO uid.
///
/// Sits directly under Recent Shifts. Styled as a quiet single row rather than
/// a full card: it's a door, not a surface with content of its own, and it
/// shouldn't compete with the cards carrying the user's actual hours.
struct HomeAdminConsoleCard: View {
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text("Admin console")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
                .frame(maxWidth: .infinity)
                // Trailing overlay rather than an HStack sibling: a chevron in
                // the flow would shift the label off true centre by its width.
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.faint)
                }
                .padding(AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Home friends visibility

/// Which friends the HOME card shows. A device-local display preference: it
/// never touches the friendship itself, and the Friends tab still lists
/// everyone. Default is everyone visible, so the card behaves exactly as
/// before until someone hides a row.
@MainActor
final class HomeFriendsFilter: ObservableObject {
    static let shared = HomeFriendsFilter()
    private static let key = "home_friends_hidden_uids_v1"

    @Published private(set) var hiddenUids: Set<String>

    private init() {
        hiddenUids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isVisible(_ uid: String) -> Bool { !hiddenUids.contains(uid) }

    func setVisible(_ visible: Bool, uid: String) {
        if visible { hiddenUids.remove(uid) } else { hiddenUids.insert(uid) }
        UserDefaults.standard.set(Array(hiddenUids), forKey: Self.key)
    }
}

/// The toggle list behind the Home card's slider button: every friend, each
/// with a switch for whether they appear on the Home card.
struct HomeFriendsPickerSheet: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject private var filter = HomeFriendsFilter.shared
    @Environment(\.dismiss) private var dismiss

    private var sortedFriends: [FriendProfile] {
        friendsService.friends.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedFriends) { friend in
                        Toggle(isOn: Binding(
                            get: { filter.isVisible(friend.uid) },
                            set: { visible in
                                Haptics.lightTap()
                                filter.setVisible(visible, uid: friend.uid)
                            }
                        )) {
                            HStack(spacing: AppSpacing.sm) {
                                ProfileAvatarView(
                                    name: friend.displayName,
                                    size: 34,
                                    photoURL: friend.profilePhotoURL,
                                    uid: friend.uid
                                )
                                Text(friend.displayName)
                                    .appText(.body)
                                    .foregroundStyle(AppColors.text)
                                    .lineLimit(1)
                                if VerifiedTracker.isVerified(reviewed: friend.hasReviewedApp) {
                                    VerifiedBadgeView(variant: .static, size: 12)
                                }
                            }
                        }
                        .tint(AppColors.accent)
                        .listRowBackground(AppColors.card.opacity(0.55))
                    }
                } footer: {
                    Text("Only changes who shows on your Home screen. Everyone stays in your Friends tab, and nobody is notified.")
                        .foregroundStyle(AppColors.faint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Friends on Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
