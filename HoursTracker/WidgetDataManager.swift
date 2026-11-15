import Foundation
import WidgetKit

// MARK: - Widget Data Model

// Must stay in sync with HoursTrackerWidget/WidgetData.swift.
/// Projected pay for the current cheque, handed to the widgets and watch.
struct PayProjection: Equatable {
    let amount: Double
    let currencyCode: String
}

struct WidgetData: Codable {
    let hoursThisCheque: Double
    let hoursThisMonth: Double
    let hoursThisWeek: Double
    let nextPayday: Date?
    let lastUpdated: Date
    let currentStreak: Int
    let prestige: Int
    /// Paid hours on worked (non-off-day) entries dated today.
    let todayHours: Double
    /// True when any entry (worked or day off) exists for today.
    let todayLogged: Bool
    /// True when today's only entries are off days.
    let todayIsOffDay: Bool
    /// Start of the day the today* fields describe. A snapshot written
    /// yesterday must not report today as logged after midnight.
    let dataDay: Date?
    /// The week window (honouring "Week starts on") `hoursThisWeek` covers.
    let weekStart: Date?
    let weekEnd: Date?
    /// Weekly OT threshold when weekly overtime rules are on; nil otherwise.
    let weeklyTarget: Double?
    /// The current cheque's projected pay (nil when there's nothing to project).
    let projectedPay: Double?
    let currencyCode: String?

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
        case todayHours, todayLogged, todayIsOffDay, dataDay, weekStart, weekEnd, weeklyTarget
        case projectedPay, currencyCode
    }

    init(
        hoursThisCheque: Double,
        hoursThisMonth: Double,
        hoursThisWeek: Double,
        nextPayday: Date?,
        lastUpdated: Date,
        currentStreak: Int,
        prestige: Int,
        todayHours: Double = 0,
        todayLogged: Bool = false,
        todayIsOffDay: Bool = false,
        dataDay: Date? = nil,
        weekStart: Date? = nil,
        weekEnd: Date? = nil,
        weeklyTarget: Double? = nil,
        projectedPay: Double? = nil,
        currencyCode: String? = nil
    ) {
        self.hoursThisCheque = hoursThisCheque
        self.hoursThisMonth = hoursThisMonth
        self.hoursThisWeek = hoursThisWeek
        self.nextPayday = nextPayday
        self.lastUpdated = lastUpdated
        self.currentStreak = currentStreak
        self.prestige = prestige
        self.todayHours = todayHours
        self.todayLogged = todayLogged
        self.todayIsOffDay = todayIsOffDay
        self.dataDay = dataDay
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.weeklyTarget = weeklyTarget
        self.projectedPay = projectedPay
        self.currencyCode = currencyCode
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
        todayHours = try container.decodeIfPresent(Double.self, forKey: .todayHours) ?? 0
        todayLogged = try container.decodeIfPresent(Bool.self, forKey: .todayLogged) ?? false
        todayIsOffDay = try container.decodeIfPresent(Bool.self, forKey: .todayIsOffDay) ?? false
        dataDay = try container.decodeIfPresent(Date.self, forKey: .dataDay)
        weekStart = try container.decodeIfPresent(Date.self, forKey: .weekStart)
        weekEnd = try container.decodeIfPresent(Date.self, forKey: .weekEnd)
        weeklyTarget = try container.decodeIfPresent(Double.self, forKey: .weeklyTarget)
        projectedPay = try container.decodeIfPresent(Double.self, forKey: .projectedPay)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
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
    
    func updateWidgetData(entries: [WorkEntry], paySettings: PaySettings, prestige: Int, projection: PayProjection?) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let widgetData = self.calculateWidgetData(
                entries: entries,
                paySettings: paySettings,
                prestige: prestige,
                projection: projection
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
        prestige: Int,
        projection: PayProjection?
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
        
        // Calculate hours this week, honouring the "Week starts on" setting (Monday when unset)
        var weekCal = calendar
        weekCal.firstWeekday = paySettings.weekStartWeekday ?? 2
        let weekStart = weekCal.dateInterval(of: .weekOfYear, for: now)?.start ?? weekCal.startOfDay(for: now)
        let weekEnd = weekCal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? now
        let hoursThisWeek = entries
            .filter { $0.date >= weekStart && $0.date < weekEnd && !$0.isOffDay }
            .reduce(0) { $0 + $1.paidHours }

        // Today: logged at all (a day off counts — the user made the call),
        // and paid hours on worked entries.
        let todayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let todayWorked = todayEntries.filter { !$0.isOffDay }
        let todayHours = todayWorked.reduce(0) { $0 + $1.paidHours }

        // Weekly target only exists when weekly overtime rules are on.
        let usesWeeklyOT = paySettings.overtimeType == .weekly || paySettings.overtimeType == .dailyAndWeekly
        let weeklyTarget: Double? = usesWeeklyOT && paySettings.weeklyOvertimeThreshold > 0
            ? paySettings.weeklyOvertimeThreshold : nil

        // Calculate current streak
        let currentStreak = calculateCurrentStreak(entries: entries)
        
        return WidgetData(
            hoursThisCheque: hoursThisCheque,
            hoursThisMonth: hoursThisMonth,
            hoursThisWeek: hoursThisWeek,
            nextPayday: paySettings.nextPayday,
            lastUpdated: Date(),
            currentStreak: currentStreak,
            prestige: max(0, min(prestige, GamificationLevelCalculator.maxPrestige)),
            todayHours: todayHours,
            todayLogged: !todayEntries.isEmpty,
            todayIsOffDay: !todayEntries.isEmpty && todayWorked.isEmpty,
            dataDay: calendar.startOfDay(for: now),
            weekStart: weekStart,
            weekEnd: weekEnd,
            weeklyTarget: weeklyTarget,
            projectedPay: projection?.amount,
            currencyCode: projection?.currencyCode
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

// MARK: - Widget deep link

/// Routes the widgets' "Log today" tap (`<app scheme>://log-today`, built in
/// HoursTrackerWidget/WidgetTodayStatus.swift) into the existing Add Shift
/// flow via the same router flag win-back pushes raise. AppTabView consumes
/// it on change and on appear, so a cold launch from the widget works too.
enum WidgetDeepLink {
    static let logTodayHost = "log-today"

    @MainActor
    @discardableResult
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard url.host == logTodayHost else { return false }
        NotificationRouter.shared.openAddShift = true
        return true
    }
}
