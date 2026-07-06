import Foundation

/// Pure, testable analytics for share sheet. Computes metrics, trends, chart data, and breakdown from entries.
struct HoursAnalyticsCalculator {

    enum TimeRange: String, CaseIterable, Identifiable {
        case thisWeek = "This Week"
        case thisPayPeriod = "This Pay Period"
        case thisMonth = "This Month"
        var id: String { rawValue }
    }

    struct MetricTrend {
        let value: Double
        let percentChange: Int?  // e.g. +12 or -5; nil if no comparison
    }

    struct ChartPoint: Identifiable {
        let id = UUID()
        let label: String
        let date: Date
        let hours: Double
    }

    struct BreakdownRow {
        let title: String
        let value: String
        let progress: Double  // 0...1
    }

    struct Result {
        let totalHours: Double
        let averageShiftHours: Double
        let overtimeHours: Double
        let shiftsCount: Int
        let trendTotal: Int?
        let trendAverage: Int?
        let trendOvertime: Int?
        let trendShifts: Int?
        let chartPoints: [ChartPoint]
        let breakdown: [BreakdownRow]
    }

    /// - Parameters:
    ///   - entries: All work entries.
    ///   - range: Selected time range.
    ///   - overtimeHours: Overtime per entry (e.g. from pay breakdown).
    ///   - payPeriodInterval: For .thisPayPeriod, the (start, end) dates. Uses last `payPeriodFallbackDays` if nil.
    ///   - calendar: Calendar for boundaries.
    static func compute(
        entries: [WorkEntry],
        range: TimeRange,
        overtimeHours: (WorkEntry) -> Double,
        payPeriodInterval: (start: Date, end: Date)? = nil,
        payPeriodFallbackDays: Int = 14,
        calendar: Calendar = .current
    ) -> Result {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let now = Date()
        let (rangeStart, rangeEnd) = interval(for: range, now: now, payPeriodInterval: payPeriodInterval, payPeriodFallbackDays: payPeriodFallbackDays, calendar: cal)
        let inRange = entries.filter { !$0.isOffDay && $0.date >= rangeStart && $0.date < rangeEnd }

        let totalHours = inRange.reduce(0) { $0 + $1.paidHours }
        let count = inRange.count
        let averageShiftHours = count > 0 ? totalHours / Double(count) : 0
        let otHours = inRange.reduce(0) { $0 + overtimeHours($1) }
        let regularHours = totalHours - otHours

        let (prevStart, prevEnd) = previousInterval(for: range, now: now, payPeriodInterval: payPeriodInterval, payPeriodFallbackDays: payPeriodFallbackDays, calendar: cal)
        let prevInRange = entries.filter { !$0.isOffDay && $0.date >= prevStart && $0.date < prevEnd }
        let prevTotal = prevInRange.reduce(0) { $0 + $1.paidHours }
        let prevCount = prevInRange.count
        let prevAvg = prevCount > 0 ? prevTotal / Double(prevCount) : 0
        let prevOT = prevInRange.reduce(0) { $0 + overtimeHours($1) }

        let trendTotal = percentChange(current: totalHours, previous: prevTotal)
        let trendAverage = percentChange(current: averageShiftHours, previous: prevAvg)
        let trendOvertime = percentChange(current: otHours, previous: prevOT)
        let trendShifts = prevCount > 0 ? Int(round((Double(count) - Double(prevCount)) / Double(prevCount) * 100)) : nil

        let chartPoints = chartData(entries: inRange, range: range, payPeriodInterval: payPeriodInterval, payPeriodFallbackDays: payPeriodFallbackDays, calendar: cal)

        let maxHours = inRange.map(\.paidHours).max() ?? 0
        var breakdown: [BreakdownRow] = []
        if totalHours > 0 {
            breakdown.append(BreakdownRow(title: "Regular Hours", value: formatHours(regularHours), progress: maxHours > 0 ? regularHours / totalHours : 0))
            breakdown.append(BreakdownRow(title: "Overtime Hours", value: formatHours(otHours), progress: maxHours > 0 ? otHours / totalHours : 0))
        }

        return Result(
            totalHours: totalHours,
            averageShiftHours: averageShiftHours,
            overtimeHours: otHours,
            shiftsCount: count,
            trendTotal: trendTotal,
            trendAverage: trendAverage,
            trendOvertime: trendOvertime,
            trendShifts: trendShifts,
            chartPoints: chartPoints,
            breakdown: breakdown
        )
    }

