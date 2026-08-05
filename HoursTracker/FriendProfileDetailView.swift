import SwiftUI
import FirebaseFunctions

/// Drill-in profile for a friend — tap from the Friends list.
///
/// Accents on this screen are tinted by the FRIEND's prestige tier
/// (`PrestigeTheme` colors for their tier) — avatar ring, tier label, stat
/// numerals, and badge rings. The global theme is never retinted; at P0 the
/// screen falls back to the viewer's normal accent.
struct FriendProfileDetailView: View {
    let friendUid: String
    @ObservedObject var friendsService: FriendsService
    var onRemoveFriend: ((FriendProfile) async -> Bool)? = nil

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveConfirm = false
    @State private var isRemoving = false
    @State private var showFullPhoto = false
    @State private var showAllBadges = false

    // Nudge (service owns cooldown + delivery; this is just the entry point).
    @State private var isSendingNudge = false
    @State private var nudgeSent = false
    @State private var nudgeMessage: String?

    // CEO-only stats recompute (also gated server-side by UID + passcode).
    @State private var showAdminPasscodePrompt = false
    @State private var adminPasscode = ""
    @State private var isAdminRecomputing = false
    @State private var adminResultMessage: String?

    private var isCEO: Bool {
        DeveloperConfig.isCEO(uid: authService.user?.uid)
    }

    private var friend: FriendProfile? {
        friendsService.friends.first { $0.uid == friendUid }
    }

    /// The friend's tier accent for this screen. P0 falls back to the app accent.
    private func tint(for friend: FriendProfile) -> Color {
        friend.prestige > 0 ? friend.prestigeTier.primary : AppColors.accent
    }

    private func secondaryTint(for friend: FriendProfile) -> Color {
        friend.prestige > 0 ? friend.prestigeTier.accent2 : AppColors.accent2
    }

