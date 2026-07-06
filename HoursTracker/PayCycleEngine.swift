import Foundation

// MARK: - Pay cycle model

/// One pay period for a cheque: work hours in `[start, end)` where `end` is the day after cutoff.
struct PayCycle: Identifiable, Hashable {
    /// Stable id: period start at start-of-day.
    var id: Date { start }
    let start: Date
    /// Exclusive upper bound (start-of-day after the last included work day).
    let end: Date
    /// Last calendar day of work included on this cheque (inclusive).
    let cutoff: Date
    /// When this cheque is paid.
    let payday: Date
    /// Relative index when built in a list (e.g. 0 = selected); default 0.
    var index: Int

    var spanDays: Int {
        max(1, Int(round(end.timeIntervalSince(start) / 86400)))
    }

    /// Human-readable work window for this cheque.
    func workRangeText(dateFormat: String = "MMM d") -> String {
        let df = DateFormatter()
        df.dateFormat = dateFormat
        return "\(df.string(from: start)) – \(df.string(from: cutoff))"
    }

    /// Work window plus payday when cutoff differs from pay date.
    func chequeRangeText(dateFormat: String = "MMM d", settings: PaySettings, calendar: Calendar = .current) -> String {
        let work = workRangeText(dateFormat: dateFormat)
        guard PayCycleEngine.usesSavedCutoff(settings) else { return work }
        let df = DateFormatter()
        df.dateFormat = dateFormat
        let today = calendar.startOfDay(for: Date())
        let payDay = calendar.startOfDay(for: payday)
        let payLabel = payDay < today ? "Paid" : "Pay"
        return "\(work) · \(payLabel) \(df.string(from: payday))"
    }
}

// MARK: - Engine

enum PayCycleEngine {

    static func spanDays(for type: PayPeriodType) -> Int {
        switch type {
        case .weekly: return 7
        case .biWeekly: return 14
        }
    }

    /// When `nextPayday` is unset, anchor `span` days forward from today (matches prior RootView fallback).
    static func fallbackNextPayday(settings: PaySettings, calendar: Calendar = .current) -> Date {
        let cal = calendar
        let span = spanDays(for: settings.payPeriodType)
        let now = Date()
        return cal.startOfDay(for: cal.date(byAdding: .day, value: span, to: now) ?? now)
    }

    /// Normalized upcoming payday boundary from settings (start of day).
    static func normalizedPaydayBoundary(settings: PaySettings, calendar: Calendar = .current) -> Date {
        let cal = calendar
        if let p = settings.nextPayday {
            return cal.startOfDay(for: p)
        }
        return fallbackNextPayday(settings: settings, calendar: cal)
    }

    /// Cutoff is only active when the user turned it on and picked a date.
    static func usesSavedCutoff(_ settings: PaySettings) -> Bool {
        settings.payPeriodUsesCutoff && settings.nextCutoff != nil
    }

    /// Normalized upcoming cutoff from settings (start of day).
    static func normalizedCutoffBoundary(settings: PaySettings, calendar: Calendar = .current) -> Date? {
        guard usesSavedCutoff(settings), let cutoff = settings.nextCutoff else { return nil }
        return calendar.startOfDay(for: cutoff)
    }

