import SwiftUI

// MARK: - Legend Status name + avatar marks (P11–P20)
//
// Anyone at Legend Status (P11+, `Tier.isLegend`) is marked wherever their
// name or avatar shows: the name is filled with a fixed gradient of their
// tier's colours (never animated, so it is always fully legible), and the
// avatar gets a tier-gradient ring. P20 (G.O.A.T.) adds a soft glow to the
// name and a thicker rotating ring.
//
// P0–P10 render EXACTLY as before — a plain `Text` in the caller's style and
// the avatar untouched — so nothing changes for everyone else.
// Reduce Motion: the P20 ring holds still.

/// A person's name, marked for Ascended ranks. Layout modifiers the caller
/// applies from outside (`lineLimit`, `minimumScaleFactor`,
/// `multilineTextAlignment`, `truncationMode`) flow through the environment
/// to both the visible text and its gradient mask, so truncation and scaling
/// behave exactly as on a plain `Text`.
struct PrestigeNameText: View {
    let name: String
    let prestige: Int
    /// Nil leaves the font to the caller (e.g. `.appText(.title)` outside).
    var font: Font? = nil
    /// The fill used for P0–P10 — pass what the call site used before.
    var style: AnyShapeStyle = AnyShapeStyle(AppColors.text)

    @ObservedObject private var supporters = SupporterRegistry.shared

    private var tier: PrestigeTheme.Tier { PrestigeTheme.tier(for: prestige) }

    private var text: Text {
        if let font { return Text(name).font(font) }
        return Text(name)
    }

    var body: some View {
        let isOwner = DeveloperConfig.isOwnerName(name)
        let isSupporter = !isOwner && supporters.contains(name)
        Group {
            if isOwner {
                // Gold, so the sweep reads (white light over white text is
                // invisible) and the owner stands apart from any rank colour.
                text.foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.gold, AppColors.goldDeep, AppColors.gold],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else if tier.isLegend {
                AscendedNameFill(text: text, tier: tier)
            } else if isSupporter {
                // Tinted rather than the plain name colour, so the sweep of
                // light has something to show against.
                text.foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accentHighlight, AppColors.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else {
                text.foregroundStyle(style)
            }
        }
        .modifier(OwnerNameShimmer(text: text, isOwner: isOwner || isSupporter))
    }
}

/// The app owner's name (@logan) is gold, and supporters' names tinted, with a
/// band of light sweeping across it every few seconds. The sweep is drawn OVER the normal fill and masked to
/// the glyphs, so the name itself is always fully visible. Its position comes
/// straight from the clock (no restartable state animation that could stack
/// when a row scrolls back into view). Reduce Motion: no sweep.
private struct OwnerNameShimmer: ViewModifier {
    let text: Text
    let isOwner: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One sweep plus a pause, in seconds.
    private let cycle: Double = 3.2
    /// Portion of the cycle the band is moving.
    private let sweepFraction: Double = 0.45

    func body(content: Content) -> some View {
        if isOwner && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: cycle) / cycle
                    let progress = min(1, t / sweepFraction)
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        let band = max(24, w * 0.35)
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.85), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band, height: geo.size.height)
                        .offset(x: -band + (w + band) * progress)
                        .opacity(t < sweepFraction ? 1 : 0)
                    }
                    .mask(text)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

private struct AscendedNameFill: View {
    let text: Text
    let tier: PrestigeTheme.Tier

    /// The tier's colours across the name.
    private var period: [Color] {
        tier.isApex
            ? [tier.highlight, tier.primary, tier.accent2, tier.primary]
            : [tier.primary, tier.highlight, tier.primary, tier.accent2]
    }

    private var staticFill: LinearGradient {
        LinearGradient(colors: period + [period[0]], startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        // A fixed gradient: the name is always fully legible. The avatar
        // ring, badge shimmer and P20 glow already carry the motion.
        text
            .foregroundStyle(staticFill)
            .shadow(color: tier.isApex ? tier.primary.opacity(0.55) : .clear, radius: tier.isApex ? 6 : 0)
    }
}

// MARK: - Avatar ring

private struct AscendedAvatarRing: ViewModifier {
    let tier: PrestigeTheme.Tier
    /// Diameter of the view being ringed — scales the stroke.
    let diameter: CGFloat
    /// How far outside the view's edge the ring's centre line sits.
    let inset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    private var lineWidth: CGFloat {
        tier.isApex ? max(2.5, diameter * 0.06) : max(1.5, diameter * 0.035)
    }

    private var colors: [Color] {
        [tier.highlight, tier.primary, tier.accent2, tier.primary, tier.highlight]
    }

    func body(content: Content) -> some View {
        if tier.isLegend {
            content.overlay {
                ring
                    .padding(-inset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var ring: some View {
        if tier.isApex {
            Circle()
                .stroke(AngularGradient(colors: colors, center: .center), lineWidth: lineWidth)
                .rotationEffect(.degrees(angle))
                .shadow(color: tier.primary.opacity(0.7), radius: lineWidth * 1.4)
                .onAppear {
                    guard !reduceMotion else { return }
                    angle = 0
                    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                }
                .onDisappear {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { angle = 0 }
                }
        } else {
            Circle()
                .stroke(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: lineWidth
                )
        }
    }
}

extension View {
    /// Tier-gradient ring for Ascended (P11+) avatars; a no-op for P0–P10.
    /// `diameter` is the avatar's size; `inset` pushes the ring outward from
    /// the view's edge (0 = centred on the edge).
    func ascendedAvatarRing(prestige: Int, diameter: CGFloat, inset: CGFloat = 0) -> some View {
        modifier(AscendedAvatarRing(
            tier: PrestigeTheme.tier(for: prestige),
            diameter: diameter,
            inset: inset
        ))
    }
}
