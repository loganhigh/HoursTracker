import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

// MARK: - Root
struct RootView: View {
    @EnvironmentObject private var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var cloudSync: CloudSyncManager
    @AppStorage("has_prompted_rate_after_5") private var hasPromptedRateAfter5 = false
    @AppStorage("display_name_prompt_last_tier") private var displayNamePromptLastTier: Int = 0
    @State private var showingDisplayNamePrompt = false
    @State private var showingCountryFlagPrompt = false
    @State private var showingCountryFlagPicker = false

    var body: some View {
        AppTabView()
        .onChange(of: store.entries.count) { _, newCount in
            if newCount >= 5 && !hasPromptedRateAfter5 {
                hasPromptedRateAfter5 = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    AppActions.rateApp()
                }
            }
            let displayName = UserDefaults.standard.string(forKey: "profile_display_name") ?? ""
            guard displayName.trimmingCharacters(in: .whitespaces).isEmpty,
                  newCount >= 10 else { return }
            let tier = newCount / 10
            guard tier > displayNamePromptLastTier else { return }
            displayNamePromptLastTier = tier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingDisplayNamePrompt = true
            }
        }
        .sheet(isPresented: $showingDisplayNamePrompt) {
            DisplayNamePromptSheet()
        }
        .alert("Hey! Add a country flag", isPresented: $showingCountryFlagPrompt) {
            Button("Choose country") {
                showingCountryFlagPicker = true
            }
            Button("Not now", role: .cancel) {
                CountryFlag.markPromptSkipped()
            }
        } message: {
            Text("Pick your country so your flag shows beside your name on the global leaderboard.")
        }
        .sheet(isPresented: $showingCountryFlagPicker) {
            NavigationStack {
                CountryFlagPickerView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCountryFlagPicker = false }
                        }
                    }
            }
        }
        .onAppear { scheduleCountryFlagPromptIfNeeded() }
        .onChange(of: authService.user?.uid) { _, _ in
            scheduleCountryFlagPromptIfNeeded()
        }
    }

    private func scheduleCountryFlagPromptIfNeeded() {
        guard authService.user != nil, CountryFlag.needsCountryPrompt else { return }
        guard !showingCountryFlagPrompt, !showingCountryFlagPicker else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard authService.user != nil, CountryFlag.needsCountryPrompt else { return }
            showingCountryFlagPrompt = true
        }
    }
}

// MARK: - Display Name Prompt (shown after every 10 logs when name is empty)
private struct DisplayNamePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile_display_name") private var displayName: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Add your display name")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.text)
                    .multilineTextAlignment(.center)
                Text("Your name appears throughout the app.")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                
                TextField("Your name", text: $displayName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.Colors.card2.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.Colors.stroke.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 32)
                
                Spacer(minLength: 20)
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.lightTap()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Invisible helper that watches `scenePhase` in its own tiny `body`, kept
/// separate from `HoursHomeView.body` so this doesn't add another modifier
/// to that already very large SwiftUI expression (which is at the edge of
/// what the type-checker can resolve in reasonable time).
private struct ScenePhaseFriendsRefreshObserver: View {
    @Environment(\.scenePhase) private var scenePhase
    let onBecomeActive: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    onBecomeActive()
                }
            }
    }
}

// MARK: - Main Home Screen
struct HoursHomeView: View {
    @EnvironmentObject private var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var tabRouter: TabRouter
    @ObservedObject private var friendsService = FriendsService.shared
    @ObservedObject private var statsListener = StatsListenerService.shared
    @ObservedObject private var topTrackers = TopTrackersService.shared

    @State private var showingAdd = false
    @State private var editingEntry: WorkEntry?
    @State private var showTrackingHint = false
    @AppStorage("tracking_hint_dismissed") private var trackingHintDismissed: Bool = false

