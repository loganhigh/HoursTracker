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
}

extension View {
    /// Shrinks text to fit — never shows an ellipsis.
    func widgetFittingText(minScale: CGFloat = 0.35) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
    }
}
