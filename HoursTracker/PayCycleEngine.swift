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
        guard PayCycleEngine.usesCutoffAnchoring(settings) else { return work }
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

    /// "Week starts on" is active only without an explicit cutoff — the saved
    /// cutoff date is the more specific instruction and wins.
    static func usesWeekStart(_ settings: PaySettings) -> Bool {
        !usesSavedCutoff(settings) && (settings.weekStartWeekday.map { (1...7).contains($0) } ?? false)
    }

    /// Cutoff anchor derived from "week starts on": the period's last day is
    /// the day before the chosen week start, placed within the week before
    /// payday. E.g. weeks starting Sunday with a Friday payday → cutoff
    /// Saturday, paid 6 days later — periods tile Sun–Sat while pay stays on
    /// the real payday.
    static func derivedWeekStartCutoff(settings: PaySettings, calendar: Calendar = .current) -> Date? {
        guard usesWeekStart(settings), let weekStart = settings.weekStartWeekday else { return nil }
        let cal = calendar
        let payday = normalizedPaydayBoundary(settings: settings, calendar: cal)
        let cutoffWeekday = weekStart == 1 ? 7 : weekStart - 1
        let lag = inferredDaysFromCutoffToPayday(cutoffWeekday: cutoffWeekday, payday: payday, calendar: cal)
        return cal.date(byAdding: .day, value: -lag, to: payday)
    }

    /// The active cutoff anchor: the explicit saved date, else the one derived
    /// from "week starts on", else nil (payday-anchored periods).
    static func activeCutoffAnchor(settings: PaySettings, calendar: Calendar = .current) -> Date? {
        normalizedCutoffBoundary(settings: settings, calendar: calendar)
            ?? derivedWeekStartCutoff(settings: settings, calendar: calendar)
    }

    /// Whether periods are anchored to a cutoff (saved or derived) rather than
    /// directly to payday.
    static func usesCutoffAnchoring(_ settings: PaySettings) -> Bool {
        usesSavedCutoff(settings) || usesWeekStart(settings)
    }

    /// Days from cutoff until payday, based on the user's saved dates.
    static func cutoffPaydayLagDays(settings: PaySettings, calendar: Calendar = .current) -> Int {
        let cal = calendar
        if usesWeekStart(settings), let weekStart = settings.weekStartWeekday {
            let payday = normalizedPaydayBoundary(settings: settings, calendar: cal)
            let cutoffWeekday = weekStart == 1 ? 7 : weekStart - 1
            return inferredDaysFromCutoffToPayday(cutoffWeekday: cutoffWeekday, payday: payday, calendar: cal)
        }
        guard usesSavedCutoff(settings),
              let cutoff = settings.nextCutoff,
              let payday = settings.nextPayday else { return 0 }
        var lag = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: cutoff),
            to: cal.startOfDay(for: payday)
        ).day ?? 0
        // A cutoff AFTER the saved payday is a legitimate way to describe the
        // schedule (onboarded between cutoff and payday: "my next payday is
        // Aug 28, my next cutoff is Sep 5"). The payday then belongs to the
        // cheque whose cutoff came one period earlier, so the lag is that
        // period's worth later — not 0, which made every payday equal its
        // cutoff and reported cheques as paid a week before they were.
        let span = spanDays(for: settings.payPeriodType)
        while lag < 0, span > 0 { lag += span }
        return max(0, lag)
    }

    /// Whether `date` is a payday in the user's schedule — independent of
    /// `nextPayday`, which is deliberately advanced past today on payday
    /// morning (the cycle rolls at payday), so comparing against it can
    /// never match "today". Paydays sit at or after the END of the cycle they
    /// pay for, so walk from the cycle containing `date` back a few cycles.
    static func isPayday(_ date: Date, settings: PaySettings, calendar: Calendar = .current) -> Bool {
        let cal = calendar
        let day = cal.startOfDay(for: date)
        var cycle = cycle(containing: day, settings: settings, calendar: cal)
        for _ in 0..<4 {
            if cal.startOfDay(for: cycle.payday) == day { return true }
            cycle = previousCycle(before: cycle, settings: settings, calendar: cal)
        }
        return false
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
    ///
    /// Rolls over the moment the cutoff passes: the day after cutoff belongs to
    /// the NEXT accumulating cheque, even though the finished cheque hasn't been
    /// paid yet. "This cheque" is always the one hours are currently landing on;
    /// the just-cut-off cheque becomes "last cheque" (still showing its upcoming
    /// payday). This matches the server's currentPayCycle in recompute.js —
    /// which has always rolled at cutoff — so the hero card's server-computed
    /// hours and the friend-facing cheque window stay in sync with the dates
    /// this returns.
    static func cycle(containing date: Date, settings: PaySettings, calendar: Calendar = .current) -> PayCycle {
        let cal = calendar
        let d = cal.startOfDay(for: date)
        let span = spanDays(for: settings.payPeriodType)

        if let anchor = activeCutoffAnchor(settings: settings, calendar: cal) {
            var cutoff = anchor
            var cycle = makeCycleFromCutoff(cutoff, settings: settings, calendar: cal)

            while d < cycle.start {
                cutoff = cal.date(byAdding: .day, value: -span, to: cutoff)
                    ?? cutoff.addingTimeInterval(Double(-span) * 86400)
                cycle = makeCycleFromCutoff(cutoff, settings: settings, calendar: cal)
            }

            while d >= cycle.end {
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
        // "Cutoff" only exists as a concept when the user turned the toggle on.
        // Without it, `cycle.cutoff` is just payday - 1 (an internal bookkeeping
        // value) and must not surface as a label.
        if usesSavedCutoff(settings), day == cal.startOfDay(for: cycle.cutoff) {
            labels.append("Cutoff")
        }
        // The containing cycle's payday is always after this day (it pays
        // for hours already cut off), so compare against the schedule instead.
        if isPayday(day, settings: settings, calendar: cal) {
            labels.append("PayDay")
        }
        return labels
    }

    static func previousCycle(before cycle: PayCycle, settings: PaySettings, calendar: Calendar = .current) -> PayCycle {
        let cal = calendar
        let span = spanDays(for: settings.payPeriodType)

        if usesCutoffAnchoring(settings) {
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

        if usesCutoffAnchoring(settings) {
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
        if usesCutoffAnchoring(settings) {
            let lag = cutoffPaydayLagDays(settings: settings, calendar: calendar)
            let cutoff = calendar.date(byAdding: .day, value: -lag, to: calendar.startOfDay(for: payday))
                ?? calendar.startOfDay(for: payday)
            return makeCycleFromCutoff(cutoff, settings: settings, calendar: calendar)
        }
        return makeCycle(payday: payday, settings: settings, calendar: calendar)
    }
}
