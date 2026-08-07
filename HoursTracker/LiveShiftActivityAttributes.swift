import ActivityKit
import Foundation

/// Live Activity state for an in-progress clocked-in shift (Hour Tracker Pro).
///
/// Duplicated field-for-field in
/// `HoursTrackerWidget/LiveShiftActivityAttributes.swift` — the widget
/// extension target can't see the app target's sources (separate
/// PBXFileSystemSynchronizedRootGroup folders, no shared framework), so
/// there's no single module to hang one definition on. Keep both copies in
/// sync; `ContentState` is `Codable`, so a field mismatch fails silently
/// (the Activity just won't decode) rather than at compile time.
struct LiveShiftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Clock-in time. The Dynamic Island's native ticking timer is
        /// driven off `startDate.addingTimeInterval(completedBreakSeconds)`
        /// so it displays *worked* time (wall time minus completed breaks)
        /// without the app needing to push a per-second update.
        var startDate: Date
        /// Total seconds from breaks that have already ended. Excludes any
        /// break currently in progress.
        var completedBreakSeconds: Int
        var isOnBreak: Bool
        /// Start of the in-progress break, when `isOnBreak` is true.
        var breakStartDate: Date?
    }
}
