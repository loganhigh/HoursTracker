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
