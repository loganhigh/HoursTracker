import SwiftUI

// MARK: - Owl placements
//
// The three ways Otto appears on a screen (only one per screen):
// - Hero: a plain `OwlView(pose:size: .hero)` (or AppEmptyState's `owl:`).
// - Companion: `OwlPerch` puts Otto and a speech bubble on the top edge of
//   the screen's hero card.
// - Peek: `.owlPeek(_:)` sets a small Otto on the top edge of the first card.

/// Otto plus one line of speech, centered as a group to match the
/// centered-headline rule.
struct OwlCompanionHeader: View {
    let pose: OwlPose
    let line: String
    var size: OwlView.Size = .companion
    var scarfTint: Color? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xxs) {
            OwlView(pose: pose, size: size, scarfTint: scarfTint)
            OwlSpeechBubble(text: line, tail: .leading)
                .frame(maxWidth: 260, alignment: .leading)
                .accessibilityLabel(line)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Puts the companion header on the top edge of `content` (the hero card):
/// Otto's feet overlap the card by a few points so he reads as sitting on it.
struct OwlPerch<Content: View>: View {
    let pose: OwlPose
    let line: String
    var size: OwlView.Size = .companion
    var scarfTint: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: -OwlPerchMetrics.feetOverlap) {
            OwlCompanionHeader(pose: pose, line: line, size: size, scarfTint: scarfTint)
                .zIndex(1)
            content()
        }
    }
}

/// The owl standing beside `content` (a photo circle or a badge), pointing at
/// it. The peek pose needs a flat edge to grip, so round or scalloped things
/// get this instead. He hangs off the leading side without taking layout
/// space, so `content` stays centred over a centred title.
struct OwlPointingAt<Content: View>: View {
    var size: OwlView.Size = .header
    var scarfTint: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .bottomLeading) {
                OwlView(pose: .point, size: size, scarfTint: scarfTint)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in d[.trailing] + AppSpacing.xxs }
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// The app's standard placement: the owl standing centred on this card's
    /// top edge at header size, no speech bubble, with the room he needs
    /// above the card already added.
    func owlStanding(_ pose: OwlPose, scarfTint: Color? = nil) -> some View {
        owlPeek(pose, size: .header, alignment: .center, scarfTint: scarfTint)
            .padding(.top, OwlPerchMetrics.headerClearance)
    }
}

enum OwlPerchMetrics {
    /// How far Otto's feet overlap the card under him.
    static let feetOverlap: CGFloat = 8
    /// Room above a card for a header-size owl standing on it.
    static let headerClearance: CGFloat = OwlView.Size.header.height - feetOverlap / 2
    /// Room to leave above a card that has a peeking owl, so the owl doesn't
    /// collide with the header above it.
    static let peekClearance: CGFloat = OwlView.Size.peek.height - feetOverlap / 2
}

private struct OwlPeekModifier: ViewModifier {
    let pose: OwlPose
    let size: OwlView.Size
    let alignment: HorizontalAlignment
    let scarfTint: Color?

    func body(content: Content) -> some View {
        content.overlay(alignment: Alignment(horizontal: alignment, vertical: .top)) {
            // Animated like everywhere else (blink, wing, peekaboo…); taps
            // still go to the card underneath.
            OwlView(pose: pose, size: size, scarfTint: scarfTint)
                .padding(.horizontal, AppSpacing.lg)
                .alignmentGuide(.top) { d in d[.bottom] - OwlPerchMetrics.feetOverlap / 2 }
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Otto standing on (or peeking over) this card's top edge. Leave the owl's
    /// height (`OwlPerchMetrics.peekClearance` at the default size) of space
    /// above the card.
    func owlPeek(
        _ pose: OwlPose = .peek,
        size: OwlView.Size = .peek,
        alignment: HorizontalAlignment = .trailing,
        scarfTint: Color? = nil
    ) -> some View {
        modifier(OwlPeekModifier(pose: pose, size: size, alignment: alignment, scarfTint: scarfTint))
    }
}

#Preview("Placements") {
    ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            OwlPerch(pose: .wave, line: "8.5h today. Nice shift.") {
                VStack(spacing: AppSpacing.xxs) {
                    Text("Today").appText(.eyebrow).foregroundStyle(AppColors.faint)
                    Text("8.5h").appText(.heroNumber).foregroundStyle(AppColors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.xl)
                .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }

            VStack(spacing: 0) {
                ForEach(["Hourly wage", "Payday", "Week starts"], id: \.self) { row in
                    Text(row)
                        .appText(.body)
                        .foregroundStyle(AppColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                }
            }
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .owlPeek()
            .padding(.top, OwlPerchMetrics.peekClearance)

            AppEmptyState(owl: .clipboard, title: "No cheques yet", message: "Log a shift and your pay periods will show up here.")
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.bg)
    .preferredColorScheme(.dark)
}
