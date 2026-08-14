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
            // No `pinnedViews`: the year should sit with its own cheques and
            // scroll away with them, not stick to the top and trail the user
            // down through later years.
            LazyVStack(spacing: AppSpacing.md) {
                if store.entries.isEmpty {
                    AppEmptyState(
                        icon: "calendar",
                        title: "No cheques yet",
                        message: "Log a shift and your pay periods will show up here."
                    )
                    .padding(.top, AppSpacing.xxl)
                } else {
                    // Each year is its own card titled with the year, so the
                    // year label travels with its cheques instead of pinning
                    // to the top and trailing the user into later years.
                    ForEach(Array(yearGroups.enumerated()), id: \.element.id) { groupIndex, group in
                        ChequeYearCard(year: group.year) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Divider().overlay(AppColors.stroke)
                                }
                                tableRow(for: row, index: index)
                            }
                        }
                        .cardAppear(index: groupIndex, group: "history")
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

    private func tableRow(for row: ChequeRow, index: Int) -> some View {
        ChequeTableRow(
            number: row.ordinal,
            title: Self.depositDateText(for: row.cycle),
            subtitle: subtitle(for: row),
            status: status(for: row),
            accentLine: accentLine(for: row),
            projection: projection(for: row),
            index: index
        ) {
            PayCycleDetailView(
                store: store,
                initialCycle: row.cycle,
                navigationTitle: row.isCurrent ? "This Cheque" : "Cheque",
                showsWeekSummary: row.isCurrent
            )
        }
    }

    /// Shift count and hours — the detail the table's removed columns used
    /// to carry, folded under the cheque's date range.
    private func subtitle(for row: ChequeRow) -> String {
        let entries = PayCycleEngine.entries(store.entries, in: row.cycle)
        return "\(shiftsCaption(for: entries)) · \(AppTheme.Format.hours(cycleHours(row.cycle)))"
    }

    /// Recorded total on a paid cheque's row, in green. Nothing renders until
    /// the user has typed totals in.
    private func accentLine(for row: ChequeRow) -> (text: String, tint: Color)? {
        guard let recorded = store.actualPayout(for: row.cycle) else { return nil }
        return (Self.currency(recorded), AppColors.positive)
    }

    /// The live cheque's projection, once at least two totals exist. The
    /// amount rides AnimatedMetricText so it rolls when hours change.
    private func projection(for row: ChequeRow) -> (amount: Double, currencyCode: String, caption: String)? {
        guard row.isCurrent, store.actualPayout(for: row.cycle) == nil else { return nil }
        guard let prediction = currentPrediction() else { return nil }
        return (prediction.amount, store.paySettings.currencyCode, prediction.confidence.label)
    }

    /// Projection for the live cheque — shared with Home's hero card, so the
    /// two can never disagree. Lives on HoursStore.
    private func currentPrediction() -> AdvancedPayPredictor.Prediction? {
        store.currentChequeProjection()
    }

    private static func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// The live cheque is In Progress; a closed one is Pending until its
    /// payday passes, then "Add Pay" until the user records what it paid,
    /// and finally Paid.
    private func status(for row: ChequeRow) -> ChequeStatus {
        if row.isCurrent { return .inProgress }
        guard row.cycle.payday <= Date() else { return .pending }
        return store.actualPayout(for: row.cycle) != nil ? .paid : .awaitingPay
    }

    // MARK: - Grouping

    /// Cheques grouped by year (newest year first, newest cheque first within
    /// the year). Ordinals count from the pay period containing the user's
    /// first-ever entry (never earlier), so the earliest real cheque is always
    /// "1st Cheque" — a later empty period between two logged cheques still
    /// consumes its number, since that's genuine (if quiet) pay history.
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

    /// Walks back from the current cheque to the pay period that contains the
    /// user's very first logged entry — never further. Stopping at the
    /// calendar year boundary instead (Jan 1) would silently count every
    /// empty pay period back to New Year's as real history, inflating the
    /// ordinal of the user's actual first cheque (e.g. "12th Cheque" for
    /// what is really their first).
    private func previousCycles(before current: PayCycle) -> [PayCycle] {
        guard let earliest = store.entries.map(\.date).min() else { return [] }
        var walked: [PayCycle] = []
        var cursor = current
        for _ in 0..<Self.maxWalkedCycles {
            cursor = PayCycleEngine.previousCycle(before: cursor, settings: store.paySettings)
            walked.append(cursor)
            // This cycle's start is on/before the earliest entry, so — since
            // cycles are contiguous and non-overlapping — it necessarily
            // contains that entry. Stop here; anything further back is
            // pre-history the user never logged.
            if cursor.start <= earliest { break }
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

    /// Row title: the payday, not the work range — "when does this money
    /// land" is the question people scan this list with. The year only
    /// appears when the deposit slips outside the year card it sits in
    /// (a late-December cheque paying in January).
    private static func depositDateText(for cycle: PayCycle) -> String {
        let payYear = Calendar.current.component(.year, from: cycle.payday)
        let cardYear = Calendar.current.component(.year, from: cycle.cutoff)
        return payYear == cardYear
            ? cycle.payday.formatted(.dateTime.month(.abbreviated).day())
            : cycle.payday.formatted(.dateTime.month(.abbreviated).day().year())
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
