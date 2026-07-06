import SwiftUI

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
        default:
            return [rgb(0xFCA5A5), rgb(0xDC2626), rgb(0x991B1B)]
        }
    }

    private static func clamped(_ prestige: Int) -> Int {
        max(0, min(prestige, 10))
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
