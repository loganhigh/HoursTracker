import SwiftUI

// MARK: - Design System (vibrant dark, fun + premium feel)

enum AppDesignSystem {

    // DEPRECATED: use AppSpacing (DesignTokens.swift) — the canonical 4/8/12/16/20/24/32
    // scale that matches real call-site usage. Do not use in new code; kept until screens migrate.
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

    // DEPRECATED: use AppTypography (DesignTokens.swift) — the ONE Dynamic Type-relative
    // scale. This fixed-size scale conflicts with AppTheme.Typography (e.g. callout 14 vs 15);
    // do not use in new code. Kept until screens migrate.
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

    /// Scheme-dynamic color: wraps a `UIColor` trait provider so the color
    /// resolves per-render from the view's current appearance. This is what
    /// lets `AppTheme.Colors` / `AppColors` tokens stay correct when the
    /// scheme flips, even in views that never re-evaluate their body.
    static func schemeAdaptive(dark: Color, light: Color) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Adaptive palette (dynamic dark/light)

extension SemanticColors {
    /// The palette the app actually runs on: every scheme-dependent slot is a
    /// dynamic color built from `.dark` / `.light`, so tokens resolve at
    /// render time from the current trait collection. Accent slots start as
    /// dynamic too, but `AdaptiveThemeModifier` replaces them with the user's
    /// prestige tier (identical in both schemes).
    static let adaptive = SemanticColors(
        background: .schemeAdaptive(dark: dark.background, light: light.background),
        surface: .schemeAdaptive(dark: dark.surface, light: light.surface),
        card: .schemeAdaptive(dark: dark.card, light: light.card),
        cardSecondary: .schemeAdaptive(dark: dark.cardSecondary, light: light.cardSecondary),
        textPrimary: .schemeAdaptive(dark: dark.textPrimary, light: light.textPrimary),
        textSecondary: .schemeAdaptive(dark: dark.textSecondary, light: light.textSecondary),
        textTertiary: .schemeAdaptive(dark: dark.textTertiary, light: light.textTertiary),
        accent: .schemeAdaptive(dark: dark.accent, light: light.accent),
        accent2: .schemeAdaptive(dark: dark.accent2, light: light.accent2),
        accentHighlight: .schemeAdaptive(dark: dark.accentHighlight, light: light.accentHighlight),
        accentGradientColors: dark.accentGradientColors,
        chartBarColors: dark.chartBarColors,
        accentMuted: .schemeAdaptive(dark: dark.accentMuted, light: light.accentMuted),
        border: .schemeAdaptive(dark: dark.border, light: light.border),
        success: .schemeAdaptive(dark: dark.success, light: light.success),
        warning: .schemeAdaptive(dark: dark.warning, light: light.warning),
        danger: .schemeAdaptive(dark: dark.danger, light: light.danger)
    )
}

// MARK: - Appearance preference (System / Light / Dark)

/// User-facing appearance setting, stored in `@AppStorage(AppAppearance.storageKey)`
/// and applied via `.preferredColorScheme` at the app root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance_mode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` follows the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Environment Key

private struct SemanticColorsKey: EnvironmentKey {
    static var defaultValue: SemanticColors = .adaptive
}

extension EnvironmentValues {
    var semanticColors: SemanticColors {
        get { self[SemanticColorsKey.self] }
        set { self[SemanticColorsKey.self] = newValue }
    }
}

/// Updates ThemeProvider and injects semantic colors. When a `prestige` value
/// is provided, the accent color (and all derived gradients) are overridden to
/// match the user's prestige rank.
///
/// Scheme handling: the base palette is `SemanticColors.adaptive`, whose
/// scheme-dependent slots are dynamic `UIColor` trait providers. That means
/// `ThemeProvider.current` never needs restamping on a scheme flip — every
/// token resolves per-render from the view's own trait collection, so the old
/// "mutable global written from body" hazard only applies to the prestige
/// accent (which IS re-stamped here whenever prestige changes and is identical
/// in both schemes).
struct AdaptiveThemeModifier: ViewModifier {
    let prestige: Int

    func body(content: Content) -> some View {
        let tier = PrestigeTheme.tier(for: prestige)
        let colors = SemanticColors.adaptive.applying(prestige: tier)
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
