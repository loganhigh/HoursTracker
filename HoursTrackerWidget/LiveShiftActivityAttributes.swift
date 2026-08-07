import ActivityKit
import Foundation

/// Live Activity state for an in-progress clocked-in shift (Hour Tracker Pro).
///
/// Duplicated field-for-field in
/// `HoursTracker/LiveShiftActivityAttributes.swift` — see that file for why.
/// Keep both copies in sync.
struct LiveShiftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var completedBreakSeconds: Int
        var isOnBreak: Bool
        var breakStartDate: Date?
    }
}