    @AppStorage("company_name") private var companyName: String = ""
    @AppStorage("company_occupation") private var occupation: String = ""
    @State private var addButtonVisible = true
    @State private var showingPrestigeConfetti = false
    @State private var showPaydayConfetti = false
    @State private var showPersonalBestBanner = false
    @State private var showStreakBurst = false
    @State private var streakBurstCount = 0
    @State private var lastKnownStreak = 0
    @State private var xpGainText: String?
    @State private var showXPGain = false
    @State private var showLevelUp = false
    @State private var levelUpNumber = 0
    /// Highest level ever celebrated with a Level Up card, per prestige run.
    /// Local totalXP includes daily/weekly challenge XP that resets at day/week
    /// boundaries, so the computed level can dip overnight and re-cross the
    /// same threshold the next shift — this ratchet ensures each level is
    /// celebrated at most once until prestige resets the run.
    @AppStorage("level_up_celebrated_hwm_v1") private var celebratedLevelHWM = 0
    @AppStorage("level_up_celebrated_prestige_v1") private var celebratedPrestige = -1
    @State private var showOffDayToast = false
    @State private var offDayToastMessage = ""
    @State private var showingHolidayPicker = false
    @State private var holidayStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var holidayDayCount: Int = 1
    @State private var logShiftBurst = 0
    @State private var offDayBurst = 0
    @State private var holidayBurst = 0
    @StateObject private var badgeUnlockTracker = BadgeUnlockTracker()
    @State private var badgeUnlockPresentation: BadgeUnlockPresentation?
    @State private var showingPrestigeInfoFromHeroCard = false

    private struct BadgeUnlockPresentation: Identifiable {
        let id: String
        let displayName: String
    }

    private var todayEntry: WorkEntry? {
        let cal = Calendar.current
        return store.entries.first { cal.isDateInToday($0.date) }
    }

    private func logOffDayForToday() {
        if let existing = todayEntry {
            offDayToastMessage = existing.isOffDay
                ? "Today is already marked as an off day"
                : "Today already has a shift logged"
            Haptics.lightTap()
            withAnimation { showOffDayToast = true }
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let entry = WorkEntry(
            date: today,
            start: today,
            end: today,
            breakMinutes: 0,
            notes: "",
            isOffDay: true,
            offDayReason: "Off"
        )
        store.add(entry)
        Haptics.success()
        offDayToastMessage = "Off day logged for today"
        withAnimation { showOffDayToast = true }
    }

    private func logHolidaySpan(startingAt start: Date, days: Int) {
        let cal = Calendar.current
        let normalizedStart = cal.startOfDay(for: start)
        var added = 0
        var skipped = 0

        for offset in 0..<max(1, days) {
            guard let day = cal.date(byAdding: .day, value: offset, to: normalizedStart) else { continue }
            if store.entries.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
                skipped += 1
                continue
            }
            let entry = WorkEntry(
                date: day,
                start: day,
                end: day,
                breakMinutes: 0,
                notes: "",
                isOffDay: true,
                offDayReason: "Holiday"
            )
            store.add(entry)
            added += 1
        }

        if added > 0 {
            Haptics.success()
            let dayWord = added == 1 ? "day" : "days"
            offDayToastMessage = skipped > 0
                ? "Logged \(added) holiday \(dayWord) — \(skipped) skipped"
                : "Logged \(added) holiday \(dayWord)"
        } else {
            Haptics.lightTap()
            offDayToastMessage = "Those days are already logged"
        }
        withAnimation { showOffDayToast = true }
    }

