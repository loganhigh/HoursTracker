import Foundation

struct WorkEntry: Identifiable, Codable, Equatable {
    var id = UUID()

    var date: Date
    var start: Date
    var end: Date
    var breakMinutes: Int
    var notes: String

    // Location (optional)
    var locationName: String = ""
    var locationURL: String = ""       // paste Google Maps share link
    var latitude: Double? = nil
    var longitude: Double? = nil

    /// True when the user logged an off day (sick, appointment, etc.) instead of a shift.
    var isOffDay: Bool = false
    /// Reason for off day, e.g. "Sick", "Appointment", "Vacation", "Personal", "Other".
    var offDayReason: String = ""
    
    /// True when this shift was worked on a statutory holiday (for holiday pay calculation).
    var isHoliday: Bool = false

    // Convenience (used throughout)
    var paidHours: Double {
        if isOffDay { return 0 }
        var raw = end.timeIntervalSince(start) / 3600.0
        
        // Handle overnight shifts
        if raw < 0 {
            raw += 24
        }
        
        let breakHrs = Double(max(0, breakMinutes)) / 60.0
        return max(0, raw - breakHrs)
    }

    /// Clipboard line for this entry, e.g. `Jun 15, 2026 - 6:00 AM/4:00 PM (10.00h) - Asphalt`
    /// or `Jun 14, 2026 - Off (Sick)`.
    func formattedForCopy(dateFormatter: DateFormatter, timeFormatter: DateFormatter) -> String {
        let dateStr = dateFormatter.string(from: date)
        if isOffDay {
            let reason = offDayReason.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty || reason.caseInsensitiveCompare("Off") == .orderedSame {
                return "\(dateStr) - Off\(copyLocationSuffix)"
            }
            return "\(dateStr) - Off (\(reason))\(copyLocationSuffix)"
        }
        let hoursStr = String(format: "%.2fh", paidHours)
        return "\(dateStr) - \(timeFormatter.string(from: start))/\(timeFormatter.string(from: end)) (\(hoursStr))\(copyLocationSuffix)"
    }

    private var copyLocationSuffix: String {
        let label = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return " - \(label)" }

        let url = locationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty { return " - \(url)" }

        return ""
    }

    enum CodingKeys: String, CodingKey {
        case id, date, start, end, breakMinutes, notes
        case locationName, locationURL, latitude, longitude
        case isOffDay, offDayReason, isHoliday
    }

    init(id: UUID = UUID(), date: Date, start: Date, end: Date, breakMinutes: Int, notes: String,
         locationName: String = "", locationURL: String = "", latitude: Double? = nil, longitude: Double? = nil,
         isOffDay: Bool = false, offDayReason: String = "", isHoliday: Bool = false) {
        self.id = id
        self.date = date
        self.start = start
        self.end = end
        self.breakMinutes = max(0, breakMinutes)
        self.notes = notes
        self.locationName = String(locationName.prefix(500))
        self.locationURL = String(locationURL.prefix(500))
        self.latitude = latitude
        self.longitude = longitude
        self.isOffDay = isOffDay
        self.offDayReason = offDayReason
        self.isHoliday = isHoliday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        breakMinutes = max(0, try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0)
        notes = try c.decode(String.self, forKey: .notes)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName) ?? ""
        locationURL = try c.decodeIfPresent(String.self, forKey: .locationURL) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        isOffDay = try c.decodeIfPresent(Bool.self, forKey: .isOffDay) ?? false
        offDayReason = try c.decodeIfPresent(String.self, forKey: .offDayReason) ?? ""
        isHoliday = try c.decodeIfPresent(Bool.self, forKey: .isHoliday) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(breakMinutes, forKey: .breakMinutes)
        try c.encode(notes, forKey: .notes)
        try c.encode(locationName, forKey: .locationName)
        try c.encode(locationURL, forKey: .locationURL)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encode(isOffDay, forKey: .isOffDay)
        try c.encode(offDayReason, forKey: .offDayReason)
        try c.encode(isHoliday, forKey: .isHoliday)
    }
}
