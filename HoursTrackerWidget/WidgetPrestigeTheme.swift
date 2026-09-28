import SwiftUI

// ⚠️ KEEP IN SYNC with HoursTracker/PrestigeTheme.swift (tier `gradient`
// values, P0–P20). The widget extension target cannot see the app target's
// sources (separate synchronized folders), so the 21 tier gradients are
// duplicated here as raw hex. If a tier color changes in PrestigeTheme,
// change it here too. Verified matching 2026-08-05 (Phase 13).

/// Prestige-driven widget backgrounds — mirrors main app rank colors.
enum WidgetPrestigeTheme {
    static func backgroundGradient(for prestige: Int) -> LinearGradient {
        let colors = gradientColors(for: prestige)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func gradientColors(for prestige: Int) -> [Color] {
        switch clamped(prestige) {
        case 0:
            return [rgb(0x7C3AED), rgb(0x6366F1), rgb(0x3B82F6)]
        case 1:
            return [rgb(0xFCD34D), rgb(0xD97706), rgb(0x92400E)]
        case 2:
            return [rgb(0xF8FAFC), rgb(0xCBD5E1), rgb(0x64748B)]
        case 3:
            return [rgb(0xFEF08A), rgb(0xFACC15), rgb(0xCA8A04)]
        case 4:
            return [rgb(0xE0F2FE), rgb(0x7DD3FC), rgb(0x0284C7)]
        case 5:
            return [rgb(0x99F6E4), rgb(0x2DD4BF), rgb(0x0D9488)]
        case 6:
            return [rgb(0xDDD6FE), rgb(0xA78BFA), rgb(0x6D28D9)]
        case 7:
            return [rgb(0xFED7AA), rgb(0xFB923C), rgb(0xDC2626)]
        case 8:
            return [rgb(0x6EE7B7), rgb(0x34D399), rgb(0x059669)]
        case 9:
            return [rgb(0xFECDD3), rgb(0xFB7185), rgb(0xBE123C)]
        case 10:
            return [rgb(0xFCA5A5), rgb(0xDC2626), rgb(0x991B1B)]
        // Legend family (P11–P20)
        case 11:
            return [rgb(0xC4B5FF), rgb(0x6D4FE0), rgb(0x1E1440)]
        case 12:
            return [rgb(0xDCE6F2), rgb(0x5B6E8A), rgb(0x141A24)]
        case 13:
            return [rgb(0xB3D1FF), rgb(0x3563D9), rgb(0x0F1E4A)]
        case 14:
            return [rgb(0xFFD7A0), rgb(0xC2530F), rgb(0x2A1206)]
        case 15:
            return [rgb(0xA8FFE0), rgb(0x0F8F84), rgb(0x062326)]
        case 16:
            return [rgb(0xF6C2FF), rgb(0x8E2BC4), rgb(0x220A33)]
        case 17:
            return [rgb(0xFFC9A8), rgb(0xE0304A), rgb(0x330812)]
        case 18:
            return [rgb(0xD9F2FF), rgb(0x2F6FC4), rgb(0x0A1633)]
        case 19:
            return [rgb(0xFFF0C2), rgb(0xB8841A), rgb(0x2B1D05)]
        default:
            return [rgb(0xFFFFFF), rgb(0xD9C39A), rgb(0x2A2418)]
        }
    }

    /// Highest defined tier — mirrors `GamificationLevelCalculator.maxPrestige`
    /// in the app target (not visible to the widget extension).
    static let maxPrestige = 20

    private static func clamped(_ prestige: Int) -> Int {
        max(0, min(prestige, maxPrestige))
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
