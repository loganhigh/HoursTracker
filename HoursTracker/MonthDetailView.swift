import SwiftUI
import UIKit

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct MonthAchievementItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    /// When non-nil, show a progress ring (OT Addict–style). 0...1.
    var progress: Double? = nil
}

private struct MonthProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.Colors.stroke.opacity(0.6), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AppTheme.Colors.accentGradient,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

private let achievementTileHeight: CGFloat = 152

private struct MonthAchievementTile: View {
    let item: MonthAchievementItem

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let p = item.progress {
                    MonthProgressRing(progress: p)
                        .frame(width: 64, height: 64)
                }
                Circle()
                    .fill(AppTheme.Colors.accentGradient)
                    .frame(width: 60, height: 60)
                    .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 8, y: 3)
                Image(systemName: item.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 64)
            VStack(spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Text(item.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: achievementTileHeight)
    }
}

struct MonthDetailView: View {
    @ObservedObject var store: HoursStore
    let monthDate: Date
    @State private var showRemoveMonthConfirm = false
    @State private var showExportMenu = false
    @State private var exportError: String?
    @State private var shareItem: IdentifiableURL?
    @State private var isExporting = false
    @State private var showingAddEntry = false
    @State private var didCopyAll = false
    @State private var copyAllBurst = 0

    init(store: HoursStore, monthDate: Date) {
        self.store = store
        self.monthDate = monthDate
    }
    private let exportService = ReportExportService()

