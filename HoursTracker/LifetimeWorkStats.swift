import Foundation

// MARK: - Lifetime work stats
//
// Everything the You tab's lifetime grid and Career sections need, computed
// in ONE pass over the merged history instead of one full scan per stat.
// Built and cached by `HoursStore.lifetimeWorkStats()`.

struct LifetimeWorkStats {
    /// Worked entries only (off days excluded), newest first.
    let workEntries: [WorkEntry]
    let shiftCount: Int
    let localTotalHours: Double
    let longestShiftHours: Double
    let daysWorked: Int
    let monthsTracked: Int
    let firstEntryDate: Date?
    /// Best calendar month by paid hours: (month start, hours).
    let bestMonth: (start: Date, hours: Double)?
    /// Paid hours and distinct days, keyed by the start of each worked day.
    /// Lets "since company start" stats filter without rescanning entries.
    let hoursByDay: [Date: Double]

    init(entries: [WorkEntry]) {
        let cal = Calendar.current
        var worked: [WorkEntry] = []
        worked.reserveCapacity(entries.count)
        var total = 0.0
        var longest = 0.0
        var hoursByDay: [Date: Double] = [:]
        var months = Set<DateComponents>()
        var byMonth: [DateComponents: Double] = [:]
        var first: Date?

        for entry in entries where !entry.isOffDay {
            worked.append(entry)
            let hours = entry.paidHours
            total += hours
            longest = max(longest, hours)
            hoursByDay[cal.startOfDay(for: entry.date), default: 0] += hours
            let month = cal.dateComponents([.year, .month], from: entry.date)
            months.insert(month)
            byMonth[month, default: 0] += hours
            if first == nil || entry.date < first! { first = entry.date }
        }

        workEntries = worked
        shiftCount = worked.count
        localTotalHours = total
        longestShiftHours = longest
        daysWorked = hoursByDay.count
        monthsTracked = months.count
        firstEntryDate = first
        self.hoursByDay = hoursByDay
        if let top = byMonth.max(by: { $0.value < $1.value }),
           let start = cal.date(from: DateComponents(year: top.key.year, month: top.key.month, day: 1)) {
            bestMonth = (start, top.value)
        } else {
            bestMonth = nil
        }
    }

    /// Paid hours on or after the start of `day`.
    func hours(since day: Date) -> Double {
        let startDay = Calendar.current.startOfDay(for: day)
        return hoursByDay.reduce(0) { $0 + ($1.key >= startDay ? $1.value : 0) }
    }

    /// Distinct worked days on or after the start of `day`.
    func daysWorked(since day: Date) -> Int {
        let startDay = Calendar.current.startOfDay(for: day)
        return hoursByDay.keys.reduce(0) { $0 + ($1 >= startDay ? 1 : 0) }
    }
}
