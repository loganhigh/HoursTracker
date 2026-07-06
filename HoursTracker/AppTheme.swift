import SwiftUI

// MARK: - App Theme (vibrant violet/indigo bridge over SemanticColors)

enum AppTheme {

    /// Resolve semantic colors for current color scheme.
    static func colors(for colorScheme: ColorScheme) -> SemanticColors {
        colorScheme == .dark ? .dark : .light
    }

    enum Colors {
        private static var c: SemanticColors { ThemeProvider.current }

        // Backgrounds
        static var bg: Color { c.background }
        static var surface: Color { c.surface }
        static var card: Color { c.card }
        static var card2: Color { c.cardSecondary }
        static var stroke: Color { c.border }
        static var strokeStrong: Color { Color.white.opacity(0.16) }

        // Text
        static var text: Color { c.textPrimary }
        static var subtext: Color { c.textSecondary }
        static var faint: Color { c.textTertiary }

        // Accent (driven by user's prestige rank — see PrestigeTheme)
        static var accent: Color { c.accent }
        static var accent2: Color { c.accent2 }
        static var brand: Color { accent }
        static var brandSoft: Color { c.accentMuted }
        static var glow: Color { c.accent.opacity(0.45) }
        static var accentHighlight: Color { c.accentHighlight }

        // Utility
        static var success: Color { c.success }
        static var warning: Color { c.warning }
        static var danger: Color { c.danger }

        // Vibrant gradients — recolored per prestige rank
        static var accentGradient: LinearGradient {
            LinearGradient(
                colors: c.accentGradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        static var cardGradient = LinearGradient(
            colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static var chartFillGradient: LinearGradient {
            let stops = c.accentGradientColors
            let top = stops.first ?? c.accent
            let mid = stops.count > 1 ? stops[1] : c.accent2
            return LinearGradient(
                colors: [top.opacity(0.35), mid.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        static var chartBarGradient: LinearGradient {
            LinearGradient(
                colors: c.chartBarColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    enum Spacing {
        static let xs: CGFloat = AppDesignSystem.Spacing.xs
        static let sm: CGFloat = AppDesignSystem.Spacing.sm
        static let md: CGFloat = AppDesignSystem.Spacing.md
        static let lg: CGFloat = AppDesignSystem.Spacing.lg
        static let xl: CGFloat = AppDesignSystem.Spacing.xl
    }

    enum Radius {
        static let sm: CGFloat = AppDesignSystem.Radius.sm
        static let md: CGFloat = AppDesignSystem.Radius.md
        static let lg: CGFloat = AppDesignSystem.Radius.lg
        static let xl: CGFloat = AppDesignSystem.Radius.xl
    }

    /// Formats hours for display: whole numbers without decimal (e.g. "10h"), fractional with decimal (e.g. "5.5h").
    enum Format {
        static func hours(_ value: Double, suffix: String = "h") -> String {
            guard value.isFinite else { return "0\(suffix)" }
            let clamped = max(0, value)
            if clamped.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(clamped))\(suffix)"
            }
            var s = String(format: "%.2f", clamped)
            while s.hasSuffix("0") && s.contains(".") { s = String(s.dropLast()) }
            if s.hasSuffix(".") { s = String(s.dropLast()) }
            return s + suffix
        }
    }

    enum Typography {
        static let h1 = Font.system(size: 34, weight: .bold, design: .rounded)
        static let h2 = Font.system(size: 24, weight: .bold, design: .rounded)
        static let h3 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular)
        static let sub = Font.system(size: 16, weight: .regular)
        static let callout = Font.system(size: 15, weight: .regular)
        static let foot = Font.system(size: 13, weight: .regular)
    }
}
