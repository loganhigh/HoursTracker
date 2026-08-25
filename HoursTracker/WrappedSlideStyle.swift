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

/// A slow, static radial wash behind every slide. Static on purpose — a
/// continuously animating background is exactly the kind of always-on
/// compositing that drains battery for very little perceived polish. Each
/// slide varies the `tint` so slides feel distinct while staying one family.
struct WrappedBackdrop: View {
    var tint: Color = WrappedPalette.accent

    var body: some View {
        ZStack {
            WrappedPalette.background

            RadialGradient(
                colors: [tint.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 520
            )

            RadialGradient(
                colors: [tint.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
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
