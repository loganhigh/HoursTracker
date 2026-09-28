import SwiftUI

// MARK: - Shared Wrapped slide styling
//
// Wrapped is an immersive, story-style canvas (like Instagram/Spotify
// Wrapped) rather than a themed app screen — it deliberately renders on a
// fixed near-black background with light text regardless of the system's
// light/dark setting, the same way Stories-style experiences elsewhere
// don't retheme per system appearance. The rest of the app's screens keep
// using AppColors/AppTheme as normal; this fixed palette is scoped to
// Wrapped only.

enum WrappedPalette {
    static let background = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let accent = Color(hex: 0xF5C518) // matches the app's existing gold/yellow accent
    static let accentDeep = Color(hex: 0xE0932B)

    /// Fill for a highlighted bar/segment — the "this is the one" treatment.
    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Fill for ordinary bars: present but clearly subordinate to the accent.
    static let barGradient = LinearGradient(
        colors: [Color.white.opacity(0.42), Color.white.opacity(0.20)],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// The animated "ribbon field" behind every slide: four feathered diagonal
/// bands (Night → Iris → Lilac → Petal) that sway and ripple slowly.
///
/// Rendered at 30fps in a Canvas, and only while a Wrapped story is on
/// screen, so the cost is bounded by how long someone watches their year.
/// Under Reduce Motion it is drawn once, at rest. Every slide shares one
/// clock, so the field keeps moving continuously as slides change instead of
/// restarting on each one.
struct WrappedBackdrop: View {
    /// Kept so existing call sites compile; the ribbon field is one shared
    /// backdrop and is deliberately not re-tinted per slide.
    var tint: Color = WrappedPalette.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let epoch = Date()

    var body: some View {
        ZStack {
            WrappedRibbonField.night

            if reduceMotion {
                WrappedRibbonField(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    WrappedRibbonField(time: timeline.date.timeIntervalSince(Self.epoch))
                }
            }

            // The palette runs all the way to a pale pink; slide copy is
            // white and gold. This scrim keeps text legible over the light
            // bands. It is tinted with the palette's own Night rather than
            // black, which greyed the pinks out instead of deepening them.
            LinearGradient(
                colors: [WrappedRibbonField.night.opacity(0.20), WrappedRibbonField.night.opacity(0.50)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// One frame of the ribbon field at `time` seconds.
///
/// A stripe field along `angle`, where each point's position along the
/// gradient axis is bent by a sine of its cross-axis position. Drawn as thin
/// slices across the cross axis, each filled with the same banded gradient
/// shifted by that slice's wave offset; a light blur feathers the slices into
/// continuous curves. No value is rounded per frame — quantising the angle or
/// offsets is what makes this kind of motion visibly step.
struct WrappedRibbonField: View {
    let time: TimeInterval

    static let night = Color(hex: 0x1B1035)

    private static let gradient = Gradient(stops: [
        .init(color: Color(hex: 0x1B1035), location: 0),      // Night
        .init(color: Color(hex: 0x1B1035), location: 0.165),
        .init(color: Color(hex: 0x4A3A8C), location: 0.2079), // Iris
        .init(color: Color(hex: 0x4A3A8C), location: 0.4571),
        .init(color: Color(hex: 0xB58AC9), location: 0.5429), // Lilac
        .init(color: Color(hex: 0xB58AC9), location: 0.7921),
        .init(color: Color(hex: 0xF5D6E6), location: 0.835),  // Petal
        .init(color: Color(hex: 0xF5D6E6), location: 1),
    ])

    private static let baseAngle = 155.0   // CSS degrees: 0 = up, clockwise
    private static let speed = 0.98
    private static let motionAmount = 0.75
    private static let wave = 12.0
    private static let slices = 72

    var body: some View {
        Canvas { context, size in
            let phase = time * Self.speed
            // Hard bands sway rather than spin. sin(0) = 0, so motion starts
            // from the resting angle without a snap.
            let angle = (Self.baseAngle + sin(phase * 0.6) * 28 * Self.motionAmount) * .pi / 180
            let clock = 20.75 + phase * 1.2
            let amplitude = (Self.wave / 100) * 0.35

            // Length of the CSS gradient line for this box and angle.
            let length = abs(size.width * sin(angle)) + abs(size.height * cos(angle))
            let reach = hypot(size.width, size.height) / 2 + 24
            let sliceWidth = (reach * 2) / Double(Self.slices)

            // Local +y runs along the gradient direction, local x across it.
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .radians(angle + .pi))

            for index in 0..<Self.slices {
                let x = -reach + Double(index) * sliceWidth
                let cross = (x + sliceWidth / 2) / length
                let offset = amplitude * sin(cross * 2.4 * 2 * .pi + clock) * length
                context.fill(
                    Path(CGRect(x: x, y: -reach, width: sliceWidth + 1, height: reach * 2)),
                    with: .linearGradient(
                        Self.gradient,
                        startPoint: CGPoint(x: 0, y: -length / 2 + offset),
                        endPoint: CGPoint(x: 0, y: length / 2 + offset)
                    )
                )
            }
        }
        .blur(radius: 5)
        // Oversized so the blur never pulls transparent edges into view.
        .padding(-24)
    }
}

/// Small uppercased label used above/below hero numbers ("YOUR BIGGEST MONTH", "HOURS").
struct WrappedEyebrow: View {
    let text: String
    var color: Color = WrappedPalette.secondaryText

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .tracking(2)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }
}

/// The large hero number/word on a slide (e.g. "2,847", "JULY").
struct WrappedHero: View {
    let text: String
    var size: CGFloat = 64

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(WrappedPalette.primaryText)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .lineLimit(2)
    }
}

/// A supporting line under a hero number (e.g. "Across 241 shifts this year").
struct WrappedSupportingLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(WrappedPalette.secondaryText)
            .multilineTextAlignment(.center)
    }
}

/// Standard full-screen slide scaffold: centers its content vertically,
/// consistent horizontal padding, safe-area-aware. Every slide view should
/// wrap its content in this rather than laying out its own VStack/padding.
struct WrappedSlideScaffold<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 18) {
                content()
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A labeled stat row used by breakdown-style slides (long-shift thresholds,
/// weekend/weekday split) — a value on the left/top, its label below/beside.
struct WrappedStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(WrappedPalette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(WrappedPalette.primaryText)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
