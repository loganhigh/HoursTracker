import SwiftUI

// MARK: - History tab

/// History tab root: every time-based drill-in that used to live in the side
/// drawer — cheques, months, and year archives — in one clean list.
struct HistoryTabView: View {
    @EnvironmentObject private var store: HoursStore

    private var currentCycle: PayCycle {
        store.currentPayCycle()
    }

    /// Same computation the drawer's "Last cheque" row used.
    private var previousCycle: PayCycle {
        PayCycleEngine.previousCycle(before: currentCycle, settings: store.paySettings)
    }

    private var currentMonthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var loggedMonthCount: Int {
        MonthHistoryHelper.loggedMonthStarts(from: store.entries).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                historySection("Cheques") {
                    historyRow(
                        icon: "banknote",
                        title: "This Cheque",
                        subtitle: currentCycle.workRangeText()
                    ) {
                        PayCycleDetailView(
                            store: store,
                            initialCycle: currentCycle,
                            navigationTitle: "This Cheque",
                            showsWeekSummary: true
                        )
                    }
                    rowDivider
                    historyRow(
                        icon: "banknote.fill",
                        title: "Last Cheque",
                        subtitle: previousCycle.workRangeText()
                    ) {
                        PayCycleDetailView(
                            store: store,
                            initialCycle: previousCycle,
                            navigationTitle: "Last Cheque",
                            showsWeekSummary: false
                        )
                    }
                }

                historySection("Months") {
                    historyRow(
                        icon: "calendar",
                        title: "This Month",
                        subtitle: monthTitle(currentMonthStart)
                    ) {
                        MonthDetailView(store: store, monthDate: currentMonthStart)
                    }
                    rowDivider
                    historyRow(
                        icon: "square.grid.2x2",
                        title: "All Months",
                        subtitle: loggedMonthCount == 1
                            ? "1 month logged"
                            : "\(loggedMonthCount) months logged"
                    ) {
                        PreviousMonthsView(store: store)
                    }
                }

                historySection("Archive") {
                    historyRow(
                        icon: "archivebox",
                        title: "Year Archives",
                        subtitle: store.yearArchives.isEmpty
                            ? "Completed years appear here"
                            : (store.yearArchives.count == 1
                                ? "1 archived year"
                                : "\(store.yearArchives.count) archived years")
                    ) {
                        YearArchivesListView(store: store)
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

    // MARK: - Building blocks

    private var rowDivider: some View {
        Divider()
            .overlay(AppColors.stroke)
            .padding(.leading, 56)
    }

    @ViewBuilder
    private func historySection<Rows: View>(
        _ title: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title.uppercased())
                .font(AppTypography.eyebrow)
                .tracking(AppTypography.eyebrowTracking)
                .foregroundStyle(AppColors.subtext)
                .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 0) {
                rows()
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
        }
    }

    private func historyRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.text)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.subtext)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monthTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d)
    }
}
