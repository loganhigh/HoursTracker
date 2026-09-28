import SwiftUI
import UIKit

// ⚠️ KEEP IN SYNC with HoursTrackerWidget/WidgetPrestigeTheme.swift: the
// widget extension cannot see this file (separate synchronized folders), so
// it duplicates every tier's `gradient` (P0–P20) as raw hex. If you change a
// tier gradient here, mirror it there. Verified matching 2026-08-05 (Phase 13).

/// Central source of truth for prestige rank cosmetics:
/// every rank P0–P20 has its own distinct color, gradient, name, and icon.
/// P0–P10 are the original metal/gem ladder; P11–P20 are the Legend family —
/// luminous primaries (they drive the app accent on a near-black UI, so they
/// must stay bright) over deep, obsidian-dark gradients, culminating in P20.
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

        /// P11–P20: the Legend family. Drives the badge shimmer
        /// (`legendShimmer`) and is available for other premium treatments.
        var isLegend: Bool { prestige > 10 }

        /// The pinnacle rank (P20) — gets a prismatic shimmer.
        var isApex: Bool { prestige >= GamificationLevelCalculator.maxPrestige }

        /// Readable text/icon color for content drawn directly on `primary`
        /// (buttons, earned-badge glyphs, anything using `AppColors.textOnAccent`).
        /// A single hardcoded white broke down on light tiers — Silver
        /// (0xCBD5E1) and Gold (0xFACC15) both wash white text out to near
        /// invisibility. Perceived-brightness threshold picks white on dark/
        /// saturated tiers and a near-black ink on light/pale ones, so every
        /// tier gets readable text automatically, including future ones.
        var onPrimary: Color {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(primary).getRed(&r, green: &g, blue: &b, alpha: &a)
            let perceivedBrightness = 0.299 * r + 0.587 * g + 0.114 * b
            return perceivedBrightness > 0.62 ? Color(hex: 0x14141C) : Color.white
        }

        /// Colors for the days-worked ring on the pay-cycle hero card.
        var daysRingColors: [Color] { gradient }

        /// Colors for the hours-this-cheque ring — slightly shifted for contrast.
        var hoursRingColors: [Color] {
            [accent2, highlight, primary]
        }
    }

    // MARK: - Tiers

    /// All defined prestige tiers, ordered 0…`GamificationLevelCalculator.maxPrestige`.
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
        ),

        // MARK: Legend family (P11–P20)
        // Luminous primaries (app accent on near-black) over deep,
        // obsidian-dark gradient tails. Widget mirror: WidgetPrestigeTheme.
        Tier(
            prestige: 11,
            name: "Obsidian",
            icon: "seal.fill",
            primary:    Color(hex: 0x9D86FF),
            accent2:    Color(hex: 0x6D4FE0),
            highlight:  Color(hex: 0xD2C6FF),
            gradient:   [Color(hex: 0xC4B5FF), Color(hex: 0x6D4FE0), Color(hex: 0x1E1440)],
            chartBar:   [Color(hex: 0xC4B5FF), Color(hex: 0x6D4FE0)]
        ),
        Tier(
            prestige: 12,
            name: "Onyx",
            icon: "circle.hexagongrid.fill",
            primary:    Color(hex: 0x94A9C4),
            accent2:    Color(hex: 0x5B6E8A),
            highlight:  Color(hex: 0xDCE6F2),
            gradient:   [Color(hex: 0xDCE6F2), Color(hex: 0x5B6E8A), Color(hex: 0x141A24)],
            chartBar:   [Color(hex: 0xDCE6F2), Color(hex: 0x5B6E8A)]
        ),
        Tier(
            prestige: 13,
            name: "Titanium",
            icon: "shield.checkered",
            primary:    Color(hex: 0x5B9BFF),
            accent2:    Color(hex: 0x3563D9),
            highlight:  Color(hex: 0xB3D1FF),
            gradient:   [Color(hex: 0xB3D1FF), Color(hex: 0x3563D9), Color(hex: 0x0F1E4A)],
            chartBar:   [Color(hex: 0xB3D1FF), Color(hex: 0x3563D9)]
        ),
        Tier(
            prestige: 14,
            name: "Eclipse",
            icon: "moon.circle.fill",
            primary:    Color(hex: 0xFF9F43),
            accent2:    Color(hex: 0xD9601A),
            highlight:  Color(hex: 0xFFD7A0),
            gradient:   [Color(hex: 0xFFD7A0), Color(hex: 0xC2530F), Color(hex: 0x2A1206)],
            chartBar:   [Color(hex: 0xFFD7A0), Color(hex: 0xD9601A)]
        ),
        Tier(
            prestige: 15,
            name: "Aurora",
            icon: "sparkle",
            primary:    Color(hex: 0x2EE6A6),
            accent2:    Color(hex: 0x0FA3A0),
            highlight:  Color(hex: 0xA8FFE0),
            gradient:   [Color(hex: 0xA8FFE0), Color(hex: 0x0F8F84), Color(hex: 0x062326)],
            chartBar:   [Color(hex: 0xA8FFE0), Color(hex: 0x0FA3A0)]
        ),
        Tier(
            prestige: 16,
            name: "Nebula",
            icon: "hurricane",
            primary:    Color(hex: 0xE36BFF),
            accent2:    Color(hex: 0xA93BE0),
            highlight:  Color(hex: 0xF6C2FF),
            gradient:   [Color(hex: 0xF6C2FF), Color(hex: 0x8E2BC4), Color(hex: 0x220A33)],
            chartBar:   [Color(hex: 0xF6C2FF), Color(hex: 0xA93BE0)]
        ),
        Tier(
            prestige: 17,
            name: "Supernova",
            icon: "sun.max.fill",
            primary:    Color(hex: 0xFF5E6C),
            accent2:    Color(hex: 0xE0304A),
            highlight:  Color(hex: 0xFFB3A0),
            gradient:   [Color(hex: 0xFFC9A8), Color(hex: 0xE0304A), Color(hex: 0x330812)],
            chartBar:   [Color(hex: 0xFFC9A8), Color(hex: 0xE0304A)]
        ),
        Tier(
            prestige: 18,
            name: "Celestial",
            icon: "moon.stars.fill",
            primary:    Color(hex: 0x6FCBFF),
            accent2:    Color(hex: 0x3A8EE0),
            highlight:  Color(hex: 0xD9F2FF),
            gradient:   [Color(hex: 0xD9F2FF), Color(hex: 0x2F6FC4), Color(hex: 0x0A1633)],
            chartBar:   [Color(hex: 0xD9F2FF), Color(hex: 0x3A8EE0)]
        ),
        Tier(
            prestige: 19,
            name: "Ascendant",
            icon: "wand.and.stars",
            primary:    Color(hex: 0xF5C451),
            accent2:    Color(hex: 0xC9921E),
            highlight:  Color(hex: 0xFFF0C2),
            gradient:   [Color(hex: 0xFFF0C2), Color(hex: 0xB8841A), Color(hex: 0x2B1D05)],
            chartBar:   [Color(hex: 0xFFF0C2), Color(hex: 0xC9921E)]
        ),
        Tier(
            prestige: 20,
            name: "Eternal",
            icon: "infinity",
            // White-hot platinum and champagne — one radiant family, not a
            // spectrum, so the top rank reads as light rather than colour.
            primary:    Color(hex: 0xF3E9D2),
            accent2:    Color(hex: 0xC9A96E),
            highlight:  Color(hex: 0xFFFFFF),
            gradient:   [Color(hex: 0xFFFFFF), Color(hex: 0xD9C39A), Color(hex: 0x2A2418)],
            chartBar:   [Color(hex: 0xF3E9D2), Color(hex: 0xC9A96E)]
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

// MARK: - Legend badge shimmer

/// A slow diagonal light sweep across a prestige BADGE/emblem, shown only for
/// Legend tiers (P11–P20). Masked to the modified view's own alpha, so it
/// follows an SF Symbol's glyph or a filled shape exactly. P20 sweeps a
/// prismatic band. Reduce Motion: no sweep — a static sheen instead.
/// Intended for emblems only; name text effects are a separate treatment.
private struct LegendShimmerModifier: ViewModifier {
    let tier: PrestigeTheme.Tier
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if tier.isLegend {
            content
                .overlay {
                    GeometryReader { geo in
                        band
                            .frame(width: geo.size.width * 0.9, height: geo.size.height * 2)
                            .rotationEffect(.degrees(24))
                            .offset(x: reduceMotion ? 0 : phase * geo.size.width * 1.4)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .opacity(reduceMotion ? 0.35 : 1)
                    .blendMode(.plusLighter)
                    .mask(content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    phase = -1
                    withAnimation(.easeInOut(duration: 2.6).delay(0.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }

    private var band: LinearGradient {
        let peak: [Color] = tier.isApex
            ? [tier.accent2.opacity(0.55), Color.white.opacity(0.7), tier.highlight.opacity(0.55)]
            : [tier.highlight.opacity(0.35), Color.white.opacity(0.6), tier.highlight.opacity(0.35)]
        return LinearGradient(
            colors: [.clear] + peak + [.clear],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

extension View {
    /// Adds the Legend-tier (P11+) shimmer to a prestige badge/emblem; a
    /// no-op for P0–P10.
    func legendShimmer(_ tier: PrestigeTheme.Tier) -> some View {
        modifier(LegendShimmerModifier(tier: tier))
    }
}