    // MARK: - Personal Best Detection
    private func checkPersonalBest() {
        guard let best = bestMonthSoFar else { return }
        let cal = Calendar.current
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        guard cal.isDate(best.monthStart, equalTo: thisMonth, toGranularity: .month) else { return }
        let key = "personal_best_shown_\(cal.component(.year, from: thisMonth))_\(cal.component(.month, from: thisMonth))"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showPersonalBestBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation { showPersonalBestBanner = false }
            }
        }
    }

    // MARK: - Level-Up Celebration

    /// Shows the Level Up card only when the displayed level exceeds the
    /// highest level already celebrated in this prestige run. The ratchet
    /// (persisted in UserDefaults) absorbs the daily/weekly challenge-XP
    /// resets that make the locally computed level dip and re-cross the same
    /// threshold — the source of phantom "Level Up" cards.
    private func evaluateLevelUpCelebration(celebrate: Bool) {
        let displayed = store.displayedLevel
        let prestige = store.displayedPrestige
        guard displayed > 0 else { return }

        if prestige != celebratedPrestige {
            // New prestige run (or first launch on this device): re-baseline
            // silently. Prestige has its own celebration flow.
            celebratedPrestige = prestige
            celebratedLevelHWM = displayed
            return
        }
        guard displayed > celebratedLevelHWM else { return }
        celebratedLevelHWM = displayed
        // Level-up popup and sound removed — ratchet still advances silently.
    }

    // MARK: - Friends + activity subscriptions

    /// Returning from background is another common "opening the app" moment —
    /// re-pull friend stats fresh here too, since a backgrounded app's
    /// listeners can sit on a stale snapshot for however long it was suspended.
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        guard authService.user?.uid != nil else { return }
        Task { await friendsService.refreshFriendProfiles() }
    }

    private func refreshFriendsSubscription() {
        guard let uid = authService.user?.uid else {
            friendsService.stopListening()
            ActivityFeedService.shared.stopListening()
            return
        }
        friendsService.startListening(uid: uid)
        refreshActivitySubscription()
        // Force a server-fresh pull immediately, rather than waiting on the
        // listener's cache-then-server delivery — this is what actually
        // guarantees every friend's hours/level are current the instant the
        // app opens, not just "eventually" once a snapshot round-trips.
        Task { await friendsService.refreshFriendProfiles() }
    }

    private func refreshActivitySubscription() {
        guard let uid = authService.user?.uid else {
            ActivityFeedService.shared.stopListening()
            return
        }
        ActivityFeedService.shared.startListening(
            uid: uid,
            friendUids: friendsService.friends.map(\.uid)
        )
    }

    // MARK: - Pay period (via PayCycleEngine)
    private func checkPaydayConfetti() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let payday = cal.startOfDay(for: nextPayday)
        guard today == payday else { return }
        // Key is unique per payday date so it only shows once
        let key = "payday_confetti_shown_\(Int(payday.timeIntervalSince1970))"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Haptics.success()
            showPaydayConfetti = true
        }
    }

    // MARK: - Pay period (via PayCycleEngine)
    private var nextPayday: Date {
        PayCycleEngine.normalizedPaydayBoundary(settings: store.paySettings)
    }

    // MARK: - Best month (personal-best detection)
    private var bestMonthSoFar: (monthStart: Date, hours: Double)? {
        let cal = Calendar.current
        let monthStarts = Set(store.entries.map {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        })
        guard !monthStarts.isEmpty else { return nil }
        let best = monthStarts
            .map { (monthStart: $0, hours: store.monthTotalHours(monthDate: $0)) }
            .max(by: { $0.hours < $1.hours })
        return best
    }
    
    private var hasAnyShifts: Bool {
        !store.entries.isEmpty
    }

    private var friendUidFingerprint: String {
        friendsService.friends.map(\.uid).sorted().joined(separator: ",")
    }

    private var authSubscriptionKey: String {
        authService.user?.uid ?? "signed_out"
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            ScrollView {
            VStack(spacing: AppSpacing.xl) {

                TodayHeroCard(store: store) {
                    showingPrestigeInfoFromHeroCard = true
                }
                .cardAppear(index: 0)

                progressionCard
                    .cardAppear(index: 1)

                HomeStatTriplet(store: store)
                    .cardAppear(index: 2)

                HoursTypeChipsRow(store: store)
                    .cardAppear(index: 3)

                VStack(spacing: 10) {
                    // Quiet primary action: flat accent fill, hairline-free,
                    // no glow — the hero card owns this screen's one glow.
                    Button {
                        Haptics.lightTap()
                        logShiftBurst &+= 1
                        showingAdd = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Add Shift")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(AppColors.accent)
                        )
                    }
                    .buttonStyle(TapBurstButtonStyle())
                    .tapBurst(trigger: logShiftBurst)
                    HStack(spacing: 10) {
                        minimalActionTile(
                            title: "Off day",
                            systemImage: "xmark.circle.fill",
                            tint: AppColors.offDayAction
                        ) {
                            Haptics.lightTap()
                            offDayBurst &+= 1
                            logOffDayForToday()
                        }
                        .tapBurst(trigger: offDayBurst)

                        minimalActionTile(
                            title: "Holiday",
                            systemImage: "airplane",
                            tint: AppColors.holidayAction
                        ) {
                            Haptics.lightTap()
                            holidayBurst &+= 1
                            holidayStartDate = Calendar.current.startOfDay(for: Date())
                            holidayDayCount = 1
                            showingHolidayPicker = true
                        }
                        .tapBurst(trigger: holidayBurst)
                    }
                }
                .cardAppear(index: 4)

                RecentShiftsSection(
                    store: store,
                    hasAnyShifts: hasAnyShifts,
                    onSelect: { entry in
                        editingEntry = entry
                    },
                    onViewAll: {
                        Haptics.lightTap()
                        tabRouter.selection = .history
                    },
                    onAddShift: {
                        Haptics.lightTap()
                        logShiftBurst &+= 1
                        showingAdd = true
                    },
                    onTrackingHint: trackingHintDismissed ? nil : {
                        trackingHintDismissed = true
                        showTrackingHint = true
                    }
                )
                .cardAppear(index: 5)

                YearlyOverviewSection(store: store)
                    .cardAppear(index: 6)

                if !premium.isPremium {
                    BannerAdView()
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                }

                HomeFriendsCard(
                    friendsService: friendsService,
                    store: store,
                    authService: authService,
                    onOpenFriends: {
                        tabRouter.selection = .friends
                    }
                )
                .cardAppear(index: 7)

                homeTopTrackersSection
                    .cardAppear(index: 8)

                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.4))
                    .tracking(1.5)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, 12)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            store.advanceNextPaydayIfNeeded()
            checkPaydayConfetti()
            store.syncProfileSnapshotToCloud()
            topTrackers.startListening()
        }
        .task(id: authSubscriptionKey) {
            refreshFriendsSubscription()
        }
        .onChange(of: friendUidFingerprint) { _, _ in
            refreshActivitySubscription()
        }
        .background(ScenePhaseFriendsRefreshObserver(onBecomeActive: {
            handleScenePhaseChange(.active)
        }))
        .refreshable {
            store.advanceNextPaydayIfNeeded()
            await store.refreshData()
        }
        .overlay {
            if showPaydayConfetti {
                PaydayConfettiOverlay {
                    showPaydayConfetti = false
                }
                .ignoresSafeArea()
            }
        }
        .overlay {
            if showXPGain, let text = xpGainText {
                VStack {
                    Spacer()
                    FloatingXPGainView(text: text)
                        .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.2), value: showXPGain)
            }
        }
        .overlay(alignment: .top) {
            if showPersonalBestBanner {
                PersonalBestBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if showStreakBurst {
                StreakBurstView(streakCount: streakBurstCount)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: showPersonalBestBanner)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            EntryEditorView(store: store, mode: .add)
        }
        .sheet(item: $editingEntry) { entry in
            EntryEditorView(store: store, mode: .edit(entry))
        }
        .sheet(isPresented: $showingHolidayPicker) {
            HolidayPickerSheet(
                startDate: $holidayStartDate,
                dayCount: $holidayDayCount,
                onConfirm: { start, days in
                    showingHolidayPicker = false
                    logHolidaySpan(startingAt: start, days: days)
                },
                onCancel: { showingHolidayPicker = false }
            )
        }
        .toast(isPresented: $showOffDayToast, message: offDayToastMessage, showsCheckmark: !offDayToastMessage.contains("already"))
        .alert("How tracking works", isPresented: $showTrackingHint) {
            Button("OK") { }
        } message: {
            Text("Log your shifts each day. Your hours and pay are calculated automatically. Monthly totals appear here once you have entries.")
        }
        .sheet(isPresented: $showingPrestigeInfoFromHeroCard) {
            PrestigeInfoSheet(currentPrestige: store.displayedGamificationProfile().prestige)
        }
        .fullScreenCover(isPresented: $showingPrestigeConfetti) {
            PrestigeCelebrationView(
                prestige: store.gamificationProfile.prestige,
                onDismiss: { showingPrestigeConfetti = false }
            )
        }
        .onChange(of: store.xpGainEvent) { _, event in
            // Only fires for XP earned by a real user action (shift logged /
            // updated) — cloud pulls and pull-to-refresh recalcs never emit
            // this event, so no more phantom "+XP" toasts on refresh.
            guard let event else { return }
            xpGainText = "+\(event.amount) XP"
            withAnimation(.easeOut(duration: 0.2)) { showXPGain = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation(.easeIn(duration: 0.4)) { showXPGain = false }
            }
        }
        .onChange(of: store.displayedLevel) { _, _ in
            evaluateLevelUpCelebration(celebrate: true)
        }
        .onChange(of: store.gamificationProfile.currentStreak) { oldStreak, newStreak in
            let milestones = [7, 14, 30, 60, 100]
            if milestones.contains(newStreak) && newStreak > lastKnownStreak {
                streakBurstCount = newStreak
                withAnimation { showStreakBurst = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showStreakBurst = false }
                }
            }
            lastKnownStreak = newStreak
        }
        .onChange(of: store.entries.count) { _, _ in
            checkPersonalBest()
        }
        .onAppear {
            // Baseline the celebration ratchet silently — never celebrate a
            // level the user merely re-loaded the app at.
            evaluateLevelUpCelebration(celebrate: false)
            lastKnownStreak = store.gamificationProfile.currentStreak
            checkPersonalBest()
        }
        .onChange(of: store.gamificationProfile.unlockedBadges) { old, new in
            let oldSet = Set(old)
            guard let badge = new.first(where: { !oldSet.contains($0) && !badgeUnlockTracker.hasCelebrated($0) }) else { return }
            badgeUnlockTracker.markCelebrated(badge)
            let label = badge.replacingOccurrences(of: "_", with: " ").capitalized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                badgeUnlockPresentation = BadgeUnlockPresentation(id: badge, displayName: label)
            }
        }
        .sheet(item: $badgeUnlockPresentation) { presentation in
            BadgeUnlockCelebrationSheet(badgeName: presentation.displayName)
        }
    }

    // MARK: - Minimal home building blocks

    /// A quiet, tinted quick-action tile (sleek minimal — colored icon, neutral
    /// label, soft tinted surface) replacing the old loud gradient buttons.
    private func minimalActionTile(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                            .stroke(tint.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(TapBurstButtonStyle())
    }

    /// Minimal section: a left-aligned small-caps label over content — quiet,
    /// editorial hierarchy instead of pill chrome. When `boxed`, the content
    /// sits in a subtle hairline surface; otherwise it floats on the
    /// background for maximum air (rows supply their own backgrounds).
    @ViewBuilder
    private func homeSection<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        boxed: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.Colors.subtext)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)

            if boxed {
                content()
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.Colors.card.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                            )
                    )
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var progressionCard: some View {
        VStack(spacing: 12) {
            HomeXPStrip(store: store)

            if store.gamificationProfile.canPrestige {
                PrestigeCallToAction(currentPrestige: store.gamificationProfile.prestige) {
                    if store.performPrestige() {
                        showingPrestigeConfetti = true
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: store.gamificationProfile.canPrestige)
            }
        }
    }

    // MARK: - Top 5 Hour Trackers (moved from the side menu)

    private var homeTopTrackersSection: some View {
        homeSection("Top 5 Hour Trackers", boxed: true) {
            VStack(spacing: 0) {
                if topTrackers.topTrackers.isEmpty {
                    Text(topTrackers.hasLoaded ? "No rankings yet" : "Loading…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    ForEach(topTrackers.topTrackers.prefix(5)) { tracker in
                        topTrackerRow(tracker: tracker)
                        if tracker.id != topTrackers.topTrackers.prefix(5).last?.id {
                            Divider()
                                .overlay(AppTheme.Colors.stroke)
                                .padding(.leading, 40)
                        }
                    }

                    NavigationLink {
                        GlobalLeaderboardView()
                    } label: {
                        Text("See more")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.Colors.accent.opacity(0.1))
                            )
                    }
                    .buttonStyle(InteractiveButtonStyle())
                    .padding(.top, 8)
                }
            }
        }
    }

    private func topTrackerRankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.98, green: 0.79, blue: 0.28) // gold
        case 2: return Color(red: 0.75, green: 0.79, blue: 0.85) // silver
        case 3: return Color(red: 0.83, green: 0.55, blue: 0.35) // bronze
        default: return AppTheme.Colors.accent
        }
    }

    private func topTrackerHoursLabel(_ hours: Double) -> String {
        if hours >= 1000 {
            return String(format: "%.0fh", hours)
        }
        return String(format: "%.1fh", hours)
    }

    private func topTrackerRow(tracker: TopTracker) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(topTrackerRankColor(tracker.rank).opacity(tracker.rank <= 3 ? 0.22 : 0.12))
                    .frame(width: 28, height: 28)
                Text("\(tracker.rank)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(topTrackerRankColor(tracker.rank))
            }

            HStack(spacing: 5) {
                Text(tracker.name)
                    .font(.system(size: 15, weight: tracker.rank <= 3 ? .semibold : .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(1)
                if let flag = CountryFlag.emoji(
                    for: CountryFlag.leaderboardCode(
                        trackerUid: tracker.uid,
                        serverCode: tracker.countryCode,
                        currentUid: authService.user?.uid
                    )
                ) {
                    Text(flag)
                        .font(.system(size: 15))
                }
            }

            Spacer()

            Text(topTrackerHoursLabel(tracker.hours))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.subtext)
        }
        .padding(.vertical, 8)
    }

}


