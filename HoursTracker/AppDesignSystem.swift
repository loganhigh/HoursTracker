import SwiftUI

// MARK: - Design System (vibrant dark, fun + premium feel)

enum AppDesignSystem {

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 22
    }

    enum Shadow {
        static let card = (color: Color.black.opacity(0.18), radius: CGFloat(10), x: CGFloat(0), y: CGFloat(3))
        static let cardLight = (color: Color.black.opacity(0.08), radius: CGFloat(6), x: CGFloat(0), y: CGFloat(2))
    }

    /// Shared animation presets — use with `AppMotion.animation(_:reduceMotion:)`.
    enum Motion {
        static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let springSmooth = Animation.spring(response: 0.42, dampingFraction: 0.88)
    }

    enum Typography {
        static let largeTitle = Font.system(size: 32, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular)
        static let callout = Font.system(size: 14, weight: .regular)
        static let subheadline = Font.system(size: 13, weight: .regular)
        static let footnote = Font.system(size: 12, weight: .regular)

        /// Game-style section label (uppercase rounded, tracked).
        static let sectionLabel = Font.system(size: 13, weight: .bold, design: .rounded)

        /// Fun, rounded numerals for hero hours / money (large, with monospaced digits).
        static func heroNumerals(size: CGFloat, weight: Font.Weight = .bold) -> Font {
            Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
    }
}

// MARK: - Semantic Colors (Adaptive Dark/Light) — vibrant violet/indigo

struct SemanticColors {
    let background: Color
    let surface: Color
    let card: Color
    let cardSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    var accent: Color
    var accent2: Color
    var accentHighlight: Color
    var accentGradientColors: [Color]
    var chartBarColors: [Color]
    var accentMuted: Color
    let border: Color
    let success: Color
    let warning: Color
    let danger: Color
}

extension SemanticColors {
    static let dark = SemanticColors(
        background: Color(hex: 0x0F0F14),
        surface: Color(hex: 0x16161D),
        card: Color(hex: 0x1A1A24),
        cardSecondary: Color(hex: 0x1E1E2A),
        textPrimary: Color.white,
        textSecondary: Color.white.opacity(0.75),
        textTertiary: Color.white.opacity(0.5),
        accent: Color(hex: 0x8B5CF6),
        accent2: Color(hex: 0x6366F1),
        accentHighlight: Color(hex: 0x3B82F6),
        accentGradientColors: [Color(hex: 0x7C3AED), Color(hex: 0x6366F1), Color(hex: 0x3B82F6)],
        chartBarColors: [Color(hex: 0x7C3AED), Color(hex: 0x6366F1)],
        accentMuted: Color(hex: 0x8B5CF6).opacity(0.25),
        border: Color.white.opacity(0.08),
        success: Color(hex: 0x34D399),
        warning: Color(hex: 0xFBBF24),
        danger: Color(hex: 0xFB7185)
    )

    static let light = SemanticColors(
        background: Color(hex: 0xF5F5F7),
        surface: Color.white,
        card: Color.white,
        cardSecondary: Color(hex: 0xF9F9FB),
        textPrimary: Color(hex: 0x1A1A1A),
        textSecondary: Color(hex: 0x4A4A4A),
        textTertiary: Color(hex: 0x6E6E73),
        accent: Color(hex: 0x7C3AED),
        accent2: Color(hex: 0x6366F1),
        accentHighlight: Color(hex: 0x3B82F6),
        accentGradientColors: [Color(hex: 0x7C3AED), Color(hex: 0x6366F1), Color(hex: 0x3B82F6)],
        chartBarColors: [Color(hex: 0x7C3AED), Color(hex: 0x6366F1)],
        accentMuted: Color(hex: 0x7C3AED).opacity(0.18),
        border: Color.black.opacity(0.1),
        success: Color(hex: 0x059669),
        warning: Color(hex: 0xD97706),
        danger: Color(hex: 0xDC2626)
    )

    /// Returns a copy with all accent-related colors replaced by the given prestige tier.
    /// Used by `AdaptiveThemeModifier` to make the entire UI follow the user's prestige rank.
    func applying(prestige tier: PrestigeTheme.Tier) -> SemanticColors {
        var copy = self
        copy.accent = tier.primary
        copy.accent2 = tier.accent2
        copy.accentHighlight = tier.highlight
        copy.accentGradientColors = tier.gradient
        copy.chartBarColors = tier.chartBar
        copy.accentMuted = tier.primary.opacity(0.25)
        return copy
    }
}

// MARK: - Color Extension (hex init)

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Environment Key

private struct SemanticColorsKey: EnvironmentKey {
    static var defaultValue: SemanticColors = .dark
}

extension EnvironmentValues {
    var semanticColors: SemanticColors {
        get { self[SemanticColorsKey.self] }
        set { self[SemanticColorsKey.self] = newValue }
    }
}

/// Updates ThemeProvider and injects semantic colors based on system color scheme.
/// When a `prestige` value is provided, the accent color (and all derived gradients)
/// are overridden to match the user's prestige rank.
struct AdaptiveThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let prestige: Int

    func body(content: Content) -> some View {
        let base = colorScheme == .dark ? SemanticColors.dark : SemanticColors.light
        let tier = PrestigeTheme.tier(for: prestige)
        let colors = base.applying(prestige: tier)
        ThemeProvider.current = colors
        return content
            .environment(\.semanticColors, colors)
    }
}

extension View {
    /// Applies the adaptive theme with an optional prestige override.
    func adaptiveTheme(prestige: Int = 0) -> some View {
        modifier(AdaptiveThemeModifier(prestige: prestige))
    }
}
