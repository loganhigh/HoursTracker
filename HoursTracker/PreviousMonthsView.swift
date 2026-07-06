import SwiftUI

enum MonthHistoryHelper {
    static func previousMonthStarts(from entries: [WorkEntry], before date: Date = Date()) -> [Date] {
        let cal = Calendar.current
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let monthStarts = Set(entries.map {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        })
        return monthStarts
            .filter { $0 < thisMonth }
            .sorted(by: >)
    }

    /// Every month that has at least one logged entry, newest first (includes current month).
    static func loggedMonthStarts(from entries: [WorkEntry]) -> [Date] {
        let cal = Calendar.current
        let monthStarts = Set(entries.map {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        })
        return monthStarts.sorted(by: >)
    }

    static func title(for monthDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: monthDate)
    }

    static func yearTitle(_ year: Int) -> String {
        String(year)
    }
}

/// Full list of every month with logged shifts (includes the current month).
struct PreviousMonthsView: View {
    @ObservedObject var store: HoursStore

    private var loggedMonths: [Date] {
        MonthHistoryHelper.loggedMonthStarts(from: store.entries)
    }

    private var monthsByYear: [(year: Int, months: [Date])] {
        Dictionary(grouping: loggedMonths) { month in
            Calendar.current.component(.year, from: month)
        }
        .sorted { $0.key > $1.key }
        .map { (year: $0.key, months: $0.value.sorted(by: >)) }
    }

    private var totalHours: Double {
        loggedMonths.reduce(0) { $0 + store.monthTotalHours(monthDate: $1) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                summaryHeader

                ForEach(monthsByYear, id: \.year) { group in
                    SectionCard(
                        title: MonthHistoryHelper.yearTitle(group.year),
                        subtitle: nil,
                        trailing: nil,
                        centerHeader: true
                    ) {
                        VStack(spacing: 12) {
                            ForEach(group.months, id: \.self) { monthDate in
                                NavigationLink {
                                    MonthDetailView(store: store, monthDate: monthDate)
                                } label: {
                                    MonthSummaryRow(
                                        title: MonthHistoryHelper.title(for: monthDate),
                                        hours: store.monthTotalHours(monthDate: monthDate),
                                        pay: store.monthEstimatedPay(monthDate: monthDate),
                                        currencyCode: store.paySettings.currencyCode,
                                        showPay: store.paySettings.showPayCalculations
                                    )
                                }
                                .premiumPress()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Hours Logged")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryHeader: some View {
        SectionCard(
            title: "\(loggedMonths.count) month\(loggedMonths.count == 1 ? "" : "s") logged",
            subtitle: nil,
            trailing: nil,
            centerHeader: true
        ) {
            HStack(spacing: 12) {
                summaryTile(
                    label: "Total hours",
                    value: AppTheme.Format.hours(totalHours),
                    icon: "clock.fill"
                )
                summaryTile(
                    label: "Avg / month",
                    value: AppTheme.Format.hours(totalHours / Double(max(loggedMonths.count, 1))),
                    icon: "chart.bar.fill"
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func summaryTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
            Text(value)
                .font(AppDesignSystem.Typography.heroNumerals(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.Colors.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
                )
        )
    }
}