// MARK: - Helper Functions

private func formatEntryForCopy(_ entry: WorkEntry) -> String {
    let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
    let tf = DateFormatter(); tf.dateFormat = "h:mm a"
    return entry.formattedForCopy(dateFormatter: df, timeFormatter: tf)
}

/// Builds the full grouped monthly clipboard string from a list of entries.
private func copyAllGroupedText(for entries: [WorkEntry]) -> String {
    let cal = Calendar.current
    let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
    let tf = DateFormatter(); tf.dateFormat = "h:mm a"
    let mf = DateFormatter(); mf.dateFormat = "MMMM yyyy"
    let sorted = entries.sorted { $0.date > $1.date }
    var byMonth: [[WorkEntry]] = []
    var current: [WorkEntry] = []
    var lastComps: (Int, Int)? = nil
    for e in sorted {
        let comps = (cal.component(.year, from: e.date), cal.component(.month, from: e.date))
        if let lc = lastComps, lc != comps {
            byMonth.append(current); current = []
        }
        current.append(e); lastComps = comps
    }
    if !current.isEmpty { byMonth.append(current) }
    var blocks: [String] = []
    for group in byMonth {
        guard let first = group.first else { continue }
        let header = "————————————\n\(mf.string(from: first.date))\n————————————"
        let lines = group.map { e -> String in
            e.formattedForCopy(dateFormatter: df, timeFormatter: tf)
        }
        blocks.append(header + "\n\n" + lines.joined(separator: "\n\n"))
    }
    return blocks.joined(separator: "\n\n")
}


