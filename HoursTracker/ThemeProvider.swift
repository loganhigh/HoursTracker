import SwiftUI

/// Holds current semantic colors; updated by root when color scheme changes.
enum ThemeProvider {
    static var current: SemanticColors = .dark
}