    var body: some View {
        let entries = store.entries(inMonth: monthDate).sorted { $0.date > $1.date }
        let hours: Double = store.monthTotalHours(monthDate: monthDate)
        let regularHours: Double = store.monthRegularHours(monthDate: monthDate)
        let overtimeHours: Double = store.monthOvertimeHours(monthDate: monthDate)
        let offDayCount = entries.filter(\.isOffDay).count
        let effectiveRate: Double = store.monthEffectiveRate(monthDate: monthDate)
        let pay: Double = store.monthEstimatedPay(monthDate: monthDate)
        let currencyCode: String = store.paySettings.currencyCode
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()
            List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // Total hours
                    HStack {
                        Text("Total hours")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text(AppTheme.Format.hours(hours, suffix: ""))
                            .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .medium))
                    }
                    
                    Divider()
                    
                    // Regular | Overtime breakdown
                    HStack {
                        Text("Regular")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppTheme.Format.hours(regularHours))
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        
                        Text("|")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        
                        Text("Overtime")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppTheme.Format.hours(overtimeHours))
                            .font(.system(size: 19, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }

                    Text("OFF DAYS - \(offDayCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.danger)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    if store.paySettings.showPayCalculations {
                        Divider()
                        
                        // Effective rate
                        HStack {
                            Text("Effective rate")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(currency(effectiveRate, code: currencyCode) + "/hr")
                                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                            Text("(gross)")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        // Estimated gross pay
                        HStack {
                            Text("Estimated gross pay")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text(currency(pay, code: currencyCode))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        }
                        
                        Text("(before deductions)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, -4)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }

            Section {
                if entries.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No entries yet — log your first shift"
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(entries) { entry in
                        ZStack {
                            NavigationLink {
                                EntryEditorView(store: store, mode: .edit(entry))
                            } label: {
                                EmptyView()
                            }
                            .opacity(0)

                            EntryRowView(
                                entry: entry,
                                breakdown: store.payBreakdown(for: entry),
                                currencyCode: store.paySettings.currencyCode,
                                showPay: store.paySettings.showPayCalculations,
                                paySettings: store.paySettings
                            )
                        }
                        .contextMenu {
                            Button(action: {
                                let copiedText = formatEntryForCopy(entry)
                                UIPasteboard.general.string = copiedText
                                Haptics.lightTap()
                            }) {
                                Label("Copy Entry", systemImage: "doc.on.doc")
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    Button {
                        copyAllEntries(entries)
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
                    .tapBurst(trigger: copyAllBurst, cornerRadius: 12, color: didCopyAll ? .green : AppTheme.Colors.accent)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Button(role: .destructive) {
                    showRemoveMonthConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Remove All This Month Entries")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("Entries")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }

        }
        .scrollContentBackground(.hidden)
        }
        .navigationTitle(monthTitleShort(monthDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.Colors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        performExport(asCSV: true)
                    } label: {
                        Label("Export as CSV", systemImage: "doc.text")
                    }
                    .disabled(isExporting)
                    Button {
                        performExport(asCSV: false)
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                    .disabled(isExporting)
                } label: {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]) { shareItem = nil }
        }
        .sheet(isPresented: $showingAddEntry) {
            EntryEditorView(store: store, mode: .add)
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "Export failed. Please try again.")
        }
        .alert("Remove all entries this month?", isPresented: $showRemoveMonthConfirm) {
            Button("Remove", role: .destructive) {
                withAnimation(.easeOut(duration: 0.25)) {
                    store.deleteEntries(inMonth: monthDate)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone. All entries in \(monthTitleShort(monthDate)) will be deleted.")
        }
    }

    private let achievementGridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    @ViewBuilder
    private func monthAchievementsGrid(_ items: [MonthAchievementItem]) -> some View {
        if items.count == 1 {
            HStack {
                Spacer(minLength: 0)
                MonthAchievementTile(item: items[0])
                    .frame(width: 120)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        } else {
            LazyVGrid(columns: achievementGridColumns, spacing: 16) {
                ForEach(items) { a in
                    MonthAchievementTile(item: a)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func monthTitleShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLL yyyy"
        return f.string(from: d)
    }

    private func currency(_ value: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private var exportCompanyName: String {
        store.payHistoryEntries.sorted(by: { $0.year > $1.year }).first?.companyName ?? ""
    }

    private func performExport(asCSV: Bool) {
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let url: URL
                if asCSV {
                    url = try await exportService.exportCSV(monthDate: monthDate, entries: store.entries, store: store, companyName: exportCompanyName.isEmpty ? nil : exportCompanyName)
                } else {
                    url = try await exportService.exportPDF(monthDate: monthDate, entries: store.entries, store: store, companyName: exportCompanyName.isEmpty ? nil : exportCompanyName)
                }
                shareItem = IdentifiableURL(url: url)
            } catch {
                exportError = (error as? LocalizedError)?.errorDescription ?? "Export failed. Please try again."
            }
        }
    }

    /// Stats for a single month's entries (used to compute earned badges for "Achievements Of The Month").
    private struct MonthStats {
        let totalHours: Double
        let totalDays: Int
        let distinctDays: Int
        let saturdays: Int
        let sundays: Int
        let overtimeDays: Int
        let longDaysOver12: Int
        let longDaysOver14: Int
        let bestStreak: Int
        let longestShift: Double

        init(entries: [WorkEntry], store: HoursStore) {
            let workEntries = entries.filter { !$0.isOffDay }
            let cal = Calendar.current
            let breakdowns = workEntries.map { store.payBreakdown(for: $0) }

            totalHours = workEntries.reduce(0) { $0 + $1.paidHours }
            totalDays = workEntries.count
            longestShift = workEntries.map(\.paidHours).filter { $0 > 0 }.max() ?? 0

            let workDates = Set(workEntries.map { cal.startOfDay(for: $0.date) })
            distinctDays = workDates.count

            saturdays = Set(workEntries.filter { cal.component(.weekday, from: $0.date) == 7 }.map { cal.startOfDay(for: $0.date) }).count
            sundays = Set(workEntries.filter { cal.component(.weekday, from: $0.date) == 1 }.map { cal.startOfDay(for: $0.date) }).count

            let otEntries = workEntries.enumerated().filter { breakdowns[$0.offset].overtimeHours > 0 }
            overtimeDays = Set(otEntries.map { cal.startOfDay(for: $0.element.date) }).count

            longDaysOver12 = workEntries.filter { $0.paidHours >= 12 }.count
            longDaysOver14 = workEntries.filter { $0.paidHours >= 14 }.count

            bestStreak = Self.computeBestStreak(dates: Array(workDates), calendar: cal)
        }

        private static func computeBestStreak(dates: [Date], calendar: Calendar) -> Int {
            guard !dates.isEmpty else { return 0 }
            let sorted = Array(Set(dates)).sorted()
            var best = 1, current = 1
            for i in 1..<sorted.count {
                let prev = calendar.startOfDay(for: sorted[i - 1])
                let curr = calendar.startOfDay(for: sorted[i])
                let daysDiff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
                if daysDiff == 1 { current += 1; best = max(best, current) } else { current = 1 }
            }
            return best
        }
    }

    /// Returns only the badges earned this month (automatic from entries + store). Empty if none earned.
    private func monthAchievements(entries: [WorkEntry], hours: Double, regularHours: Double, store: HoursStore, monthDate: Date) -> [MonthAchievementItem] {
        let workEntries = entries.filter { !$0.isOffDay }
        guard !workEntries.isEmpty else { return [] }

        let s = MonthStats(entries: entries, store: store)
        var earned: [MonthAchievementItem] = []

        // Hours (month total)
        if s.totalHours >= 50 { earned.append(MonthAchievementItem(id: "50h", icon: "clock.fill", title: "50 Hours", detail: "Logged \(Int(s.totalHours)) hours this month")) }
        if s.totalHours >= 100 { earned.append(MonthAchievementItem(id: "100h", icon: "clock.badge.checkmark.fill", title: "100 Hours", detail: "Logged \(Int(s.totalHours)) hours this month")) }
        if s.totalHours >= 200 { earned.append(MonthAchievementItem(id: "200h", icon: "dumbbell.fill", title: "200h Month", detail: "200+ hours in one month")) }

        // Shifts
        if s.totalDays >= 10 { earned.append(MonthAchievementItem(id: "10sh", icon: "checkmark.circle", title: "10 Shifts Logged", detail: "\(s.totalDays) shifts this month")) }
        if s.totalDays >= 20 { earned.append(MonthAchievementItem(id: "20sh", icon: "checkmark.seal.fill", title: "Consistent", detail: "\(s.totalDays) days logged")) }
        if s.totalDays >= 25 { earned.append(MonthAchievementItem(id: "25sh", icon: "checkmark.circle", title: "25 Shifts Logged", detail: "\(s.totalDays) shifts this month")) }

        // Streak (within month)
        if s.bestStreak >= 7 { earned.append(MonthAchievementItem(id: "7str", icon: "flame.fill", title: "No Days Off", detail: "\(s.bestStreak) consecutive days")) }
        if s.bestStreak >= 14 { earned.append(MonthAchievementItem(id: "14str", icon: "flame.fill", title: "14-Day Streak", detail: "\(s.bestStreak) consecutive days")) }

        // Overtime
        if s.overtimeDays >= 1 { earned.append(MonthAchievementItem(id: "ot1", icon: "bolt.fill", title: "First Overtime Shift", detail: "\(s.overtimeDays) OT day\(s.overtimeDays == 1 ? "" : "s")")) }
        if s.overtimeDays >= 10 { earned.append(MonthAchievementItem(id: "ot10", icon: "bolt.fill", title: "Overtime Beast", detail: "\(s.overtimeDays) OT days")) }

        // Long shifts
        if s.longDaysOver12 >= 1 { earned.append(MonthAchievementItem(id: "12h", icon: "figure.walk.motion", title: "Longest Shift Logged", detail: "12+ hour shift • \(AppTheme.Format.hours(s.longestShift)) max")) }
        if s.longDaysOver14 >= 1 { earned.append(MonthAchievementItem(id: "14h", icon: "sunrise.fill", title: "Sunrise to Sunset", detail: "14+ hour day")) }

        // Weekend
        if s.saturdays >= 3 { earned.append(MonthAchievementItem(id: "sat3", icon: "calendar.badge.clock", title: "Weekend Starter", detail: "\(s.saturdays) Saturdays")) }
        if s.saturdays >= 10 { earned.append(MonthAchievementItem(id: "sat10", icon: "calendar.badge.clock", title: "Saturday Grinder", detail: "\(s.saturdays) Saturdays")) }
        if s.sundays >= 2 { earned.append(MonthAchievementItem(id: "sun2", icon: "sun.max.fill", title: "Sunday Double-Time", detail: "\(s.sundays) Sundays")) }
        if s.sundays >= 5 { earned.append(MonthAchievementItem(id: "sun5", icon: "sun.max.fill", title: "Sunday Warrior", detail: "\(s.sundays) Sundays")) }

        // Deduplicate by keeping highest tier per category (e.g. show "100 Hours" not both "50 Hours" and "100 Hours") – optional; for now show all earned.
        return earned.sorted { $0.id < $1.id }
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
        let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        return entry.formattedForCopy(dateFormatter: df, timeFormatter: tf)
    }

    /// Builds the full grouped monthly clipboard string from a list of entries.
    private func copyAllText(for entries: [WorkEntry]) -> String {
        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        let mf = DateFormatter(); mf.dateFormat = "MMMM yyyy"
        let sorted = entries.sorted { $0.date > $1.date }
        var byMonth: [[WorkEntry]] = []
        var current: [WorkEntry] = []
        var lastComps: (Int, Int)? = nil
        for e in sorted {
            let comps = (cal.component(.year, from: e.date), cal.component(.month, from: e.date))
            if let lc = lastComps, lc != comps {
                byMonth.append(current); current = []
            }
            current.append(e); lastComps = comps
        }
        if !current.isEmpty { byMonth.append(current) }
        var blocks: [String] = []
        for group in byMonth {
            guard let first = group.first else { continue }
            let header = "————————————\n\(mf.string(from: first.date))\n————————————"
            let lines = group.map { e -> String in
                e.formattedForCopy(dateFormatter: df, timeFormatter: tf)
            }
            blocks.append(header + "\n\n" + lines.joined(separator: "\n\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

}