// MARK: - Prestige Call To Action

private struct PrestigeCallToAction: View {
    let currentPrestige: Int
    let onPrestige: () -> Void
    @State private var glowPulse: CGFloat = 0.6

    private var prestigeLevel: Int { 25 }

    var body: some View {
        Button {
            Haptics.success()
            onPrestige()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                VStack(spacing: 1) {
                    Text("YOU'VE REACHED LEVEL \(prestigeLevel)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .opacity(0.85)
                    Text("Tap to Prestige →")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                }
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(AppColors.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [AppTheme.Colors.accent, AppTheme.Colors.accent2, AppTheme.Colors.accentHighlight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.Colors.accent.opacity(glowPulse * 0.8), radius: 16, y: 4)
            .shadow(color: AppTheme.Colors.accentHighlight.opacity(glowPulse * 0.5), radius: 10, y: 2)
        }
        .buttonStyle(InteractiveButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }

        }
    }
}

// MARK: - Floating XP Gain Text

private struct FloatingXPGainView: View {
    let text: String
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.7

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: 0xFBBF24).opacity(0.4), lineWidth: 1)
                    )
            )
            .shadow(color: Color(hex: 0xF59E0B).opacity(0.5), radius: 12)
            .scaleEffect(scale)
            .offset(y: offsetY)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    opacity = 1
                    scale = 1.0
                }
                withAnimation(.easeOut(duration: 1.8).delay(0.1)) {
                    offsetY = -30
                }
                withAnimation(.easeIn(duration: 0.45).delay(2.0)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Prestige Info Sheet

struct PrestigeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentPrestige: Int

    private var tiers: [(level: Int, icon: String, title: String, color: Color)] {
        PrestigeTheme.tiers.map { tier in
            (
                level: tier.prestige,
                icon: tier.icon,
                title: tier.name,
                color: tier.prestige == 0 ? Color.gray : tier.primary
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.Colors.accent.opacity(0.2), AppTheme.Colors.accent.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)

                            Image(systemName: "sparkles")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                                .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 10)
                        }

                        Text("What is Prestige?")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.text)

                        Text("Hit Level 25 to Prestige. Your level resets, your rank goes up.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.subtext)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text("HOW IT WORKS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(AppTheme.Colors.subtext)
                            .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .leading, spacing: 12) {
                            infoRow(icon: "arrow.up.circle.fill", text: "Reach Level 25 to Prestige")
                            infoRow(icon: "arrow.counterclockwise.circle.fill", text: "Level resets to 1, rank goes up")
                            infoRow(icon: "crown.fill", text: "10 ranks — climb all the way to Prestige Master")
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.Colors.card2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                        )
                    }

                    VStack(spacing: 6) {
                        Text("PRESTIGE RANKS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(AppTheme.Colors.subtext)
                            .frame(maxWidth: .infinity, alignment: .center)

                        VStack(spacing: 0) {
                            ForEach(tiers, id: \.level) { tier in
                                HStack(spacing: 12) {
                                    Image(systemName: tier.icon)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(tier.color)
                                        .shadow(color: tier.level == currentPrestige ? tier.color.opacity(0.5) : .clear, radius: 6)
                                        .frame(width: 24)

                                    Text("P\(tier.level)")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundStyle(tier.color)
                                        .frame(width: 30, alignment: .leading)

                                    Text(tier.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(tier.level == currentPrestige ? AppColors.text : AppTheme.Colors.subtext)

                                    Spacer()

                                    if tier.level == currentPrestige {
                                        Text("YOU")
                                            .font(.system(size: 10, weight: .black, design: .rounded))
                                            .tracking(1)
                                            .foregroundStyle(AppColors.textOnAccent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule().fill(tier.color)
                                            )
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(
                                    tier.level == currentPrestige
                                        ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(tier.color.opacity(0.1))
                                        : nil
                                )

                                if tier.level < 10 {
                                    Divider().overlay(AppTheme.Colors.stroke.opacity(0.5))
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.Colors.card2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Prestige")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Personal Best Banner

private struct PersonalBestBanner: View {
    @State private var shimmer: CGFloat = -200

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0xFBBF24))
            Text("New Personal Best Month! 🏆")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textOnAccent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(
            ZStack {
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xF59E0B).opacity(0.9), AppTheme.Colors.accent.opacity(0.9)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Capsule()
                    .stroke(Color(hex: 0xFBBF24).opacity(0.5), lineWidth: 1)
            }
        )
        .shadow(color: Color(hex: 0xF59E0B).opacity(0.4), radius: 14, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmer = 250
            }
        }
    }
}

// MARK: - Streak Milestone Burst

private struct StreakBurstView: View {
    let streakCount: Int
    @State private var particles: [BurstParticle] = []

    struct BurstParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var targetX: CGFloat
        var targetY: CGFloat
        var color: Color
        var size: CGFloat
        var opacity: Double
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            AppColors.overlay.ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    ForEach(particles) { p in
                        Circle()
                            .fill(p.color)
                            .frame(width: p.size, height: p.size)
                            .opacity(p.opacity)
                            .offset(x: p.x, y: p.y)
                    }
                    Text("🔥")
                        .font(.system(size: 64))
                }
                .frame(width: 120, height: 120)

                VStack(spacing: 4) {
                    Text("\(streakCount) DAY STREAK")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(AppColors.text)
                    Text("You're on fire. Keep it up!")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.subtext)
                }
            }
        }
        .onAppear {
            spawnParticles()
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [.orange, .yellow, Color(hex: 0xEF4444), Color(hex: 0xFBBF24)]
        particles = (0..<24).map { _ in
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let dist = CGFloat.random(in: 60...140)
            return BurstParticle(
                x: 0, y: 0,
                targetX: cos(angle) * dist,
                targetY: sin(angle) * dist,
                color: colors.randomElement()!,
                size: CGFloat.random(in: 6...14),
                opacity: 1.0
            )
        }
        withAnimation(.easeOut(duration: 0.8)) {
            for i in particles.indices {
                particles[i].x = particles[i].targetX
                particles[i].y = particles[i].targetY
            }
        }
        withAnimation(.easeIn(duration: 0.6).delay(1.2)) {
            for i in particles.indices {
                particles[i].opacity = 0
            }
        }
    }
}

