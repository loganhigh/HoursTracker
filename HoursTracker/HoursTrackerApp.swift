import SwiftUI
import FirebaseCore
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@main
struct HoursTrackerApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase
    // Declared without default values — all StateObjects are constructed
    // exactly once inside `init()` so we never accidentally build a throw-
    // away `HoursStore()` from the property default *and* a real one in
    // init. Prior versions created two stores; the lazy `StateObject`
    // autoclosure usually masked it, but explicit assignment here is
    // unambiguous and matches the dependency wiring (coordinator + session
    // manager need the same `store` reference).
    @StateObject private var authService: AuthService
    @StateObject private var store: HoursStore
    @StateObject private var networkMonitor: NetworkMonitor
    @StateObject private var cloudSync: CloudSyncManager
    @StateObject private var startupCoordinator: StartupCoordinator
    @StateObject private var sessionManager: AppSessionManager
    @StateObject private var localization: LocalizationManager

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            #if DEBUG
            print("⚠️ GoogleService-Info.plist missing — Firebase not configured. See FIREBASE_SETUP.md")
            #endif
        }

        let store = HoursStore()
        let coordinator = StartupCoordinator(store: store)
        _store = StateObject(wrappedValue: store)
        _authService = StateObject(wrappedValue: AuthService.shared)
        _networkMonitor = StateObject(wrappedValue: NetworkMonitor.shared)
        _cloudSync = StateObject(wrappedValue: CloudSyncManager.shared)
        _startupCoordinator = StateObject(wrappedValue: coordinator)
        _sessionManager = StateObject(wrappedValue: AppSessionManager(store: store, startupCoordinator: coordinator))
        _localization = StateObject(wrappedValue: LocalizationManager.shared)

        store.configureCloudSync(authService: AuthService.shared)
        PushNotificationService.shared.configureIfNeeded()
        PremiumManager.shared.configure()
    }

    /// Starts the ads SDK once after launch. No App Tracking Transparency
    /// prompt — ads aren't active in this build and we don't track users
    /// across apps (required for App Store privacy / review).
    @State private var didStartMonetization = false
    private func startMonetizationIfNeeded() {
        guard !didStartMonetization else { return }
        didStartMonetization = true
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .environmentObject(authService)
                .environmentObject(networkMonitor)
                .environmentObject(cloudSync)
                .environmentObject(startupCoordinator)
                .environmentObject(sessionManager)
                .environmentObject(localization)
                .environmentObject(PremiumManager.shared)
                .adaptiveTheme(prestige: store.gamificationProfile.prestige)
                // App is dark-mode only. Several screens (RootView greeting/level card,
                // CompanyProfileView, MonthlyWrappedView) use hardcoded .foregroundStyle(.white)
                // that would become near-invisible over AppTheme.Colors.card/bg in light mode.
                // Before removing this or adding a light-mode toggle, switch those to
                // AppTheme.Colors.text (or an explicit onDarkSurface token).
                .preferredColorScheme(.dark)
                .background(AppTheme.Colors.bg.ignoresSafeArea())
                .onChange(of: authService.user?.uid) { _, newUID in
                    PremiumManager.shared.identify(uid: newUID)
                    if newUID != nil {
                        if networkMonitor.isConnected, cloudSync.isCloudAvailable {
                            cloudSync.pullFromCloud()
                        } else {
                            store.syncProfileOnLogin()
                        }
                        // Upload FCM token on sign-in so nudges arrive immediately
                        // without waiting for the next scene-active cycle.
                        Task { @MainActor in
                            await PushNotificationService.shared.registerForPushIfSignedIn()
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if case .active = newPhase {
                startMonetizationIfNeeded()
            }
            if case .background = newPhase {
                sessionManager.resetSession(reason: .background)
                WidgetDataManager.shared.updateWidgetData(
                    entries: store.entries,
                    paySettings: store.paySettings,
                    prestige: store.gamificationProfile.prestige
                )
                WidgetDataManager.shared.reloadAllWidgets()
            }
            if case .active = newPhase {
                store.advanceNextPaydayIfNeeded()
                store.applyYearlyResetIfNeeded()
                WidgetDataManager.shared.reloadAllWidgets()
                SmartNotifier.shared.scheduleDailyReminder()
                SmartNotifier.shared.scheduleForgotHoursReminderIfNeeded(entries: store.entries)
                SmartNotifier.shared.cancelGoalReminder()
                SmartNotifier.shared.scheduleMotivationReminderIfNeeded(entries: store.entries)
                SmartNotifier.shared.scheduleStreakNotificationsIfNeeded(entries: store.entries, currentStreak: store.gamificationProfile.currentStreak)
                Task { @MainActor in
                    await PushNotificationService.shared.registerForPushIfSignedIn()
                }
                if networkMonitor.isConnected, cloudSync.isCloudAvailable {
                    cloudSync.pullFromCloud {
                        store.applyAutoOffDaysForForgottenShifts()
                        cloudSync.runDailyCloudRepairIfNeeded()
                    }
                } else {
                    store.applyAutoOffDaysForForgottenShifts()
                    store.syncProfileSnapshotToCloud()
                }
            }
        }
    }
}

// MARK: - App root (onboarding + startup)

private struct AppRootView: View {
    @AppStorage(AppTutorialStorage.completeKey) private var appTutorialComplete = false
    @EnvironmentObject private var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var cloudSync: CloudSyncManager
    @EnvironmentObject private var startupCoordinator: StartupCoordinator
    @EnvironmentObject private var sessionManager: AppSessionManager

    var body: some View {
        Group {
            if appTutorialComplete {
                MainAppWithStartup()
                    .id(sessionManager.rootResetToken)
            } else {
                AppTutorialView(isPresented: .constant(true), dismissesWhenComplete: false)
                    .environmentObject(authService)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: appTutorialComplete)
        .onOpenURL { url in
            _ = AuthService.handleIncomingURL(url)
        }
    }
}

// MARK: - Main app with startup splash

private struct MainAppWithStartup: View {
    @EnvironmentObject private var store: HoursStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var cloudSync: CloudSyncManager
    @EnvironmentObject private var startupCoordinator: StartupCoordinator

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()
            Group {
                switch startupCoordinator.state {
                case .loading:
                    SplashView()
                        .transition(.opacity)
                case .ready:
                    ContentView()
                        // Friends system hidden for now — revisit later.
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        .onAppear { deferHeavyWork() }
                case .error(let msg):
                    StartupErrorView(
                        message: msg,
                        onRetry: { startupCoordinator.retry() },
                        onResetCache: { startupCoordinator.resetCacheAndRetry() }
                    )
                    .transition(.opacity)
                }
            }
            .animation(AppMotion.Spring.smooth, value: startupCoordinator.state)
        }
        .onAppear {
            if case .loading = startupCoordinator.state {
                startupCoordinator.start()
            }
        }
    }

    private func deferHeavyWork() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            store.applyYearlyResetIfNeeded()
            store.applyAutoOffDaysForForgottenShifts()
            WeeklyMilestoneNotifier.shared.resetWeeklyStateIfNeeded()
            WeeklyMilestoneNotifier.shared.checkMilestones(for: store.entries)
            SmartNotifier.shared.scheduleDailyReminder()
            SmartNotifier.shared.scheduleForgotHoursReminderIfNeeded(entries: store.entries)
            SmartNotifier.shared.scheduleMotivationReminderIfNeeded(entries: store.entries)
            SmartNotifier.shared.scheduleStreakNotificationsIfNeeded(entries: store.entries, currentStreak: store.gamificationProfile.currentStreak)
            SmartNotifier.shared.checkPayPeriodProgress(for: store.entries, paySettings: store.paySettings)
            if networkMonitor.isConnected, cloudSync.isCloudAvailable {
                cloudSync.pullFromCloud {
                    store.syncToCloud()
                }
            } else if authService.isSignedIn {
                store.syncProfileOnLogin()
            }
            Task { @MainActor in
                await PushNotificationService.shared.registerForPushIfSignedIn()
            }
        }
    }
}
