import XCTest
import SwiftUI
@testable import HoursTracker

/// Full-screen owl renders for screens the Simulator can't easily reach
/// (signed-in Friends, a populated You tab, celebrations). Skipped unless
/// MASCOT_DUMP_DIR is set (pass TEST_RUNNER_MASCOT_DUMP_DIR to xcodebuild).
/// Each view is hosted in a real window, so NavigationStack, List and
/// toolbars draw as they do on device.
@MainActor
final class MascotScreenDumpTests: XCTestCase {
    /// HoursStore's isolated deinit aborts if one deallocates mid-run (see
    /// LiveShiftManagerTests), so test stores live for the whole process.
    private static var retainedStores: [HoursStore] = []

    private static func makeStore() -> HoursStore {
        let store = HoursStore()
        retainedStores.append(store)
        return store
    }

    /// Friends screens with sample friends. They need a signed-in account in
    /// the Simulator, and most sit in a NavigationStack that ImageRenderer
    /// can't draw, so each is hosted in a real window and snapshotted.
    func testDumpFriendsScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASCOT_DUMP_DIR"] else {
            throw XCTSkip("Set MASCOT_DUMP_DIR to dump Friends screen renders")
        }
        let friends = [
            Self.sampleFriend(uid: "dana", name: "Dana", hours: 41.5, prestige: 2, streak: 6),
            Self.sampleFriend(uid: "marcus", name: "Marcus", hours: 36, prestige: 0, streak: 0),
            Self.sampleFriend(uid: "priya", name: "Priya", hours: 22.5, prestige: 1, streak: 3),
        ]
        let saved = FriendsService.shared.friends
        FriendsService.shared.friends = friends
        defer { FriendsService.shared.friends = saved }

        var entries = [LeaderboardEntry(id: "me", name: "Logan", isMe: true, level: 12, prestige: 0, streak: 4,
                                        payPeriodHours: 38, photoURL: nil, hoursHidden: false)]
        entries += friends.map {
            LeaderboardEntry(id: $0.uid, name: $0.displayName, isMe: false, level: $0.level, prestige: $0.prestige,
                             streak: $0.currentStreak, payPeriodHours: $0.chequeHours, photoURL: nil, hoursHidden: false)
        }
        entries.sort { $0.payPeriodHours > $1.payPeriodHours }
        for index in entries.indices { entries[index].rank = index + 1 }
        let owl = OwlLines.friends(myRank: entries.first(where: \.isMe)?.rank ?? 0, total: entries.count)

        let trackers = [
            TopTracker(uid: "t1", name: "Ava", hours: 2140, countryCode: "CA", rank: 1, level: 30, prestige: 4),
            TopTracker(uid: "t2", name: "Mateo", hours: 1985, countryCode: "US", rank: 2, level: 27, prestige: 3),
            TopTracker(uid: "t3", name: "Sofia", hours: 1870, countryCode: "GB", rank: 3, level: 25, prestige: 2),
        ]
        let global = OwlLines.globalRank(7)

        let screens: [(String, AnyView)] = [
            ("friends-hub", AnyView(ScrollView {
                VStack(spacing: AppSpacing.md) {
                    FriendsHeroHeader(onAddFriend: {})
                    OwlPerch(pose: owl.pose, line: owl.line) { PayPeriodPodiumCard(entries: entries) }
                    ForEach(entries) { LeaderboardRankRow(entry: $0, onOpen: {}, onNudge: nil) }
                }
                .padding(AppSpacing.md)
            }.background(AppColors.bg))),
            ("add-friend", AnyView(NavigationStack {
                ScrollView {
                    UsernameCard(username: "logan", usernameInput: .constant(""), isSending: false,
                                 copyConfirmation: false, onCopy: {}, onAdd: {}, onSetUsername: {})
                        .owlPeek(.buddies, size: .header)
                        .padding(.top, OwlView.Size.header.height - OwlPerchMetrics.feetOverlap / 2)
                        .padding(AppSpacing.md)
                }
                .background(AppColors.bg)
                .navigationTitle("Add a friend")
                .navigationBarTitleDisplayMode(.inline)
            })),
            ("friend-profile", AnyView(NavigationStack {
                FriendProfileDetailView(friendUid: "dana", friendsService: .shared)
            })),
            ("global-board", AnyView(ScrollView {
                VStack(spacing: AppSpacing.sm) {
                    GlobalLeaderboardHeader(onBack: {})
                    OwlPerch(pose: global.pose, line: global.line) { GlobalRankHeroCard(rank: 7) }
                    VerifiedReviewNote(isVerified: false, onTap: {})
                    GlobalStatsStrip(trackerCount: 154, totalHours: 48_210, activeNow: 9)
                    GlobalPodiumRow(entries: trackers, currentUid: nil).padding(.top, AppSpacing.xs)
                }
                .padding(.horizontal, AppSpacing.md)
            }.background(AppColors.bg))),
            ("public-profile", AnyView(PublicProfileSheet(tracker: trackers[0], currentUid: nil))),
            ("country-picker", AnyView(NavigationStack { CountryFlagPickerView(store: Self.makeStore()) })),
            ("verified-proof", AnyView(VerifiedReviewProofSheet(isVerified: false, accountName: "Logan", accountUid: nil))),
            ("username", AnyView(UsernameSheet(mode: .firstTime, currentUsername: nil, suggestedFrom: "Logan",
                                               friendsService: .shared))),
            // Stand-in for onboarding's photo page (a private page of OnboardingView).
            ("onboarding-photo", AnyView(VStack(spacing: AppSpacing.lg) {
                OwlPointingAt(size: .form) {
                    Circle().fill(AppColors.accent.opacity(0.18)).frame(width: 132, height: 132)
                        .overlay(Text("L").font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.accent))
                }
                OnboardingTitle(title: "Add a photo",
                                subline: "Friends and the leaderboard see it next to your name. You can change it any time.")
            }
            .padding(.horizontal, AppSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.bg))),
        ]
        for (name, view) in screens {
            // The signed-out host app's listeners empty the list between renders.
            FriendsService.shared.friends = friends
            let data = Self.windowSnapshot(view.environmentObject(AuthService.shared))
            try data?.write(to: URL(fileURLWithPath: "\(dir)/friends-\(name).png"))
        }
    }

    /// The You tab with six weeks of shifts, a company and a savings goal,
    /// plus the screens and sheets it opens. Everything seeded is removed again.
    func testDumpYouScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASCOT_DUMP_DIR"] else {
            throw XCTSkip("Set MASCOT_DUMP_DIR to dump You screen renders")
        }
        let store = Self.makeStore()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var added: [WorkEntry] = []
        for back in 1...42 {
            guard let day = cal.date(byAdding: .day, value: -back, to: today), !cal.isDateInWeekend(day),
                  let start = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day),
                  let end = cal.date(bySettingHour: 16, minute: 0, second: 0, of: day) else { continue }
            let entry = WorkEntry(date: day, start: start, end: end, breakMinutes: 30, notes: "")
            store.add(entry)
            added.append(entry)
        }
        let defaults = UserDefaults.standard
        let companyKeys = ["company_name", "company_occupation", "company_start_date_ts"]
        let savedCompany = companyKeys.map { defaults.object(forKey: $0) }
        defaults.set("Northline Electric", forKey: "company_name")
        defaults.set("Electrician", forKey: "company_occupation")
        defaults.set(cal.date(byAdding: .month, value: -27, to: today)!.timeIntervalSince1970, forKey: "company_start_date_ts")
        let goal = EarningsGoal(name: "Truck down payment", targetAmount: 8000, alreadySaved: 2500, monthlyContribution: 600)
        EarningsGoalStore.shared.add(goal)
        EarningsGoalStore.shared.addDeposit(1200, to: goal.id)
        defer {
            added.forEach { store.delete($0) }
            for (key, value) in zip(companyKeys, savedCompany) { defaults.set(value, forKey: key) }
            EarningsGoalStore.shared.delete(id: goal.id)
        }

        let photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { ctx in
            UIColor(red: 0.30, green: 0.27, blue: 0.52, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            UIColor(red: 0.93, green: 0.76, blue: 0.56, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 190, y: 170, width: 220, height: 220))
            ctx.cgContext.fillEllipse(in: CGRect(x: 100, y: 430, width: 400, height: 420))
        }
        let phone = CGSize(width: 390, height: 844)
        let screens: [(String, AnyView, CGSize, TimeInterval)] = [
            ("you", AnyView(NavigationStack { AccountView(store: store) }), phone, 1.2),
            ("you-full", AnyView(NavigationStack { AccountView(store: store) }), CGSize(width: 390, height: 2700), 1.2),
            ("badges", AnyView(NavigationStack { AchievementsView(store: store) }), phone, 1.2),
            ("company", AnyView(NavigationStack { CompanyProfileView(store: store) }), phone, 1.2),
            ("goal-detail", AnyView(EarningsGoalDetailSheet(goalID: goal.id, store: store)), phone, 1.2),
            ("goal-editor", AnyView(EarningsGoalEditorSheet(existing: nil, currencyCode: "USD")), phone, 1.2),
            // The portal opening runs ~2.8s before the reveal settles.
            ("prestige", AnyView(PrestigeCelebrationView(prestige: 4, onDismiss: {})), phone, 5),
            ("crop", AnyView(ProfilePhotoCropView(image: photo, onCancel: {}, onConfirm: { _ in })), phone, 1.2),
        ]
        for (name, view, size, settle) in screens {
            let data = Self.windowSnapshot(view.environmentObject(AuthService.shared), size: size, settle: settle)
            try data?.write(to: URL(fileURLWithPath: "\(dir)/you-\(name).png"))
        }
    }

    /// Settings and its sub-screens, with two saved job sites (removed again).
    func testDumpSettingsScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASCOT_DUMP_DIR"] else {
            throw XCTSkip("Set MASCOT_DUMP_DIR to dump Settings screen renders")
        }
        let store = Self.makeStore()
        let sites = [
            store.addJobSite(JobSite(name: "Northline Shop", detail: "1420 Industrial Ave")),
            store.addJobSite(JobSite(name: "Riverside Tower", detail: "Level 12 fit-out")),
        ]
        defer { sites.forEach { store.deleteJobSite($0) } }

        let phone = CGSize(width: 390, height: 844)
        let screens: [(String, AnyView, CGSize)] = [
            ("settings", AnyView(SettingsView(store: store, settings: .constant(store.paySettings))), phone),
            ("friends-privacy", AnyView(NavigationStack { FriendsPrivacySettingsView(store: store) }), phone),
            ("job-sites", AnyView(NavigationStack { JobSitesSettingsView(store: store) }), phone),
            ("job-site-editor", AnyView(JobSiteEditorSheet(store: store, existing: nil)), phone),
            ("notifications", AnyView(NotificationsSheet(store: store, onDismiss: {})), phone),
            ("reminder", AnyView(ReminderTimePickerSheet(hour: .constant(17), onDismiss: {})), phone),
            ("export", AnyView(DataExportSheet(store: store)), phone),
            // Roughly the medium detent the pay-cycle pickers open at.
            ("date-picker", AnyView(AutoDismissDatePickerSheet(date: .constant(Date()), title: "Next Payday",
                                                               onDismiss: {})), CGSize(width: 390, height: 480)),
        ]
        for (name, view, size) in screens {
            let data = Self.windowSnapshot(view.environmentObject(AuthService.shared), size: size)
            try data?.write(to: URL(fileURLWithPath: "\(dir)/settings-\(name).png"))
        }
    }

    /// The tip jar and the Pro paywall (no StoreKit products in tests, so
    /// both show their no-products state).
    func testDumpSupportScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASCOT_DUMP_DIR"] else {
            throw XCTSkip("Set MASCOT_DUMP_DIR to dump support screen renders")
        }
        let screens: [(String, AnyView)] = [
            ("tip-jar", AnyView(TipJarView())),
            ("paywall", AnyView(PremiumUpgradeView())),
        ]
        for (name, view) in screens {
            let data = Self.windowSnapshot(view.environmentObject(AuthService.shared), settle: 2.5)
            try data?.write(to: URL(fileURLWithPath: "\(dir)/support-\(name).png"))
        }
    }

    private static func sampleFriend(uid: String, name: String, hours: Double, prestige: Int, streak: Int) -> FriendProfile {
        FriendProfile(
            uid: uid, displayName: name, level: 14, prestige: prestige, currentStreak: streak, bestStreak: 12,
            totalHours: 1240, chequeHours: hours, weeklyHours: hours / 2, weeklyShiftsLogged: 4, weeklyDaysLogged: 4,
            badgeCount: 9, unlockedBadgeSummaries: [], equippedTitle: "", profilePhotoURL: nil,
            companyName: "Northline Electric", companyOccupation: "Electrician", companyStartDate: nil,
            companyHoursLogged: 1240, companyDaysWorked: 150, updatedAt: nil, friendsSince: nil,
            chequeDailySummary: [], chequeWindowStart: "", chequeWindowCutoff: "", privacy: .default
        )
    }

    /// Hosts `view` in a window on the test host's scene and draws it, so
    /// NavigationStack, List and toolbars render as they do on device.
    private static func windowSnapshot<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 390, height: 844),
        settle: TimeInterval = 1.2
    ) -> Data? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        defer { window.isHidden = true }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }.pngData()
    }
}
