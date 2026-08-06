import SwiftUI
import UIKit

// MARK: - Year archives
// Moved out of SideMenu.swift during the tab-navigation restructure.
// Content unchanged apart from dropping the sheet chrome (NavigationStack +
// Done button) so the list works pushed from the History tab.

struct YearArchivesListView: View {
    @ObservedObject var store: HoursStore

    var body: some View {
        Group {
            if store.yearArchives.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.faint)
                    Text("No archived years yet")
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.text)
                    Text("Completed years appear here when entries roll over.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
            } else {
                List {
                    ForEach(store.yearArchives.sorted(by: { $0.year > $1.year })) { arch in
                        NavigationLink {
                            ArchivedYearEntriesView(store: store, archive: arch)
                        } label: {
                            Text("\(arch.year) — \(arch.entries.count) entries")
                        }
                    }
                }
            }
        }
        .navigationTitle("Year archives")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ArchivedYearEntriesView: View {
    @ObservedObject var store: HoursStore
    let archive: YearArchive

    @State private var didCopyAll = false
    @State private var copyAllBurst = 0

    private var sortedEntries: [WorkEntry] {
        archive.entries.sorted { $0.date > $1.date }
    }

    private var workEntries: [WorkEntry] {
        sortedEntries.filter { !$0.isOffDay }
    }

    private var totalHours: Double {
        workEntries.reduce(0) { $0 + $1.paidHours }
    }

    private var regularHours: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).regularHours }
    }

    private var overtimeHours: Double {
        workEntries.reduce(0) { $0 + store.payBreakdown(for: $1).overtimeHours }
    }

    private var offDayCount: Int {
        sortedEntries.filter(\.isOffDay).count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Total hours")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text(AppTheme.Format.hours(totalHours, suffix: ""))
                            .font(AppDesignSystem.Typography.heroNumerals(size: 24, weight: .medium))
                    }

                    Divider()

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
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }

            Section {
                ForEach(sortedEntries) { entry in
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
                    copyAllEntries(sortedEntries)
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
            } header: {
                Text("Entries")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle(String(archive.year))
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
        return entries
            .sorted { $0.date > $1.date }
            .map { $0.formattedForCopy(dateFormatter: df, timeFormatter: tf) }
            .joined(separator: "\n\n")
    }
}

// MARK: - Pay Period Mini Calendar
// Moved unchanged from SideMenu.swift.

/// Pay-period breakdown as a horizontal bar chart — one row per day from the
/// start of the cheque through today, with a proportional bar for hours worked.
/// Unworked past days show a faded track and an em dash.
struct PayPeriodMiniCalendar: View {
    let cycle: PayCycle
    let entries: [WorkEntry]

    @Environment(\.semanticColors) private var theme

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    /// Total paid hours logged on each day in the cycle (non-off-day entries).
    private var hoursByDay: [Date: Double] {
        var totals: [Date: Double] = [:]
        for entry in entries where !entry.isOffDay {
            let day = cal.startOfDay(for: entry.date)
            totals[day, default: 0] += entry.paidHours
        }
        return totals
    }

