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
    @State private var showingNameEditor = false
    @State private var showingDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @ObservedObject private var verifiedStatus = VerifiedStatusService.shared
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUpdatingPhoto = false
    /// The raw picked photo, awaiting the crop step. Non-nil drives the crop
    /// sheet's presentation.
    @State private var pendingCropImage: UIImage?
    @State private var showingPhotoOptions = false
    @State private var showingPhotoViewer = false
    @State private var showingPhotoPicker = false
    @State private var showingPrestigeInfo = false
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
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Inside the ScrollView, so it sits at the top-right of the
                // page and scrolls away with the content rather than floating
                // over it. Grouped with the hero at zero spacing so the gear
                // reads as part of that header block.
                VStack(spacing: 0) {
                    settingsBar
                    identityHero
                }
                ProfileXPCapsule(store: store)
                lifetimeStatsSection
                navigationCard
                accountSection
                versionFooter
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, settings: $store.paySettings)
                .environmentObject(authService)
        }
        .sheet(isPresented: $showingNameEditor) {
            DisplayNameEditorSheet(store: store)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: Binding(
            get: { pendingCropImage != nil },
            set: { if !$0 { pendingCropImage = nil } }
        )) {
            if let pendingCropImage {
                ProfilePhotoCropView(
                    image: pendingCropImage,
                    onCancel: { self.pendingCropImage = nil },
                    onConfirm: { cropped in
                        self.pendingCropImage = nil
                        Task { await saveCroppedPhoto(cropped) }
                    }
                )
            }
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
        // No horizontal padding of its own — it now sits inside the scroll
        // content, which already applies the page margin.
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
            Button {
                Haptics.lightTap()
                // Nothing to view yet, so skip the menu and go straight to
                // picking one — a two-item sheet where one item is dead is
                // worse than no sheet.
                if photoManager.localImage == nil {
                    showingPhotoPicker = true
                } else {
                    showingPhotoOptions = true
                }
            } label: {
                // The ring is 5pt wider than the avatar on every edge. Reserving
                // that overflow in the button's own frame (rather than letting
                // the ring bleed past a 96x96 layout size via a bare overlay)
                // keeps the ring fully inside this view's bounds — it can no
                // longer be sliced by an ancestor's clipping (the ScrollView
                // this sits at the top of, in particular) regardless of scroll
                // position or spacing above it.
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatarView(
                        name: displayName,
                        size: 96,
                        uid: avatarUID
                    )
                    .padding(5)
                    .overlay(
                        Circle()
                            .stroke(ringColor.opacity(0.7), lineWidth: 2)
                    )

                    if isSignedIn {
                        cameraBadge
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isSignedIn || isUpdatingPhoto)
            .confirmationDialog("Profile photo", isPresented: $showingPhotoOptions, titleVisibility: .hidden) {
                Button("View photo") { showingPhotoViewer = true }
                Button("Change photo") { showingPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task { await loadImageForCropping(item) }
            }
            .fullScreenCover(isPresented: $showingPhotoViewer) {
                ProfilePhotoViewer(image: photoManager.localImage)
            }
            .padding(.bottom, AppSpacing.xxs)

            Button {
                Haptics.lightTap()
                showingNameEditor = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .appText(.title)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)
                    // Own profile earns the badge on the same rule as every
                    // other surface. Shimmering here: one badge on screen.
                    if verifiedStatus.isVerified {
                        VerifiedBadgeView(variant: .shimmer, size: 17)
                    }
                    // The pencil is what makes the name discoverable as
                    // editable — a bare tappable name looks like a label.
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit display name")

            // The prestige ranks chart's only reliable way in. Home's copy of
            // this row sits inside the hero card's NavigationLink, which
            // swallows the tap and pushes the pay cycle instead — and it is
            // hidden entirely below Prestige 1, so unranked users could never
            // reach the chart that explains what prestige is.
            Button {
                Haptics.lightTap()
                showingPrestigeInfo = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tier.icon)
                        .font(.footnote.weight(.bold))
                    Text("Prestige \(profile.prestige) • Level \(profile.level)")
                        .appText(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.6)
                }
                .foregroundStyle(ringColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the prestige ranks")
            .sheet(isPresented: $showingPrestigeInfo) {
                PrestigeInfoSheet(currentPrestige: profile.prestige)
            }

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
        // Was (2, 2) against the avatar's own 96x96 frame. The avatar now
        // carries 5pt of padding so the ring can fit inside its own bounds
        // (see the PhotosPicker label above), which grew the ZStack's
        // bottom-trailing anchor by that same 5pt — subtracted back out here
        // so the badge still sits snug against the photo's actual corner.
        .offset(x: -3, y: -3)
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
                openURL(AppLegalURLs.support)
            } label: {
                AccountNavRow(icon: "envelope.fill", title: "Contact Support")
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

                    // Legal links continue the same list rather than sitting
                    // in their own tile pair below it. LegalLinksSection (the
                    // two-tile layout) is still what the paywall uses.
                    Button {
                        Haptics.lightTap()
                        openURL(AppLegalURLs.privacyPolicy)
                    } label: {
                        AccountNavRow(icon: "hand.raised.fill", title: "Privacy Policy")
                    }
                    .buttonStyle(PremiumPressStyle())

                    AccountRowHairline()

                    Button {
                        Haptics.lightTap()
                        openURL(AppLegalURLs.termsOfUse)
                    } label: {
                        AccountNavRow(icon: "doc.text.fill", title: "Terms of Use")
                    }
                    .buttonStyle(PremiumPressStyle())

                    AccountRowHairline()

                    // The two account actions sit together at the foot of the
                    // card, past everything routine, ordered least to most
                    // destructive.
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

                    // Account deletion is required by App Store Review
                    // Guideline 5.1.1(v); the confirmation flow is unchanged.
                    deleteAccountRow
                }
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
        // The eyebrow style uppercases, which rendered this as "V2.5" — the
        // font and tracking are kept, the textCase is not.
        Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            .font(AppTypography.eyebrow)
            .tracking(AppTypography.eyebrowTracking)
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

    /// Loads the picked photo's data and hands it to the crop step — nothing
    /// is saved yet. `photoPickerItem` is cleared immediately so re-picking
    /// the same photo later still fires `onChange`.
    private func loadImageForCropping(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        pendingCropImage = image
    }

    private func saveCroppedPhoto(_ image: UIImage) async {
        guard authService.isSignedIn else { return }
        isUpdatingPhoto = true
        defer { isUpdatingPhoto = false }
        do {
            try await photoManager.setPhoto(image)
            store.syncProfileSnapshotToCloud()
            Haptics.success()
        } catch {
            Haptics.error()
            deleteAccountError = error.localizedDescription
        }
    }
}
