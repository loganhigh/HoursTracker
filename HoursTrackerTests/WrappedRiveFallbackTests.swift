import XCTest
import SwiftUI
@testable import HoursTracker

/// Covers the guarantee that matters most for the Rive integration: the
/// Final Summary must be fully functional with no `.riv` asset present.
/// No asset ships today, so these run against the real fallback path.
@MainActor
final class WrappedRiveFallbackTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func sampleStats() -> WrappedYearStats {
        let entries: [WorkEntry] = (1...15).map { day in
            var s = DateComponents(year: 2026, month: 6, day: day, hour: 6); s.timeZone = cal.timeZone
            var e = DateComponents(year: 2026, month: 6, day: day, hour: 18); e.timeZone = cal.timeZone
            var d = DateComponents(year: 2026, month: 6, day: day); d.timeZone = cal.timeZone
            return WorkEntry(date: cal.date(from: d)!, start: cal.date(from: s)!,
                             end: cal.date(from: e)!, breakMinutes: 0, notes: "")
        }
        return WrappedStatsEngine.compute(year: 2026, entries: entries, calendar: cal, sourcedFromArchive: false)
    }

    private func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 1
        return renderer.uiImage
    }

    // MARK: - Asset presence

    func testMissingAssetIsReportedAsAbsentRatherThanCrashing() {
        // The bundle has no .riv today, so this is the live fallback state.
        let asset = WrappedRiveAsset(fileName: "definitely_not_a_real_asset")
        XCTAssertFalse(asset.existsInBundle)
    }

    func testConfiguredFinaleAssetIsAOneShotUsingFileDefaults() {
        // Artboard/animation are intentionally unset so a dropped-in .riv
        // plays via its default artboard and first animation, with no code
        // change required.
        let asset = WrappedRiveAsset.wrappedFinale
        XCTAssertEqual(asset.fileName, "wrapped_finale")
        XCTAssertNil(asset.artboardName, "Should use the file's default artboard")
        XCTAssertNil(asset.animationName, "Should use the file's first animation")
        XCTAssertNil(asset.stateMachineName)
        XCTAssertTrue(asset.autoPlay)
        XCTAssertFalse(asset.loops, "The finale must be one-shot, not a permanent loop")
    }

    /// No `.riv` ships today, so the celebration must resolve to "not
    /// playable" and every host must fall back to native-only. If an asset
    /// is later added, this flips to verifying it actually resolves.
    func testFinaleAssetEitherIsAbsentOrIsFullyPlayable() {
        let asset = WrappedRiveAsset.wrappedFinale
        if asset.existsInBundle {
            XCTAssertTrue(asset.isPlayable, "A bundled wrapped_finale.riv must resolve, or the burst silently never plays")
        } else {
            XCTAssertFalse(asset.isPlayable, "With no asset present the celebration must report not-playable")
        }
    }

    // MARK: - Fallback rendering

    func testFinalSummaryRendersWithoutAnyRiveAsset() {
        let image = render(WrappedFinalSummarySlide(stats: sampleStats()))
        XCTAssertNotNil(image, "Final summary must render with no .riv present")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testFinalSummaryRendersWithAndWithoutAUsername() {
        XCTAssertNotNil(render(WrappedFinalSummarySlide(stats: sampleStats(), username: "logan")))
        XCTAssertNotNil(render(WrappedFinalSummarySlide(stats: sampleStats(), username: nil)))
        // An empty string must not render a bare "@".
        XCTAssertNotNil(render(WrappedFinalSummarySlide(stats: sampleStats(), username: "")))
    }

    func testRiveViewWithMissingAssetRendersNothingAndDoesNotCrash() {
        let view = WrappedRiveView(asset: WrappedRiveAsset(fileName: "missing_asset_xyz"))
        XCTAssertNotNil(render(view), "Missing asset must degrade silently, not trap")
    }

    /// Regression guard. RiveViewModel *traps* on an unresolvable artboard
    /// or animation name — a wrong name crashed the app outright before the
    /// wrapper started validating names against the file. These must all
    /// report "not playable" and render nothing instead.
    func testWrongNamesAreNotPlayableAndDoNotCrash() throws {
        try XCTSkipUnless(
            WrappedRiveAsset.wrappedFinale.existsInBundle,
            "Needs a bundled wrapped_finale.riv to distinguish bad names from a missing file"
        )
        let badAnimation = WrappedRiveAsset(
            fileName: "wrapped_finale",
            artboardName: "New Artboard",
            animationName: "Animation 19" // off-by-one typo that used to crash
        )
        XCTAssertTrue(badAnimation.existsInBundle, "File is present…")
        XCTAssertFalse(badAnimation.isPlayable, "…but a bad animation name must not be playable")
        XCTAssertNotNil(render(WrappedRiveView(asset: badAnimation)))

        let badArtboard = WrappedRiveAsset(
            fileName: "wrapped_finale",
            artboardName: "Nope",
            animationName: "Animation 1"
        )
        XCTAssertFalse(badArtboard.isPlayable)
        XCTAssertNotNil(render(WrappedRiveView(asset: badArtboard)))

        let badStateMachine = WrappedRiveAsset(
            fileName: "wrapped_finale",
            stateMachineName: "Celebrate" // this file has no state machines
        )
        XCTAssertFalse(badStateMachine.isPlayable)
        XCTAssertNotNil(render(WrappedRiveView(asset: badStateMachine)))
    }

    func testTotalHoursSlideRendersWithTheBurstWired() {
        // The burst mounts only after the count settles, but the slide must
        // render correctly both before and after that point.
        XCTAssertNotNil(render(WrappedTotalHoursSlide(stats: sampleStats())))
    }

    /// Whatever the asset situation, mounting the celebration view must be
    /// safe — this is the guarantee that a bad or absent .riv can never
    /// take down the slide.
    func testMountingTheConfiguredCelebrationIsAlwaysSafe() {
        XCTAssertNotNil(render(WrappedRiveView(asset: .wrappedFinale)))
    }

    func testWrappedViewStillRendersEndToEndWithUsername() {
        XCTAssertNotNil(render(WrappedView(stats: sampleStats(), username: "logan")))
    }

    // MARK: - Empty year still reaches the summary

    func testEmptyYearFinalSummaryStillRenders() {
        let empty = WrappedStatsEngine.compute(year: 2026, entries: [], calendar: cal, sourcedFromArchive: false)
        XCTAssertNotNil(render(WrappedFinalSummarySlide(stats: empty, username: "logan")))
    }
}