    private static func interval(for range: TimeRange, now: Date, payPeriodInterval: (start: Date, end: Date)?, payPeriodFallbackDays: Int, calendar: Calendar) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        switch range {
        case .thisWeek:
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start {
                return (weekStart, end)
            }
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return (start, end)
        case .thisPayPeriod:
            if let pp = payPeriodInterval {
                return (pp.start, pp.end)
            }
            let fallbackStart = calendar.date(byAdding: .day, value: -payPeriodFallbackDays, to: dayStart) ?? dayStart
            return (fallbackStart, end)
        case .thisMonth:
            if let monthStart = calendar.dateInterval(of: .month, for: now)?.start {
                return (monthStart, end)
            }
            let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
            return (start, end)
        }
    }

    private static func previousInterval(for range: TimeRange, now: Date, payPeriodInterval: (start: Date, end: Date)?, payPeriodFallbackDays: Int, calendar: Calendar) -> (start: Date, end: Date) {
        let (currStart, currEnd) = interval(for: range, now: now, payPeriodInterval: payPeriodInterval, payPeriodFallbackDays: payPeriodFallbackDays, calendar: calendar)
        let span = currEnd.timeIntervalSince(currStart)
        let prevEnd = currStart
        let prevStart = prevEnd.addingTimeInterval(-span)
        return (prevStart, prevEnd)
    }

    private static func percentChange(current: Double, previous: Double) -> Int? {
        guard previous > 0 else { return nil }
        let pct = ((current - previous) / previous) * 100
        let rounded = Int(round(pct))
        return rounded == 0 ? nil : rounded
    }

    private static func chartData(entries: [WorkEntry], range: TimeRange, payPeriodInterval: (start: Date, end: Date)?, payPeriodFallbackDays: Int, calendar: Calendar) -> [ChartPoint] {
        let (rangeStart, rangeEnd) = interval(for: range, now: Date(), payPeriodInterval: payPeriodInterval, payPeriodFallbackDays: payPeriodFallbackDays, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current

        switch range {
        case .thisWeek:
            formatter.dateFormat = "EEE"
            var dayToHours: [Date: Double] = [:]
            var d = rangeStart
            while d < rangeEnd {
                dayToHours[calendar.startOfDay(for: d)] = 0
                guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
            for e in entries {
                let day = calendar.startOfDay(for: e.date)
                dayToHours[day, default: 0] += e.paidHours
            }
            return dayToHours.keys.sorted().map { day in
                ChartPoint(label: formatter.string(from: day), date: day, hours: dayToHours[day] ?? 0)
            }
        case .thisPayPeriod, .thisMonth:
            formatter.dateFormat = "M/d"
            var dayToHours: [Date: Double] = [:]
            var d = rangeStart
            while d < rangeEnd {
                dayToHours[calendar.startOfDay(for: d)] = 0
                guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
            for e in entries {
                let day = calendar.startOfDay(for: e.date)
                dayToHours[day, default: 0] += e.paidHours
            }
            return dayToHours.keys.sorted().map { day in
                ChartPoint(label: formatter.string(from: day), date: day, hours: dayToHours[day] ?? 0)
            }
        }
    }

    private static func formatHours(_ h: Double) -> String {
        AppTheme.Format.hours(h, suffix: "")
    }

    private static func formatDay(_ d: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}
