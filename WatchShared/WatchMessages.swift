import Foundation

// MARK: - Phone ⇄ Watch message format
//
// Compiled into both the iPhone app and the watch app. The phone is the
// source of truth: it owns the entries, the live shift and sync. The watch
// sends commands and renders the latest snapshot the phone pushes back.
// Everything travels as JSON `Data` under a single key so both sides share
// one Codable definition instead of hand-built dictionaries.

enum WatchKeys {
    static let command = "cmd"
    static let snapshot = "snapshot"
    static let result = "result"
    static let monthShifts = "monthShifts"
    /// A board / chat / messages reply (see WatchSocial.swift).
    static let payload = "payload"
}

/// One break during a live shift. `end == nil` while it's still running.
struct WatchBreak: Codable, Equatable, Hashable {
    var start: Date
    var end: Date?
}

/// The live shift as the watch draws it.
struct WatchLiveShift: Codable, Equatable {
    var startDate: Date
    var breaks: [WatchBreak]

    var isOnBreak: Bool { !breaks.isEmpty && breaks.last?.end == nil }

    func breakSeconds(at now: Date) -> TimeInterval {
        breaks.reduce(0) { $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start)) }
    }

    func workedSeconds(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startDate) - breakSeconds(at: now))
    }
}

/// A saved shift template, flattened for the watch.
struct WatchTemplate: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var locationName: String
}

/// A recently logged shift, for the "Recent" list and "same as last".
struct WatchRecentShift: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var day: Date
    var start: Date
    var end: Date
    var breakMinutes: Int
    var hours: Double
    var locationName: String
}

/// One calendar month of logged work, for the watch's history list.
struct WatchMonth: Codable, Equatable, Identifiable, Hashable {
    /// First day of the month.
    var id: Date
    var hours: Double
    var shiftCount: Int
}

/// Everything the watch needs to draw itself, pushed by the phone.
struct WatchSnapshot: Codable, Equatable {
    var signedIn: Bool
    var liveShift: WatchLiveShift?
    /// Logged hours, not counting the live shift (the watch adds that itself).
    var chequeHours: Double
    var monthHours: Double
    /// The current pay period's work window, `[start, end)`.
    var chequeStart: Date
    var chequeEnd: Date
    var templates: [WatchTemplate]
    var places: [String]
    var recentShifts: [WatchRecentShift]
    /// Every month with work in it, newest first. Each month's shifts are
    /// fetched on demand with `.requestMonth` to keep the snapshot small.
    var months: [WatchMonth]
    var generatedAt: Date

    static let empty = WatchSnapshot(
        signedIn: false, liveShift: nil, chequeHours: 0, monthHours: 0,
        chequeStart: .distantPast, chequeEnd: .distantPast,
        templates: [], places: [], recentShifts: [], months: [], generatedAt: .distantPast
    )
}

/// A shift entered on the watch. Times are minutes after midnight on `day`;
/// an end at or before the start means the shift ran past midnight.
struct WatchShiftDraft: Codable, Equatable, Hashable {
    /// Lets the phone drop a repeat when a queued copy arrives twice.
    var id: String = UUID().uuidString
    var day: Date
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    var locationName: String
    var templateID: String?

    /// Paid hours the draft works out to (same +24h wrap as WorkEntry).
    var paidHours: Double {
        var minutes = endMinutes - startMinutes
        if minutes <= 0 { minutes += 24 * 60 }
        return max(0, Double(minutes - breakMinutes) / 60)
    }
}

/// What the watch asks the phone to do. Live-shift commands carry the
/// moment the button was pressed, so a queued command delivered later
/// still records the right time.
enum WatchCommand: Codable, Equatable {
    case requestSnapshot
    case clockIn(at: Date)
    case startBreak(at: Date)
    case endBreak(at: Date)
    case clockOut(at: Date)
    case addShift(WatchShiftDraft)
    /// Every shift in the month starting on this date; the reply carries
    /// them under `WatchKeys.monthShifts`.
    case requestMonth(Date)
    case requestBoard
    case requestChat
    /// Posts to Board Chat; the reply carries the refreshed chat.
    case sendChat(text: String)
    case requestInbox
    case requestThread(otherUid: String)
    /// Sends a direct message; the reply carries the refreshed thread.
    case sendDirect(otherUid: String, otherUsername: String, text: String)
}

enum WatchCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Any?) -> T? {
        guard let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
