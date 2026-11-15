import SwiftUI

enum WidgetFormatting {
    /// Compact hours label that scales down instead of truncating with an ellipsis.
    static func hours(_ hours: Double, suffix: String = "h") -> String {
        if hours == 0 { return "0\(suffix)" }
        if hours >= 100 { return "\(Int(hours.rounded()))\(suffix)" }
        if hours.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(hours))\(suffix)" }
        if hours >= 10 { return String(format: "%.0f\(suffix)", hours) }
        return String(format: "%.1f\(suffix)", hours)
    }

    /// Whole-unit money ("$2,140"); "$12.4k" from 10,000 up so it fits.
    static func money(_ amount: Double, currencyCode: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode ?? Locale.current.currency?.identifier ?? "USD"
        f.maximumFractionDigits = 0
        if amount >= 10_000 {
            f.maximumFractionDigits = 1
            let short = f.string(from: NSNumber(value: amount / 1000)) ?? "\(Int(amount / 1000))"
            return short + "k"
        }
        return f.string(from: NSNumber(value: amount.rounded())) ?? "$\(Int(amount.rounded()))"
    }
}

extension View {
    /// Shrinks text to fit — never shows an ellipsis.
    func widgetFittingText(minScale: CGFloat = 0.35) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
    }
}
