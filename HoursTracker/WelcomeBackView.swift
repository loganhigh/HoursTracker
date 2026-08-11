import SwiftUI

// MARK: - Welcome Back screen
//
// Shown once per cold launch, right after the startup splash and before Home
// appears: a full-screen "Welcome back, {name}!" that auto-dismisses into the
// app. Not shown on background/foreground resumes or sign-out/sign-in resets
// within the same process — only on an actual fresh start.
//
// The greeting uses the vertical-cut reveal below: heavy, tightly-tracked type
// where each glyph springs up out of a hard horizontal cut, staggered outward
// from the middle character.

struct WelcomeBackView: View {
    @AppStorage("profile_display_name") private var storedDisplayName: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called once the greeting has finished its beat on screen.
    var onFinished: () -> Void

    @State private var logoVisible = false
    @State private var isRevealed = false
    @State private var isExiting = false

    private var name: String {
        let trimmed = storedDisplayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : trimmed
    }

    /// Deliberate line breaks rather than wrapping: a per-character reveal has
    /// to lay its glyphs out itself, so it can't hand off to Text's wrapping.
    /// Splitting the name onto its own line also lets long names shrink without
    /// dragging "Welcome back," down with them.
    /// Uppercased whole rather than per character, so locale-specific mappings
    /// that grow a letter (ß → SS) come out right.
    private var lines: [String] {
        let raw = name.isEmpty ? ["Welcome back!"] : ["Welcome back,", "\(name)!"]
        return raw.map { $0.uppercased() }
    }

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                // The app logo, matching the onboarding welcome — the generic
                // SF hourglass here read as a system placeholder rather than
                // Hour Tracker.
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(logoVisible ? 1 : 0.92)
                    .accessibilityHidden(true)

                // One size is chosen for the whole greeting so both lines match;
                // the first candidate that fits the available width wins.
                ViewThatFits(in: .horizontal) {
                    greeting(fontSize: 40)
                    greeting(fontSize: 34)
                    greeting(fontSize: 28)
                    greeting(fontSize: 23)
                    greeting(fontSize: 19)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .opacity(isExiting ? 0 : 1)
            .scaleEffect(isExiting ? 0.97 : 1)
        }
        .onAppear { play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plainGreeting)
    }

    private func greeting(fontSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                VerticalCutRevealText(
                    text: line,
                    fontSize: fontSize,
                    isRevealed: isRevealed,
                    reduceMotion: reduceMotion,
                    // A lead-in per line, so the greeting reads top-down
                    // instead of both lines blooming at once.
                    startDelay: Double(index) * 0.25
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Flat text for VoiceOver — the per-character split would otherwise be
    /// read out one letter at a time.
    private var plainGreeting: String {
        name.isEmpty ? "Welcome back!" : "Welcome back, \(name)!"
    }

    private func play() {
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            logoVisible = true
        }

        // Kicked off a frame later so the characters animate from their hidden
        // state rather than being laid out already revealed, and so the logo
        // lands just ahead of the type.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isRevealed = true
        }

        // One quiet beat on screen, then hand off to the app. The stagger plus
        // its settle runs about 1.6s, so this leaves roughly a second of the
        // greeting sitting still before it hands off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if reduceMotion {
                onFinished()
            } else {
                withAnimation(AppMotion.Spring.smooth) { isExiting = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onFinished() }
            }
        }
    }
}

// MARK: - Vertical cut reveal

/// Text that reveals one glyph at a time, each springing up out of a hard
/// horizontal cut.
///
/// A SwiftUI port of the web `VerticalCutReveal` component: every character sits
/// in its own clip box, starts a full line-height below it, and springs into
/// place with a delay that grows outward from the middle character
/// (`staggerFrom="center"`). Because every glyph on a line shares one baseline
/// and one box height, clipping the line as a whole is equivalent to the web
/// version's per-character `overflow: hidden` — and it costs one clip instead of
/// one per character.
///
/// The spring is `interpolatingSpring(stiffness:damping:)`, which takes the same
/// two numbers as the original's `{ type: "spring", stiffness: 300, damping: 20 }`.
struct VerticalCutRevealText: View {
    let text: String
    let fontSize: CGFloat
    let isRevealed: Bool
    let reduceMotion: Bool

    /// Seconds added per character step away from the middle.
    var staggerDuration: Double = 0.1
    /// Delay before this line's own stagger begins.
    var startDelay: Double = 0
    /// Negative to match the original's `tracking-tighter`. Applied as HStack
    /// spacing, since per-character `Text` runs have no following glyph for
    /// SwiftUI's own tracking to pull against.
    var tracking: CGFloat = -1

    /// The clip box, and the distance each glyph travels.
    ///
    /// Deliberately tighter than the font's own line box (~1.2× the point size,
    /// most of the slack being descender space). The greeting is set in caps, so
    /// nothing reaches below the baseline and the cut can sit close to the
    /// letterforms — which is what makes it read as a cut rather than as type
    /// bouncing in open space.
    private var lineHeight: CGFloat { fontSize * 1.1 }

    private var characters: [(offset: Int, element: Character)] {
        Array(text.enumerated())
    }

    var body: some View {
        HStack(spacing: tracking) {
            ForEach(characters, id: \.offset) { index, character in
                // A literal space would collapse at the edges of the run; a
                // non-breaking space holds its width.
                Text(character == " " ? "\u{00A0}" : String(character))
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .offset(y: hiddenOffset)
                    .animation(animation(forCharacterAt: index), value: isRevealed)
            }
        }
        .frame(height: lineHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    private var hiddenOffset: CGFloat {
        // Reduce Motion keeps the type in place and lets the screen's own fade
        // carry it in — no travel, no stagger.
        if reduceMotion { return 0 }
        return isRevealed ? 0 : lineHeight
    }

    private func animation(forCharacterAt index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let center = Double(characters.count - 1) / 2
        let stepsFromCenter = abs(Double(index) - center)
        // Slower and looser than the original's stiffness 300 / damping 20,
        // which crossed the cut too quickly to be seen. Same underdamped feel —
        // the glyphs still overshoot slightly before settling.
        return .spring(response: 0.8, dampingFraction: 0.6)
            .delay(startDelay + stepsFromCenter * staggerDuration)
    }
}
