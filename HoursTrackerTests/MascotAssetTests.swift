import XCTest
import SwiftUI
@testable import HoursTracker

/// Otto's vector assets are compiled by the asset catalog, so a missing or
/// unparseable SVG only shows up at runtime as a blank space. These checks
/// load every pose and scarf layer, render OwlView, and keep his speech
/// within one line.
@MainActor
final class MascotAssetTests: XCTestCase {

    func testEveryPoseHasOwlAndScarfAssets() {
        for pose in OwlPose.allCases {
            let owl = UIImage(named: pose.assetName)
            XCTAssertNotNil(owl, "Missing asset \(pose.assetName)")
            XCTAssertGreaterThan(owl?.size.width ?? 0, 0, "\(pose.assetName) has no size")
            XCTAssertNotNil(UIImage(named: pose.scarfAssetName), "Missing asset \(pose.scarfAssetName)")
        }
    }

    func testScarfLayerMatchesOwlFrame() {
        // The scarf is drawn over the owl at the same scaledToFit size, so the
        // two vectors must share an aspect ratio or the scarf drifts.
        for pose in OwlPose.allCases {
            guard let owl = UIImage(named: pose.assetName),
                  let scarf = UIImage(named: pose.scarfAssetName) else { continue }
            XCTAssertEqual(owl.size.width / owl.size.height,
                           scarf.size.width / scarf.size.height,
                           accuracy: 0.001, "\(pose.rawValue) scarf aspect differs")
        }
    }

    func testOwlViewRendersEverySize() {
        for pose in OwlPose.allCases {
            for size in [OwlView.Size.hero, .emptyState, .companion, .peek] {
                let renderer = ImageRenderer(content: OwlView(pose: pose, size: size, bobs: false))
                renderer.scale = 2
                guard let image = renderer.uiImage else {
                    XCTFail("\(pose.rawValue) at \(size.height)pt produced no image")
                    continue
                }
                XCTAssertEqual(image.size.height, size.height, accuracy: 1, "\(pose.rawValue) wrong height")
            }
        }
    }

    func testSpeechBubbleRenders() {
        let renderer = ImageRenderer(content: OwlCompanionHeader(pose: .wave, line: "8.5h today. Nice shift.").frame(width: 390))
        XCTAssertNotNil(renderer.uiImage)
    }

    func testHomeLinesFitOneBubble() {
        let hourSamples: [Double] = [0, 0.25, 1, 4.5, 7.75, 8, 9.99, 10, 12.5, 16.25, 23.75]
        for seed in 0..<6 {
            for streak in [0, 2, 3, 30, 365] {
                for isDayOff in [false, true] {
                    for hours in hourSamples {
                        let line = OwlLines.home(todayHours: hours, isDayOff: isDayOff, streakDays: streak, daySeed: seed)
                        XCTAssertFalse(line.isEmpty)
                        XCTAssertLessThanOrEqual(line.count, OwlLines.maxLength, "Too long: \(line)")
                    }
                }
            }
        }
    }

    func testHomeLinePrefersDayOffThenHours() {
        XCTAssertTrue(OwlLines.home(todayHours: 8, isDayOff: true, streakDays: 0, daySeed: 0).contains("off")
                      || OwlLines.home(todayHours: 8, isDayOff: true, streakDays: 0, daySeed: 0).contains("Recharge"))
        XCTAssertTrue(OwlLines.home(todayHours: 8.5, isDayOff: false, streakDays: 0, daySeed: 0).hasPrefix("8.5h"))
        XCTAssertTrue(OwlLines.home(todayHours: 11, isDayOff: false, streakDays: 0, daySeed: 0).contains("Big one"))
        XCTAssertTrue(OwlLines.home(todayHours: 0, isDayOff: false, streakDays: 4, daySeed: 0).hasPrefix("4-day streak"))
    }

    func testHomePoseMatchesTheDay() {
        XCTAssertEqual(OwlLines.homePose(todayHours: 0, isDayOff: true, streakDays: 9), .sleep)
        XCTAssertEqual(OwlLines.homePose(todayHours: 7.5, isDayOff: false, streakDays: 9), .cheer)
        XCTAssertEqual(OwlLines.homePose(todayHours: 0, isDayOff: false, streakDays: 3), .streak)
        XCTAssertEqual(OwlLines.homePose(todayHours: 0, isDayOff: false, streakDays: 1), .coffee)
    }

    func testHomeLineForBrandNewUser() {
        let line = OwlLines.home(todayHours: 0, isDayOff: false, streakDays: 0, hasAnyShifts: false, daySeed: 4)
        XCTAssertEqual(line, "Log your first shift below.")
        XCTAssertLessThanOrEqual(line.count, OwlLines.maxLength)
    }

