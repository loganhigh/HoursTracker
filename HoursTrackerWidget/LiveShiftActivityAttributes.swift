import ActivityKit
import Foundation

/// Live Activity state for an in-progress clocked-in shift.
///
/// Duplicated field-for-field in
/// `HoursTracker/LiveShiftActivityAttributes.swift` — see that file for why.
/// Keep both copies in sync.
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
        /// Pay so far, from the app's own pay rules (overtime included), as
        /// of `updatedAt`. nil when no wage is set — the card shows no money.
        var earned: Double?
        /// The rate the next hour earns at ("$69.00/hr" during overtime).
        var currentRate: Double?
        var currencyCode: String
        var updatedAt: Date
    }
}
