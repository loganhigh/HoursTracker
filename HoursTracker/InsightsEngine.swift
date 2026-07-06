import Foundation

/// Time range for insights. Drives filtering and all calculations.
enum InsightsTimeRange: String, CaseIterable {
    case last7 = "Last 7 Days"
    case last30 = "Last 30 Days"
    case last90 = "Last 90 Days"
    case thisYear = "This Year"
    /// For month report; use `month(_:)` to construct.
    case month = "Month"
}

/// Use for month-report insights (filter to a specific month).
struct MonthRange {
    let date: Date
}

/// Pure, testable insights engine. Uses stored shift data only.
struct InsightsEngine {

    struct Insight: Identifiable {
        let id: String
        let icon: String
        let title: String?
        let message: String
    }

    /// - Parameters:
    ///   - entries: All work entries (will be filtered by timeRange).
    ///   - timeRange: .last7 / .last30 / .last90 / .thisYear, or .month with monthRange.
    ///   - monthRange: Required when timeRange == .month.
    ///   - calendar: Calendar for intervals.
    /// - Returns: Insights from real data. Omits when insufficient data.
    static func compute(
        entries: [WorkEntry],
        timeRange: InsightsTimeRange,
        monthRange: MonthRange? = nil,
        calendar: Calendar = .current
    ) -> [Insight] {
        let work = entries.filter { !$0.isOffDay }
        let (start, end) = interval(for: timeRange, monthRange: monthRange, calendar: calendar)
        let inRange = work.filter { $0.date >= start && $0.date < end }

        var result: [Insight] = []

        // 1) Busiest month (this year, always)
        if let busiest = busiestMonth(entries: work, calendar: calendar) {
            result.append(busiest)
        }

        // 2) Average shift length (over selected range)
        if let avg = averageShiftLength(entries: inRange) {
            result.append(avg)
        }

        // 3) Longest streak (over selected range)
        if let streak = longestStreak(entries: inRange, calendar: calendar) {
            result.append(streak)
        }

        // 4) Month-over-month % (current vs previous month)
        if let mom = monthOverMonth(entries: work, calendar: calendar) {
            result.append(mom)
        }

        return result
    }

    // MARK: - Interval

    private static func interval(
        for range: InsightsTimeRange,
        monthRange: MonthRange?,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let now = Date()
        switch range {
        case .last7:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return (start, end)
        case .last30:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
            return (start, end)
        case .last90:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(byAdding: .day, value: -90, to: end) ?? end
            return (start, end)
        case .thisYear:
            guard let yearStart = calendar.dateInterval(of: .year, for: now)?.start,
                  let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
                return (now, now)
            }
            return (yearStart, yearEnd)
        case .month:
            guard let m = monthRange else { return (now, now) }
            guard let monthStart = calendar.dateInterval(of: .month, for: m.date)?.start,
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return (now, now)
            }
            return (monthStart, monthEnd)
        }
    }

    // MARK: - A) Busiest month (this year)

    private static func busiestMonth(entries: [WorkEntry], calendar: Calendar) -> Insight? {
        let now = Date()
        guard let yearStart = calendar.dateInterval(of: .year, for: now)?.start,
              let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else { return nil }
        let inYear = entries.filter { $0.date >= yearStart && $0.date < yearEnd }
        var byMonth: [Date: Double] = [:]
        for e in inYear {
            guard let m = calendar.dateInterval(of: .month, for: e.date)?.start else { continue }
            byMonth[m, default: 0] += e.paidHours
        }
        guard let (busiestStart, hours) = byMonth.max(by: { $0.value < $1.value }),
              hours > 0, byMonth.count >= 2 else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM"
        let monthName = formatter.string(from: busiestStart)
        let thisStart = calendar.dateInterval(of: .month, for: now)?.start

        if thisStart == busiestStart {
            return Insight(
                id: "busiest_month",
                icon: "star.fill",
                title: nil,
                message: "This is your busiest month so far this year."
            )
        }
        return Insight(
            id: "busiest_month",
            icon: "star.fill",
            title: nil,
            message: "Your busiest month so far this year is \(monthName) with \(formatOneDecimal(hours)) hours."
        )
    }

    // MARK: - B) Month-over-month %

    private static func monthOverMonth(entries: [WorkEntry], calendar: Calendar) -> Insight? {
        let now = Date()
        guard let thisStart = calendar.dateInterval(of: .month, for: now)?.start,
              let thisEnd = calendar.date(byAdding: .month, value: 1, to: thisStart),
              let lastStart = calendar.date(byAdding: .month, value: -1, to: thisStart) else { return nil }
        let thisMonth = entries.filter { $0.date >= thisStart && $0.date < thisEnd }
        let lastMonth = entries.filter { $0.date >= lastStart && $0.date < thisStart }
        let thisHours = thisMonth.reduce(0) { $0 + $1.paidHours }
        let lastHours = lastMonth.reduce(0) { $0 + $1.paidHours }

        if lastHours <= 0 {
            if thisHours > 0 {
                return Insight(
                    id: "mom",
                    icon: "chart.line.uptrend.xyaxis",
                    title: nil,
                    message: "Not enough data to compare to last month."
                )
            }
            return nil
        }

        let pct = ((thisHours - lastHours) / lastHours) * 100
        let rounded = Int(round(abs(pct)))
        if rounded < 1 { return nil }
        let more = pct > 0
        return Insight(
            id: "mom",
            icon: more ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
            title: nil,
            message: more
                ? "You worked \(rounded)% more this month than last month."
                : "You worked \(rounded)% less this month than last month."
        )
    }

    // MARK: - C) Average shift length

    private static func averageShiftLength(entries: [WorkEntry]) -> Insight? {
        let valid = entries.filter { $0.paidHours > 0 }
        guard !valid.isEmpty else { return nil }
        let total = valid.reduce(0) { $0 + $1.paidHours }
        let avg = total / Double(valid.count)
        return Insight(
            id: "avg_shift",
            icon: "clock.fill",
            title: nil,
            message: "Your average shift length is \(AppTheme.Format.hours(avg, suffix: "")) hours."
        )
    }

    // MARK: - D) Longest streak (worked days in a row)

    private static func longestStreak(entries: [WorkEntry], calendar: Calendar) -> Insight? {
        let days = Set(entries.filter { $0.paidHours > 0 }.map { calendar.startOfDay(for: $0.date) })
        let sorted = days.sorted()
        guard !sorted.isEmpty else { return nil }
        var best = 1
        var cur = 1
        for i in 1..<sorted.count {
            let gap = calendar.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 999
            if gap == 1 { cur += 1 } else { best = max(best, cur); cur = 1 }
        }
        let n = max(best, cur)
        guard n >= 1 else { return nil }
        return Insight(
            id: "longest_streak",
            icon: "flame.fill",
            title: nil,
            message: "Your longest streak was \(n) days in a row."
        )
    }

    private static func formatOneDecimal(_ value: Double) -> String {
        AppTheme.Format.hours(value, suffix: "")
    }
}
