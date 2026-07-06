import Foundation
import SwiftUI
import Combine

// MARK: - Localization Manager

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "app_language")
            updateBundle()
        }
    }
    
    private var bundle: Bundle = Bundle.main
    
    private init() {
        currentLanguage = UserDefaults.standard.string(forKey: "app_language") ?? "en"
        updateBundle()
    }
    
    private func updateBundle() {
        if let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            self.bundle = bundle
        } else {
            self.bundle = Bundle.main
        }
    }
    
    func localizedString(_ key: String, comment: String = "") -> String {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - Localized String Helper

struct L {
    // MARK: - General
    static var cancel: String { LocalizationManager.shared.localizedString("cancel") }
    static var done: String { LocalizationManager.shared.localizedString("done") }
    static var save: String { LocalizationManager.shared.localizedString("save") }
    static var edit: String { LocalizationManager.shared.localizedString("edit") }
    static var delete: String { LocalizationManager.shared.localizedString("delete") }
    static var close: String { LocalizationManager.shared.localizedString("close") }
    
    // MARK: - Navigation
    static var settings: String { LocalizationManager.shared.localizedString("settings") }
    static var insights: String { LocalizationManager.shared.localizedString("insights") }
    static var reporting: String { LocalizationManager.shared.localizedString("reporting") }
    static var achievements: String { LocalizationManager.shared.localizedString("achievements") }
    
    // MARK: - Entries
    static var addEntry: String { LocalizationManager.shared.localizedString("add_entry") }
    static var editEntry: String { LocalizationManager.shared.localizedString("edit_entry") }
    static var deleteEntry: String { LocalizationManager.shared.localizedString("delete_entry") }
    static var notes: String { LocalizationManager.shared.localizedString("notes") }
    static var optional: String { LocalizationManager.shared.localizedString("optional") }
    
    // MARK: - Time
    static var start: String { LocalizationManager.shared.localizedString("start") }
    static var end: String { LocalizationManager.shared.localizedString("end") }
    static var date: String { LocalizationManager.shared.localizedString("date") }
    static var hours: String { LocalizationManager.shared.localizedString("hours") }
    static var days: String { LocalizationManager.shared.localizedString("days") }
    
    // MARK: - Goal
    static var biWeeklyHourGoal: String { LocalizationManager.shared.localizedString("biweekly_hour_goal") }
    static var goalMet: String { LocalizationManager.shared.localizedString("goal_met") }
    static var shortOfGoal: String { LocalizationManager.shared.localizedString("short_of_goal") }
    
    // MARK: - Settings
    static var language: String { LocalizationManager.shared.localizedString("language") }
    static var appLanguage: String { LocalizationManager.shared.localizedString("app_language") }
    static var languageChangeNote: String { LocalizationManager.shared.localizedString("language_change_note") }
    static var notifications: String { LocalizationManager.shared.localizedString("notifications") }
    static var holidayPay: String { LocalizationManager.shared.localizedString("holiday_pay") }
    static var vacationPay: String { LocalizationManager.shared.localizedString("vacation_pay") }
    
    // MARK: - Pay
    static var showPayCalculations: String { LocalizationManager.shared.localizedString("show_pay_calculations") }
    static var hourlyWage: String { LocalizationManager.shared.localizedString("hourly_wage") }
    static var currency: String { LocalizationManager.shared.localizedString("currency") }
    
    // Helper function for formatted strings
    static func youAreShortOfGoal(hours: String) -> String {
        String(format: LocalizationManager.shared.localizedString("you_are_short_of_goal"), hours)
    }
    
    static func goalMetOver(hours: String) -> String {
        String(format: LocalizationManager.shared.localizedString("goal_met_over"), hours)
    }
}

// MARK: - Environment Key for Language Updates

struct LocalizationEnvironmentKey: EnvironmentKey {
    static let defaultValue: LocalizationManager = LocalizationManager.shared
}

extension EnvironmentValues {
    var localization: LocalizationManager {
        get { self[LocalizationEnvironmentKey.self] }
        set { self[LocalizationEnvironmentKey.self] = newValue }
    }
}
