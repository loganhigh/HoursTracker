import Foundation
import SwiftUI
import Combine
import UserNotifications

// MARK: - Weekly Milestone Notifier Service
class WeeklyMilestoneNotifier: ObservableObject {
    static let shared = WeeklyMilestoneNotifier()
    
    var isEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "weekly_milestone_notifications_enabled")
            if let boolValue = savedValue as? Bool {
                return boolValue
            }
            return true // Default value
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "weekly_milestone_notifications_enabled")
        }
    }
    
    private let milestones: [Double] = [40, 50, 60, 70, 80]
    private let notificationManager = NotificationManager.shared
    
    private init() {
        // Initialize default value if not set
        let savedValue = UserDefaults.standard.object(forKey: "weekly_milestone_notifications_enabled")
        if savedValue == nil {
            UserDefaults.standard.set(true, forKey: "weekly_milestone_notifications_enabled")
        }
    }
    
    // MARK: - Check and Notify
    func checkMilestones(for entries: [WorkEntry]) {
        guard isEnabled else { return }
        
        Task {
            // Ensure we have permission
            let hasPermission = await notificationManager.hasPermission()
            guard hasPermission else { return }
            
            let currentWeekTotal = calculateWeeklyTotal(entries: entries)
            let weekStart = getWeekStartDate()
            
            for milestone in milestones {
                if currentWeekTotal >= milestone {
                    let key = notificationKey(weekStart: weekStart, milestone: milestone)
                    let alreadyNotified = UserDefaults.standard.bool(forKey: key)
                    
                    if !alreadyNotified {
                        await sendNotification(for: milestone)
                        UserDefaults.standard.set(true, forKey: key)
                    }
                }
            }
        }
    }
    
    // MARK: - Reset Weekly State
    func resetWeeklyStateIfNeeded() {
        let currentWeekStart = getWeekStartDate()
        let lastCheckedWeekKey = "last_checked_week_start"
        
        if let lastCheckedWeekString = UserDefaults.standard.string(forKey: lastCheckedWeekKey),
           let lastCheckedWeek = dateFromString(lastCheckedWeekString),
           lastCheckedWeek == currentWeekStart {
            // Same week, no reset needed
            return
        }
        
        // New week - run heavy UserDefaults iteration off main thread
        let weekString = stringFromDate(currentWeekStart)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.clearPreviousWeekNotifications()
            UserDefaults.standard.set(weekString, forKey: lastCheckedWeekKey)
        }
    }
    
    // MARK: - Private Helpers
    private func calculateWeeklyTotal(entries: [WorkEntry]) -> Double {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return 0
        }
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        
        return entries
            .filter { $0.date >= weekStart && $0.date < weekEnd }
            .reduce(0) { $0 + $1.paidHours }
    }
    
    private func getWeekStartDate() -> Date {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return Date()
        }
        return calendar.startOfDay(for: weekStart)
    }
    
    private func notificationKey(weekStart: Date, milestone: Double) -> String {
        let dateString = stringFromDate(weekStart)
        return "weeklyMilestoneNotified_\(dateString)_\(Int(milestone))"
    }
    
    private func stringFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
    
    private func sendNotification(for milestone: Double) async {
        let content = UNMutableNotificationContent()
        content.title = "Weekly milestone unlocked 🎉"
        content.body = milestoneMessage(for: milestone)
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "weekly_milestone_\(Int(milestone))_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate delivery
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            await MainActor.run { Haptics.mediumTap() }
        } catch {
            #if DEBUG
            print("Failed to send notification: \(error)")
            #endif
        }
    }
    
    private func milestoneMessage(for milestone: Double) -> String {
        switch milestone {
        case 40:
            return "You just hit 40 hours this week. Keep it going."
        case 50:
            return "You just hit 50 hours this week. Amazing progress!"
        case 60:
            return "You just hit 60 hours this week. Absolute machine."
        case 70:
            return "You just hit 70 hours this week. Incredible dedication!"
        case 80:
            return "You just hit 80 hours this week. Legend status! 🔥"
        default:
            return "You just hit \(Int(milestone)) hours this week. Keep it up!"
        }
    }
    
    private func clearPreviousWeekNotifications() {
        // Clear all milestone notification keys
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix("weeklyMilestoneNotified_") {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

// MARK: - Notification Manager
class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            #if DEBUG
            print("Notification permission error: \(error)")
            #endif
            return false
        }
    }
    
    func hasPermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
}
