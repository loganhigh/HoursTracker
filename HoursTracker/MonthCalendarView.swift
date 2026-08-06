import SwiftUI

// MARK: - Month calendar (Phase 5)
//
// Calendar navigation for MonthDetailView: a month grid where each day
// carries a small dot scaled by hours worked (three buckets), logged off
// days show a hollow dot, today is ringed with the accent, and days from
// adjacent months are dimmed. Tapping a day with entries selects it; the
// parent shows a day-detail strip under the calendar.

struct MonthCalendarView: View {
    let monthDate: Date
    let entries: [WorkEntry]
    @Binding var selectedDay: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cal: Calendar { Calendar.current }

    private struct GridDay: Identifiable {
        let id: Date
        let inMonth: Bool
    }

    // MARK: - Derived data

    private var hoursByDay: [Date: Double] {
        var totals: [Date: Double] = [:]
        for entry in entries where !entry.isOffDay {
            totals[cal.startOfDay(for: entry.date), default: 0] += entry.paidHours
        }
        return totals
    }

    private var offDays: Set<Date> {
        Set(entries.filter(\.isOffDay).map { cal.startOfDay(for: $0.date) })
    }

    /// Full weeks covering the month — leading/trailing days from adjacent
    /// months included (dimmed) so the grid is always rectangular.
    private var gridDays: [GridDay] {
        let monthStart = cal.startOfDay(
            for: cal.date(from: cal.dateComponents([.year, .month], from: monthDate)) ?? monthDate
        )
        guard let dayRange = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = cal.component(.weekday, from: monthStart)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let total = Int((Double(leading + dayRange.count) / 7).rounded(.up)) * 7
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: monthStart) else { return [] }
        return (0..<total).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return GridDay(id: day, inMonth: cal.isDate(day, equalTo: monthStart, toGranularity: .month))
        }
    }

    /// Weekday header symbols ordered by the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index].uppercased())
                        .appText(.eyebrow)
                        .foregroundStyle(AppColors.faint)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(gridDays) { day in
                    dayCell(day)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.stroke, lineWidth: 0.5)
        )
    }

    // MARK: - Cells

    @ViewBuilder
    private func dayCell(_ day: GridDay) -> some View {
        let hours = hoursByDay[day.id] ?? 0
        let isOff = offDays.contains(day.id)
        let hasEntries = day.inMonth && (hours > 0 || isOff)
        let isToday = cal.isDateInToday(day.id)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day.id) } ?? false

        Button {
            guard hasEntries else { return }
            Haptics.lightTap()
            withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                selectedDay = isSelected ? nil : day.id
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day.id))")
                    .font(.system(size: 13, weight: hasEntries ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dayNumberColor(day, hasEntries: hasEntries))
                    .frame(width: 28, height: 28)
                    .overlay {
                        if isToday {
                            Circle()
                                .stroke(AppColors.accent, lineWidth: 1.2)
                        }
                    }

                dot(hours: hours, isOff: isOff, inMonth: day.inMonth)
                    .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .fill(isSelected ? AppColors.accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasEntries)
        .accessibilityLabel(accessibilityLabel(day, hours: hours, isOff: isOff))
    }

    private func dayNumberColor(_ day: GridDay, hasEntries: Bool) -> Color {
        if !day.inMonth { return AppColors.faint.opacity(0.5) }
        return hasEntries ? AppColors.text : AppColors.subtext
    }

    /// Hours dot in three buckets; off days hollow; empty days blank.
    @ViewBuilder
    private func dot(hours: Double, isOff: Bool, inMonth: Bool) -> some View {
        if !inMonth {
            Color.clear
        } else if hours >= 10 {
            Circle().fill(AppColors.accent).frame(width: 8, height: 8)
        } else if hours >= 6 {
            Circle().fill(AppColors.accent.opacity(0.85)).frame(width: 6, height: 6)
        } else if hours > 0 {
            Circle().fill(AppColors.accent.opacity(0.65)).frame(width: 4.5, height: 4.5)
        } else if isOff {
            Circle().stroke(AppColors.subtext, lineWidth: 1).frame(width: 5, height: 5)
        } else {
            Color.clear
        }
    }

    private func accessibilityLabel(_ day: GridDay, hours: Double, isOff: Bool) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        let name = df.string(from: day.id)
        if hours > 0 { return "\(name), \(AppTheme.Format.hours(hours)) worked" }
        if isOff { return "\(name), off day" }
        return name
    }
}

// MARK: - Day detail strip
//
// Shown under the calendar when a day is selected: date, shift count, and
// that day's entries, each tappable into the existing entry editor.

struct MonthDayDetailStrip: View {
    @ObservedObject var store: HoursStore
    let day: Date
    let entries: [WorkEntry]

    private var workEntries: [WorkEntry] {
        entries.filter { !$0.isOffDay }
    }

    private var headerCaption: String {
        if workEntries.isEmpty {
            return entries.isEmpty ? "No entries" : "Off day"
        }
        let hours = workEntries.reduce(0) { $0 + $1.paidHours }
        let shiftWord = workEntries.count == 1 ? "shift" : "shifts"
        return "\(workEntries.count) \(shiftWord) · \(AppTheme.Format.hours(hours))"
    }

    private var dayTitle: String {
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d"
        return df.string(from: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(dayTitle)
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Spacer()
                Text(headerCaption)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }

            ForEach(entries) { entry in
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
            }
        }
        .padding(AppSpacing.sm)
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
