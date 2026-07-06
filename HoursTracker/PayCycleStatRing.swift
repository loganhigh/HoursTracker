import SwiftUI

/// Circular progress ring used on the pay-cycle hero card — tinted by prestige rank.
struct PayCycleStatRing: View {
    enum Size {
        case regular
        case compact

        var diameter: CGFloat {
            switch self {
            case .regular: return 130
            case .compact: return 92
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .regular: return 8
            case .compact: return 6
            }
        }

        var valueFontSize: CGFloat {
            switch self {
            case .regular: return 28
            case .compact: return 22
            }
        }

        var captionFontSize: CGFloat {
            switch self {
            case .regular: return 11
            case .compact: return 10
            }
        }

        /// Usable width inside the ring stroke for the value label.
        var valueMaxWidth: CGFloat {
            diameter - (lineWidth * 2) - 14
        }

        func valueFontSize(for value: String) -> CGFloat {
            let base = valueFontSize
            switch value.count {
            case ...3: return base
            case 4: return base * 0.88
            case 5: return base * 0.78
            case 6: return base * 0.70
            default: return base * 0.62
            }
        }
    }

    let progress: Double
    let value: String
    let caption: String
    let ringColors: [Color]
    var size: Size = .regular
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Colors.stroke, lineWidth: size.lineWidth)
                .frame(width: size.diameter, height: size.diameter)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringStroke,
                    style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
                )
                .frame(width: size.diameter, height: size.diameter)
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColors.first?.opacity(0.30) ?? .clear, radius: size == .compact ? 4 : 6)

            VStack(spacing: 2) {
                Text(value)
                    .font(AppDesignSystem.Typography.heroNumerals(size: size.valueFontSize(for: value), weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .frame(maxWidth: size.valueMaxWidth)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: value)

                Text(caption)
                    .font(.system(size: size.captionFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: size.valueMaxWidth)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ringStroke: some ShapeStyle {
        let colors = ringColors.isEmpty
            ? [AppTheme.Colors.accent]
            : ringColors
        return AngularGradient(
            colors: colors + [colors[0]],
            center: .center
        )
    }
}

/// Shared prestige-tinted styling for the pay-cycle summary card shell.
enum PayCycleCardStyle {
    static func cardBackground(theme: SemanticColors) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                .fill(theme.card)
            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.accent.opacity(0.14),
                            theme.accent2.opacity(0.07),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    static func cardBorder(theme: SemanticColors) -> some View {
        RoundedRectangle(cornerRadius: AppDesignSystem.Radius.lg, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        theme.accent.opacity(0.52),
                        theme.accent2.opacity(0.38),
                        theme.accentHighlight.opacity(0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
    }

    static func compactCardBackground(theme: SemanticColors) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                .fill(theme.card)
            RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.accent.opacity(0.10),
                            theme.accent2.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    static func compactCardBorder(theme: SemanticColors) -> some View {
        RoundedRectangle(cornerRadius: AppDesignSystem.Radius.md, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        theme.accent.opacity(0.40),
                        theme.accent2.opacity(0.28),
                        theme.accentHighlight.opacity(0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