    func testLiveShiftOwlFollowsTheTimer() {
        let working = OwlLines.liveShift(isOnBreak: false, isStale: false)
        let onBreak = OwlLines.liveShift(isOnBreak: true, isStale: false)
        let stale = OwlLines.liveShift(isOnBreak: true, isStale: true)
        XCTAssertEqual(working.pose, .coffee)
        XCTAssertEqual(onBreak.pose, .sleep)
        XCTAssertEqual(stale.pose, .oops)
        for line in [working.line, onBreak.line, stale.line] {
            XCTAssertLessThanOrEqual(line.count, OwlLines.maxLength, line)
        }
    }

    func testHistoryOwlPrefersMissingDays() {
        XCTAssertEqual(OwlLines.history(currentChequeHours: 30, missingDays: 2).pose, .search)
        XCTAssertEqual(OwlLines.history(currentChequeHours: 30, missingDays: 1).line, "One workday looks unlogged.")
        XCTAssertEqual(OwlLines.history(currentChequeHours: 30, missingDays: 0).line, "30h on this cheque so far.")
        XCTAssertEqual(OwlLines.history(currentChequeHours: 0, missingDays: 0).pose, .clipboard)
        for missing in [0, 1, 2, 21] {
            for hours in [0.0, 7.5, 88.25, 168] {
                let line = OwlLines.history(currentChequeHours: hours, missingDays: missing).line
                XCTAssertLessThanOrEqual(line.count, OwlLines.maxLength, line)
            }
        }
    }

    func testChequeOwlFollowsTheChequeState() {
        XCTAssertEqual(OwlLines.cheque(.inProgress, hours: 12).line, "12h logged so far.")
        XCTAssertEqual(OwlLines.cheque(.pending, hours: 80).pose, .calendar)
        XCTAssertEqual(OwlLines.cheque(.awaitingTotal, hours: 80).pose, .point)
        XCTAssertEqual(OwlLines.cheque(.recorded, hours: 80).pose, .cheer)
        for state in [OwlLines.ChequeState.inProgress, .pending, .awaitingTotal, .recorded] {
            for hours in [0.0, 9.75, 120.5] {
                let line = OwlLines.cheque(state, hours: hours).line
                XCTAssertLessThanOrEqual(line.count, OwlLines.maxLength, line)
            }
        }
    }

    func testFriendsOwlFollowsYourRank() {
        XCTAssertEqual(OwlLines.friends(myRank: 1, total: 6).pose, .trophy)
        XCTAssertEqual(OwlLines.friends(myRank: 3, total: 6).line, "#3 this cheque. On the podium!")
        XCTAssertEqual(OwlLines.friends(myRank: 5, total: 6).line, "#5 of 6. Time to climb.")
        XCTAssertEqual(OwlLines.friends(myRank: 0, total: 6).pose, .buddies)
        for rank in [0, 1, 2, 3, 4, 99] {
            XCTAssertLessThanOrEqual(OwlLines.friends(myRank: rank, total: 120).line.count, OwlLines.maxLength)
        }
    }

    func testGlobalRankOwl() {
        XCTAssertEqual(OwlLines.globalRank(nil).pose, .search)
        XCTAssertEqual(OwlLines.globalRank(1).pose, .crown)
        XCTAssertEqual(OwlLines.globalRank(7).line, "Top 10 worldwide. Huge.")
        XCTAssertEqual(OwlLines.globalRank(4521).line, "#4521 worldwide. Keep climbing.")
        for rank in [nil, 1, 10, 11, 99_999] as [Int?] {
            XCTAssertLessThanOrEqual(OwlLines.globalRank(rank).line.count, OwlLines.maxLength)
        }
    }

