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
            HomeSectionHeader("Recent shifts")

            if recentEntries.isEmpty {
                // No owl here: the Today card's owl directly above already
                // points new users at this button (one owl per view).
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
                VStack(spacing: 0) {
                    ForEach(Array(recentEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0, !Calendar.current.isDateInToday(entry.date),
                           !Calendar.current.isDateInToday(recentEntries[index - 1].date) {
                            Divider().overlay(AppColors.stroke)
                        }
                        Button {
                            Haptics.lightTap()
                            onSelect(entry)
                        } label: {
                            EntryRowView(
                                entry: entry,
                                breakdown: store.payBreakdown(for: entry),
                                currencyCode: store.paySettings.currencyCode,
                                showPay: store.paySettings.showPayCalculations,
                                paySettings: store.paySettings,
                                leaf: true
                            )
                        }
                        .buttonStyle(PremiumPressStyle())
                    }

                    Button("View all shifts", action: onViewAll)
                        .buttonStyle(QuietSectionButtonStyle())
                        .padding(.top, AppSpacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Friends standings card (every friend, this cheque)

struct HomeFriendsCard: View {
    @ObservedObject var friendsService: FriendsService
    @ObservedObject var store: HoursStore
    @ObservedObject var authService: AuthService

    @State private var showingFriendsPicker = false

    var body: some View {
        // Each friend's row opens their profile (with their cheque day by
        // day); the card itself is not a button.
            VStack(spacing: AppSpacing.sm) {
                HomeSectionHeader(title: "Friends") {
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
                        .offset(y: -6)
                    }

                HomeFriendsCardContent(
                    friendsService: friendsService,
                    store: store,
                    authService: authService
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xxs)
                .padding(.horizontal, AppSpacing.md)
                .homeCard()
            }
            .frame(maxWidth: .infinity)
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
        /// Drives the Ascended (P11+) name/avatar marks.
        var prestige: Int = 0
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
                hasReviewedApp: VerifiedStatusService.shared.isVerified,
                prestige: store.displayedPrestige
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
                    hasReviewedApp: $0.hasReviewedApp,
                    prestige: $0.prestige
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
                    hasReviewedApp: $0.hasReviewedApp,
                    prestige: $0.prestige
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
                        Divider().overlay(AppColors.stroke)
                    }
                    profileLink(row) { standingsRow(row, rank: index + 1) }
                }

                ForEach(hidden) { row in
                    Divider().overlay(AppColors.stroke)
                    profileLink(row) { standingsRow(row, rank: nil) }
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

    /// Friends' rows push their profile; your own row isn't a link.
    @ViewBuilder
    private func profileLink<Row: View>(_ row: StandingsRow, @ViewBuilder _ content: () -> Row) -> some View {
        if row.isMe {
            content()
        } else {
            NavigationLink {
                FriendProfileDetailView(friendUid: row.id, friendsService: friendsService)
            } label: {
                content().contentShape(Rectangle())
            }
            .buttonStyle(PremiumPressStyle())
            .accessibilityHint("Shows their hours for each day of this cheque")
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
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill((rank.map(rankColor) ?? AppColors.subtext).opacity(0.2))
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
                size: 34,
                photoURL: row.profilePhotoURL,
                uid: row.id
            )
            .ascendedAvatarRing(prestige: row.prestige, diameter: 34, inset: 1.5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    PrestigeNameText(name: row.name, prestige: row.prestige, uid: row.id)
                        .appText(.subheadline)
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
                HoursValue(hours: row.hours, size: 18, unitSize: 11, gap: 4)
            }
            if !row.isMe {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.subtext.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
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
        }
        .buttonStyle(ChunkyButtonStyle(kind: .secondary))
    }
}
