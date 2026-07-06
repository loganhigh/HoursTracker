import SwiftUI
import Charts

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ReportingView: View {
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPeriod: TimePeriod = .month
    @State private var selectedDate = Date()
    @State private var showExportMenu = false
    @State private var exportError: String?
    @State private var shareItem: ExportShareItem?
    @State private var isExporting = false
    @State private var showingDatePicker = false

    private let exportService = ReportExportService()
    
    enum TimePeriod: String, CaseIterable {
        case biWeek = "Bi-weekly"
        case month = "Month"
        case year = "Year"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    periodSelector
                    insightsSection
                    chartsSection
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 20)
            }
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Reports & Analytics")
            .navigationBarTitleDisplayMode(.large)
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
                            ProgressView().scaleEffect(0.9)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url]) { shareItem = nil }
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "Export failed. Please try again.")
            }
        }
    }
    
    private var exportCompanyName: String {
        store.payHistoryEntries.sorted(by: { $0.year > $1.year }).first?.companyName ?? ""
    }

    private func performExport(asCSV: Bool) {
        isExporting = true
        let monthDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate)) ?? selectedDate
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let url: URL
                if asCSV {
                    url = try await exportService.exportCSV(monthDate: monthDate, entries: store.entries, store: store, companyName: exportCompanyName.isEmpty ? nil : exportCompanyName)
                } else {
                    url = try await exportService.exportPDF(monthDate: monthDate, entries: store.entries, store: store, companyName: exportCompanyName.isEmpty ? nil : exportCompanyName)
                }
                shareItem = ExportShareItem(url: url)
            } catch {
                exportError = (error as? LocalizedError)?.errorDescription ?? "Export failed. Please try again."
            }
        }
    }

    // MARK: - Period Selector
    private var periodSelector: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(period.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedPeriod == period ? .white : AppTheme.Colors.subtext)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedPeriod == period ? AppTheme.Colors.accent : AppTheme.Colors.card2)
                            )
                    }
                }
            }

            Button {
                showingDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(AppTheme.Colors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.Colors.accent.opacity(0.12))
                )
            }
            .sheet(isPresented: $showingDatePicker) {
                AutoDismissDatePickerSheet(
                    date: $selectedDate,
                    title: "Select Date",
                    onDismiss: { showingDatePicker = false }
                )
            }
        }
    }
    
    // MARK: - Insights Section
    private var insightsSection: some View {
        SectionCard(title: "Key Insights", subtitle: nil, trailing: nil) {
            VStack(alignment: .leading, spacing: 16) {
                let insights = calculateInsights()
                
                InsightRow(
                    icon: "clock.fill",
                    title: "Total Hours",
                    value: AppTheme.Format.hours(insights.totalHours, suffix: ""),
                    subtitle: insights.periodLabel
                )
                
                Divider()
                    .background(AppTheme.Colors.stroke)
                
                InsightRow(
                    icon: "calendar",
                    title: "Days Worked",
                    value: "\(insights.daysWorked)",
                    subtitle: insights.periodLabel
                )
                
                Divider()
                    .background(AppTheme.Colors.stroke)
                
                InsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Average Hours",
                    value: AppTheme.Format.hours(insights.averageHours, suffix: ""),
                    subtitle: insights.averageLabel
                )
                
                if insights.hasOvertime {
                    Divider()
                        .background(AppTheme.Colors.stroke)
                    
                    InsightRow(
                        icon: "bolt.fill",
                        title: "Overtime Hours",
                        value: AppTheme.Format.hours(insights.overtimeHours, suffix: ""),
                        subtitle: insights.periodLabel
                    )
                }
            }
        }
    }
    
    // MARK: - Charts Section
    private var chartsSection: some View {
        VStack(spacing: 20) {
            // Hours Distribution Chart
            SectionCard(title: "Hours Breakdown", subtitle: nil, trailing: nil) {
                let breakdown = calculateHoursBreakdown()
                PieChartView(
                    regularHours: breakdown.regular,
                    overtimeHours: breakdown.overtime,
                    weekendHours: breakdown.weekend
                )
                .frame(height: 250)
            }
        }
    }
    
    // MARK: - Calculations
    private func calculateInsights() -> (totalHours: Double, daysWorked: Int, averageHours: Double, overtimeHours: Double, periodLabel: String, averageLabel: String, hasOvertime: Bool) {
        let entries = getEntriesForPeriod()
        let calendar = Calendar.current
        
        let totalHours = entries.reduce(0) { $0 + $1.paidHours }
        let daysWorked = Set(entries.map { calendar.startOfDay(for: $0.date) }).count
        
        var regularHours: Double = 0
        var overtimeHours: Double = 0
        var weekendHours: Double = 0
        
        for entry in entries {
            let weekday = calendar.component(.weekday, from: entry.date)
            let breakdown = store.payBreakdown(for: entry)
            
            if weekday == 1 || weekday == 7 {
                weekendHours += entry.paidHours
            } else {
                // Regular hours = raw hours - overtime hours
                let regularHrs = breakdown.rawHours - breakdown.overtimeHours
                regularHours += regularHrs
                overtimeHours += breakdown.overtimeHours
            }
        }
        
        let periodDays = getPeriodDays()
        let averageHours = periodDays > 0 ? totalHours / Double(periodDays) : 0
        
        let periodLabel: String = {
            switch selectedPeriod {
            case .biWeek: return "bi-weekly"
            case .month: return "month"
            case .year: return "year"
            }
        }()
        let averageLabel: String = {
            switch selectedPeriod {
            case .biWeek: return "per day"
            case .month: return "per week"
            case .year: return "per month"
            }
        }()
        
        return (totalHours, daysWorked, averageHours, overtimeHours, periodLabel, averageLabel, overtimeHours > 0)
    }
    
    private func calculateHoursBreakdown() -> (regular: Double, overtime: Double, weekend: Double) {
        let entries = getEntriesForPeriod()
        let calendar = Calendar.current
        
        var regular: Double = 0
        var overtime: Double = 0
        var weekend: Double = 0
        
        for entry in entries {
            let weekday = calendar.component(.weekday, from: entry.date)
            let breakdown = store.payBreakdown(for: entry)
            
            if weekday == 1 || weekday == 7 {
                weekend += entry.paidHours
            } else {
                // Regular hours = raw hours - overtime hours
                let regularHrs = breakdown.rawHours - breakdown.overtimeHours
                regular += regularHrs
                overtime += breakdown.overtimeHours
            }
        }
        
        return (regular, overtime, weekend)
    }
    
    private func calculateTrendData() -> [(date: Date, hours: Double)] {
        let entries = getEntriesForPeriod()
        let calendar = Calendar.current
        
        var data: [(date: Date, hours: Double)] = []
        
        if selectedPeriod == .month {
            // Group by week
            let grouped = Dictionary(grouping: entries) { entry in
                calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date
            }
            
            for (weekStart, weekEntries) in grouped.sorted(by: { $0.key < $1.key }) {
                let hours = weekEntries.reduce(0) { $0 + $1.paidHours }
                data.append((weekStart, hours))
            }
        } else if selectedPeriod == .year {
            // Group by month
            let grouped = Dictionary(grouping: entries) { entry in
                let components = calendar.dateComponents([.year, .month], from: entry.date)
                return calendar.date(from: components) ?? entry.date
            }
            
            for (monthStart, monthEntries) in grouped.sorted(by: { $0.key < $1.key }) {
                let hours = monthEntries.reduce(0) { $0 + $1.paidHours }
                data.append((monthStart, hours))
            }
        }
        
        return data
    }
    
    private func getEntriesForPeriod() -> [WorkEntry] {
        let calendar = Calendar.current
        var startDate: Date
        var endDate: Date
        
        switch selectedPeriod {
        case .biWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            startDate = interval?.start ?? selectedDate
            endDate = calendar.date(byAdding: .weekOfYear, value: 2, to: startDate) ?? selectedDate
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            startDate = calendar.date(from: components) ?? selectedDate
            endDate = calendar.date(byAdding: .month, value: 1, to: startDate) ?? selectedDate
            
        case .year:
            let components = calendar.dateComponents([.year], from: selectedDate)
            startDate = calendar.date(from: components) ?? selectedDate
            endDate = calendar.date(byAdding: .year, value: 1, to: startDate) ?? selectedDate
        }
        
        // Span the year archive so a past ("Year") report isn't empty after the
        // Jan-1 rollover, and exclude auto-filled off-days so "Days Worked" counts
        // days actually worked rather than every calendar day in the period.
        return store.allEntriesIncludingArchive().filter {
            !$0.isOffDay && $0.date >= startDate && $0.date < endDate
        }
    }
    
    private func getPeriodDays() -> Int {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .biWeek: return 14
        case .month:
            if let range = calendar.range(of: .day, in: .month, for: selectedDate) {
                return range.count
            }
            return 30
        case .year: return 365
        }
    }
    
}

