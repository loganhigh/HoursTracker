import SwiftUI

// MARK: - Pay Period Type

enum PayPeriodType: String, Codable, CaseIterable {
    case weekly = "weekly"
    case biWeekly = "bi-weekly"
    
    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biWeekly: return "Bi-Weekly"
        }
    }
    
    var icon: String {
        switch self {
        case .weekly: return "calendar"
        case .biWeekly: return "calendar.badge.clock"
        }
    }
}

// MARK: - PaySettings (single source of truth)

struct PaySettings: Codable, Equatable {
    // Money basics
    var hourlyRate: Double = 35.00
    var currencyCode: String = "CAD"
    var provinceState: String = ""

    // Pay period type
    var payPeriodType: PayPeriodType = .biWeekly

    // Overtime rules
    /// How weekday OT is calculated. New in 1.10; old data decodes as nil and is migrated.
    var overtimeType: OvertimeType = .daily
    /// Daily OT threshold (hours per shift before OT kicks in). Used by .daily and .dailyAndWeekly.
    var weekdayOvertimeAfterHours: Double = 8.0
    var weekdayOvertimeMultiplier: Double = 1.5
    /// Weekly OT cap (total hours in a week before OT kicks in). Used by .weekly and .dailyAndWeekly.
    var weeklyOvertimeThreshold: Double = 40.0
    /// Legacy optional — kept for backward-compatible decoding. Migrated to overtimeType + weeklyOvertimeThreshold on first load.
    var weeklyOvertimeAfterHours: Double? = nil
    /// Saturday: first N hours at regular rate, remaining at saturdayMultiplier (1.5x).
    var saturdayOvertimeAfterHours: Double = 4.0
    var saturdayMultiplier: Double = 1.5
    var sundayMultiplier: Double = 2.0

    // Bi-weekly alignment
    // 1=Sunday ... 7=Saturday
    var paydayWeekday: Int = 6 // default Friday
    
    // Next payday date (user-set)
    var nextPayday: Date? = nil

    /// When enabled, hours on a cheque stop at the cutoff date, not payday.
    var payPeriodUsesCutoff: Bool = false
    /// User-set date when the current pay period stops counting toward this cheque.
    var nextCutoff: Date? = nil
    /// Legacy weekday fallback when `nextCutoff` is unset (1=Sunday … 7=Saturday).
    var payCutoffWeekday: Int = 7
    /// Legacy fallback when deriving cutoff from weekday.
    var daysFromCutoffToPayday: Int = 6

    var email: String = ""
    
    // Display preferences
    var showPayCalculations: Bool = false
    
    // Holiday pay
    var holidayPayEnabled: Bool = false
    var holidayPayMultiplier: Double = 1.5
    
    // Vacation pay
    var vacationPayEnabled: Bool = false
    var vacationPayPercentage: Double = 4.0 // Common default: 4% = 2 weeks/year

    // Savings goal
    var goalName: String = "New tires"
    var goalTarget: Double = 1200.0
    var goalSaved: Double = 0.0

    init() {}

    enum CodingKeys: String, CodingKey {
        case hourlyRate, currencyCode, provinceState, payPeriodType
        case overtimeType, weekdayOvertimeAfterHours, weekdayOvertimeMultiplier
        case weeklyOvertimeThreshold, weeklyOvertimeAfterHours
        case saturdayOvertimeAfterHours, saturdayMultiplier, sundayMultiplier
        case paydayWeekday, nextPayday
        case payPeriodUsesCutoff, nextCutoff, payCutoffWeekday, daysFromCutoffToPayday
        case email, showPayCalculations
        case holidayPayEnabled, holidayPayMultiplier
        case vacationPayEnabled, vacationPayPercentage
        case goalName, goalTarget, goalSaved
    }

    /// Tolerant decoder: every field is optional with a fallback to its default.
    ///
    /// Swift's *synthesized* `Decodable` throws `keyNotFound` whenever a
    /// non-optional property is absent from the stored JSON — default values do
    /// NOT cover missing keys. That meant every app update that introduced a new
    /// `PaySettings` field made the previously-saved settings (in UserDefaults
    /// AND Firestore) fail to decode, silently resetting users back to defaults
    /// and wiping their pay date. Decoding each key individually with
    /// `decodeIfPresent` keeps old payloads forward-compatible across updates.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PaySettings()

        func req<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            if let value = try? c.decodeIfPresent(T.self, forKey: key) {
                return value
            }
            return defaultValue
        }
        func opt<T: Decodable>(_ key: CodingKeys) -> T? {
            try? c.decodeIfPresent(T.self, forKey: key)
        }

        hourlyRate = req(.hourlyRate, fallback.hourlyRate)
        currencyCode = req(.currencyCode, fallback.currencyCode)
        provinceState = req(.provinceState, fallback.provinceState)
        payPeriodType = req(.payPeriodType, fallback.payPeriodType)
        overtimeType = req(.overtimeType, fallback.overtimeType)
        weekdayOvertimeAfterHours = req(.weekdayOvertimeAfterHours, fallback.weekdayOvertimeAfterHours)
        weekdayOvertimeMultiplier = req(.weekdayOvertimeMultiplier, fallback.weekdayOvertimeMultiplier)
        weeklyOvertimeThreshold = req(.weeklyOvertimeThreshold, fallback.weeklyOvertimeThreshold)
        weeklyOvertimeAfterHours = opt(.weeklyOvertimeAfterHours)
        saturdayOvertimeAfterHours = req(.saturdayOvertimeAfterHours, fallback.saturdayOvertimeAfterHours)
        saturdayMultiplier = req(.saturdayMultiplier, fallback.saturdayMultiplier)
        sundayMultiplier = req(.sundayMultiplier, fallback.sundayMultiplier)
        paydayWeekday = req(.paydayWeekday, fallback.paydayWeekday)
        nextPayday = opt(.nextPayday)
        payPeriodUsesCutoff = req(.payPeriodUsesCutoff, fallback.payPeriodUsesCutoff)
        nextCutoff = opt(.nextCutoff)
        payCutoffWeekday = req(.payCutoffWeekday, fallback.payCutoffWeekday)
        daysFromCutoffToPayday = req(.daysFromCutoffToPayday, fallback.daysFromCutoffToPayday)
        email = req(.email, fallback.email)
        showPayCalculations = req(.showPayCalculations, fallback.showPayCalculations)
        holidayPayEnabled = req(.holidayPayEnabled, fallback.holidayPayEnabled)
        holidayPayMultiplier = req(.holidayPayMultiplier, fallback.holidayPayMultiplier)
        vacationPayEnabled = req(.vacationPayEnabled, fallback.vacationPayEnabled)
        vacationPayPercentage = req(.vacationPayPercentage, fallback.vacationPayPercentage)
        goalName = req(.goalName, fallback.goalName)
        goalTarget = req(.goalTarget, fallback.goalTarget)
        goalSaved = req(.goalSaved, fallback.goalSaved)
    }
}

