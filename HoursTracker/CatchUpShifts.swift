import SwiftUI

// MARK: - Planner

/// Works out which usual workdays a returning user skipped logging, with each
/// day pre-filled from their most recent shift on the same weekday.
///
/// Only the trailing gap counts — days after the latest logged entry (shift or
/// off day). Gaps between logged days are left alone: if someone logged Monday
/// and Wednesday, Tuesday was most likely a day off, not a forgotten shift.
enum CatchUpPlanner {
    /// Never reach back further than this.
    static let maxDays = 14
    /// Need this much history before guessing anyone's routine.
    static let minWorkShifts = 6

    static func missedShifts(
        entries: [WorkEntry],
        dismissedDayKeys: Set<String> = [],
        liveShiftRunning: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkEntry] {
        guard let lastDay = entries.map({ calendar.startOfDay(for: $0.date) }).max() else { return [] }
        let work = entries.filter { !$0.isOffDay }
        guard work.count >= minWorkShifts else { return [] }

        // The routine as it was up to the last logged day. Measuring back from
        // `now` would find nothing for someone who has been away a while.
        guard let windowEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return [] }
        let usual = WorkScheduleInference.usualWorkWeekdays(
            entries: entries, lookbackDays: 28, minOccurrences: 3,
            now: windowEnd, calendar: calendar
        )
        guard !usual.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -maxDays, to: today),
              var day = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return [] }
        if day < earliest { day = earliest }

        let byRecency = work.sorted { $0.start > $1.start }
        var missed: [WorkEntry] = []
        while day <= today {
            let weekday = calendar.component(.weekday, from: day)
            if usual.contains(weekday),
               !dismissedDayKeys.contains(dayKey(day, calendar: calendar)),
               let template = byRecency.first(where: { calendar.component(.weekday, from: $0.date) == weekday }),
               let entry = shift(on: day, like: template, now: now, calendar: calendar) {
                // Today only once its usual shift is over, and never while a
                // live shift is running.
                let isToday = day == today
                if !isToday || (!liveShiftRunning && entry.end.addingTimeInterval(30 * 60) <= now) {
                    missed.append(entry)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return missed
    }

    /// `template`'s clock times, break, job and place, moved to `day`.
    static func shift(on day: Date, like template: WorkEntry, now: Date, calendar: Calendar) -> WorkEntry? {
        let hm = calendar.dateComponents([.hour, .minute], from: template.start)
        guard let start = calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day) else {
            return nil
        }
        // Keep the template's exact span, overnight shifts included.
        let end = start.addingTimeInterval(template.end.timeIntervalSince(template.start))
        var entry = WorkEntry(date: day, start: start, end: end, breakMinutes: template.breakMinutes, notes: "")
        entry.locationName = template.locationName
        entry.locationURL = template.locationURL
        entry.latitude = template.latitude
        entry.longitude = template.longitude
        entry.jobID = template.jobID
        entry.createdAt = now
        return entry
    }

    static func dayKey(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "You missed Tue–Thu." / "You missed Tuesday's shift." / "You missed 4 shifts."
    static func summary(for shifts: [WorkEntry], calendar: Calendar = .current) -> String {
        guard let first = shifts.first?.date, let last = shifts.last?.date else { return "" }
        if shifts.count == 1 {
            return "You missed \(first.formatted(.dateTime.weekday(.wide)))'s shift."
        }
        let span = calendar.dateComponents([.day], from: first, to: last).day ?? 99
        let consecutive = span == shifts.count - 1
        if consecutive && span < 7 {
            let a = first.formatted(.dateTime.weekday(.abbreviated))
            let b = last.formatted(.dateTime.weekday(.abbreviated))
            return "You missed \(a)–\(b)."
        }
        return "You missed \(shifts.count) shifts."
    }
}

// MARK: - Dismissed days

/// Days the user has already answered (logged or skipped), so the sheet never
/// asks about the same day twice.
enum CatchUpDismissals {
    private static let key = "catchup_dismissed_days_v1"

    static var keys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func add(_ days: [Date]) {
        var all = keys
        for day in days { all.insert(CatchUpPlanner.dayKey(day)) }
        // Only the last few weeks can ever be asked about; keep the list small.
        let recent = all.sorted().suffix(60)
        UserDefaults.standard.set(Array(recent), forKey: key)
    }
}

/// Identifiable wrapper for `.sheet(item:)`.
struct CatchUpBatch: Identifiable {
    let id = UUID()
    let shifts: [WorkEntry]
}

// MARK: - Sheet

/// "You missed Tue–Thu. Were these your usual shifts?" — every day ticked,
/// one button logs them all.
struct CatchUpSheet: View {
    let shifts: [WorkEntry]
    let store: HoursStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>

    init(shifts: [WorkEntry], store: HoursStore) {
        self.shifts = shifts
        self.store = store
        _selected = State(initialValue: Set(shifts.map(\.id)))
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            VStack(spacing: 6) {
                Text("Catch up on your shifts")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                Text("\(CatchUpPlanner.summary(for: shifts)) Were these your usual shifts?")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, AppSpacing.lg)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(shifts) { shift in row(shift) }
                }
            }

            Button {
                logSelected()
            } label: {
                Text(selected.count == 1 ? "Log 1 shift" : "Log \(selected.count) shifts")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected.isEmpty)

            Button("Not now") {
                CatchUpDismissals.add(shifts.map(\.date))
                dismiss()
            }
            .appText(.subheadline)
            .foregroundStyle(AppColors.subtext)
            .padding(.bottom, AppSpacing.sm)
        }
        .padding(.horizontal, AppSpacing.lg)
        .background(AppColors.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func row(_ shift: WorkEntry) -> some View {
        let isOn = selected.contains(shift.id)
        return Button {
            Haptics.lightTap()
            if isOn { selected.remove(shift.id) } else { selected.insert(shift.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn ? AppColors.accent : AppColors.subtext)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                    Text(timeRange(shift))
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                }
                Spacer(minLength: 0)
                Text(String(format: "%.1fh", shift.paidHours))
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
            }
            .padding(AppSpacing.md)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppColors.card))
        }
        .buttonStyle(.plain)
    }

    private func timeRange(_ shift: WorkEntry) -> String {
        let t = Date.FormatStyle.dateTime.hour().minute()
        var text = "\(shift.start.formatted(t)) – \(shift.end.formatted(t))"
        if shift.breakMinutes > 0 { text += " · \(shift.breakMinutes)m break" }
        return text
    }

    private func logSelected() {
        Haptics.success()
        for shift in shifts where selected.contains(shift.id) {
            store.add(shift)
        }
        // Unticked days were answered too ("didn't work that day").
        CatchUpDismissals.add(shifts.map(\.date))
        dismiss()
    }
}
