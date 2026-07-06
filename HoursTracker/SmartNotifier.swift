import Foundation
import SwiftUI
import Combine
import UserNotifications

// MARK: - Smart Notifier Service
class SmartNotifier: ObservableObject {
    static let shared = SmartNotifier()
    
    // MARK: - Settings Properties
    
    var payProgressEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_pay_progress_enabled")
            if let boolValue = savedValue as? Bool {
                return boolValue
            }
            return true // Default enabled
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_pay_progress_enabled")
        }
    }
    
    var dailyReminderEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_daily_reminder_enabled")
            if let boolValue = savedValue as? Bool {
                return boolValue
            }
            return true // Default enabled
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_daily_reminder_enabled")
            // Reschedule when toggled
            if newValue {
                scheduleDailyReminder()
            } else {
                cancelDailyReminder()
            }
        }
    }
    
    var dailyReminderHour: Int {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_daily_reminder_hour")
            if let intValue = savedValue as? Int {
                return intValue
            }
            return 18 // Default 6 PM
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_daily_reminder_hour")
            // Reschedule with new time
            if dailyReminderEnabled {
                scheduleDailyReminder()
            }
        }
    }
    
    /// "Did you work today?" reminder on days the user usually works. Default on.
    var forgotHoursReminderEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_forgot_hours_enabled")
            if let boolValue = savedValue as? Bool {
                return boolValue
            }
            return true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_forgot_hours_enabled")
            if !newValue {
                cancelForgotHoursReminder()
            }
        }
    }

    /// Reminder with hours left to reach bi-weekly goal. Default on.
    var goalReminderEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_goal_reminder_enabled")
            if let boolValue = savedValue as? Bool { return boolValue }
            return true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_goal_reminder_enabled")
            if !newValue { cancelGoalReminder() }
        }
    }

    /// Streak notifications: at-risk warning + milestone celebrations. Default on.
    var streakNotificationsEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_streak_enabled")
            if let boolValue = savedValue as? Bool { return boolValue }
            return true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_streak_enabled")
            if !newValue {
                cancelStreakNotifications()
            }
        }
    }

    /// Daily motivational quote reminder near usual first-shift start time. Default on.
    var motivationReminderEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_motivation_enabled")
            if let boolValue = savedValue as? Bool { return boolValue }
            return true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_motivation_enabled")
            if !newValue {
                cancelMotivationReminders()
            }
        }
    }

    /// Alert when a friend logs a shift (e.g. "Jacob worked 13h today").
    var friendShiftNotificationsEnabled: Bool {
        get {
            let savedValue = UserDefaults.standard.object(forKey: "notifications_friend_shift_enabled")
            if let boolValue = savedValue as? Bool { return boolValue }
            return true
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "notifications_friend_shift_enabled")
            Task { @MainActor in
                await PushNotificationService.shared.syncAlertPreferenceToCloud()
            }
        }
    }
    
    private let notificationManager = NotificationManager.shared
    private static let friendShiftPrefix = "friend_shift_"
    
    private init() {
        // Initialize default values if not set
        if UserDefaults.standard.object(forKey: "notifications_pay_progress_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_pay_progress_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_daily_reminder_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_daily_reminder_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_daily_reminder_hour") == nil {
            UserDefaults.standard.set(18, forKey: "notifications_daily_reminder_hour")
        }
        if UserDefaults.standard.object(forKey: "notifications_forgot_hours_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_forgot_hours_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_goal_reminder_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_goal_reminder_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_motivation_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_motivation_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_streak_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_streak_enabled")
        }
        if UserDefaults.standard.object(forKey: "notifications_friend_shift_enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications_friend_shift_enabled")
        }
    }
    
    // MARK: - Pay Period Progress Notification
    
    func checkPayPeriodProgress(for entries: [WorkEntry], paySettings: PaySettings) {
        guard payProgressEnabled else { return }
        
        Task {
            // Ensure we have permission
            let hasPermission = await notificationManager.hasPermission()
            guard hasPermission else { return }
            
            let calendar = Calendar.current
            
            // Calculate current pay period
            guard paySettings.nextPayday != nil else { return }
            let currentCycle = PayCycleEngine.currentCycle(settings: paySettings, calendar: calendar)
            let payPeriodStart = currentCycle.start
            let payPeriodEnd = currentCycle.end
            let previousCycle = PayCycleEngine.previousCycle(before: currentCycle, settings: paySettings, calendar: calendar)
            let previousPayPeriodStart = previousCycle.start
            let previousPayPeriodEnd = previousCycle.end
            
            // Get hours for current pay period
            let currentPeriodHours = entries
                .filter { $0.date >= payPeriodStart && $0.date < payPeriodEnd }
                .reduce(0) { $0 + $1.paidHours }
            
            // Get hours for previous pay period
            let previousPeriodHours = entries
                .filter { $0.date >= previousPayPeriodStart && $0.date < previousPayPeriodEnd }
                .reduce(0) { $0 + $1.paidHours }
            
            // Check if within 8 hours of beating previous period
            let hoursRemaining = previousPeriodHours - currentPeriodHours
            
            if hoursRemaining > 0 && hoursRemaining <= 8 {
                // Check if we've already notified for this pay period
                let key = notificationKey(payPeriodStart: payPeriodStart)
                let alreadyNotified = UserDefaults.standard.bool(forKey: key)
                
                if !alreadyNotified {
                    await sendPayProgressNotification(hoursRemaining: hoursRemaining)
                    UserDefaults.standard.set(true, forKey: key)
                }
            }
        }
    }
    
    private func notificationKey(payPeriodStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: payPeriodStart)
        return "smart_notify_progress_\(dateString)"
    }
    
    private func sendPayProgressNotification(hoursRemaining: Double) async {
        let content = UNMutableNotificationContent()
        content.title = "Almost there!"
        content.body = "You're \(String(format: "%.1f", hoursRemaining)) hours from beating last cheque!"
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "pay_progress_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate delivery
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            await MainActor.run { Haptics.mediumTap() }
        } catch {
            #if DEBUG
            print("Failed to send pay progress notification: \(error)")
            #endif
        }
    }
    
    // MARK: - Daily Shift Reminder
    
    func scheduleDailyReminder() {
        guard dailyReminderEnabled else {
            cancelDailyReminder()
            return
        }
        
        Task {
            // Request permission if not yet determined; use it if already granted
            var hasPermission = await notificationManager.hasPermission()
            if !hasPermission {
                hasPermission = await notificationManager.requestPermission()
            }
            guard hasPermission else { return }
            
            // Cancel existing reminder
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_shift_reminder"])
            
            // Create new reminder
            let content = UNMutableNotificationContent()
            content.title = "Don't forget!"
            content.body = "Don't forget to log today's shift"
            content.sound = .default
            content.badge = 1
            
            // Set trigger for daily at specified hour
            var dateComponents = DateComponents()
            dateComponents.hour = dailyReminderHour
            dateComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
            let request = UNNotificationRequest(
                identifier: "daily_shift_reminder",
                content: content,
                trigger: trigger
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                #if DEBUG
                print("Daily reminder scheduled for \(dailyReminderHour):00")
                #endif
            } catch {
                #if DEBUG
                print("Failed to schedule daily reminder: \(error)")
                #endif
            }
        }
    }
    
    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_shift_reminder"])
    }
    
    func cancelDailyReminderIfNeeded(for date: Date, entries: [WorkEntry]) {
        guard dailyReminderEnabled else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entryDay = calendar.startOfDay(for: date)
        
        // If the entry is for today, check if we should cancel today's notification
        if entryDay == today {
            // Check if there's already an entry for today
            let hasEntryForToday = entries.contains { entry in
                calendar.isDate(entry.date, inSameDayAs: today)
            }
            
            if hasEntryForToday {
                // User has logged today's shift, so we can consider canceling delivered notifications
                // Note: We can't selectively cancel delivered notifications, but we can remove pending ones
                // The daily reminder will still fire tomorrow as scheduled
                #if DEBUG
                print("Entry logged for today, daily reminder will still fire tomorrow as scheduled")
                #endif
            }
        }
    }
    
    // MARK: - "Did you work today?" (forgot hours) reminder
    
    private static let forgotHoursIdentifier = "forgot_hours_reminder"
    
    /// Weekdays (1 = Sunday … 7 = Saturday) the user has worked at least twice in the last 28 days.
    private func usualWorkWeekdays(for entries: [WorkEntry]) -> Set<Int> {
        WorkScheduleInference.usualWorkWeekdays(entries: entries)
    }
    
    func scheduleForgotHoursReminderIfNeeded(entries: [WorkEntry]) {
        guard forgotHoursReminderEnabled else {
            cancelForgotHoursReminder()
            return
        }
        Task {
            let hasPermission = await notificationManager.hasPermission()
            guard hasPermission else { return }
            
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let usual = usualWorkWeekdays(for: entries)
            let weekday = calendar.component(.weekday, from: today)
            guard usual.contains(weekday) else {
                cancelForgotHoursReminder()
                return
            }
            let hasEntryToday = entries.contains { calendar.isDate($0.date, inSameDayAs: today) }
            guard !hasEntryToday else {
                cancelForgotHoursReminder()
                return
            }
            
            cancelForgotHoursReminder()
            
            var dateComponents = DateComponents()
            dateComponents.year = calendar.component(.year, from: today)
            dateComponents.month = calendar.component(.month, from: today)
            dateComponents.day = calendar.component(.day, from: today)
            dateComponents.hour = dailyReminderHour
            dateComponents.minute = 0
            
            let content = UNMutableNotificationContent()
            content.title = "Did you work today?"
            content.body = "Add a shift?"
            content.sound = .default
            content.badge = 1
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.forgotHoursIdentifier,
                content: content,
                trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                #if DEBUG
                print("Forgot-hours reminder scheduled for today at \(dailyReminderHour):00")
                #endif
            } catch {
                #if DEBUG
                print("Failed to schedule forgot-hours reminder: \(error)")
                #endif
            }
        }
    }
    
    func cancelForgotHoursReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.forgotHoursIdentifier])
    }
    
    func cancelForgotHoursReminderIfNeeded(for date: Date, entries: [WorkEntry]) {
        guard forgotHoursReminderEnabled else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard calendar.isDate(date, inSameDayAs: today) else { return }
        let hasEntryToday = entries.contains { calendar.isDate($0.date, inSameDayAs: today) }
        if hasEntryToday {
            cancelForgotHoursReminder()
        }
    }

    // MARK: - Bi-weekly goal reminder (hours left)

    private static let goalReminderIdentifier = "goal_reminder"

    func scheduleGoalReminderIfNeeded(entries: [WorkEntry], paySettings: PaySettings) {
        guard goalReminderEnabled else {
            cancelGoalReminder()
            return
        }
        let goalHours = UserDefaults.standard.double(forKey: "biweeklyGoalHours")
        guard goalHours > 0 else {
            cancelGoalReminder()
            return
        }
        let calendar = Calendar.current
        guard paySettings.nextPayday != nil else {
            cancelGoalReminder()
            return
        }
        let current = PayCycleEngine.currentCycle(settings: paySettings, calendar: calendar)
        let payPeriodStart = current.start
        let payPeriodEnd = current.end
        let periodHours = entries
            .filter { $0.date >= payPeriodStart && $0.date < payPeriodEnd }
            .reduce(0) { $0 + $1.paidHours }
        let remaining = goalHours - periodHours
        guard remaining > 0 else {
            cancelGoalReminder()
            return
        }
        Task {
            let hasPermission = await notificationManager.hasPermission()
            guard hasPermission else { return }
            cancelGoalReminder()
            let today = calendar.startOfDay(for: Date())
            var dateComponents = DateComponents()
            dateComponents.year = calendar.component(.year, from: today)
            dateComponents.month = calendar.component(.month, from: today)
            dateComponents.day = calendar.component(.day, from: today)
            dateComponents.hour = dailyReminderHour
            dateComponents.minute = 0
            let hoursText = remaining >= 1 && remaining == floor(remaining)
                ? "\(Int(remaining))h"
                : String(format: "%.1fh", remaining)
            let content = UNMutableNotificationContent()
            content.title = "Bi-weekly goal"
            content.body = "You're \(hoursText) short of your goal!"
            content.sound = .default
            content.badge = 1
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.goalReminderIdentifier,
                content: content,
                trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch { }
        }
    }

    func cancelGoalReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.goalReminderIdentifier])
    }

    // MARK: - Daily motivation reminders

    private static let motivationIdentifierPrefix = "daily_motivation_"
    private static let motivationDaysToSchedule = 30

    func scheduleMotivationReminderIfNeeded(entries: [WorkEntry]) {
        guard motivationReminderEnabled else {
            cancelMotivationReminders()
            return
        }

        Task {
            let hasPermission = await notificationManager.hasPermission()
            guard hasPermission else { return }

            let calendar = Calendar.current
            let (hour, minute) = preferredMotivationTime(for: entries)

            await removePendingMotivationReminders()

            for dayOffset in 0..<Self.motivationDaysToSchedule {
                guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
                let dayStart = calendar.startOfDay(for: targetDate)
                let quote = MotivationalQuotes.quote(for: dayStart)

                var dateComponents = calendar.dateComponents([.year, .month, .day], from: dayStart)
                dateComponents.hour = hour
                dateComponents.minute = minute

                let content = UNMutableNotificationContent()
                content.title = "Daily motivation"
                content.body = quote
                content.sound = .default
                content.badge = 1

                let identifier = Self.motivationIdentifierPrefix + motivationDateKey(for: dayStart)
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    #if DEBUG
                    print("Failed to schedule motivation reminder for \(identifier): \(error)")
                    #endif
                }
            }
        }
    }

    func cancelMotivationReminders() {
        Task {
            await removePendingMotivationReminders()
        }
    }

    private func removePendingMotivationReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.motivationIdentifierPrefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Picks the usual first-shift start time from recent history, clamped to morning hours.
    private func preferredMotivationTime(for entries: [WorkEntry]) -> (hour: Int, minute: Int) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: Date()) else {
            return (8, 0)
        }

        let recent = entries.filter { !$0.isOffDay && $0.date >= cutoff }
        guard !recent.isEmpty else { return (8, 0) }

        // For each day, take earliest start time.
        var firstShiftByDay: [Date: Date] = [:]
        for entry in recent {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = firstShiftByDay[day] {
                if entry.start < existing {
                    firstShiftByDay[day] = entry.start
                }
            } else {
                firstShiftByDay[day] = entry.start
            }
        }

        var minutesOfDay: [Int] = firstShiftByDay.values.map {
            let comps = calendar.dateComponents([.hour, .minute], from: $0)
            return (comps.hour ?? 7) * 60 + (comps.minute ?? 0)
        }
        guard !minutesOfDay.isEmpty else { return (7, 0) }

        minutesOfDay.sort()
        let median = minutesOfDay[minutesOfDay.count / 2]
        let hour = median / 60
        let minute = median % 60

        // Keep daily motivation in the morning window.
        let clampedHour = min(max(hour, 5), 11)
        return (clampedHour, minute)
    }

    private func motivationDateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
    
    // MARK: - Streak notifications

    private static let streakAtRiskIdentifier = "streak_at_risk"
    private static let streakMilestonePrefix = "streak_milestone_"
    private static let streakMilestones: [Int] = [3, 5, 7, 10, 14, 21, 30, 50, 75, 100]

    func scheduleStreakNotificationsIfNeeded(entries: [WorkEntry], currentStreak: Int) {
        guard streakNotificationsEnabled else {
            cancelStreakNotifications()
            return
        }
        Task {
            let hasPermission = await notificationManager.hasPermission()
            guard hasPermission else { return }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let hasEntryToday = entries.contains { calendar.isDate($0.date, inSameDayAs: today) }

            // --- Streak at risk: fire tonight if they haven't logged today and have an active streak ---
            cancelStreakAtRisk()
            if currentStreak >= 1 && !hasEntryToday {
                var dateComponents = DateComponents()
                dateComponents.year = calendar.component(.year, from: today)
                dateComponents.month = calendar.component(.month, from: today)
                dateComponents.day = calendar.component(.day, from: today)
                dateComponents.hour = 20
                dateComponents.minute = 0

                let content = UNMutableNotificationContent()
                content.title = "Your streak is at risk! 🔥"
                content.body = "You have a \(currentStreak)-day streak. Log a shift today to keep it alive."
                content.sound = .default
                content.badge = 1

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: Self.streakAtRiskIdentifier, content: content, trigger: trigger)
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    #if DEBUG
                    print("Failed to schedule streak-at-risk notification: \(error)")
                    #endif
                }
            }

            // --- Streak milestone celebration (immediate, once per milestone) ---
            for milestone in Self.streakMilestones where currentStreak == milestone {
                let key = "streak_milestone_notified_\(milestone)"
                guard !UserDefaults.standard.bool(forKey: key) else { continue }
                UserDefaults.standard.set(true, forKey: key)

                let content = UNMutableNotificationContent()
                content.title = "\(milestone)-Day Streak! 🔥🔥🔥"
                content.body = streakMilestoneBody(for: milestone)
                content.sound = .default
                content.badge = 1

                let request = UNNotificationRequest(
                    identifier: Self.streakMilestonePrefix + "\(milestone)",
                    content: content,
                    trigger: nil
                )
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    await MainActor.run { Haptics.success() }
                } catch {
                    #if DEBUG
                    print("Failed to send streak milestone notification: \(error)")
                    #endif
                }
            }
        }
    }

    func cancelStreakNotifications() {
        cancelStreakAtRisk()
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.streakMilestonePrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    private func cancelStreakAtRisk() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.streakAtRiskIdentifier])
    }

    private func streakMilestoneBody(for days: Int) -> String {
        switch days {
        case 3: return "3 days strong. Building momentum."
        case 5: return "5 days in a row. You're locked in."
        case 7: return "Full week streak. Streak Freeze earned."
        case 10: return "Double digits. Most people don't make it this far."
        case 14: return "Two full weeks. Relentless."
        case 21: return "21 days — this is a habit now."
        case 30: return "30-day streak. Absolutely unstoppable."
        case 50: return "50-day streak. Elite discipline."
        case 75: return "75 days. You're a machine."
        case 100: return "100-day streak. Legendary status unlocked."
        default: return "Keep the streak alive."
        }
    }


    // MARK: - Work Anniversary Notification

    func scheduleWorkAnniversaryNotification(companyName: String, startDate: Date) {
        let center = UNUserNotificationCenter.current()
        let identifier = "work_anniversary_\(companyName.lowercased().replacingOccurrences(of: " ", with: "_"))"

        // Remove any existing anniversary notification for this company
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let cal = Calendar.current
        let startComponents = cal.dateComponents([.month, .day], from: startDate)
        guard let month = startComponents.month, let day = startComponents.day else { return }

        // Calculate next anniversary year
        let today = cal.startOfDay(for: Date())
        let thisYearAnniversary = cal.date(from: DateComponents(
            year: cal.component(.year, from: today),
            month: month, day: day
        )) ?? today
        let nextAnniversary = thisYearAnniversary < today
            ? cal.date(byAdding: .year, value: 1, to: thisYearAnniversary) ?? thisYearAnniversary
            : thisYearAnniversary
        let yearsCompleted = cal.dateComponents([.year], from: startDate, to: nextAnniversary).year ?? 1

        let content = UNMutableNotificationContent()
        content.title = "Work Anniversary! 🎉"
        content.body = anniversaryBody(companyName: companyName, years: yearsCompleted)
        content.sound = .default
        content.badge = 1

        // Fire at 9 AM on the anniversary date, repeating yearly
        var trigger = DateComponents()
        trigger.month = month
        trigger.day = day
        trigger.hour = 9
        trigger.minute = 0

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        )

        Task {
            do {
                try await center.add(request)
            } catch {
                #if DEBUG
                print("Failed to schedule anniversary notification: \(error)")
                #endif
            }
        }
    }

    private func anniversaryBody(companyName: String, years: Int) -> String {
        switch years {
        case 1:  return "1 year at \(companyName). Another year in the books — congrats! 🏆"
        case 2:  return "2 years strong at \(companyName). You're a veteran now."
        case 3:  return "3 years at \(companyName). Keep grinding — you're on a roll."
        case 5:  return "5 years at \(companyName). Half a decade of showing up. Respect. 💪"
        case 10: return "10 years at \(companyName). An absolute legend. 🔥"
        default:
            return "\(years) years at \(companyName). Another year in the books — congrats! 🎊"
        }
    }

    // MARK: - Friend activity

    func notifyFriendShiftLogged(authorName: String, body: String, eventId: String) async {
        guard friendShiftNotificationsEnabled else { return }
        guard await notificationManager.hasPermission() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your friend logged a shift!"
        content.body = "\(authorName) \(body)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.friendShiftPrefix + eventId,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("Failed to schedule friend shift notification: \(error)")
            #endif
        }
    }

    // MARK: - Permissions
    
    func requestPermissionsIfNeeded() async -> Bool {
        return await notificationManager.requestPermission()
    }
}
