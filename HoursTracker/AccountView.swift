import SwiftUI
import PhotosUI

// MARK: - Account view (Phase 9 — You tab root)
//
// Identity hero on the background (no card), XP capsule seeded from the Home
// strip's cache, lifetime stats grid, quiet navigation card, and the account
// card (cloud sync / sign out / delete / sign-in options). Auth, photo, and
// deletion flows are unchanged — this phase is presentation only. Row/capsule
// building blocks live in AccountSections.swift.

struct AccountView: View {
    @ObservedObject var store: HoursStore
    // Server stats drive displayedGamificationProfile(); observe so the hero
    // and lifetime grid re-render when the server snapshot lands (HoursStore
    // itself doesn't republish on it).
    @ObservedObject private var statsListener = StatsListenerService.shared
    @EnvironmentObject private var authService: AuthService
    @Environment(\.openURL) private var openURL

    @AppStorage("profile_display_name") private var storedDisplayName: String = ""

    @State private var showingSettings = false
    @State private var showingDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUpdatingPhoto = false
    @ObservedObject private var photoManager = ProfilePhotoManager.shared

    // MARK: - Identity data

    private var displayName: String {
        let trimmed = storedDisplayName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let fbName = authService.user?.displayName?.trimmingCharacters(in: .whitespaces)
        if let fbName, !fbName.isEmpty { return fbName }
        return "Guest"
    }

    private var equippedTitle: String {
        store.displayedEquippedTitle
    }

    // MARK: - Lifetime stats

    private var workEntries: [WorkEntry] {
        // Span the year archive: archivePriorYearsIfNeeded moves prior-year
        // entries out of `store.entries`, so reading `entries` alone would drop
        // every year before the current one after the Jan-1 rollover.
        store.allEntriesIncludingArchive().filter { !$0.isOffDay }
    }

