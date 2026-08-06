import SwiftUI

// MARK: - History tab (Phase 5)
//
// Rich period cards behind a Cheques / Months / Years scope control.
// Every scope leads into the existing detail screens: PayCycleDetailView,
// MonthDetailView, and ArchivedYearEntriesView.

enum HistoryScope: String, CaseIterable, Identifiable {
    case cheques = "Cheques"
    case months = "Months"
    case years = "Years"

    var id: String { rawValue }
}

struct HistoryTabView: View {
    @EnvironmentObject private var store: HoursStore
    @State private var scope: HistoryScope = .cheques

    private var cal: Calendar { Calendar.current }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                scopePicker

                switch scope {
                case .cheques: chequesScope
                case .months: monthsScope
                case .years: yearsScope
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Scope control

    private var scopePicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(HistoryScope.allCases) { item in
                MotionSegmentChip(
                    title: item.rawValue,
                    systemImage: nil,
                    isSelected: scope == item
                ) {
                    scope = item
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Cheques scope

    private var chequesScope: some View {
        let current = store.currentPayCycle()
        let previous = previousCycles(before: current)

        return VStack(spacing: AppSpacing.sm) {
            CurrentPeriodCard(
                title: current.workRangeText(),
                badge: "In progress",
                hours: cycleHours(current),
                caption: shiftsDaysCaption(for: PayCycleEngine.entries(store.entries, in: current)),
                cells: cycleCells(current)
            ) {
                PayCycleDetailView(
                    store: store,
                    initialCycle: current,
                    navigationTitle: "This Cheque",
                    showsWeekSummary: true
                )
            }

            if !previous.isEmpty {
                SectionEyebrow("Previous Cheques")
                    .padding(.top, AppSpacing.xs)

                ForEach(previous) { cycle in
                    CompactPeriodCard(
                        title: cycle.workRangeText(),
                        caption: shiftsDaysCaption(for: PayCycleEngine.entries(store.entries, in: cycle)),
                        hours: cycleHours(cycle)
                    ) {
                        PayCycleDetailView(
                            store: store,
                            initialCycle: cycle,
                            navigationTitle: "Cheque",
                            showsWeekSummary: false
                        )
                    }
                }
            }
        }
    }

    /// Previous cycles worth showing: walks back from the current cheque until
    /// the earliest logged entry (capped), keeping the most recent cheque even
    /// when empty plus every older cheque that has entries.
    private func previousCycles(before current: PayCycle) -> [PayCycle] {
        let earliest = store.entries.map(\.date).min()
        var walked: [PayCycle] = []
        var cursor = current
        for _ in 0..<26 {
            cursor = PayCycleEngine.previousCycle(before: cursor, settings: store.paySettings)
            walked.append(cursor)
            guard let earliest, cursor.start > earliest else { break }
        }
        return walked.enumerated()
            .filter { index, cycle in
                index == 0 || !PayCycleEngine.entries(store.entries, in: cycle).isEmpty
            }
            .map(\.element)
    }

    private func cycleHours(_ cycle: PayCycle) -> Double {
        PayCycleEngine.entries(store.entries, in: cycle)
            .filter { !$0.isOffDay }
            .reduce(0) { $0 + $1.paidHours }
    }

    /// Day-by-day strip cells for a pay cycle (start through cutoff).
    private func cycleCells(_ cycle: PayCycle) -> [DayStripCell] {
        let entries = PayCycleEngine.entries(store.entries, in: cycle)
        let start = cal.startOfDay(for: cycle.start)
        let last = cal.startOfDay(for: cycle.cutoff)
        return stripCells(from: start, to: last, entries: entries)
    }

    // MARK: - Months scope

    private var monthsScope: some View {
        let thisMonth = currentMonthStart
        let previousMonths = MonthHistoryHelper.previousMonthStarts(from: store.entries)
        let byYear = monthsByYear(previousMonths)

        return VStack(spacing: AppSpacing.sm) {
            CurrentPeriodCard(
                title: monthTitle(thisMonth),
                badge: "In progress",
                hours: store.monthTotalHours(monthDate: thisMonth),
                caption: shiftsDaysCaption(for: store.entries(inMonth: thisMonth)),
                cells: monthCells(thisMonth)
            ) {
                MonthDetailView(store: store, monthDate: thisMonth)
            }

            ForEach(byYear, id: \.year) { group in
                SectionEyebrow(String(group.year))
                    .padding(.top, AppSpacing.xs)

                ForEach(group.months, id: \.self) { monthDate in
                    CompactPeriodCard(
                        title: monthTitle(monthDate),
                        caption: shiftsDaysCaption(for: store.entries(inMonth: monthDate)),
                        hours: store.monthTotalHours(monthDate: monthDate),
                        cells: monthCells(monthDate)
                    ) {
                        MonthDetailView(store: store, monthDate: monthDate)
                    }
                }
            }
        }
    }

    private var currentMonthStart: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private func monthsByYear(_ months: [Date]) -> [(year: Int, months: [Date])] {
        Dictionary(grouping: months) { cal.component(.year, from: $0) }
            .sorted { $0.key > $1.key }
            .map { (year: $0.key, months: $0.value.sorted(by: >)) }
    }

    /// Thin daily sparkline cells for a month (1st through last day).
    private func monthCells(_ monthStart: Date) -> [DayStripCell] {
        guard let range = cal.range(of: .day, in: .month, for: monthStart),
              let lastDay = cal.date(byAdding: .day, value: range.count - 1, to: monthStart)
        else { return [] }
        let entries = store.entries(inMonth: monthStart)
        return stripCells(from: cal.startOfDay(for: monthStart), to: cal.startOfDay(for: lastDay), entries: entries)
    }

    // MARK: - Years scope

    private var yearsScope: some View {
        let archives = store.yearArchives.sorted { $0.year > $1.year }

        return VStack(spacing: AppSpacing.sm) {
            if archives.isEmpty {
                AppEmptyState(
                    icon: "archivebox",
                    title: "No archived years yet",
                    message: "Completed years appear here when entries roll over."
                )
                .padding(.top, AppSpacing.xl)
            } else {
                ForEach(archives) { archive in
                    CompactPeriodCard(
                        title: String(archive.year),
                        caption: yearCaption(archive),
                        hours: archive.entries
                            .filter { !$0.isOffDay }
                            .reduce(0) { $0 + $1.paidHours }
                    ) {
                        ArchivedYearEntriesView(store: store, archive: archive)
                    }
                }
            }
        }
    }

    private func yearCaption(_ archive: YearArchive) -> String {
        let monthCount = Set(archive.entries.map { cal.component(.month, from: $0.date) }).count
        let monthWord = monthCount == 1 ? "month" : "months"
        let entryWord = archive.entries.count == 1 ? "entry" : "entries"
        return "\(monthCount) \(monthWord) · \(archive.entries.count) \(entryWord)"
    }

    // MARK: - Shared helpers

    /// Builds strip cells for consecutive days: worked (accent, sized by
    /// hours), logged off days, empty past days, and hollow future days.
    private func stripCells(from start: Date, to last: Date, entries: [WorkEntry]) -> [DayStripCell] {
        var hoursByDay: [Date: Double] = [:]
        var offDays: Set<Date> = []
        for entry in entries {
            let day = cal.startOfDay(for: entry.date)
            if entry.isOffDay {
                offDays.insert(day)
            } else {
                hoursByDay[day, default: 0] += entry.paidHours
            }
        }

        let today = cal.startOfDay(for: Date())
        var cells: [DayStripCell] = []
        var day = start
        while day <= last {
            let state: DayStripState
            if let hours = hoursByDay[day], hours > 0 {
                state = .worked(hours)
            } else if offDays.contains(day) {
                state = .off
            } else if day > today {
                state = .future
            } else {
                state = .rest
            }
            cells.append(DayStripCell(id: day, state: state))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return cells
    }

    private func shiftsDaysCaption(for entries: [WorkEntry]) -> String {
        let work = entries.filter { !$0.isOffDay }
        let dayCount = Set(work.map { cal.startOfDay(for: $0.date) }).count
        let shiftWord = work.count == 1 ? "shift" : "shifts"
        let dayWord = dayCount == 1 ? "day" : "days"
        return "\(work.count) \(shiftWord) · \(dayCount) \(dayWord)"
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d)
    }
}
