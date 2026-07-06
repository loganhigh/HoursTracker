import SwiftUI

/// Central source of truth for prestige rank cosmetics:
/// every rank P0–P10 has its own distinct color, gradient, name, and icon.
/// The active rank drives the app-wide accent color through `AdaptiveThemeModifier`.
enum PrestigeTheme {

    struct Tier: Identifiable {
        let prestige: Int
        let name: String
        let icon: String
        /// Primary accent color (used as the app accent when this rank is active).
        let primary: Color
        /// Secondary accent — used as `AppTheme.Colors.accent2`.
        let accent2: Color
        /// Bright highlight tone — used as `AppTheme.Colors.accentHighlight`.
        let highlight: Color
        /// Three-stop colors used by the app-wide `accentGradient`.
        let gradient: [Color]
        /// Two-stop colors used by chart bars and the hours ring.
        let chartBar: [Color]

        var id: Int { prestige }

        /// Colors for the days-worked ring on the pay-cycle hero card.
        var daysRingColors: [Color] { gradient }

        /// Colors for the hours-this-cheque ring — slightly shifted for contrast.
        var hoursRingColors: [Color] {
            [accent2, highlight, primary]
        }
    }

    // MARK: - Tiers

    /// All defined prestige tiers, ordered 0…10.
    static let tiers: [Tier] = [
        Tier(
            prestige: 0,
            name: "Unranked",
            icon: "shield",
            primary:    Color(hex: 0x8B5CF6),
            accent2:    Color(hex: 0x6366F1),
            highlight:  Color(hex: 0x3B82F6),
            gradient:   [Color(hex: 0x7C3AED), Color(hex: 0x6366F1), Color(hex: 0x3B82F6)],
            chartBar:   [Color(hex: 0x7C3AED), Color(hex: 0x6366F1)]
        ),
        Tier(
            prestige: 1,
            name: "Bronze",
            icon: "shield.fill",
            primary:    Color(hex: 0xD97706),
            accent2:    Color(hex: 0xB45309),
            highlight:  Color(hex: 0xFBBF24),
            gradient:   [Color(hex: 0xFCD34D), Color(hex: 0xD97706), Color(hex: 0x92400E)],
            chartBar:   [Color(hex: 0xFBBF24), Color(hex: 0xB45309)]
        ),
        Tier(
            prestige: 2,
            name: "Silver",
            icon: "shield.lefthalf.filled",
            primary:    Color(hex: 0xCBD5E1),
            accent2:    Color(hex: 0x94A3B8),
            highlight:  Color(hex: 0xF1F5F9),
            gradient:   [Color(hex: 0xF8FAFC), Color(hex: 0xCBD5E1), Color(hex: 0x64748B)],
            chartBar:   [Color(hex: 0xF1F5F9), Color(hex: 0x94A3B8)]
        ),
        Tier(
            prestige: 3,
            name: "Gold",
            icon: "star.fill",
            primary:    Color(hex: 0xFACC15),
            accent2:    Color(hex: 0xEAB308),
            highlight:  Color(hex: 0xFDE047),
            gradient:   [Color(hex: 0xFEF08A), Color(hex: 0xFACC15), Color(hex: 0xCA8A04)],
            chartBar:   [Color(hex: 0xFDE047), Color(hex: 0xEAB308)]
        ),
        Tier(
            prestige: 4,
            name: "Platinum",
            icon: "sparkles",
            primary:    Color(hex: 0x7DD3FC),
            accent2:    Color(hex: 0x38BDF8),
            highlight:  Color(hex: 0xE0F2FE),
            gradient:   [Color(hex: 0xE0F2FE), Color(hex: 0x7DD3FC), Color(hex: 0x0284C7)],
            chartBar:   [Color(hex: 0xBAE6FD), Color(hex: 0x0284C7)]
        ),
        Tier(
            prestige: 5,
            name: "Diamond",
            icon: "diamond.fill",
            primary:    Color(hex: 0x2DD4BF),
            accent2:    Color(hex: 0x14B8A6),
            highlight:  Color(hex: 0x5EEAD4),
            gradient:   [Color(hex: 0x99F6E4), Color(hex: 0x2DD4BF), Color(hex: 0x0D9488)],
            chartBar:   [Color(hex: 0x5EEAD4), Color(hex: 0x0F766E)]
        ),
        Tier(
            prestige: 6,
            name: "Master",
            icon: "crown.fill",
            primary:    Color(hex: 0xA78BFA),
            accent2:    Color(hex: 0x8B5CF6),
            highlight:  Color(hex: 0xC4B5FD),
            gradient:   [Color(hex: 0xDDD6FE), Color(hex: 0xA78BFA), Color(hex: 0x6D28D9)],
            chartBar:   [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED)]
        ),
        Tier(
            prestige: 7,
            name: "Grandmaster",
            icon: "flame.fill",
            primary:    Color(hex: 0xFB923C),
            accent2:    Color(hex: 0xEF4444),
            highlight:  Color(hex: 0xFDBA74),
            gradient:   [Color(hex: 0xFED7AA), Color(hex: 0xFB923C), Color(hex: 0xDC2626)],
            chartBar:   [Color(hex: 0xFDBA74), Color(hex: 0xDC2626)]
        ),
        Tier(
            prestige: 8,
            name: "Champion",
            icon: "trophy.fill",
            primary:    Color(hex: 0x34D399),
            accent2:    Color(hex: 0x10B981),
            highlight:  Color(hex: 0xFBBF24),
            gradient:   [Color(hex: 0x6EE7B7), Color(hex: 0x34D399), Color(hex: 0x059669)],
            chartBar:   [Color(hex: 0xFBBF24), Color(hex: 0x10B981)]
        ),
        Tier(
            prestige: 9,
            name: "Legend",
            icon: "bolt.fill",
            primary:    Color(hex: 0xFB7185),
            accent2:    Color(hex: 0xF43F5E),
            highlight:  Color(hex: 0xFDA4AF),
            gradient:   [Color(hex: 0xFECDD3), Color(hex: 0xFB7185), Color(hex: 0xBE123C)],
            chartBar:   [Color(hex: 0xFDA4AF), Color(hex: 0xBE123C)]
        ),
        Tier(
            prestige: 10,
            name: "Prestige Master",
            icon: "crown.fill",
            primary:    Color(hex: 0xDC2626),
            accent2:    Color(hex: 0xB91C1B),
            highlight:  Color(hex: 0xF87171),
            gradient:   [Color(hex: 0xFCA5A5), Color(hex: 0xDC2626), Color(hex: 0x991B1B)],
            chartBar:   [Color(hex: 0xF87171), Color(hex: 0xB91C1B)]
        )
    ]

    /// Returns the tier definition for the given prestige level (clamped to the valid range).
    static func tier(for prestige: Int) -> Tier {
        let clamped = max(0, min(prestige, tiers.count - 1))
        return tiers[clamped]
    }

    /// Convenience: primary accent color for a prestige rank.
    static func color(for prestige: Int) -> Color {
        tier(for: prestige).primary
    }
}
