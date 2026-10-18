import Foundation

// MARK: - Otto, the Hour Tracker owl
//
// Each pose is a pair of vector assets in Assets.xcassets/Mascot:
// `otto-<pose>` is the whole owl, and `otto-<pose>-scarf` is the scarf alone
// in gray, so OwlView can tint it with the user's prestige accent.
// Sources and the regeneration pipeline live in docs/mascot and
// scripts/mascot.

enum OwlPose: String, CaseIterable {
    /// Standing, wings folded. The default companion.
    case idle
    /// Hello: Splash, Welcome Back, onboarding welcome.
    case wave
    /// Both wings up: shift saved, level-up, payday, personal best.
    case cheer
    /// Holding a coffee: adding a shift, live shift while working.
    case coffee
    /// Reading a clipboard: History, cheque detail, statements, export.
    case clipboard
    /// Asleep on a moon: days off, breaks, quiet empty states.
    case sleep
    /// Trophy overhead: leaderboards, achievements, Top 5.
    case trophy
    /// Beside a flame: streaks.
    case streak
    /// Wearing a crown: prestige, Pro.
    case crown
    /// High-fiving a friend: Friends.
    case buddies
    /// Hugging a heart: tip jar.
    case heart
    /// Magnifying glass: missing shifts, no results.
    case search
    /// Wrench on the shoulder: Settings, overtime rules.
    case wrench
    /// Calendar page: pay cycle dates, holidays, week start.
    case calendar
    /// Ringing a bell: notifications, reminders, announcements.
    case bell
    /// Shield with a check: privacy, sign-in, verification.
    case shield
    /// Map pin: locations, country.
    case pin
    /// Sunglasses: Wrapped.
    case shades
    /// Head and wing tips over a straight edge: small peeks over cards.
    case peek
    /// Sheepish: errors and failed syncs.
    case oops
    /// Pointing right: hints and calls to action.
    case point

    var assetName: String { "otto-\(rawValue)" }
    var scarfAssetName: String { "otto-\(rawValue)-scarf" }
}
