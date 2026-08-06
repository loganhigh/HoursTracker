import SwiftUI

// MARK: - History tab
//
// Every cheque (pay period) as a compact, scannable preview row, grouped by
// year with the newest year first. Each row is labelled with its position in
// that year ("1st Cheque"), counted across ALL pay periods in the year — so a
// period with no logged shifts still consumes its number and the labels keep
// matching real pay history. Tapping a row opens PayCycleDetailView.

struct HistoryTabView: View {
    @EnvironmentObject private var store: HoursStore

    /// Hard stop on the backward walk (roughly two years of bi-weekly cheques).
    private static let maxWalkedCycles = 60

    /// One row of the list: a pay cycle, its ordinal within its year, and
    /// whether it is the live one.
    private struct ChequeRow: Identifiable {
        let cycle: PayCycle
        let ordinal: Int
        let isCurrent: Bool
        var id: Date { cycle.start }
    }

    /// A year's worth of rows, newest cheque first.
    private struct YearGroup: Identifiable {
        let year: Int
        let rows: [ChequeRow]
        var id: Int { year }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm, pinnedViews: [.sectionHeaders]) {
                if store.entries.isEmpty {
                    AppEmptyState(
                        icon: "calendar",
                        title: "No cheques yet",
                        message: "Log a shift and your pay periods will show up here."
                    )
                    .padding(.top, AppSpacing.xxl)
                } else {
                    ForEach(yearGroups) { group in
                        Section {
                            ForEach(group.rows) { row in
                                card(for: row)
                            }
                        } header: {
                            yearHeader(group.year)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xl)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Rows

    private func yearHeader(_ year: Int) -> some View {
        SectionEyebrow(String(year))
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xxs)
            .background(AppColors.bg)
    }

    private func card(for row: ChequeRow) -> some View {
        ChequePreviewCard(
            title: row.cycle.workRangeText(),
            caption: caption(for: row),
            hours: cycleHours(row.cycle),
            isCurrent: row.isCurrent
        ) {
            PayCycleDetailView(
                store: store,
                initialCycle: row.cycle,
                navigationTitle: row.isCurrent ? "This Cheque" : "Cheque",
                showsWeekSummary: row.isCurrent
            )
        }
    }

    private func caption(for row: ChequeRow) -> String {
        let label = "\(Self.ordinalText(row.ordinal)) Cheque"
        if row.isCurrent { return "\(label) · In progress" }
        return "\(label) · \(shiftsCaption(for: PayCycleEngine.entries(store.entries, in: row.cycle)))"
    }

    // MARK: - Grouping

    /// Cheques grouped by year (newest year first, newest cheque first within
    /// the year). Empty cheques are hidden, but they still count toward the
    /// ordinals so "5th Cheque" always means the fifth pay period of that year.
    private var yearGroups: [YearGroup] {
        let calendar = Calendar.current
        let current = store.currentPayCycle()
        let walked = [current] + previousCycles(before: current)

        // Ordinal = chronological position among every pay period sharing the
        // cheque's year, so the numbering survives skipped/empty periods.
        var byYear: [Int: [PayCycle]] = [:]
        for cycle in walked {
            let year = calendar.component(.year, from: cycle.cutoff)
            byYear[year, default: []].append(cycle)
        }

        return byYear.keys.sorted(by: >).compactMap { year in
            let ascending = (byYear[year] ?? []).sorted { $0.start < $1.start }
            let rows: [ChequeRow] = ascending.enumerated().compactMap { index, cycle in
                let isCurrent = cycle.start == current.start
                let hasEntries = !PayCycleEngine.entries(store.entries, in: cycle).isEmpty
                guard isCurrent || hasEntries else { return nil }
                return ChequeRow(cycle: cycle, ordinal: index + 1, isCurrent: isCurrent)
            }
            guard !rows.isEmpty else { return nil }
            return YearGroup(year: year, rows: rows.reversed())
        }
    }

    /// Walks back from the current cheque far enough to cover every year that
    /// has entries — including the periods before the first logged shift of the
    /// earliest year, which the ordinals depend on.
    private func previousCycles(before current: PayCycle) -> [PayCycle] {
        guard let earliest = store.entries.map(\.date).min() else { return [] }
        let calendar = Calendar.current
        let earliestYear = calendar.component(.year, from: earliest)
        var walked: [PayCycle] = []
        var cursor = current
        for _ in 0..<Self.maxWalkedCycles {
            cursor = PayCycleEngine.previousCycle(before: cursor, settings: store.paySettings)
            // Stop once we drop below the earliest year that has any entries.
            if calendar.component(.year, from: cursor.cutoff) < earliestYear { break }
            walked.append(cursor)
        }
        return walked
    }

    // MARK: - Formatting

    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()

    private static func ordinalText(_ value: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func cycleHours(_ cycle: PayCycle) -> Double {
        PayCycleEngine.entries(store.entries, in: cycle)
            .filter { !$0.isOffDay }
            .reduce(0) { $0 + $1.paidHours }
    }

    private func shiftsCaption(for entries: [WorkEntry]) -> String {
        let count = entries.filter { !$0.isOffDay }.count
        return "\(count) \(count == 1 ? "shift" : "shifts")"
    }
}
