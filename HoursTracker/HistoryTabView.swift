import SwiftUI

// MARK: - History tab (Phase 5)
//
// One thing only: every cheque (pay period) as a compact, scannable preview
// row, newest first. Tapping a row opens the existing PayCycleDetailView.

struct HistoryTabView: View {
    @EnvironmentObject private var store: HoursStore

    /// How far back to walk when building the cheque list.
    private static let maxPreviousCycles = 26

    /// One row of the list: a pay cycle plus whether it is the live one.
    private struct ChequeRow: Identifiable {
        let cycle: PayCycle
        let isCurrent: Bool
        var id: Date { cycle.start }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                if store.entries.isEmpty {
                    AppEmptyState(
                        icon: "calendar",
                        title: "No cheques yet",
                        message: "Log a shift and your pay periods will show up here."
                    )
                    .padding(.top, AppSpacing.xxl)
                } else {
                    ForEach(rows) { row in
                        card(for: row)
                    }
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

    // MARK: - Rows

    private func card(for row: ChequeRow) -> some View {
        ChequePreviewCard(
            title: row.cycle.workRangeText(),
            caption: row.isCurrent
                ? "In progress"
                : shiftsCaption(for: PayCycleEngine.entries(store.entries, in: row.cycle)),
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

    /// Current cheque first, then every previous cheque back to the earliest entry.
    private var rows: [ChequeRow] {
        let current = store.currentPayCycle()
        return [ChequeRow(cycle: current, isCurrent: true)]
            + previousCycles(before: current).map { ChequeRow(cycle: $0, isCurrent: false) }
    }

    /// Previous cycles worth showing: walks back from the current cheque until
    /// the earliest logged entry (capped), keeping the most recent cheque even
    /// when empty plus every older cheque that has entries.
    private func previousCycles(before current: PayCycle) -> [PayCycle] {
        let earliest = store.entries.map(\.date).min()
        var walked: [PayCycle] = []
        var cursor = current
        for _ in 0..<Self.maxPreviousCycles {
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

    private func shiftsCaption(for entries: [WorkEntry]) -> String {
        let count = entries.filter { !$0.isOffDay }.count
        return "\(count) \(count == 1 ? "shift" : "shifts")"
    }
}
