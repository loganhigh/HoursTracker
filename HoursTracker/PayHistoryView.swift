import SwiftUI

/// Dedicated screen for the user's pay-rate progression: raises, role
/// changes, and a visual hourly-rate timeline. Keep the focus narrow —
/// long-term hour totals live in CareerView.
struct PayHistoryView: View {
    @ObservedObject var store: HoursStore
    @State private var showingEditor = false
    @State private var editingEntry: PayHistoryEntry?
    @State private var entryPendingDeletion: PayHistoryEntry?

    // MARK: - Source data

    private var sortedEntries: [PayHistoryEntry] {
        store.payHistoryEntries.sorted { $0.year < $1.year }
    }

    private var primaryCurrencyCode: String {
        sortedEntries.last?.currencyCode.isEmpty == false
            ? sortedEntries.last!.currencyCode
            : (store.paySettings.currencyCode.isEmpty ? "USD" : store.paySettings.currencyCode)
    }

    private var currentRate: Double { sortedEntries.last?.hourlyRate ?? 0 }
    private var startingRate: Double { sortedEntries.first?.hourlyRate ?? 0 }
    private var highestRate: Double { sortedEntries.map(\.hourlyRate).max() ?? 0 }

    private var totalRoles: Int { sortedEntries.count }

    private var distinctCompanies: Int {
        Set(sortedEntries.map { $0.companyName.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }).count
    }

    private var yearsTrackedSpan: Int? {
        guard let first = sortedEntries.first, let last = sortedEntries.last,
              last.year > first.year else { return nil }
        return last.year - first.year
    }

    private var payIncreasePercent: Double? {
        guard sortedEntries.count >= 2, startingRate > 0 else { return nil }
        return ((currentRate - startingRate) / startingRate) * 100
    }

    private var biggestSingleRaise: Double? {
        let sorted = sortedEntries
        guard sorted.count >= 2 else { return nil }
        var best: Double = 0
        for i in 1..<sorted.count {
            let prev = sorted[i - 1].hourlyRate
            let curr = sorted[i].hourlyRate
            if prev > 0 {
                let delta = ((curr - prev) / prev) * 100
                if delta > best { best = delta }
            }
        }
        return best > 0 ? best : nil
    }

    private var averageAnnualRaise: Double? {
        guard let first = sortedEntries.first, let last = sortedEntries.last,
              sortedEntries.count >= 2, first.hourlyRate > 0,
              last.year > first.year else { return nil }
        let totalGrowth = ((last.hourlyRate - first.hourlyRate) / first.hourlyRate) * 100
        let years = Double(last.year - first.year)
        return totalGrowth / years
    }

