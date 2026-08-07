import Foundation

/// A saved shift pattern — "Morning Shift, 6:00 AM – 5:00 PM, 30m break".
///
/// Applying one fills the Add Shift wizard's time/break/location fields; it
/// never creates an entry by itself, so a template can be renamed or deleted
/// without touching logged shifts. Hour Tracker Pro only.
///
/// Times are minutes-from-midnight rather than `Date`s: a template has no
/// calendar day, and storing wall-clock minutes keeps it stable across time
/// zones and DST instead of drifting with whatever date it was created on.
struct ShiftTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var startMinutes: Int
    var endMinutes: Int
    var breakMinutes: Int
    /// Optional — matches a saved job site's name, or free text, or empty.
    var locationName: String
    var createdAt: Date
    var lastUsedAt: Date?

    static let nameLimit = 60
    static let minutesInDay = 24 * 60

    init(
        id: String = UUID().uuidString,
        name: String,
        startMinutes: Int,
        endMinutes: Int,
        breakMinutes: Int = 0,
        locationName: String = "",
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = ShiftTemplate.clean(name, limit: ShiftTemplate.nameLimit)
        self.startMinutes = ShiftTemplate.clampMinutes(startMinutes)
        self.endMinutes = ShiftTemplate.clampMinutes(endMinutes)
        self.breakMinutes = max(0, breakMinutes)
        self.locationName = ShiftTemplate.clean(locationName, limit: JobSite.nameLimit)
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = ShiftTemplate.clean(
            try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            limit: ShiftTemplate.nameLimit
        )
        startMinutes = ShiftTemplate.clampMinutes(try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 0)
        endMinutes = ShiftTemplate.clampMinutes(try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 0)
        breakMinutes = max(0, try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0)
        locationName = ShiftTemplate.clean(
            try c.decodeIfPresent(String.self, forKey: .locationName) ?? "",
            limit: JobSite.nameLimit
        )
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    private static func clean(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(max(0, value), minutesInDay - 1)
    }

    // MARK: - Derived

    /// Worked hours this template represents. An end at or before the start
    /// is treated as overnight (+24h), the same wrap `WorkEntry.paidHours`
    /// applies, so a 6 PM – 2 AM template reads as 8 hours.
    var paidHours: Double {
        var span = Double(endMinutes - startMinutes)
        if span <= 0 { span += Double(Self.minutesInDay) }
        return max(0, (span - Double(breakMinutes)) / 60.0)
    }

    var isOvernight: Bool { endMinutes <= startMinutes }

    var timeRangeText: String {
        let range = "\(Self.timeText(startMinutes)) – \(Self.timeText(endMinutes))"
        return isOvernight ? "\(range) +1" : range
    }

    /// Row subtitle: the time range, plus break and location when set.
    var displaySubtitle: String {
        var parts = [timeRangeText]
        if breakMinutes > 0 { parts.append("\(breakMinutes)m break") }
        if !locationName.isEmpty { parts.append(locationName) }
        return parts.joined(separator: " · ")
    }

    /// Formats minutes-from-midnight in the user's locale ("6:00 AM").
    static func timeText(_ minutes: Int) -> String {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let date = cal.date(byAdding: .minute, value: clampMinutes(minutes), to: base) ?? base
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Minutes-from-midnight for a wall-clock time, dropping its date.
    static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return clampMinutes((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    /// A `Date` on `day` carrying this template's wall-clock time, seconds
    /// zeroed — the same merge convention the entry editor uses.
    func date(_ minutes: Int, on day: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = Self.clampMinutes(minutes) / 60
        comps.minute = Self.clampMinutes(minutes) % 60
        comps.second = 0
        return cal.date(from: comps) ?? day
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(trimmed)
            || locationName.localizedCaseInsensitiveContains(trimmed)
    }
}
