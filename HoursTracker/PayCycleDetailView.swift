import SwiftUI
import UIKit

/// Full drill-in for one pay cycle: totals, ring progress, breakdown, entries by week, cycle picker, share.
struct PayCycleDetailView: View {
    @ObservedObject var store: HoursStore
    let initialCycle: PayCycle
    var navigationTitle: String
    var showsWeekSummary: Bool

    @State private var selectedCycle: PayCycle
    @State private var showShare = false
    @State private var didCopyAll = false
    @State private var copyAllBurst = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.semanticColors) private var theme

    private var prestigeTier: PrestigeTheme.Tier {
        PrestigeTheme.tier(for: store.gamificationProfile.prestige)
    }

    init(
        store: HoursStore,
        initialCycle: PayCycle,
        navigationTitle: String = "This Cheque",
        showsWeekSummary: Bool = true
    ) {
        self.store = store
        self.initialCycle = initialCycle
        self.navigationTitle = navigationTitle
        self.showsWeekSummary = showsWeekSummary
        _selectedCycle = State(initialValue: initialCycle)
    }

    private var cycleEntries: [WorkEntry] {
        PayCycleEngine.entries(store.entries, in: selectedCycle)
    }

    private var periodHours: Double {
        cycleEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var periodPay: Double {
        cycleEntries.reduce(0) { $0 + store.payBreakdown(for: $1).pay }
    }

    private var workEntries: [WorkEntry] {
        cycleEntries.filter { !$0.isOffDay }
    }

    private var offDayCount: Int {
        cycleEntries.filter(\.isOffDay).count
    }

    private var aggregatedRegular: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).regularHours }
    }

    private var aggregatedOT: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).overtimeHours }
    }

    private var cycleDayProgress: (elapsed: Int, total: Int, fraction: Double) {
        let cal = Calendar.current
        let total = max(1, selectedCycle.spanDays)
        let today = cal.startOfDay(for: Date())
        let accrualEnd = PayCycleEngine.usesSavedCutoff(store.paySettings)
            ? selectedCycle.cutoff
            : cal.date(byAdding: .day, value: -1, to: selectedCycle.end) ?? selectedCycle.cutoff
        let endCap = min(today, accrualEnd)
        let elapsed = max(0, cal.dateComponents([.day], from: selectedCycle.start, to: endCap).day ?? 0)
        let frac = min(1, max(0, Double(elapsed) / Double(total)))
        return (elapsed, total, frac)
    }

    private var sortedCycleEntries: [WorkEntry] {
        cycleEntries.sorted { $0.date > $1.date }
    }

    private var weekSections: [(label: String, entries: [WorkEntry])] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let grouped = Dictionary(grouping: cycleEntries) { entry -> Date in
            cal.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return grouped.keys.sorted().map { weekStart in
            let label = "Week of \(fmt.string(from: weekStart))"
            let items = (grouped[weekStart] ?? []).sorted { $0.date > $1.date }
            return (label, items)
        }
    }

    private var cycleStrip: [PayCycle] {
        store.recentPayCycles(count: 8)
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    heroBlock

                    payBreakdownSection

                    if cycleEntries.isEmpty {
                        EmptyStateView(
                            icon: "calendar",
                            title: "No entries this period",
                            subtitle: "Log a shift from the home screen to fill this pay period.",
                            primaryTitle: "Add First Shift",
                            primaryAction: { dismiss() }
                        )
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(sortedCycleEntries) { entry in
                                NavigationLink {
                                    EntryEditorView(store: store, mode: .edit(entry))
                                } label: {
                                    EntryRowView(
                                        entry: entry,
                                        breakdown: store.payBreakdown(for: entry),
                                        currencyCode: store.paySettings.currencyCode,
                                        showPay: store.paySettings.showPayCalculations,
                                        paySettings: store.paySettings
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = formatEntryForCopy(entry)
                                        Haptics.lightTap()
                                    } label: {
                                        Label("Copy Entry", systemImage: "doc.on.doc")
                                    }
                                }
                            }

                            Button {
                                copyAllEntries(sortedCycleEntries)
                            } label: {
                                HStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: didCopyAll ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.system(size: 14, weight: .bold))
                                    Text(didCopyAll ? "Copied!" : "Copy All")
                                        .font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(didCopyAll ? Color.green : AppTheme.Colors.accent)
                                .padding(.vertical, 8)
                                .contentTransition(.opacity)
                            }
                            .buttonStyle(.plain)
                            .tapBurst(trigger: copyAllBurst, cornerRadius: 12, color: didCopyAll ? .green : AppTheme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            HoursShareAnalyticsSheet(
                store: store,
                achievementTitle: nil,
                payPeriodOverride: (selectedCycle.start, selectedCycle.end)
            )
        }
        .onAppear {
            selectedCycle = initialCycle
        }
    }

    private var daysWorked: Int {
        let cal = Calendar.current
        return Set(workEntries.map { cal.startOfDay(for: $0.date) }).count
    }

    private var totalCycleDays: Int { max(1, selectedCycle.spanDays) }

    private var hoursFraction: Double {
        let target = max(1, Double(totalCycleDays) * 8.0)
        return min(1, max(0, periodHours / target))
    }

    private var daysFraction: Double {
        min(1, max(0, Double(daysWorked) / Double(totalCycleDays)))
    }

    // MARK: - This week (within selected cheque)

    private var chequeWeekInterval: DateInterval? {
        let week = WeeklyStatsCalculator.currentWeekInterval()
        let start = max(week.start, selectedCycle.start)
        let end = min(week.end, selectedCycle.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    private var chequeWeekWorkEntries: [WorkEntry] {
        guard let interval = chequeWeekInterval else { return [] }
        return workEntries.filter { interval.contains($0.date) }
    }

    private var chequeWeekHours: Double {
        chequeWeekWorkEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var chequeWeekDaysWorked: Int {
        let cal = Calendar.current
        return Set(chequeWeekWorkEntries.map { cal.startOfDay(for: $0.date) }).count
    }

    private var chequeWeekDaySpan: Int {
        guard let interval = chequeWeekInterval else { return 7 }
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: interval.start)
        let endDay = cal.startOfDay(for: interval.end)
        let days = cal.dateComponents([.day], from: startDay, to: endDay).day ?? 7
        return max(1, days)
    }

    private var chequeWeekDaysFraction: Double {
        min(1, max(0, Double(chequeWeekDaysWorked) / Double(chequeWeekDaySpan)))
    }

    private var chequeWeekHoursFraction: Double {
        let target = max(1, Double(chequeWeekDaySpan) * 8.0)
        return min(1, max(0, chequeWeekHours / target))
    }

    private var chequeWeekSubtitle: String {
        guard let interval = chequeWeekInterval else { return "This week" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let cal = Calendar.current
        let lastIncluded = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(fmt.string(from: interval.start)) – \(fmt.string(from: lastIncluded)) · this week"
    }

    private var heroBlock: some View {
        VStack(spacing: 16) {
            Text(subtitleLine)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if store.paySettings.showPayCalculations {
                Text(formattedCurrency(periodPay))
                    .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.text)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 18) {
                PayCycleStatRing(
                    progress: daysFraction,
                    value: "\(daysWorked)",
                    caption: daysWorked == 1 ? "day worked" : "days worked",
                    ringColors: prestigeTier.daysRingColors
                )
                PayCycleStatRing(
                    progress: hoursFraction,
                    value: AppTheme.Format.hours(periodHours),
                    caption: "this cheque",
                    ringColors: prestigeTier.hoursRingColors
                )
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(AppDesignSystem.Spacing.md)
        .background(PayCycleCardStyle.cardBackground(theme: theme))
        .overlay(PayCycleCardStyle.cardBorder(theme: theme))
        .shadow(color: theme.accent.opacity(0.25), radius: 14, y: 6)
        .id(store.gamificationProfile.prestige)
    }

    private var chequeWeekHeroBlock: some View {
        payCycleRingsCard(
            subtitle: chequeWeekSubtitle,
            daysWorked: chequeWeekDaysWorked,
            daysFraction: chequeWeekDaysFraction,
            daysCaption: chequeWeekDaysWorked == 1 ? "day this week" : "days this week",
            hours: chequeWeekHours,
            hoursFraction: chequeWeekHoursFraction,
            hoursCaption: "hours this week"
        )
    }

    private func payCycleRingsCard(
        subtitle: String,
        daysWorked: Int,
        daysFraction: Double,
        daysCaption: String,
        hours: Double,
        hoursFraction: Double,
        hoursCaption: String
    ) -> some View {
        VStack(spacing: 16) {
            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 18) {
                PayCycleStatRing(
                    progress: daysFraction,
                    value: "\(daysWorked)",
                    caption: daysCaption,
                    ringColors: prestigeTier.daysRingColors
                )
                PayCycleStatRing(
                    progress: hoursFraction,
                    value: AppTheme.Format.hours(hours),
                    caption: hoursCaption,
                    ringColors: prestigeTier.hoursRingColors
                )
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(AppDesignSystem.Spacing.md)
        .background(PayCycleCardStyle.cardBackground(theme: theme))
        .overlay(PayCycleCardStyle.cardBorder(theme: theme))
        .shadow(color: theme.accent.opacity(0.25), radius: 14, y: 6)
    }

    private var subtitleLine: String {
        selectedCycle.chequeRangeText(settings: store.paySettings)
    }

    private var payBreakdownSection: some View {
        SectionCard(
            title: "Summary",
            subtitle: nil,
            trailing: nil,
            centerHeader: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                breakdownRow(title: "Regular hours", value: AppTheme.Format.hours(aggregatedRegular, suffix: ""))
                breakdownRow(title: "Overtime hours", value: AppTheme.Format.hours(aggregatedOT, suffix: ""))
                Text("OFF DAYS - \(offDayCount)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.danger)
                    .frame(maxWidth: .infinity, alignment: .center)
                if store.paySettings.showPayCalculations {
                    breakdownRow(title: "Estimated pay", value: formattedCurrency(periodPay))
                }
                let otType = store.paySettings.overtimeType
                if otType == .weekly {
                    Text("\(otType.displayName) OT · \(AppTheme.Format.hours(store.paySettings.weeklyOvertimeThreshold, suffix: ""))/wk weekly threshold")
                        .font(AppDesignSystem.Typography.footnote)
                        .foregroundStyle(AppTheme.Colors.faint)
                }
            }
        }
    }

    private func breakdownRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
            Spacer()
            Text(value)
                .font(AppDesignSystem.Typography.heroNumerals(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.Colors.text)
        }
    }

    private var cyclePickerStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Recent cycles", subtitle: "Tap to compare")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cycleStrip) { c in
                        let isSel = c.start == selectedCycle.start && c.end == selectedCycle.end
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedCycle = c
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shortRange(c))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSel ? .white : AppTheme.Colors.text)
                                Text(hoursIn(c))
                                    .font(AppDesignSystem.Typography.heroNumerals(size: 14, weight: .bold))
                                    .foregroundStyle(isSel ? .white.opacity(0.95) : AppTheme.Colors.accent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSel ? AnyShapeStyle(AppTheme.Colors.accentGradient) : AnyShapeStyle(AppTheme.Colors.card2))
                                    .shadow(color: isSel ? AppTheme.Colors.accent.opacity(0.4) : Color.clear, radius: 6, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func shortRange(_ c: PayCycle) -> String {
        c.workRangeText()
    }

    private func hoursIn(_ c: PayCycle) -> String {
        let h = PayCycleEngine.entries(store.entries, in: c).reduce(0) { $0 + $1.paidHours }
        return AppTheme.Format.hours(h)
    }

    private func formattedCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = store.paySettings.currencyCode
        return f.string(from: NSNumber(value: value)) ?? "—"
    }

    private func copyAllEntries(_ entries: [WorkEntry]) {
        UIPasteboard.general.string = copyAllText(for: entries)
        Haptics.success()
        copyAllBurst &+= 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            didCopyAll = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                didCopyAll = false
            }
        }
    }

    private func formatEntryForCopy(_ entry: WorkEntry) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return entry.formattedForCopy(dateFormatter: df, timeFormatter: tf)
    }

    private func copyAllText(for entries: [WorkEntry]) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        let sorted = entries.sorted { $0.date > $1.date }
        return sorted
            .map { $0.formattedForCopy(dateFormatter: df, timeFormatter: tf) }
            .joined(separator: "\n\n")
    }
}
