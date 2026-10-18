import SwiftUI

// MARK: - Yearly Overview (12-month bar chart)

struct YearlyOverviewSection: View {
    @ObservedObject var store: HoursStore

    // Hoisted out of the render path so the 12-month chart doesn't allocate a
    // DateFormatter on every body evaluation.
    private static let monthAbbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private var monthlyHoursByMonth: [(label: String, hours: Double)] {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        return (1...12).compactMap { month -> (String, Double)? in
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            guard let start = cal.date(from: comps) else { return nil }
            let hours = store.monthTotalHours(monthDate: start)
            let label = Self.monthAbbrevFormatter.string(from: start)
            return (label, hours)
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            HomeSectionHeader("Yearly overview")

            VStack(spacing: AppSpacing.md) {
                Text(verbatim: "\(Calendar.current.component(.year, from: Date()))")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .center)

                MonthlyOverviewChart(data: monthlyHoursByMonth)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.md)
            .homeCard()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Monthly Overview Bar Chart (moved from RootView)

struct MonthlyOverviewChart: View {
    let data: [(label: String, hours: Double)]
    @State private var appeared = false
    /// Month whose value is shown; nil = this month.
    @State private var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxHours: Double {
        max(data.map(\.hours).max() ?? 8, 8)
    }

    private var currentMonthIndex: Int {
        Calendar.current.component(.month, from: Date()) - 1
    }

    private var shownIndex: Int { selected ?? currentMonthIndex }

    var body: some View {
        let chartHeight: CGFloat = 130
        let barSpacing: CGFloat = 6
        let labelReserve: CGFloat = 0

        VStack(spacing: AppSpacing.sm) {
            // One value at a time — the selected month (this month until you
            // tap another) — instead of a number crammed over every bar.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HoursValue(hours: data.indices.contains(shownIndex) ? data[shownIndex].hours : 0,
                           size: 22, unitSize: 13, gap: 4)
                    .contentTransition(.numericText())
                Text("in \(monthName(shownIndex))")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
            }
            .animation(.easeOut(duration: 0.15), value: shownIndex)
            .padding(.bottom, AppSpacing.xs)

            GeometryReader { geo in
                let barWidth = max(12, (geo.size.width - barSpacing * CGFloat(max(data.count - 1, 0))) / CGFloat(max(data.count, 1)))

                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        let isShown = index == shownIndex
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: item.hours > 0 ? 5 : 1.5, style: .continuous)
                                .fill(item.hours > 0
                                      ? (isShown ? AppColors.accent : AppColors.accent.opacity(0.55))
                                      : AppColors.stroke)
                                .frame(
                                    width: barWidth,
                                    height: item.hours > 0
                                        ? (appeared ? max(4, CGFloat(item.hours / maxHours) * (chartHeight - labelReserve - 8)) : 0)
                                        : 3
                                )
                                // Ease-out growth from the baseline: fast
                                // launch, gentle landing — no spring wobble on
                                // a data chart. 40ms per month keeps the whole
                                // year under a second.
                                .animation(
                                    reduceMotion
                                        ? nil
                                        : .easeOut(duration: 0.55).delay(Double(index) * 0.04),
                                    value: appeared
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.lightTap()
                            withAnimation(.easeOut(duration: 0.15)) { selected = index }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.label): \(AppTheme.Format.hours(item.hours, suffix: " hours"))")
                        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: chartHeight)

            // Single-letter months so the row never crowds.
            HStack(spacing: barSpacing) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    Text(String(item.label.prefix(1)))
                        .font(.system(size: 12, weight: index == shownIndex ? .bold : .medium, design: .rounded))
                        .foregroundStyle(index == shownIndex ? AppColors.text : AppColors.subtext)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            Text("Tap a month to see its hours")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
        }
        .padding(.vertical, AppSpacing.xs)
        .onAppear { appeared = true }
    }

    private func monthName(_ index: Int) -> String {
        let symbols = Calendar.current.standaloneMonthSymbols
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}
