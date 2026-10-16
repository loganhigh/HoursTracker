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
}
