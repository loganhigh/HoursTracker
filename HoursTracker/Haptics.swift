import UIKit

/// Lightweight haptics for buttons, row taps, and UI feedback.
enum Haptics {

    /// Light tap — use for button and row taps.
    static func lightTap() {
        guard HapticsManager.shared.isEnabled else { return }
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    /// Medium tap — use for month completion, stronger feedback.
    static func mediumTap() {
        guard HapticsManager.shared.isEnabled else { return }
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred()
    }

    /// Success — use after saving a shift, unlocking badge.
    static func success() {
        guard HapticsManager.shared.isEnabled else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// Error — use for validation failures (e.g. end before start).
    static func error() {
        guard HapticsManager.shared.isEnabled else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.error)
    }

    /// Warning — optional softer feedback.
    static func warning() {
        guard HapticsManager.shared.isEnabled else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }
}

/// Manages haptics preference. Respects Settings toggle.
final class HapticsManager {
    static let shared = HapticsManager()

    private let key = "haptics_enabled"

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
