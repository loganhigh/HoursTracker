import Foundation

// Shared data model read by the widget from the App Group UserDefaults.
// Must stay in sync with WidgetDataManager.swift in the main app target.
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

    // Loads latest data from the shared App Group UserDefaults
    static func load() -> WidgetData {
        let appGroupID = "group.com.loganh.HourTracker"
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: "widget_data")
        else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetData.self, from: data)) ?? .empty
    }
}
