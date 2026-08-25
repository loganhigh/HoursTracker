import SwiftUI
import RiveRuntime

// MARK: - Reusable Rive wrapper
//
// One place that knows how to load and drive a `.riv` asset, so feature
// views (currently only the Wrapped final summary) never contain Rive setup
// code. Everything here is optional-by-design: if the asset isn't in the
// bundle, or fails to load, or the user has Reduce Motion on, this renders
// nothing at all and the host view's native content stands on its own.

/// Describes a `.riv` asset and how to play it. A value type so a feature
/// can declare its animation as a constant and hand it to the view.
struct WrappedRiveAsset: Equatable {
    /// Filename without the `.riv` extension, as added to the app bundle.
    let fileName: String
    /// Optional artboard. `nil` uses the file's default artboard.
    var artboardName: String? = nil
    /// Optional linear animation. Ignored when `stateMachineName` is set —
    /// Rive drives one or the other, and a state machine takes precedence.
    var animationName: String? = nil
    /// Optional state machine. Preferred over `animationName` when both are
    /// present, since state machines are how modern Rive files are authored.
    var stateMachineName: String? = nil
    /// Whether playback starts as soon as the view appears.
    var autoPlay: Bool = true
    /// False = play through once and stop (the default for a celebration);
    /// true = loop continuously. Looping keeps the render loop awake, so it
    /// should be reserved for cases that genuinely need it.
    var loops: Bool = false

    /// True when a matching `.riv` file actually exists in the bundle.
    /// Checked before any Rive object is constructed, because
    /// `RiveViewModel(fileName:)` traps on a missing file rather than
    /// returning nil — so "does it exist" has to be answered first.
    var existsInBundle: Bool {
        Bundle.main.url(forResource: fileName, withExtension: "riv") != nil
    }

    /// Verifies the artboard / animation / state-machine names in this
    /// descriptor actually exist inside the `.riv`.
    ///
    /// This matters because `RiveViewModel` **traps** on a name it can't
    /// resolve — a mistyped or re-exported animation name crashes the app
    /// rather than failing softly. Since this whole layer is decorative,
    /// that trade is unacceptable, so names are validated against the file
    /// first and a mismatch degrades to no animation at all.
    var isPlayable: Bool {
        guard existsInBundle else { return false }
        guard let file = try? RiveFile(name: fileName) else { return false }

        let artboard: RiveArtboard
        if let artboardName {
            guard let named = try? file.artboard(fromName: artboardName) else { return false }
            artboard = named
        } else {
            guard let defaultArtboard = try? file.artboard() else { return false }
            artboard = defaultArtboard
        }

        if let stateMachineName {
            return artboard.stateMachineNames().contains(stateMachineName)
        }
        if let animationName {
            return artboard.animationNames().contains(animationName)
        }
        // No specific animation requested — anything playable will do.
        return artboard.animationCount() > 0 || artboard.stateMachineCount() > 0
    }
}

/// Renders a `.riv` asset, or nothing at all if it can't or shouldn't play.
///
/// Failure is silent by design: a missing or broken decorative animation
/// should never take down (or visibly degrade) the real content it sits
/// behind. The one exception is a debug log, so a missing asset during
/// development isn't a total mystery.
struct WrappedRiveView: View {
    let asset: WrappedRiveAsset
    /// Called when the animation has had time to play through, so the host
    /// can tear it down. Only fires for non-looping assets.
    var onFinished: (() -> Void)? = nil
    /// How long to let a one-shot run before calling `onFinished`. Rive's
    /// SwiftUI wrapper doesn't surface a reliable "animation ended" callback
    /// for every file/state-machine shape, so the host gets a predictable
    /// ceiling instead of waiting on something that may never arrive.
    var oneShotDuration: Double = 3.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: RiveViewModel?
    @State private var finishTask: DispatchWorkItem?

    var body: some View {
        Group {
            if let viewModel {
                viewModel.view()
                    // Purely decorative: never intercept the taps that drive
                    // story navigation.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                // No asset, or Reduce Motion — occupy no space at all so the
                // host's layout is identical with and without the animation.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: cleanUp)
    }

    private func load() {
        // Reduce Motion: skip the decorative layer entirely and let the host
        // show its final content immediately.
        guard !reduceMotion else { return }

        // Validates both presence AND that the configured names resolve —
        // an unresolvable name would otherwise trap inside RiveViewModel.
        guard asset.isPlayable else {
            #if DEBUG
            print("[WrappedRive] '\(asset.fileName).riv' missing or its artboard/animation names don't resolve — falling back to native content.")
            #endif
            return
        }

        let model: RiveViewModel
        if let stateMachineName = asset.stateMachineName {
            model = RiveViewModel(
                fileName: asset.fileName,
                stateMachineName: stateMachineName,
                autoPlay: asset.autoPlay,
                artboardName: asset.artboardName
            )
        } else if let animationName = asset.animationName {
            model = RiveViewModel(
                fileName: asset.fileName,
                animationName: animationName,
                autoPlay: asset.autoPlay,
                artboardName: asset.artboardName
            )
        } else {
            model = RiveViewModel(
                fileName: asset.fileName,
                autoPlay: asset.autoPlay,
                artboardName: asset.artboardName
            )
        }

        viewModel = model

        // One-shots get stopped and reported after their window, so a
        // finished celebration isn't left holding a live render loop.
        guard !asset.loops else { return }
        let task = DispatchWorkItem {
            model.stop()
            onFinished?()
        }
        finishTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + oneShotDuration, execute: task)
    }

    private func cleanUp() {
        // Cancel the pending finish so it can't fire against a torn-down
        // view, then stop playback and drop the model — otherwise a
        // dismissed Wrapped could leave Rive animating off-screen.
        finishTask?.cancel()
        finishTask = nil
        viewModel?.stop()
        viewModel = nil
    }
}