    /// Count of shifts logged on each day (non-off-day entries).
    private var shiftsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for entry in entries where !entry.isOffDay {
            let day = cal.startOfDay(for: entry.date)
            counts[day, default: 0] += 1
        }
        return counts
    }

    /// Days explicitly logged as an off day.
    private var offDays: Set<Date> {
        Set(entries.filter(\.isOffDay).map { cal.startOfDay(for: $0.date) })
    }

    /// First off-day entry per calendar day (for reason / holiday label).
    private var offDayEntryByDay: [Date: WorkEntry] {
        var map: [Date: WorkEntry] = [:]
        for entry in entries.filter(\.isOffDay) {
            let day = cal.startOfDay(for: entry.date)
            map[day] = entry
        }
        return map
    }

    private func isHolidayDay(_ day: Date) -> Bool {
        guard let entry = offDayEntryByDay[day] else { return false }
        if entry.isHoliday { return true }
        return entry.offDayReason.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare("Holiday", options: .caseInsensitive) == .orderedSame
    }

    private func offDayBarLabel(for day: Date) -> String {
        isHolidayDay(day) ? "Holiday" : "OFF"
    }

    /// Days from the start of the cheque through today (never into the future).
    /// Falls back to the whole period if today lands outside the cycle.
    private var days: [Date] {
        let start = cal.startOfDay(for: cycle.start)
        let lastCycleDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: cycle.end)) ?? cycle.end
        let cap = min(lastCycleDay, today)
        var list: [Date] = []
        var day = start
        while day <= (cap >= start ? cap : lastCycleDay) {
            list.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return list
    }

    private var totalHours: Double {
        hoursByDay.values.reduce(0, +)
    }

    private var totalShifts: Int {
        shiftsByDay.values.reduce(0, +)
    }

    private var rangeLabel: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let lastDay = cal.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end
        return "\(df.string(from: cycle.start)) – \(df.string(from: lastDay))"
    }

    private var summaryLabel: String {
        let shiftWord = totalShifts == 1 ? "shift" : "shifts"
        return "\(totalShifts) \(shiftWord) • \(hoursDisplay(totalHours))"
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header — single centered stack so title, dates, and summary align
            VStack(spacing: 3) {
                Text("This Cheque")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(rangeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(summaryLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Bars
            VStack(spacing: 3) {
                ForEach(days, id: \.self) { day in
                    dayRow(day)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let hours = hoursByDay[day] ?? 0
        let shifts = shiftsByDay[day] ?? 0
        let hasShift = hours > 0 || shifts > 0
        let isOffDay = offDays.contains(day)
        let isHoliday = isHolidayDay(day)

        HStack(spacing: 10) {
            // Day label
            VStack(alignment: .center, spacing: 0) {
                Text(dayAbbrev(day))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hasShift || isOffDay ? AppTheme.Colors.subtext : AppTheme.Colors.faint)
                Text(dayNum(day))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(hasShift || isOffDay ? AppTheme.Colors.text : AppTheme.Colors.faint)
            }
            .frame(width: 36)

            // Progress bar — flat full-width pill for every logged day (no
            // proportional fill) so the row reads calmly at a glance; hours
            // are still called out precisely in the trailing column.
            GeometryReader { geo in
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(offDayRowFill(hasShift: hasShift, isOffDay: isOffDay, isHoliday: isHoliday, theme: theme))
                        .frame(height: 24)
                    if hasShift {
                        Text("WORKED")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(AppTheme.Colors.success)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .frame(width: geo.size.width, height: 24, alignment: .center)
                    }
                    if isOffDay {
                        Text(offDayBarLabel(for: day))
                            .font(.system(size: isHoliday ? 10 : 11, weight: .heavy, design: .rounded))
                            .tracking(isHoliday ? 0.3 : 1)
                            .foregroundStyle(
                                isHoliday
                                    ? Color(red: 0.34, green: 0.74, blue: 0.46)
                                    : AppTheme.Colors.danger
                            )
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .frame(width: geo.size.width, height: 24, alignment: .center)
                    }
                }
            }
            .frame(height: 24)

            // Hours + shift count
            VStack(alignment: .trailing, spacing: 0) {
                Text(hasShift ? hoursDisplay(hours) : "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(hasShift ? AppTheme.Colors.text : AppTheme.Colors.faint)
                    .monospacedDigit()
                if shifts > 1 {
                    Text("\(shifts) shifts")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                }
            }
            .frame(width: 52, alignment: .trailing)
        }
        .opacity(hasShift || isOffDay ? 1 : 0.55)
    }

    /// Off days get a dark red pill (holidays get a dark green pill to match
    /// their green "Holiday" label) so they read as distinctly different
    /// from worked days at a glance, not just a neutral faded track.
    private func offDayRowFill(hasShift: Bool, isOffDay: Bool, isHoliday: Bool, theme: SemanticColors) -> Color {
        if hasShift { return AppTheme.Colors.success.opacity(0.18) }
        if isOffDay {
            return isHoliday
                ? Color(red: 0.34, green: 0.74, blue: 0.46).opacity(0.18)
                : AppTheme.Colors.danger.opacity(0.22)
        }
        return theme.accent.opacity(0.05)
    }

    private func dayAbbrev(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private func dayNum(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private func hoursDisplay(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value) + "h"
        }
        return AppTheme.Format.hours(value)
    }
}