// MARK: - Supporting Views
private struct InsightRow: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.Colors.accent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
            }
            
            Spacer()
            
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext.opacity(0.7))
        }
    }
}

private struct PieChartView: View {
    let regularHours: Double
    let overtimeHours: Double
    let weekendHours: Double
    
    private var total: Double {
        regularHours + overtimeHours + weekendHours
    }
    
    var body: some View {
        if total > 0 {
            Chart {
                SectorMark(
                    angle: .value("Regular", regularHours),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(AppTheme.Colors.accent)
                .annotation(position: .overlay) {
                    if regularHours / total > 0.15 {
                        Text(AppTheme.Format.hours(regularHours, suffix: ""))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                
                SectorMark(
                    angle: .value("Overtime", overtimeHours),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(Color.orange)
                .annotation(position: .overlay) {
                    if overtimeHours / total > 0.15 {
                        Text(AppTheme.Format.hours(overtimeHours, suffix: ""))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                
                SectorMark(
                    angle: .value("Weekend", weekendHours),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .foregroundStyle(Color.purple)
                .annotation(position: .overlay) {
                    if weekendHours / total > 0.15 {
                        Text(AppTheme.Format.hours(weekendHours, suffix: ""))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 200)
            
            // Legend
            VStack(spacing: 8) {
                LegendItem(color: AppTheme.Colors.accent, label: "Regular", hours: regularHours)
                LegendItem(color: Color.orange, label: "Overtime", hours: overtimeHours)
                LegendItem(color: Color.purple, label: "Weekend", hours: weekendHours)
            }
            .padding(.top, 8)
        } else {
            Text("No data available")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let hours: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
            
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.text)
            
            Spacer()
            
            Text(AppTheme.Format.hours(hours))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
        }
    }
}

private struct TrendChartView: View {
    let data: [(date: Date, hours: Double)]
    
    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                LineMark(
                    x: .value("Period", index),
                    y: .value("Hours", item.hours)
                )
                .foregroundStyle(AppTheme.Colors.accent)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Period", index),
                    y: .value("Hours", item.hours)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.Colors.accent.opacity(0.3), AppTheme.Colors.accent.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(5, data.count))) { value in
                AxisGridLine()
                    .foregroundStyle(AppTheme.Colors.stroke.opacity(0.3))
                AxisValueLabel()
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                    .foregroundStyle(AppTheme.Colors.stroke.opacity(0.3))
                AxisValueLabel()
                    .foregroundStyle(AppTheme.Colors.subtext)
            }
        }
    }
}
