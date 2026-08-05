import SwiftUI

/// Holds the current semantic colors. The palette is `SemanticColors.adaptive`
/// (dynamic dark/light colors that resolve per-render), so this global only
/// changes when the prestige accent changes — `AdaptiveThemeModifier` restamps
/// it with the user's tier. Scheme flips never require an update.
enum ThemeProvider {
    static var current: SemanticColors = .adaptive
}
