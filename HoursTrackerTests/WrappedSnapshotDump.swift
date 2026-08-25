import XCTest
import SwiftUI
@testable import HoursTracker

/// TEMPORARY visual dump — writes slide renders to disk for eyeballing.
/// Skipped unless WRAPPED_DUMP_DIR is set, so it never runs in a normal suite.
///
/// Uses a real UIWindow + UIHostingController rather than ImageRenderer,
/// because ImageRenderer snapshots at t=0 — before count-ups have run and
/// while bars are still rising. Hosting the view for real and spinning the
/// run loop lets the entrance animations finish, so the captures show the
/// settled slide the user actually ends up looking at.
@MainActor
final class WrappedSnapshotDump: XCTestCase {

    /// ImageRenderer captures frame zero, so `wrappedRendersSettled` tells
    /// the slides to skip their entrance and draw final values immediately —
    /// otherwise every hero number would read "0" and bars would be mid-rise.
    private func settledSnapshot<V: View>(_ view: V, size: CGSize, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .environment(\.wrappedRendersSettled, true)
        )
        renderer.scale = scale
        return renderer.uiImage
    }

    func testDumpSlides() throws {
        guard let dir = ProcessInfo.processInfo.environment["WRAPPED_DUMP_DIR"] else {
            throw XCTSkip("Set WRAPPED_DUMP_DIR to dump slide renders")
        }

        let stats = WrappedPreviewData.busyYear
        let slides: [(String, AnyView)] = [
            ("01-intro", AnyView(WrappedIntroSlide(stats: stats))),
            ("02-hours", AnyView(WrappedTotalHoursSlide(stats: stats))),
            ("03-shifts", AnyView(WrappedTotalShiftsSlide(stats: stats))),
            ("04-month", AnyView(WrappedBiggestMonthSlide(stats: stats))),
            ("05-longest", AnyView(WrappedLongestShiftSlide(stats: stats))),
            ("06-schedule", AnyView(WrappedWorkScheduleSlide(stats: stats))),
            ("07-longshift", AnyView(WrappedLongShiftBreakdownSlide(stats: stats))),
            ("08-week", AnyView(WrappedBiggestWeekSlide(stats: stats))),
            ("09-weekend", AnyView(WrappedWeekendVsWeekdaySlide(stats: stats))),
            ("10-streak", AnyView(WrappedWorkStreakSlide(stats: stats))),
            ("11-personality", AnyView(WrappedWorkerPersonalitySlide(stats: stats))),
            ("12-summary", AnyView(WrappedFinalSummarySlide(stats: stats, username: "logan"))),
        ]

        for (name, view) in slides {
            guard let image = settledSnapshot(view, size: CGSize(width: 390, height: 844), scale: 2) else { continue }
            if let data = image.pngData() {
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
    }
}