// MARK: - Add Button Visibility Preference Key
private struct AddButtonVisibilityKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

// MARK: - Payday Confetti Overlay
private struct PaydayConfettiOverlay: View {
    let onDismiss: () -> Void

    @State private var burst = false
    @State private var visible = true
    @State private var badgeScale: CGFloat = 0.4
    @State private var badgeOpacity: Double = 0
    @State private var emojiFloat: CGFloat = 0

    var body: some View {
        ZStack {
            // Dimmed backdrop
            AppColors.overlay
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti
            ConfettiLayer(active: burst)
                .allowsHitTesting(false)

            // Central badge
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xFFD700).opacity(0.3), Color(hex: 0xFF9500).opacity(0.15)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(LinearGradient(colors: [Color(hex: 0xFFD700), Color(hex: 0xFF9500)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                        )
                        .shadow(color: Color(hex: 0xFFD700).opacity(0.5), radius: 24)

                    Text("💰")
                        .font(.system(size: 54))
                        .offset(y: emojiFloat)
                }

                VStack(spacing: 8) {
                    Text("Payday!")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: 0xFFD700), Color(hex: 0xFF9500)], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: Color(hex: 0xFFD700).opacity(0.4), radius: 10)

                    Text("You earned it. Go get it. 💸")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Let's go!")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(LinearGradient(colors: [Color(hex: 0xFFD700), Color(hex: 0xFF9500)], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: Color(hex: 0xFFD700).opacity(0.5), radius: 12, y: 4)
                        )
                }
                .buttonStyle(InteractiveButtonStyle())
                .padding(.top, 4)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color(hex: 0xFFD700).opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
            .scaleEffect(badgeScale)
            .opacity(badgeOpacity)
        }
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                burst = true
                badgeScale = 1.0
                badgeOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                emojiFloat = -8
            }
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            visible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onDismiss()
        }
    }
}

