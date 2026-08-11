import SwiftUI

// MARK: - Level badge
//
// The single visual identity for a level emblem: a metallic hexagon tinted by
// the prestige tier, with the level number (or any content) centered. Used by
// the My Level hero and by the level-up celebration, so the badge the user
// levels up INTO is the badge they see on their profile afterwards.

struct LevelBadgeView<Content: View>: View {
    let tier: PrestigeTheme.Tier
    /// Diameter-ish width; height follows the hexagon's 150:166 proportions.
    var width: CGFloat = 150
    /// Glow strength 0…1. The My Level screen runs 0 (Home owns the app's
    /// resting glow); the celebration drives this up during the energy build.
    var glow: Double = 0
    @ViewBuilder var content: Content

    private var height: CGFloat { width * (166.0 / 150.0) }
    private var corner: CGFloat { width * (14.0 / 150.0) }

    var body: some View {
        ZStack {
            // Metallic face: a vertical brushed-metal ramp under a tier tint.
            LevelHexagon(cornerRadius: corner)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(
                    LevelHexagon(cornerRadius: corner)
                        .fill(tier.primary.opacity(0.14))
                )

            // Bevel: bright top edge, dark bottom edge, tier-colored rim.
            LevelHexagon(cornerRadius: corner)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            tier.primary.opacity(0.55),
                            Color.black.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(1.5, width / 75)
                )

            LevelHexagon(cornerRadius: corner)
                .stroke(tier.primary.opacity(0.45), lineWidth: 1)
                .padding(width / 18)

            content
        }
        .frame(width: width, height: height)
        .shadow(color: tier.primary.opacity(0.55 * glow), radius: 24 * glow)
        .shadow(color: tier.highlight.opacity(0.35 * glow), radius: 60 * glow)
    }
}

/// The standard interior: eyebrow + level number.
struct LevelBadgeNumber: View {
    let level: Int
    let tier: PrestigeTheme.Tier
    var eyebrow: String = "Level"

    var body: some View {
        VStack(spacing: 0) {
            Text(eyebrow)
                .appText(.eyebrow)
                .foregroundStyle(tier.primary)
            Text("\(level)")
                .font(AppTypography.heroNumber)
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, AppSpacing.md)
                .contentTransition(.numericText(value: Double(level)))
        }
    }
}
