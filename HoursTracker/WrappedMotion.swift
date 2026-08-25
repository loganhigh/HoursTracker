import SwiftUI

// MARK: - Wrapped motion primitives
//
// Story-specific motion built on top of the app's existing AppMotion tokens
// (springs + `AppMotion.animation(_:reduceMotion:)`), so Wrapped animates
// with the same feel as the rest of the app rather than inventing a second
// motion language.
//
// Reduce Motion rule used throughout: content still *appears* (nothing is
// hidden from someone who turns motion off), it just arrives without
// travel, scale, or counting — the value snaps to final immediately.

enum WrappedMotion {
    /// The beat every slide's entrance is built on. Slower and springier
    /// than in-app card motion because a full-screen story reveal has more
    /// distance to cover and wants a touch of drama.
    static let reveal = Animation.spring(response: 0.55, dampingFraction: 0.78)
    static let hero = Animation.spring(response: 0.62, dampingFraction: 0.70)

    /// How long a hero number spends counting up. Long enough to read as
    /// deliberate, short enough that a fast tapper is never waiting on it.
    static let countDuration: Double = 1.1

    /// Per-item delay for staggered entrances, capped so a long list never
    /// leaves the last item lagging behind a user's tap to advance.
    static func stagger(_ index: Int, step: Double = 0.09, cap: Double = 0.72) -> Double {
        min(cap, Double(index) * step)
    }

    /// Per-bar delay for sequential chart animation. Tighter than `stagger`
    /// because charts have more elements (7 or 12) to get through.
    static func barStagger(_ index: Int, step: Double = 0.045, cap: Double = 0.6) -> Double {
        min(cap, Double(index) * step)
    }
}

// MARK: - Counting number

/// A number that animates from one value to another by interpolating the
/// value itself (not a text cross-fade), so it reads as a real odometer
/// count-up. Conforms to `Animatable`, so `withAnimation` drives it.
///
/// Formatting runs once per frame, so the closure must stay cheap — the
/// convenience initializers below use a cached formatter rather than
/// `Double.formatted()`, which allocates a new format style per call.
struct WrappedCountingText: View, Animatable {
    var value: Double
    var font: Font
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .font(font)
            .foregroundStyle(WrappedPalette.primaryText)
            .monospacedDigit() // no width jitter as digits change
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

extension WrappedCountingText {
    /// Grouped whole number ("2,847"). Uses a cached formatter because this
    /// runs on every animation frame.
    static func wholeNumber(value: Double, font: Font) -> WrappedCountingText {
        WrappedCountingText(value: value, font: font) { current in
            WrappedCountingFormatters.grouped.string(from: NSNumber(value: Int(current.rounded()))) ?? "0"
        }
    }
}

/// Formatters are expensive to build and these run per animation frame, so
/// they're created once and reused.
enum WrappedCountingFormatters {
    static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
}

// MARK: - Entrance reveal

/// Standard staggered entrance: fade + rise + a slight scale settle.
/// `isActive` is driven by the slide's own appear state so every element on
/// a slide animates from the same trigger.
struct WrappedRevealModifier: ViewModifier {
    let isActive: Bool
    let index: Int
    var yOffset: CGFloat = 22
    var scaleFrom: CGFloat = 0.94

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wrappedRendersSettled) private var rendersSettled

    private var settled: Bool { reduceMotion || rendersSettled }

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive || settled ? 0 : yOffset)
            .scaleEffect(isActive || settled ? 1 : scaleFrom)
            // `nil` when snapshotting: any ambient animation here would
            // also interpolate a child WrappedCountingText's animatableData,
            // capturing it mid-count (i.e. at 0) instead of at its final
            // value. Reduce Motion still gets a gentle fade — that's opacity,
            // not motion.
            .animation(
                rendersSettled
                    ? nil
                    : (reduceMotion
                        ? .easeOut(duration: 0.2)
                        : WrappedMotion.reveal.delay(WrappedMotion.stagger(index))),
                value: isActive
            )
    }
}

extension View {
    /// Staggered entrance for one element of a slide. `index` orders the
    /// stagger; elements sharing an index arrive together.
    func wrappedReveal(_ isActive: Bool, index: Int = 0, yOffset: CGFloat = 22, scaleFrom: CGFloat = 0.94) -> some View {
        modifier(WrappedRevealModifier(isActive: isActive, index: index, yOffset: yOffset, scaleFrom: scaleFrom))
    }
}

// MARK: - Settled-render flag

/// When true, a slide skips its entrance animation and renders in its final
/// state on the first frame.
///
/// Exists because snapshotting (SwiftUI previews, `ImageRenderer`) captures
/// frame zero — before any count-up has run — which makes every hero number
/// read "0". Setting this renders what the user actually ends up seeing.
/// Defaults to false, so normal app playback is unaffected.
private struct WrappedRendersSettledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wrappedRendersSettled: Bool {
        get { self[WrappedRendersSettledKey.self] }
        set { self[WrappedRendersSettledKey.self] = newValue }
    }
}

// MARK: - Slide appearance driver

/// Gives a slide a single "has appeared" flag plus the animated hero value,
/// so each slide body stays declarative instead of juggling several
/// @State booleans and onAppear closures.
///
/// Because `WrappedView` gives each slide a fresh identity (`.id(index)`),
/// this re-runs every time a slide is navigated to — including on the way
/// back — so revisiting a slide replays its entrance.
struct WrappedSlideAppearance<Content: View>: View {
    /// Final value for any counting number on this slide; `0` when the
    /// slide has none.
    var countTarget: Double = 0
    /// Extra delay before the count starts, letting a title land first.
    var countDelay: Double = 0.18
    /// Haptic fired as the slide settles. `nil` for slides that shouldn't
    /// buzz — most of them, so the ones that do still feel like an event.
    var haptic: WrappedHaptic? = nil
    /// Fires the moment the hero count reaches its final value, so a slide
    /// can land an effect exactly on that beat instead of guessing at the
    /// timing. Called immediately under Reduce Motion, where there is no
    /// count to wait for.
    var onCountSettled: (() -> Void)? = nil

    @ViewBuilder var content: (_ appeared: Bool, _ countValue: Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.wrappedRendersSettled) private var rendersSettled
    @State private var appeared = false
    @State private var countValue: Double = 0
    @State private var settleTask: DispatchWorkItem?

    var body: some View {
        content(appeared, countValue)
            .onAppear {
                if reduceMotion || rendersSettled {
                    // Everything lands immediately; no travel, no counting.
                    appeared = true
                    countValue = countTarget
                    haptic?.fire()
                    onCountSettled?()
                    return
                }

                appeared = true
                withAnimation(.easeOut(duration: WrappedMotion.countDuration).delay(countDelay)) {
                    countValue = countTarget
                }
                haptic?.fire(after: countDelay)

                if let onCountSettled {
                    settleTask?.cancel()
                    let task = DispatchWorkItem(block: onCountSettled)
                    settleTask = task
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + countDelay + WrappedMotion.countDuration,
                        execute: task
                    )
                }
            }
            .onDisappear {
                // Never fire into a slide the user already navigated away from.
                settleTask?.cancel()
                settleTask = nil
            }
    }
}

/// The small set of haptics Wrapped uses, so slides don't reach into
/// `Haptics` directly and accidentally over-buzz the experience.
enum WrappedHaptic {
    case light
    case medium
    case success

    func fire(after delay: Double = 0) {
        guard delay > 0 else {
            trigger()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { trigger() }
    }

    private func trigger() {
        switch self {
        case .light: Haptics.lightTap()
        case .medium: Haptics.mediumTap()
        case .success: Haptics.success()
        }
    }
}