    /// Most-tenured company by `yearsWorkedAtCompany`, falling back to entry count.
    private var longestTenureCompany: (name: String, years: Int)? {
        var byName: [String: Int] = [:]
        for e in sortedEntries {
            let name = e.companyName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let years = e.yearsWorkedAtCompany ?? 0
            byName[name] = max(byName[name] ?? 0, years)
        }
        guard let top = byName.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
        return (top.key, top.value)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                heroSummary

                SectionCard(
                    title: "Pay stats",
                    subtitle: "Snapshot of where you are now",
                    trailing: nil,
                    centerHeader: true
                ) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        PayStatTile(
                            label: "Current Rate",
                            value: formatRate(currentRate),
                            icon: "dollarsign.circle.fill"
                        )
                        PayStatTile(
                            label: "Starting Rate",
                            value: sortedEntries.isEmpty ? "—" : formatRate(startingRate),
                            icon: "flag.fill"
                        )
                        PayStatTile(
                            label: "Roles",
                            value: "\(totalRoles)",
                            icon: "briefcase.fill"
                        )
                        PayStatTile(
                            label: "Companies",
                            value: distinctCompanies > 0 ? "\(distinctCompanies)" : "—",
                            icon: "building.2.fill"
                        )
                    }
                    .padding(.vertical, 8)
                }

                if !sortedEntries.isEmpty {
                    SectionCard(
                        title: "Raise insights",
                        subtitle: "Highlights from your pay journey",
                        trailing: nil,
                        centerHeader: true
                    ) {
                        VStack(spacing: 10) {
                            if let pct = payIncreasePercent {
                                recordRow(
                                    icon: "chart.line.uptrend.xyaxis",
                                    title: "Total Growth",
                                    value: String(format: "+%.0f%%", pct),
                                    detail: "Since \(sortedEntries.first?.year ?? 0)",
                                    tint: .green
                                )
                            }
                            if let r = biggestSingleRaise {
                                recordRow(
                                    icon: "arrow.up.right.circle.fill",
                                    title: "Biggest Jump",
                                    value: String(format: "+%.0f%%", r),
                                    tint: .orange
                                )
                            }
                            if let avg = averageAnnualRaise {
                                recordRow(
                                    icon: "calendar",
                                    title: "Avg / Year",
                                    value: String(format: "%+.1f%%", avg),
                                    tint: AppTheme.Colors.accent
                                )
                            }
                            recordRow(
                                icon: "trophy.fill",
                                title: "Highest Rate",
                                value: formatRate(highestRate),
                                tint: .yellow
                            )
                            if let span = yearsTrackedSpan {
                                recordRow(
                                    icon: "hourglass",
                                    title: "Years Tracked",
                                    value: span == 1 ? "1 year" : "\(span) years",
                                    tint: .blue
                                )
                            }
                            if let tenure = longestTenureCompany {
                                recordRow(
                                    icon: "building.columns.fill",
                                    title: "Longest Tenure",
                                    value: tenure.years == 1 ? "1 year" : "\(tenure.years) years",
                                    detail: tenure.name,
                                    tint: .purple
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    SectionCard(
                        title: "Rate over time",
                        subtitle: "Your hourly rate, year by year",
                        trailing: nil,
                        centerHeader: true
                    ) {
                        HourlyRateChart(entries: sortedEntries)
                            .frame(height: 160)
                            .padding(.vertical, 8)
                    }
                }

                SectionCard(
                    title: "Promotion & pay history",
                    subtitle: sortedEntries.isEmpty ? "Log your first raise to start tracking" : "Tap a row to edit",
                    trailing: nil,
                    centerHeader: true
                ) {
                    VStack(spacing: 12) {
                        if sortedEntries.isEmpty {
                            Text("Add your first role or pay raise to see your progression over the years.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(sortedEntries) { entry in
                                PayHistoryRow(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingEntry = entry
                                        showingEditor = true
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            entryPendingDeletion = entry
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        Button {
                            editingEntry = nil
                            showingEditor = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("Add role or raise")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(InteractiveButtonStyle())
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Pay history")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this pay record?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryPendingDeletion {
                    Haptics.warning()
                    store.deletePayHistoryEntry(entry)
                }
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
        } message: {
            Text("This can’t be undone.")
        }
        .sheet(isPresented: $showingEditor) {
            PayHistoryEditorSheet(
                store: store,
                existing: editingEntry,
                onDismiss: {
                    showingEditor = false
                    editingEntry = nil
                }
            )
        }
    }

    // MARK: - Hero

    private var heroSummary: some View {
        VStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accentGradient)

            Text(heroValue)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(heroSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)

            heroBadge
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var heroValue: String {
        if sortedEntries.isEmpty { return "—" }
        return formatRate(currentRate)
    }

    private var heroSubtitle: String {
        if sortedEntries.isEmpty { return "No pay history logged yet" }
        if let pct = payIncreasePercent {
            let sign = pct >= 0 ? "+" : ""
            return "Up \(sign)\(String(format: "%.0f", pct))% since you started tracking"
        }
        return "Current hourly rate"
    }

    @ViewBuilder
    private var heroBadge: some View {
        if sortedEntries.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Text("Start logging raises")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppTheme.Colors.accent.opacity(0.15)))
        } else if let span = yearsTrackedSpan {
            HStack(spacing: 6) {
                Image(systemName: "calendar.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(span == 1 ? "1 year tracked" : "\(span) years tracked")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppTheme.Colors.accent.opacity(0.15)))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(totalRoles == 1 ? "1 role" : "\(totalRoles) roles")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(AppTheme.Colors.accent.opacity(0.15)))
        }
    }

    // MARK: - Record row

    private func recordRow(
        icon: String,
        title: String,
        value: String,
        detail: String? = nil,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
    }

    // MARK: - Formatting

    private func formatRate(_ rate: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = primaryCurrencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return (f.string(from: NSNumber(value: rate)) ?? "$\(rate)") + "/hr"
    }
}

// MARK: - Pay stat tile (matches CareerStatTile)

private struct PayStatTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Pay history row

private struct PayHistoryRow: View {
    let entry: PayHistoryEntry

    var body: some View {
        HStack(alignment: .top) {
            Text(verbatim: String(entry.year))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.jobTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.text)
                if !entry.companyName.isEmpty {
                    Text(entry.companyName)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                if let y = entry.yearsWorkedAtCompany, y > 0 {
                    let startYear = Calendar.current.component(.year, from: Date()) - y
                    Text(verbatim: "Here since \(startYear)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
            Spacer()
            Text(formatRate(entry.hourlyRate))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.accent)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Colors.card2)
        )
    }

    private func formatRate(_ rate: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = entry.currencyCode.isEmpty ? "USD" : entry.currencyCode
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return (f.string(from: NSNumber(value: rate)) ?? "$\(rate)") + "/hr"
    }
}

// MARK: - Hourly rate chart

/// Lightweight line chart of hourly rate across years using Path.
/// Avoids Charts framework dependency for older iOS compatibility.
private struct HourlyRateChart: View {
    let entries: [PayHistoryEntry]

    var body: some View {
        GeometryReader { geo in
            let points = layoutPoints(in: geo.size)
            ZStack {
                gridLines(in: geo.size)

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for p in points.dropFirst() {
                        path.addLine(to: p)
                    }
                }
                .stroke(
                    AppTheme.Colors.accentGradient,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    path.addLine(to: first)
                    for p in points.dropFirst() {
                        path.addLine(to: p)
                    }
                    path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [AppTheme.Colors.accent.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(AppTheme.Colors.accent, lineWidth: 2))
                        .position(p)
                }

                if let first = entries.first, let last = entries.last {
                    Text(verbatim: String(first.year))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .position(x: 16, y: geo.size.height - 8)
                    Text(verbatim: String(last.year))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .position(x: geo.size.width - 16, y: geo.size.height - 8)
                }
            }
        }
    }

    private func layoutPoints(in size: CGSize) -> [CGPoint] {
        guard !entries.isEmpty else { return [] }
        let rates = entries.map(\.hourlyRate)
        let minRate = rates.min() ?? 0
        let maxRate = rates.max() ?? 1
        let span = max(maxRate - minRate, 0.0001)
        let inset: CGFloat = 14
        let usableW = max(size.width - inset * 2, 1)
        let usableH = max(size.height - inset * 2 - 16, 1)
        if entries.count == 1 {
            return [CGPoint(x: size.width / 2, y: size.height / 2)]
        }
        return entries.enumerated().map { idx, e in
            let xRatio = CGFloat(idx) / CGFloat(entries.count - 1)
            let yRatio = CGFloat((e.hourlyRate - minRate) / span)
            return CGPoint(
                x: inset + xRatio * usableW,
                y: inset + (1 - yRatio) * usableH
            )
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3) { _ in
                Rectangle()
                    .fill(AppTheme.Colors.stroke.opacity(0.4))
                    .frame(height: 1)
                Spacer()
            }
            Rectangle()
                .fill(AppTheme.Colors.stroke.opacity(0.4))
                .frame(height: 1)
        }
        .frame(width: size.width, height: size.height - 16)
    }
}

// MARK: - Years celebration payload

private struct YearsCelebrationItem: Identifiable {
    let id = UUID()
    let years: Int
    let companyName: String
}

// MARK: - Pay history editor sheet

private struct PayHistoryEditorSheet: View {
    @ObservedObject var store: HoursStore
    var existing: PayHistoryEntry?
    let onDismiss: () -> Void

    @State private var companyName: String
    @State private var year: Int
    @State private var jobTitle: String
    @State private var yearsWorkedAtCompany: Int
    @State private var hourlyRate: String
    @State private var currencyCode: String
    @State private var showYearsCelebration: YearsCelebrationItem?

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    init(store: HoursStore, existing: PayHistoryEntry?, onDismiss: @escaping () -> Void) {
        self.store = store
        self.existing = existing
        self.onDismiss = onDismiss
        _companyName = State(initialValue: existing?.companyName ?? "")
        _year = State(initialValue: existing?.year ?? Calendar.current.component(.year, from: Date()))
        _jobTitle = State(initialValue: existing?.jobTitle ?? "")
        _yearsWorkedAtCompany = State(initialValue: existing?.yearsWorkedAtCompany ?? 0)
        _hourlyRate = State(initialValue: existing.map { String(format: "%.2f", $0.hourlyRate) } ?? "")
        _currencyCode = State(initialValue: existing?.currencyCode ?? store.paySettings.currencyCode)
    }

    private var canSave: Bool {
        !jobTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(hourlyRate.replacingOccurrences(of: ",", with: "")) != nil &&
        year >= 2000 && year <= currentYear + 1
    }

    /// Currency picker options. Always includes the currently-selected code so an
    /// existing entry with an uncommon currency still shows the right selection.
    private var currencyOptionsForPicker: [CurrencyOption] {
        var options = CurrencyCatalog.common
        if !options.contains(where: { $0.code == currencyCode }) {
            options.insert(CurrencyCatalog.option(for: currencyCode), at: 0)
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Year") {
                    Stepper(value: $year, in: 2000...(currentYear + 1)) {
                        HStack {
                            Text("Year")
                            Spacer()
                            Text(verbatim: String(year))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.accent)
                                .monospacedDigit()
                        }
                    }
                }
                Section("Company") {
                    TextField("Company name", text: $companyName)
                }
                Section("Job title") {
                    TextField("e.g. Labourer, Operator, Foreman", text: $jobTitle)
                }
                Section("How many years have you worked here?") {
                    Picker("Years", selection: $yearsWorkedAtCompany) {
                        Text("Not set").tag(0)
                        ForEach(1...50, id: \.self) { n in
                            Text(n == 1 ? "1 year" : "\(n) years").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Hourly rate") {
                    TextField("Rate", text: $hourlyRate)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(currencyOptionsForPicker) { option in
                            Text("\(option.symbol)  \(option.code) — \(option.displayName)")
                                .tag(option.code)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Add role" : "Edit role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(item: $showYearsCelebration, onDismiss: onDismiss) { item in
                ConfettiUnlockSheet(
                    title: item.years == 1 ? "1 year!" : "\(item.years) years!",
                    subtitle: item.companyName.isEmpty ? "Thanks for your dedication." : "\(item.years) years at \(item.companyName)."
                )
            }
        }
    }

    private func save() {
        guard let rate = Double(hourlyRate.replacingOccurrences(of: ",", with: "")), rate > 0 else { return }
        let company = companyName.trimmingCharacters(in: .whitespaces)
        let years = yearsWorkedAtCompany > 0 ? yearsWorkedAtCompany : nil
        let shouldCelebrateYears = years != nil && (existing == nil ? true : (existing?.yearsWorkedAtCompany ?? 0) != years)
        if let existing = existing {
            var updated = existing
            updated.companyName = company
            updated.year = year
            updated.jobTitle = jobTitle.trimmingCharacters(in: .whitespaces)
            updated.hourlyRate = rate
            updated.currencyCode = currencyCode
            updated.yearsWorkedAtCompany = years
            store.updatePayHistoryEntry(updated)
            if shouldCelebrateYears, let y = years {
                showYearsCelebration = YearsCelebrationItem(years: y, companyName: company)
                return
            }
        } else {
            let entry = PayHistoryEntry(
                companyName: company,
                year: year,
                jobTitle: jobTitle.trimmingCharacters(in: .whitespaces),
                hourlyRate: rate,
                currencyCode: currencyCode,
                yearsWorkedAtCompany: years
            )
            store.addPayHistoryEntry(entry)
            if shouldCelebrateYears, let y = years {
                showYearsCelebration = YearsCelebrationItem(years: y, companyName: company)
                return
            }
        }
        Haptics.success()
        onDismiss()
    }
}