    var body: some View {
        Group {
            if let friend {
                profileContent(friend: friend)
            } else {
                AppLoadingState(message: "Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.bg.ignoresSafeArea())
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
        .alert("Admin passcode", isPresented: $showAdminPasscodePrompt) {
            SecureField("Passcode", text: $adminPasscode)
            Button("Recompute") {
                Task { await performAdminRecompute() }
            }
            Button("Cancel", role: .cancel) { adminPasscode = "" }
        } message: {
            Text("Force a stats recompute for this user.")
        }
        .alert("Admin", isPresented: Binding(
            get: { adminResultMessage != nil },
            set: { if !$0 { adminResultMessage = nil } }
        )) {
            Button("OK") { adminResultMessage = nil }
        } message: {
            Text(adminResultMessage ?? "")
        }
    }

    @ViewBuilder
    private func profileContent(friend: FriendProfile) -> some View {
        let accent = tint(for: friend)

        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                identityHeader(friend: friend, accent: accent)

                if friend.hasCompanyInfo {
                    companyCard(friend: friend, accent: accent)
                }

                personalBestsCard(friend: friend, accent: accent)

                if friend.privacy.shareHours {
                    careerStatsCard(friend: friend, accent: accent)
                } else {
                    FriendHiddenHoursCard()
                }

                if friend.privacy.shareBadges, friend.hasBadgeDetail {
                    FriendBadgesCard(friend: friend, accent: accent, showAllBadges: $showAllBadges)
                }

                if isCEO {
                    adminRecomputeButton(friend: friend)
                }

                nudgeSection(friend: friend, accent: accent)

                if onRemoveFriend != nil {
                    removeFriendButton(friend: friend)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, 10)
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
    }

    // MARK: - Identity

    private func identityHeader(friend: FriendProfile, accent: Color) -> some View {
        let tier = friend.prestigeTier
        return VStack(spacing: 10) {
            ProfileAvatarView(
                name: friend.displayName,
                size: 76,
                photoURL: friend.profilePhotoURL,
                uid: friend.uid,
                showsAccentRing: false
            )
            .overlay(
                Circle()
                    .stroke(accent.opacity(0.75), lineWidth: 2)
                    .padding(-4)
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

            Text(friend.displayName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)

            Text(friend.rankTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent)

            Text(friend.levelDisplayLine)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.subtext)

            HStack(spacing: 6) {
                Image(systemName: tier.icon)
                    .font(.system(size: 12, weight: .bold))
                Text("Prestige \(friend.prestige) • \(tier.name)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(accent.opacity(0.12))
                    .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 1))
            )

            if !friend.equippedTitle.isEmpty, friend.privacy.shareBadges {
                Text("\u{201C}\(friend.equippedTitle)\u{201D}")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Company

    private func companyCard(friend: FriendProfile, accent: Color) -> some View {
        SectionCard(
            title: companyTitle(for: friend),
            subtitle: companySubtitle(for: friend),
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                if let start = friend.companyStartDate {
                    FriendRecordRow(
                        icon: "building.2.fill",
                        title: "Started",
                        value: FriendProfileFormat.companyStartedString(from: start),
                        tint: accent
                    )
                    FriendRecordRow(
                        icon: "briefcase.fill",
                        title: "Time at company",
                        value: FriendProfileFormat.tenureAtCompanyString(from: start),
                        tint: accent
                    )
                    let years = FriendProfileFormat.yearsAtCompany(from: start)
                    if years >= 0.1 {
                        FriendRecordRow(
                            icon: "star.circle.fill",
                            title: "Years worked",
                            value: String(format: "%.1f", years),
                            tint: accent
                        )
                    }
                    if let anniversary = FriendProfileFormat.nextWorkAnniversary(from: start) {
                        FriendRecordRow(
                            icon: "gift.fill",
                            title: "Next anniversary",
                            value: FriendProfileFormat.anniversaryCountdownString(to: anniversary),
                            detail: FriendProfileFormat.anniversaryDateString(anniversary),
                            tint: accent
                        )
                    }
                }

                if friend.privacy.shareHours {
                    FriendRecordRow(
                        icon: "clock.fill",
                        title: "Hours logged",
                        value: FriendProfileFormat.hoursDisplay(friend.companyHoursLogged),
                        detail: friend.companyStartDate == nil ? "All shared shifts" : "Since start date",
                        tint: accent
                    )
                    FriendRecordRow(
                        icon: "calendar",
                        title: "Days worked",
                        value: "\(friend.companyDaysWorked)",
                        tint: accent
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

    // MARK: - Stats

    private func careerStatsCard(friend: FriendProfile, accent: Color) -> some View {
        SectionCard(
            title: "Career stats",
            subtitle: "Long-term totals from shared data",
            trailing: nil,
            centerHeader: true
        ) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                MetricDisplay(icon: "clock.fill", label: "All-Time Hours", value: FriendProfileFormat.hoursDisplay(friend.totalHours), tint: accent, valueTint: accent)
                MetricDisplay(icon: "calendar", label: "Hours This Week", value: FriendProfileFormat.hoursDisplay(friend.weeklyHours), tint: accent, valueTint: accent)
                MetricDisplay(icon: "plus.circle.fill", label: "Shifts This Week", value: "\(friend.weeklyShiftsLogged)", tint: accent, valueTint: accent)
                MetricDisplay(icon: "chart.bar.fill", label: "Days This Week", value: "\(friend.weeklyDaysLogged)", tint: accent, valueTint: accent)
            }
            .padding(.vertical, 8)
        }
    }

    private func personalBestsCard(friend: FriendProfile, accent: Color) -> some View {
        SectionCard(
            title: "Personal bests",
            subtitle: "Streaks and milestones",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                FriendRecordRow(icon: "flame.fill", title: "Best Streak", value: FriendProfileFormat.streakValueString(friend.bestStreak), tint: AppColors.streak)
                FriendRecordRow(icon: "flame", title: "Current Streak", value: FriendProfileFormat.streakValueString(friend.currentStreak), tint: accent)
                if let since = friend.friendsSince {
                    FriendRecordRow(icon: "person.2.fill", title: "Friends since", value: FriendProfileFormat.friendsSinceString(since), tint: secondaryTint(for: friend))
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Nudge

    private func nudgeSection(friend: FriendProfile, accent: Color) -> some View {
        VStack(spacing: 6) {
            FriendShiftNudgeButton(
                friendUid: friend.uid,
                isSending: isSendingNudge,
                didSend: nudgeSent,
                tint: accent
            ) {
                Task { await performNudge(friend: friend) }
            }
            if let nudgeMessage {
                Text(nudgeMessage)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
    }

    private func performNudge(friend: FriendProfile) async {
        guard !isSendingNudge, !nudgeSent else { return }
        guard let uid = authService.user?.uid else { return }
        let myName = UserDefaults.standard.string(forKey: "profile_display_name") ?? "A friend"
        isSendingNudge = true
        nudgeMessage = nil
        defer { isSendingNudge = false }
        do {
            try await FriendShiftNudgeService.shared.sendNudge(
                to: friend.uid,
                myUid: uid,
                myName: myName
            )
            Haptics.success()
            nudgeSent = true
            nudgeMessage = "They'll get a reminder to log their shifts."
        } catch {
            Haptics.error()
            nudgeMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't send the nudge. Try again later."
        }
    }

    // MARK: - Admin

    private func adminRecomputeButton(friend: FriendProfile) -> some View {
        Button {
            adminPasscode = ""
            showAdminPasscodePrompt = true
        } label: {
            HStack(spacing: 8) {
                if isAdminRecomputing {
                    ProgressView().tint(AppColors.accent)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(isAdminRecomputing ? "Recomputing…" : "Recompute stats (admin)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isAdminRecomputing)
    }

    private func performAdminRecompute() async {
        let passcode = adminPasscode
        adminPasscode = ""
        guard !passcode.isEmpty else { return }
        isAdminRecomputing = true
        defer { isAdminRecomputing = false }
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("adminRecomputeUserStats")
                .call(["targetUid": friendUid, "passcode": passcode])
            await friendsService.refreshFriendProfiles()
            adminResultMessage = "Stats recomputed. Pull to refresh if needed."
        } catch {
            adminResultMessage = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Remove

    private func removeFriendButton(friend: FriendProfile) -> some View {
        Button(role: .destructive) {
            showRemoveConfirm = true
        } label: {
            HStack(spacing: 10) {
                if isRemoving {
                    ProgressView()
                        .tint(AppColors.negative)
                } else {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Remove Friend")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppColors.negative)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.negative.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.negative.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isRemoving)
        .padding(.top, 4)
    }

    private func performRemove() async {
        guard let friend, let onRemoveFriend else { return }
        isRemoving = true
        let removed = await onRemoveFriend(friend)
        isRemoving = false
        if removed {
            dismiss()
        }
    }
}