// MARK: - HolidayPickerSheet

private struct HolidayPickerSheet: View {
    @Binding var startDate: Date
    @Binding var dayCount: Int
    let onConfirm: (Date, Int) -> Void
    let onCancel: () -> Void

    private var endDate: Date {
        Calendar.current.date(byAdding: .day, value: max(0, dayCount - 1), to: startDate) ?? startDate
    }

    private var rangeText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        if dayCount <= 1 {
            return f.string(from: startDate)
        }
        return "\(f.string(from: startDate)) → \(f.string(from: endDate))"
    }

    private var dayWord: String { dayCount == 1 ? "day" : "days" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accentGradient)
                            .padding(.top, 4)
                        Text("Log Holiday")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.text)
                        Text("Block off the days you'll be away.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.subtext)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Starting")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(AppTheme.Colors.subtext)
                        DatePicker(
                            "",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .tint(AppTheme.Colors.accent)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                                .fill(AppTheme.Colors.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Number of days")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(AppTheme.Colors.subtext)
                        HStack(spacing: 16) {
                            Button {
                                Haptics.lightTap()
                                if dayCount > 1 {
                                    dayCount -= 1
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(dayCount > 1 ? AppTheme.Colors.text : AppTheme.Colors.subtext.opacity(0.5))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(AppTheme.Colors.card2)
                                            .overlay(Circle().stroke(AppTheme.Colors.stroke, lineWidth: 1))
                                    )
                            }
                            .disabled(dayCount <= 1)

                            VStack(spacing: 2) {
                                Text("\(dayCount)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(AppTheme.Colors.accentGradient)
                                    .contentTransition(.numericText())
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dayCount)
                                Text(dayWord)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.subtext)
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                Haptics.lightTap()
                                if dayCount < 90 {
                                    dayCount += 1
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(dayCount < 90 ? AppTheme.Colors.text : AppTheme.Colors.subtext.opacity(0.5))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(AppTheme.Colors.card2)
                                            .overlay(Circle().stroke(AppTheme.Colors.stroke, lineWidth: 1))
                                    )
                            }
                            .disabled(dayCount >= 90)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                                .fill(AppTheme.Colors.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                        )
                    }

                    VStack(spacing: 4) {
                        Text("Will be logged for")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(AppTheme.Colors.subtext)
                        Text(rangeText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.text)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 6)

                    PrimaryButton(
                        dayCount == 1 ? "Log holiday" : "Log \(dayCount) days",
                        systemImage: "checkmark"
                    ) {
                        onConfirm(startDate, dayCount)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
        }
        .presentationDetents([.large])
    }
}