    private var allTimeHours: Double {
        // Prefer the server-computed total so this grid, Career, and the
        // leaderboard always agree. Local sum when offline or signed out.
        if let serverTotal = statsListener.lifetimeStats?.totalHours, serverTotal > 0 {
            return serverTotal
        }
        return workEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var daysWorked: Int {
        let cal = Calendar.current
        return Set(workEntries.map { cal.startOfDay(for: $0.date) }).count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Outside the ScrollView so settings stays reachable from anywhere
            // on the page rather than scrolling away with the hero.
            settingsBar

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    identityHero
                    ProfileXPCapsule(store: store)
                    lifetimeStatsSection
                    navigationCard
                    accountSection
                    versionFooter
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.xl)
            }
            .scrollContentBackground(.hidden)
        }
        .background(AppColors.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, settings: $store.paySettings)
                .environmentObject(authService)
        }
        .onAppear {
            // Same recovery hook as CareerView: guarantees the server-stats
            // listeners are attached whenever a level-displaying screen appears.
            StatsListenerService.shared.ensureListening()
            Task {
                await photoManager.uploadLocalPhotoIfNeeded()
                if authService.isSignedIn {
                    store.syncProfileSnapshotToCloud()
                }
            }
        }
    }

    // MARK: - Settings bar

    private var settingsBar: some View {
        HStack {
            Spacer(minLength: 0)

            Button {
                Haptics.lightTap()
                showingSettings = true
            } label: {
                // No circle chrome — a filled badge here read as clipping into
                // the avatar just below it. The icon alone still gets a full
                // 40x40 tap target.
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Identity hero (no card — sits on the background)

    private var identityHero: some View {
        let profile = store.displayedGamificationProfile()
        let tier = PrestigeTheme.tier(for: profile.prestige)
        let ringColor = profile.prestige == 0 ? AppColors.accent : tier.primary
        // Read the auth state here (main-actor context) rather than inside the
        // PhotosPicker label, whose builder closure is treated as nonisolated.
        let avatarUID = authService.user?.uid
        let isSignedIn = authService.isSignedIn

        return VStack(spacing: AppSpacing.xs) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(
                        name: displayName,
                        size: 96,
                        uid: avatarUID
                    )
                    // Thin prestige-tier ring (accent at P0).
                    .overlay(
                        Circle()
                            .stroke(ringColor.opacity(0.7), lineWidth: 2)
                            .padding(-5)
                    )

                    if isSignedIn {
                        cameraBadge
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isSignedIn || isUpdatingPhoto)
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task { await updateProfilePhoto(from: item) }
            }
            .padding(.bottom, AppSpacing.xxs)

            Text(displayName)
                .appText(.title)
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Image(systemName: tier.icon)
                    .font(.footnote.weight(.bold))
                Text("Prestige \(profile.prestige) • Level \(profile.level)")
                    .appText(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .foregroundStyle(ringColor)

            if !equippedTitle.isEmpty {
                Text(equippedTitle)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cameraBadge: some View {
        ZStack {
            Circle()
                .fill(AppColors.card)
                .frame(width: 28, height: 28)
            if isUpdatingPhoto {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .overlay(Circle().stroke(AppColors.bg, lineWidth: 2))
        .offset(x: 2, y: 2)
    }

    // MARK: - Lifetime stats

    private var lifetimeStatsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Lifetime")
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: AppSpacing.sm),
                GridItem(.flexible(), spacing: AppSpacing.sm)
            ], spacing: AppSpacing.sm) {
                MetricDisplay(
                    icon: "clock.fill",
                    label: "All-Time Hours",
                    value: hoursDisplay(allTimeHours)
                )
                MetricDisplay(
                    icon: "calendar",
                    label: "Days Worked",
                    value: "\(daysWorked)"
                )
                MetricDisplay(
                    icon: "checkmark.circle.fill",
                    label: "Shifts Completed",
                    value: "\(workEntries.count)"
                )
                MetricDisplay(
                    icon: "flame.fill",
                    label: "Best Streak",
                    value: streakDisplay(store.gamificationProfile.bestStreak),
                    tint: AppColors.streak
                )
            }
        }
    }

    // MARK: - Navigation card

    private var navigationCard: some View {
        let badgeCounts = AchievementsView.badgeCollectionCounts(for: store)

        return AccountRowsCard {
            NavigationLink(destination: CareerView(store: store)) {
                AccountNavRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Career"
                )
            }
            .buttonStyle(PremiumPressStyle())

            AccountRowHairline()

            NavigationLink(destination: AchievementsView(store: store)) {
                AccountNavRow(
                    icon: "rosette",
                    title: "Badges",
                    detail: "\(badgeCounts.earned) of \(badgeCounts.total)"
                )
            }
            .buttonStyle(PremiumPressStyle())

            AccountRowHairline()

            Button {
                openURL(AppLegalURLs.website)
            } label: {
                AccountNavRow(icon: "globe", title: "Website")
            }
            .buttonStyle(PremiumPressStyle())

            AccountRowHairline()

            Button {
                openURL(AppLegalURLs.support)
            } label: {
                AccountNavRow(icon: "envelope.fill", title: "Contact")
            }
            .buttonStyle(PremiumPressStyle())
        }
    }

    // MARK: - Account section (cloud sync, sign out, delete — flows unchanged)

    @ViewBuilder
    private var accountSection: some View {
        VStack(spacing: AppSpacing.sm) {
            SectionEyebrow("Account")

            if authService.isSignedIn {
                AccountRowsCard {
                    AccountNavRow(
                        icon: "checkmark.icloud.fill",
                        title: "Cloud sync",
                        subtitle: signedInSubtitle,
                        tint: AppColors.positive,
                        showsChevron: false
                    )

                    AccountRowHairline()

                    Button {
                        try? authService.signOut()
                    } label: {
                        AccountNavRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Sign Out",
                            titleTint: AppColors.accent,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(PremiumPressStyle())

                    AccountRowHairline()

                    // Account deletion — required by App Store Review
                    // Guideline 5.1.1(v). Confirmation flow unchanged.
                    deleteAccountRow
                }

                LegalLinksSection()
                    .padding(.top, AppSpacing.xxs)
            } else {
                AccountRowsCard {
                    VStack(spacing: AppSpacing.sm) {
                        Text("Sign in to sync your hours across devices and add friends.")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.subtext)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        AuthSignInOptionsView()
                    }
                    .padding(AppSpacing.md)
                }
            }
        }
    }

    private var signedInSubtitle: String {
        if let email = authService.user?.email, !email.isEmpty {
            return email
        }
        return "Backed up automatically"
    }

    private var deleteAccountRow: some View {
        Button(role: .destructive) {
            Haptics.warning()
            showingDeleteAccountConfirm = true
        } label: {
            AccountNavRow(
                icon: "trash.fill",
                title: isDeletingAccount ? "Deleting account…" : "Delete Account",
                subtitle: "Permanently removes your account and synced data",
                tint: AppColors.negative,
                titleTint: AppColors.negative,
                showsChevron: !isDeletingAccount,
                isBusy: isDeletingAccount
            )
        }
        .buttonStyle(PremiumPressStyle())
        .disabled(isDeletingAccount)
        .alert("Delete account?", isPresented: $showingDeleteAccountConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performAccountDeletion() }
            }
        } message: {
            Text("This permanently removes your Hour Tracker account, all synced hours, friends, and badges. This cannot be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
    }

    // MARK: - Footer

    private var versionFooter: some View {
        Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .appText(.eyebrow)
            .foregroundStyle(AppColors.subtext.opacity(0.4))
            .padding(.top, AppSpacing.xs)
    }

    // MARK: - Formatting

    private func hoursDisplay(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value) + "h"
        }
        return AppTheme.Format.hours(value)
    }

    private func streakDisplay(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    // MARK: - Actions (unchanged flows)

    private func performAccountDeletion() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await AccountDeletionService.deleteAccount(store: store)
            Haptics.success()
        } catch {
            Haptics.error()
            deleteAccountError = error.localizedDescription
        }
    }

    private func updateProfilePhoto(from item: PhotosPickerItem) async {
        guard authService.isSignedIn else { return }
        isUpdatingPhoto = true
        defer {
            isUpdatingPhoto = false
            photoPickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            try await photoManager.setPhoto(image)
            store.syncProfileSnapshotToCloud()
            Haptics.success()
        } catch {
            Haptics.error()
            deleteAccountError = error.localizedDescription
        }
    }
}