    /// Days from cutoff until payday, based on the user's saved dates.
    static func cutoffPaydayLagDays(settings: PaySettings, calendar: Calendar = .current) -> Int {
        let cal = calendar
        guard usesSavedCutoff(settings),
              let cutoff = settings.nextCutoff,
              let payday = settings.nextPayday else { return 0 }
        let lag = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: cutoff),
            to: cal.startOfDay(for: payday)
        ).day ?? 0
        return max(0, lag)
    }

    private static func payday(forCutoff cutoff: Date, settings: PaySettings, calendar: Calendar = .current) -> Date {
        let cal = calendar
        let cutoffDay = cal.startOfDay(for: cutoff)
        let lag = cutoffPaydayLagDays(settings: settings, calendar: cal)
        return cal.date(byAdding: .day, value: lag, to: cutoffDay) ?? cutoffDay
    }

    private static func makeCycleFromCutoff(
        _ cutoff: Date,
        settings: PaySettings,
        index: Int = 0,
        calendar: Calendar = .current
    ) -> PayCycle {
        let cal = calendar
        let span = spanDays(for: settings.payPeriodType)
        let cutoffDay = cal.startOfDay(for: cutoff)
        let end = cal.date(byAdding: .day, value: 1, to: cutoffDay)
            ?? cutoffDay.addingTimeInterval(86400)
        let start = cal.date(byAdding: .day, value: -span, to: end)
            ?? end.addingTimeInterval(Double(-span) * 86400)
        let paydayStart = cal.startOfDay(for: payday(forCutoff: cutoffDay, settings: settings, calendar: cal))
        return PayCycle(
            start: cal.startOfDay(for: start),
            end: cal.startOfDay(for: end),
            cutoff: cutoffDay,
            payday: paydayStart,
            index: index
        )
    }

    /// Pay period ending on payday — all logged hours before payday count on the cheque.
    private static func makeCycle(
        payday: Date,
        settings: PaySettings,
        index: Int = 0,
        calendar: Calendar = .current
    ) -> PayCycle {
        let cal = calendar
        let span = spanDays(for: settings.payPeriodType)
        let paydayStart = cal.startOfDay(for: payday)
        let end = paydayStart
        let start = cal.date(byAdding: .day, value: -span, to: end)
            ?? end.addingTimeInterval(Double(-span) * 86400)
        let cutoffDay = cal.date(byAdding: .day, value: -1, to: end) ?? start
        return PayCycle(
            start: cal.startOfDay(for: start),
            end: end,
            cutoff: cal.startOfDay(for: cutoffDay),
            payday: paydayStart,
            index: index
        )
    }

    /// The pay period / cheque that contains `date`.
    static func cycle(containing date: Date, settings: PaySettings, calendar: Calendar = .current) -> PayCycle {
        let cal = calendar
        let d = cal.startOfDay(for: date)
        let span = spanDays(for: settings.payPeriodType)

        if usesSavedCutoff(settings), let anchor = normalizedCutoffBoundary(settings: settings, calendar: cal) {
            var cutoff = anchor
            var cycle = makeCycleFromCutoff(cutoff, settings: settings, calendar: cal)

            while d < cycle.start {
                cutoff = cal.date(byAdding: .day, value: -span, to: cutoff)
                    ?? cutoff.addingTimeInterval(Double(-span) * 86400)
                cycle = makeCycleFromCutoff(cutoff, settings: settings, calendar: cal)
            }

            while d >= cycle.end {
                if d < cycle.payday { break }
                cutoff = cal.date(byAdding: .day, value: span, to: cutoff)
                    ?? cutoff.addingTimeInterval(Double(span) * 86400)
                cycle = makeCycleFromCutoff(cutoff, settings: settings, calendar: cal)
            }

            return cycle
        }

        var payday = normalizedPaydayBoundary(settings: settings, calendar: cal)
        var cycle = makeCycle(payday: payday, settings: settings, calendar: cal)

        while d < cycle.start {
            payday = cal.date(byAdding: .day, value: -span, to: payday)
                ?? payday.addingTimeInterval(Double(-span) * 86400)
            cycle = makeCycle(payday: payday, settings: settings, calendar: cal)
        }

        while d >= cycle.end {
            if usesSavedCutoff(settings) && d < cycle.payday {
                break
            }
            payday = cal.date(byAdding: .day, value: span, to: payday)
                ?? payday.addingTimeInterval(Double(span) * 86400)
            cycle = makeCycle(payday: payday, settings: settings, calendar: cal)
        }

        return cycle
    }

    static func currentCycle(settings: PaySettings, asOf date: Date = Date(), calendar: Calendar = .current) -> PayCycle {
        cycle(containing: date, settings: settings, calendar: calendar)
    }

    static func entries(_ all: [WorkEntry], in cycle: PayCycle) -> [WorkEntry] {
        all.filter { $0.date >= cycle.start && $0.date < cycle.end }
            .sorted { $0.date > $1.date }
    }

    /// Labels to show under an entry's hours when its date is the cheque cutoff and/or payday.
    static func periodDayMarkerLabels(
        for date: Date,
        settings: PaySettings,
        calendar: Calendar = .current
    ) -> [String] {
        let cal = calendar
        let day = cal.startOfDay(for: date)
        let cycle = cycle(containing: date, settings: settings, calendar: cal)
        var labels: [String] = []
        if day == cal.startOfDay(for: cycle.cutoff) {
            labels.append("Cutoff")
        }
        if day == cal.startOfDay(for: cycle.payday) {
            labels.append("PayDay")
        }
        return labels
    }

    static func previousCycle(before cycle: PayCycle, settings: PaySettings, calendar: Calendar = .current) -> PayCycle {
        let cal = calendar
        let span = spanDays(for: settings.payPeriodType)

        if usesSavedCutoff(settings) {
            let prevCutoff = cal.date(byAdding: .day, value: -span, to: cycle.cutoff)
                ?? cycle.cutoff.addingTimeInterval(Double(-span) * 86400)
            var prev = makeCycleFromCutoff(prevCutoff, settings: settings, calendar: cal)
            prev.index = cycle.index - 1
            return prev
        }

        let prevPayday = cal.date(byAdding: .day, value: -span, to: cycle.payday)
            ?? cycle.payday.addingTimeInterval(Double(-span) * 86400)
        var prev = makeCycle(payday: prevPayday, settings: settings, calendar: cal)
        prev.index = cycle.index - 1
        return prev
    }

    static func nextCycle(after cycle: PayCycle, settings: PaySettings, calendar: Calendar = .current) -> PayCycle {
        let cal = calendar
        let span = spanDays(for: settings.payPeriodType)

        if usesSavedCutoff(settings) {
            let nextCutoff = cal.date(byAdding: .day, value: span, to: cycle.cutoff)
                ?? cycle.cutoff.addingTimeInterval(Double(span) * 86400)
            var next = makeCycleFromCutoff(nextCutoff, settings: settings, calendar: cal)
            next.index = cycle.index + 1
            return next
        }

        let nextPayday = cal.date(byAdding: .day, value: span, to: cycle.payday)
            ?? cycle.payday.addingTimeInterval(Double(span) * 86400)
        var next = makeCycle(payday: nextPayday, settings: settings, calendar: cal)
        next.index = cycle.index + 1
        return next
    }

    /// Most recent `count` cycles: index 0 = cycle containing `reference`, then older periods.
    static func cycles(endingAtOrBefore reference: Date, count: Int, settings: PaySettings, calendar: Calendar = .current) -> [PayCycle] {
        guard count > 0 else { return [] }
        var first = cycle(containing: reference, settings: settings, calendar: calendar)
        first.index = 0
        var list: [PayCycle] = [first]
        for i in 1..<count {
            var prev = previousCycle(before: list[i - 1], settings: settings, calendar: calendar)
            prev.index = -i
            list.append(prev)
        }
        return list
    }

    /// `count` periods ending at or before today, oldest last (for horizontal pickers).
    static func recentCyclesEndingBeforeNow(settings: PaySettings, count: Int, calendar: Calendar = .current) -> [PayCycle] {
        cycles(endingAtOrBefore: Date(), count: count, settings: settings, calendar: calendar)
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols[index]
    }

    /// Days between cutoff day and payday (e.g. Saturday → Friday = 6).
    static func inferredDaysFromCutoffToPayday(
        cutoffWeekday: Int,
        payday: Date,
        calendar: Calendar = .current
    ) -> Int {
        let paydayWeekday = calendar.component(.weekday, from: payday)
        let diff = (paydayWeekday - cutoffWeekday + 7) % 7
        return diff == 0 ? 7 : diff
    }

    /// The cheque paid on a specific payday (for settings previews).
    static func cycle(forPayday payday: Date, settings: PaySettings, calendar: Calendar = .current) -> PayCycle {
        if usesSavedCutoff(settings) {
            let lag = cutoffPaydayLagDays(settings: settings, calendar: calendar)
            let cutoff = calendar.date(byAdding: .day, value: -lag, to: calendar.startOfDay(for: payday))
                ?? calendar.startOfDay(for: payday)
            return makeCycleFromCutoff(cutoff, settings: settings, calendar: calendar)
        }
        return makeCycle(payday: payday, settings: settings, calendar: calendar)
    }
}
