import Foundation
import WidgetKit

// MARK: - Widget Data Model

struct WidgetData: Codable {
    let hoursThisCheque: Double
    let hoursThisMonth: Double
    let hoursThisWeek: Double
    let nextPayday: Date?
    let lastUpdated: Date
    let currentStreak: Int
    let prestige: Int
    
    static var empty: WidgetData {
        WidgetData(
            hoursThisCheque: 0,
            hoursThisMonth: 0,
            hoursThisWeek: 0,
            nextPayday: nil,
            lastUpdated: Date(),
            currentStreak: 0,
            prestige: 0
        )
    }

    enum CodingKeys: String, CodingKey {
        case hoursThisCheque, hoursThisMonth, hoursThisWeek, nextPayday, lastUpdated, currentStreak, prestige
    }

    init(
        hoursThisCheque: Double,
        hoursThisMonth: Double,
        hoursThisWeek: Double,
        nextPayday: Date?,
        lastUpdated: Date,
        currentStreak: Int,
        prestige: Int
    ) {
        self.hoursThisCheque = hoursThisCheque
        self.hoursThisMonth = hoursThisMonth
        self.hoursThisWeek = hoursThisWeek
        self.nextPayday = nextPayday
        self.lastUpdated = lastUpdated
        self.currentStreak = currentStreak
        self.prestige = prestige
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hoursThisCheque = try container.decode(Double.self, forKey: .hoursThisCheque)
        hoursThisMonth = try container.decode(Double.self, forKey: .hoursThisMonth)
        hoursThisWeek = try container.decodeIfPresent(Double.self, forKey: .hoursThisWeek) ?? 0
        nextPayday = try container.decodeIfPresent(Date.self, forKey: .nextPayday)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        prestige = try container.decodeIfPresent(Int.self, forKey: .prestige) ?? 0
    }
}

// MARK: - Widget Data Manager

class WidgetDataManager {
    static let shared = WidgetDataManager()
    
    // IMPORTANT: Update this to match your actual App Group ID
    private let appGroupID = "group.com.loganh.HourTracker"
    private let widgetDataKey = "widget_data"
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    private init() {}
    
    // MARK: - Update Widget Data
    
    func updateWidgetData(entries: [WorkEntry], paySettings: PaySettings, prestige: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let widgetData = self.calculateWidgetData(
                entries: entries,
                paySettings: paySettings,
                prestige: prestige
            )
            self.saveWidgetData(widgetData)
            DispatchQueue.main.async {
                self.reloadAllWidgets()
            }
        }
    }
    
    private func calculateWidgetData(
        entries: [WorkEntry],
        paySettings: PaySettings,
        prestige: Int
    ) -> WidgetData {
        let calendar = Calendar.current
        let now = Date()
        
        // Calculate hours this cheque (current pay period)
        let cycle = PayCycleEngine.currentCycle(settings: paySettings, asOf: now, calendar: calendar)
        let hoursThisCheque = entries
            .filter { $0.date >= cycle.start && $0.date < cycle.end }
            .reduce(0) { $0 + $1.paidHours }
        
        // Calculate hours this month
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
        let hoursThisMonth = entries
            .filter { $0.date >= monthStart && $0.date < monthEnd }
            .reduce(0) { $0 + $1.paidHours }
        
        // Calculate hours this week (Mon–Sun, respecting firstWeekday)
        var weekCal = calendar
        weekCal.firstWeekday = 2 // Monday
        let weekStart = weekCal.dateInterval(of: .weekOfYear, for: now)?.start ?? weekCal.startOfDay(for: now)
        let weekEnd = weekCal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? now
        let hoursThisWeek = entries
            .filter { $0.date >= weekStart && $0.date < weekEnd && !$0.isOffDay }
            .reduce(0) { $0 + $1.paidHours }

        // Calculate current streak
        let currentStreak = calculateCurrentStreak(entries: entries)
        
        return WidgetData(
            hoursThisCheque: hoursThisCheque,
            hoursThisMonth: hoursThisMonth,
            hoursThisWeek: hoursThisWeek,
            nextPayday: paySettings.nextPayday,
            lastUpdated: Date(),
            currentStreak: currentStreak,
            prestige: max(0, min(prestige, 10))
        )
    }
    
    private func calculateCurrentStreak(entries: [WorkEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }

        let cal = Calendar.current
        // Only actually-worked days count, and the streak is "current" only if the
        // most recent worked day is today or yesterday. Without these guards the
        // widget shows an ever-growing streak fed by auto-filled off-days that
        // never resets. Mirrors HoursStore.currentWorkStreak().
        let workDates = Set(
            entries.filter { !$0.isOffDay }.map { cal.startOfDay(for: $0.date) }
        ).sorted(by: >)

        guard let mostRecent = workDates.first else { return 0 }

        let today = cal.startOfDay(for: Date())
        let daysSinceLastWork = cal.dateComponents([.day], from: mostRecent, to: today).day ?? 99
        guard daysSinceLastWork <= 1 else { return 0 }

        var streak = 1
        var currentDate = mostRecent

        for i in 1..<workDates.count {
            let previousDate = workDates[i]
            let daysDiff = cal.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            
            if daysDiff == 1 {
                streak += 1
                currentDate = previousDate
            } else {
                break
            }
        }
        
        return streak
    }
    
    // MARK: - Save & Load
    
    private func saveWidgetData(_ data: WidgetData) {
        guard let defaults = sharedDefaults else {
            #if DEBUG
            print("WidgetDataManager: Failed to access shared UserDefaults")
            #endif
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encoded = try encoder.encode(data)
            defaults.set(encoded, forKey: widgetDataKey)
            
            #if DEBUG
            print("WidgetDataManager: Data saved successfully")
            #endif
        } catch {
            #if DEBUG
            print("WidgetDataManager: Failed to encode widget data: \(error)")
            #endif
        }
    }
    
    func getWidgetData() -> WidgetData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: widgetDataKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetData.self, from: data)
        } catch {
            #if DEBUG
            print("WidgetDataManager: Failed to decode widget data: \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Reload Widgets
    
    func reloadAllWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #if DEBUG
        print("WidgetDataManager: All widgets reloaded")
        #endif
        #endif
    }
}
