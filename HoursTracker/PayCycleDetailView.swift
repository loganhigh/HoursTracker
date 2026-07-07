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
                            Text("SHIFTS")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(1.6)
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 2)

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

    private enum CycleDayState { case worked, off, empty }

    /// One state per day of the cycle: capped at today while the cycle is
    /// live, the full span once it has ended (mirrors the Home hero strip).
    private var cycleDayStates: [CycleDayState] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var workedDays: Set<Date> = []
        var offDays: Set<Date> = []
        for e in cycleEntries {
            let d = cal.startOfDay(for: e.date)
            if e.isOffDay { offDays.insert(d) } else { workedDays.insert(d) }
        }
        let start = cal.startOfDay(for: selectedCycle.start)
        let lastCycleDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: selectedCycle.end)) ?? selectedCycle.end
        let cap = min(lastCycleDay, today)
        let end = cap >= start ? cap : lastCycleDay
        var states: [CycleDayState] = []
        var day = start
        while day <= end && states.count < 62 {
            if workedDays.contains(day) { states.append(.worked) }
            else if offDays.contains(day) { states.append(.off) }
            else { states.append(.empty) }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return states
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 2) {
                Text(navigationTitle.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(AppTheme.Colors.subtext)
                Text(subtitleLine)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.faint)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                AnimatedMetricText(value: periodHours) { AppTheme.Format.hours($0, suffix: "") }
                    .font(AppDesignSystem.Typography.heroNumerals(size: 44, weight: .heavy))
                    .foregroundStyle(AppTheme.Colors.text)
                Text("hrs")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)
                Spacer(minLength: 8)
                if store.paySettings.showPayCalculations {
                    AnimatedMetricText(currency: periodPay, code: store.paySettings.currencyCode)
                        .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }

            HStack(spacing: 3) {
                ForEach(Array(cycleDayStates.enumerated()), id: \.offset) { _, state in
                    Capsule()
                        .fill(
                            state == .worked
                                ? AppTheme.Colors.success
                                : AppTheme.Colors.danger.opacity(state == .off ? 0.9 : 0.35)
                        )
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.Colors.success)
                        .frame(width: 6, height: 6)
                    Text("\(daysWorked) \(daysWorked == 1 ? "day" : "days") worked")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.text)
                }
                if offDayCount > 0 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.Colors.danger)
                            .frame(width: 6, height: 6)
                        Text("\(offDayCount) off")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.text)
                    }
                }
                Spacer()
                Text("Day \(min(cycleDayProgress.elapsed + 1, cycleDayProgress.total)) of \(cycleDayProgress.total)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.Colors.card2)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.accent.opacity(0.14),
                                Color.clear,
                                AppTheme.Colors.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.accent.opacity(0.4),
                            AppTheme.Colors.accent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: AppTheme.Colors.accent.opacity(0.18), radius: 18, y: 8)
    }

    private var subtitleLine: String {
        selectedCycle.chequeRangeText(settings: store.paySettings)
    }

    private var payBreakdownSection: some View {
        SectionCard(
            title: "Summary",
            subtitle: nil,
            trailing: nil,
            centerHeader: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                breakdownRow(title: "Regular hours", value: AppTheme.Format.hours(aggregatedRegular, suffix: ""))
                breakdownRow(title: "Overtime hours", value: AppTheme.Format.hours(aggregatedOT, suffix: ""))
                breakdownRow(title: "Off days", value: "\(offDayCount)", valueColor: offDayCount > 0 ? AppTheme.Colors.danger : AppTheme.Colors.text)
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

    private func breakdownRow(title: String, value: String, valueColor: Color = AppTheme.Colors.text) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.subtext)
            Spacer()
            Text(value)
                .font(AppDesignSystem.Typography.heroNumerals(size: 17, weight: .bold))
                .foregroundStyle(valueColor)
        }
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
