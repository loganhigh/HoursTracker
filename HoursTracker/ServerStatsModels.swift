import Foundation
import FirebaseFirestore

struct ServerWeekStats: Equatable {
    let weekStart: Date?
    let weekEnd: Date?
    let hours: Double
    let shifts: Int
    let daysWorked: Int
    let currentStreak: Int
    let updatedAt: Date?

    static func fromFirestore(_ data: [String: Any]?) -> ServerWeekStats? {
        guard let data else { return nil }
        return ServerWeekStats(
            weekStart: firestoreDate(data["weekStart"]),
            weekEnd: firestoreDate(data["weekEnd"]),
            hours: firestoreDouble(data, key: "hours"),
            shifts: firestoreInt(data, key: "shifts"),
            daysWorked: firestoreInt(data, key: "daysWorked"),
            currentStreak: firestoreInt(data, key: "currentStreak"),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

struct ServerPayPeriodStats: Equatable {
    let periodStart: Date?
    let periodEnd: Date?
    let hours: Double
    let shifts: Int
    let daysWorked: Int
    let estimatedPay: Double?
    let updatedAt: Date?

    static func fromFirestore(_ data: [String: Any]?) -> ServerPayPeriodStats? {
        guard let data else { return nil }
        let pay = data["estimatedPay"] as? Double ?? (data["estimatedPay"] as? NSNumber)?.doubleValue
        return ServerPayPeriodStats(
            periodStart: firestoreDate(data["periodStart"]),
            periodEnd: firestoreDate(data["periodEnd"]),
            hours: firestoreDouble(data, key: "hours"),
            shifts: firestoreInt(data, key: "shifts"),
            daysWorked: firestoreInt(data, key: "daysWorked"),
            estimatedPay: pay,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

struct ServerLifetimeStats: Equatable {
    let totalHours: Double
    let totalXP: Int
    let level: Int
    let prestige: Int
    let bestStreak: Int
    let badgeCount: Int
    let updatedAt: Date?

    static func fromFirestore(_ data: [String: Any]?) -> ServerLifetimeStats? {
        guard let data else { return nil }
        return ServerLifetimeStats(
            totalHours: firestoreDouble(data, key: "totalHours"),
            totalXP: firestoreInt(data, key: "totalXP"),
            level: firestoreInt(data, key: "level", default: 1),
            prestige: firestoreInt(data, key: "prestige"),
            bestStreak: firestoreInt(data, key: "bestStreak"),
            badgeCount: firestoreInt(data, key: "badgeCount"),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }
}

private func firestoreDate(_ value: Any?) -> Date? {
    if let ts = value as? Timestamp { return ts.dateValue() }
    if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000) }
    if let ms = value as? Int64 { return Date(timeIntervalSince1970: Double(ms) / 1000) }
    if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000) }
    return nil
}

private func firestoreInt(_ data: [String: Any], key: String, default defaultValue: Int = 0) -> Int {
    if let v = data[key] as? Int { return v }
    if let v = data[key] as? Int64 { return Int(v) }
    if let v = data[key] as? NSNumber { return v.intValue }
    return defaultValue
}

private func firestoreDouble(_ data: [String: Any], key: String) -> Double {
    if let v = data[key] as? Double { return v }
    if let v = data[key] as? NSNumber { return v.doubleValue }
    return 0
}