    func testLineStaysTheSameAllDay() {
        let cal = Calendar(identifier: .gregorian)
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 6))!
        let night = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 23))!
        XCTAssertEqual(OwlLines.daySeed(for: morning, calendar: cal), OwlLines.daySeed(for: night, calendar: cal))
    }

    func testLoadingDotsStayVisibleAndStagger() {
        for step in 0..<240 {
            let t = 1_000_000 + Double(step) * 0.01
            for index in 0..<3 {
                let o = LoadingDots.opacity(at: t, index: index)
                XCTAssertGreaterThanOrEqual(o, 0.3 - 1e-9)
                XCTAssertLessThanOrEqual(o, 1.0 + 1e-9)
            }
        }
        // Neighbouring dots are out of phase: over one cycle they clearly diverge.
        let biggestGap = (0..<120).map { step -> Double in
            let t = 1_000_000 + Double(step) * 0.01
            return abs(LoadingDots.opacity(at: t, index: 0) - LoadingDots.opacity(at: t, index: 1))
        }.max() ?? 0
        XCTAssertGreaterThan(biggestGap, 0.3)
    }

    func testPickWrapsNegativeSeeds() {
        XCTAssertEqual(OwlLines.pick(["a", "b", "c"], seed: -1), "c")
        XCTAssertEqual(OwlLines.pick([], seed: 3), "")
    }

    /// Visual check of the three placements on the app's dark background.
    /// Skipped unless MASCOT_DUMP_DIR is set (pass TEST_RUNNER_MASCOT_DUMP_DIR
    /// to xcodebuild).
    func testDumpPlacements() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASCOT_DUMP_DIR"] else {
            throw XCTSkip("Set MASCOT_DUMP_DIR to dump owl placement renders")
        }
        let card = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        let perch = OwlPerch(pose: .wave, line: "8.5h today. Nice shift.") {
            VStack(spacing: AppSpacing.xxs) {
                Text("Today").appText(.eyebrow).foregroundStyle(AppColors.faint)
                Text("8.5h").appText(.heroNumber).foregroundStyle(AppColors.text)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.xl)
            .background(AppColors.card, in: card)
            .overlay(card.stroke(AppColors.stroke, lineWidth: 1))
        }
        let rows = VStack(spacing: 0) {
            ForEach(["Hourly wage", "Payday", "Week starts"], id: \.self) { row in
                Text(row).appText(.body).foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
            }
        }
        .background(AppColors.card, in: card)
        let views: [(String, AnyView)] = [
            ("perch", AnyView(perch)),
            ("peek", AnyView(rows.owlPeek().padding(.top, OwlPerchMetrics.peekClearance))),
            ("peek-bell", AnyView(rows.owlPeek(.bell, alignment: .leading).padding(.top, OwlPerchMetrics.peekClearance))),
            ("empty", AnyView(AppEmptyState(owl: .clipboard, title: "No cheques yet", message: "Log a shift and your pay periods will show up here."))),
            ("hero-cheer", AnyView(OwlView(pose: .cheer, size: .hero, bobs: false))),
        ]
        for (name, view) in views {
            let renderer = ImageRenderer(content: view
                .padding(AppSpacing.md)
                .frame(width: 390)
                .background(AppColors.bg)
                .environment(\.colorScheme, .dark))
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() {
                try data.write(to: URL(fileURLWithPath: "\(dir)/owl-\(name).png"))
            }
        }
    }

    /// Full-screen launch states that are hard to reach in the Simulator
    /// (the splash is usually gone in a blink; the error needs a failed load).
    func testDumpLaunchScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["MASCOT_DUMP_DIR"] else {
            throw XCTSkip("Set MASCOT_DUMP_DIR to dump launch screen renders")
        }
        let announcement = Announcement(
            id: "dump", title: "New in 3.5", message: "Shifts now sync faster across your devices.",
            kind: "news", buttonTitle: "Got it"
        )
        let screens: [(String, AnyView)] = [
            ("splash", AnyView(SplashView())),
            ("payday", AnyView(PaydayConfettiOverlay(onDismiss: {}))),
            ("streak", AnyView(StreakBurstView(streakCount: 14))),
            ("announcement", AnyView(AnnouncementPromptOverlay(announcement: announcement, onFinish: { _ in }))),
            ("country", AnyView(CountryFlagPromptOverlay(onChoose: {}))),
            ("prestige-info", AnyView(PrestigeInfoSheet(currentPrestige: 3))),
            ("best-and-xp", AnyView(VStack(spacing: 40) {
                PersonalBestBanner()
                FloatingXPGainView(text: "+120 XP")
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AppColors.bg))),
            ("startup-error", AnyView(StartupErrorView(
                message: "We couldn't load your saved hours.",
                onRetry: {},
                onResetCache: {}
            ))),
        ]
        for (name, view) in screens {
            let renderer = ImageRenderer(content: view
                .frame(width: 390, height: 844)
                .environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let data = renderer.uiImage?.pngData() {
                try data.write(to: URL(fileURLWithPath: "\(dir)/screen-\(name).png"))
            }
        }
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
            ("country-picker", AnyView(NavigationStack { CountryFlagPickerView(store: HoursStore()) })),
            ("verified-proof", AnyView(VerifiedReviewProofSheet(isVerified: false, accountName: "Logan", accountUid: nil))),
            ("username", AnyView(UsernameSheet(mode: .firstTime, currentUsername: nil, suggestedFrom: "Logan",
                                               friendsService: .shared))),
        ]
        for (name, view) in screens {
            // The signed-out host app's listeners empty the list between renders.
            FriendsService.shared.friends = friends
            let data = Self.windowSnapshot(view.environmentObject(AuthService.shared))
            try data?.write(to: URL(fileURLWithPath: "\(dir)/friends-\(name).png"))
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
    private static func windowSnapshot<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) -> Data? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        defer { window.isHidden = true }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }.pngData()
    }
}
