import SwiftUI

// MARK: - Design Tokens (canonical layer — Phase 1 of the UI redesign)
//
// `AppColors` / `AppTypography` / `AppSpacing` / `AppRadius` / `AppShadow`
// are the canonical tokens for all NEW and migrated UI. They sit on top of
// the existing prestige-aware theme (AppTheme.Colors → ThemeProvider →
// PrestigeTheme), so accent-derived colors keep retinting with the user's
// prestige rank. Semantic colors only — no raw hex outside this file and
// PrestigeTheme.swift.

// MARK: - Colors

/// Canonical semantic color tokens. Everything accent-derived stays
/// prestige-aware because it forwards to `AppTheme.Colors` (which reads
/// `ThemeProvider.current`, updated by `AdaptiveThemeModifier`).
enum AppColors {

    // Backgrounds & surfaces
    static var bg: Color { AppTheme.Colors.bg }
    static var surface: Color { AppTheme.Colors.surface }
    static var card: Color { AppTheme.Colors.card }
    static var card2: Color { AppTheme.Colors.card2 }
    static var stroke: Color { AppTheme.Colors.stroke }
    static var strokeStrong: Color { AppTheme.Colors.strokeStrong }

    // Text
    static var text: Color { AppTheme.Colors.text }
    static var subtext: Color { AppTheme.Colors.subtext }
    static var faint: Color { AppTheme.Colors.faint }
    /// Text placed on top of accent-gradient fills (buttons, chips, earned
    /// badges). Tracks the active prestige tier's readable-text color — a
    /// fixed white washed out on light tiers like Silver and Gold.
    static var textOnAccent: Color { AppTheme.Colors.textOnAccent }

    // Accent (prestige-driven)
    static var accent: Color { AppTheme.Colors.accent }
    static var accent2: Color { AppTheme.Colors.accent2 }
    static var accentHighlight: Color { AppTheme.Colors.accentHighlight }
    static var accentMuted: Color { AppTheme.Colors.brandSoft }
    static var glow: Color { AppTheme.Colors.glow }

    // Status
    static var positive: Color { AppTheme.Colors.success }
    static var negative: Color { AppTheme.Colors.danger }
    static var warning: Color { AppTheme.Colors.warning }

    // Celebration (payday / prestige gold family — intentionally fixed,
    // not prestige-retinted; used ~17x as raw hex before this token).
    static let gold = Color(hex: 0xFFD700)
    static let goldDeep = Color(hex: 0xFF9500)
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [gold, goldDeep], startPoint: .leading, endPoint: .trailing)
    }

    // Podium metals (leaderboard rank pips — fixed, not prestige-retinted).
    static let rankGold = Color(red: 0.98, green: 0.79, blue: 0.28)
    static let rankSilver = Color(red: 0.75, green: 0.79, blue: 0.85)
    static let rankBronze = Color(red: 0.83, green: 0.55, blue: 0.35)

    /// Streak flame — fixed ember orange (matches the flame icon everywhere).
    static let streak = Color(hex: 0xF97316)

    // Quick-action tints (semantic: off day = rest/red, holiday = away/green).
    static let offDayAction = Color(red: 0.94, green: 0.30, blue: 0.34)
    static let holidayAction = Color(red: 0.34, green: 0.74, blue: 0.46)

    // Overlay tints (scrims behind sheets / photo viewers)
    static var overlay: Color { Color.black.opacity(0.45) }
    static var overlaySubtle: Color { Color.black.opacity(0.2) }

    // Gradients (prestige-driven)
    static var accentGradient: LinearGradient { AppTheme.Colors.accentGradient }
    static var chartFillGradient: LinearGradient { AppTheme.Colors.chartFillGradient }
    static var chartBarGradient: LinearGradient { AppTheme.Colors.chartBarGradient }
}

// MARK: - Typography

/// ONE Dynamic Type–relative scale. Text-style based (not fixed sizes) so
/// everything scales with the user's accessibility settings.
enum AppTypography {
    /// Hero ledger numerals (hours / money). Rounded + monospaced digits.
    static let heroNumber = Font.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()
    /// Screen / card title.
    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    /// Row & section headline.
    static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    /// Body copy.
    static let body = Font.system(.body)
    /// Secondary copy.
    static let subheadline = Font.system(.subheadline, design: .default, weight: .medium)
    /// Caption / metadata.
    static let caption = Font.system(.caption, design: .default, weight: .medium)
    /// Centered small-caps section eyebrow — pair with `.tracking(AppTypography.eyebrowTracking)`
    /// (or just use `.appText(.eyebrow)` / `SectionEyebrow`).
    static let eyebrow = Font.system(.caption2, design: .rounded, weight: .bold)
    static let eyebrowTracking: CGFloat = 1.6
    /// Stat tile value (22-ish, bold rounded, monospaced digits).
    static let metricValue = Font.system(.title3, design: .rounded, weight: .bold).monospacedDigit()
    /// Stat tile label (13-ish, medium).
    static let metricLabel = Font.system(.footnote, design: .default, weight: .medium)
    /// Primary button label.
    static let button = Font.system(.body, design: .rounded, weight: .bold)
}

/// Semantic text styles for `.appText(_:)`.
enum AppTextStyle {
    case heroNumber, title, headline, body, subheadline, caption, eyebrow, metricValue, metricLabel

    var font: Font {
        switch self {
        case .heroNumber: return AppTypography.heroNumber
        case .title: return AppTypography.title
        case .headline: return AppTypography.headline
        case .body: return AppTypography.body
        case .subheadline: return AppTypography.subheadline
        case .caption: return AppTypography.caption
        case .eyebrow: return AppTypography.eyebrow
        case .metricValue: return AppTypography.metricValue
        case .metricLabel: return AppTypography.metricLabel
        }
    }
}

extension View {
    /// Ergonomic typography: `.appText(.headline)`. The `.eyebrow` style also
    /// applies its wide tracking + uppercase treatment.
    @ViewBuilder
    func appText(_ style: AppTextStyle) -> some View {
        if case .eyebrow = style {
            self.font(style.font)
                .tracking(AppTypography.eyebrowTracking)
                .textCase(.uppercase)
        } else {
            self.font(style.font)
        }
    }
}

// MARK: - Spacing

/// Canonical spacing scale — matches real call-site usage (4/8/12/16/20/24/32).
/// Supersedes `AppTheme.Spacing` / `AppDesignSystem.Spacing` (6/10/14/18 scale).
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Radius

/// Canonical corner radii — 12/16/20/24 are the four most-used values in the
/// codebase. Use with `style: .continuous`.
enum AppRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    /// Pill shapes — prefer the `Capsule()` shape; this is for APIs that need a number.
    static let capsule: CGFloat = 999
}

// MARK: - Shadow

extension View {
    /// Subtle resting-card shadow.
    func appShadowCard() -> some View {
        shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 3)
    }

    /// Hero glow — the Hero Ledger card treatment.
    func appShadowHero(accent: Color? = nil) -> some View {
        shadow(color: (accent ?? AppColors.accent).opacity(0.18), radius: 18, x: 0, y: 8)
    }

    /// Raised / floating element (pressed states, floating buttons).
    func appShadowRaised() -> some View {
        shadow(color: Color.black.opacity(0.3), radius: 16, x: 0, y: 10)
    }
}
