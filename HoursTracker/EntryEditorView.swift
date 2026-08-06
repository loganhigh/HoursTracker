import SwiftUI

// MARK: - Entry editor (Phase 4 rebuild)
//
// One fast, quiet editor for both add and edit. Presets fill the form
// instantly (add mode), Start/End rows expand inline native pickers, breaks
// are one tap, and a live summary card shows the hour breakdown as you type.
// The save/delete paths into HoursStore are unchanged.

struct EntryEditorView: View {
    enum Mode {
        case add
        case edit(WorkEntry)
    }

    enum ShiftKind: Hashable {
        case work, offDay, holiday
    }

    enum EditorPreset: Hashable {
        case yesterday, usual, custom
    }

    private enum ExpandableField: Hashable {
        case date, start, end
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: HoursStore
    private let mode: Mode

    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int

    /// Free-form label for the location and/or job of the day. Stored in `WorkEntry.locationName`.
    @State private var locationLabel: String
    @State private var notes: String

    @State private var shiftKind: ShiftKind
    @State private var offDayReason: String

    @State private var selectedPreset: EditorPreset = .custom
    @State private var expandedField: ExpandableField?
    @State private var showCustomBreak: Bool
    @State private var isApplyingPreset = false

    @State private var showDeleteConfirm = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showSaveSuccess = false

    private let yesterdayPreset: EntryShiftPreset?
    private let usualPreset: EntryShiftPreset?

    /// Shared with `AddShiftWizardView` so both editors offer the same reasons.
    static let offDayReasons = ["Sick", "Appointment", "Vacation", "Personal", "Other"]
    static let holidayReason = "Holiday"

    // MARK: - Init (same signature as before — all call sites unchanged)

    init(store: HoursStore, mode: Mode) {
        self.store = store
        self.mode = mode

        let now = Date()
        let cal = Calendar.current

        switch mode {
        case .add:
            _date = State(initialValue: cal.startOfDay(for: now))

            let mostRecentEntry = store.entries.filter { !$0.isOffDay }.sorted { $0.date > $1.date }.first
            let defaultStartHour = mostRecentEntry.map { cal.component(.hour, from: $0.start) } ?? 7
            let defaultStartMinute = mostRecentEntry.map { cal.component(.minute, from: $0.start) } ?? 0
            let defaultEndHour = mostRecentEntry.map { cal.component(.hour, from: $0.end) } ?? 17
            let defaultEndMinute = mostRecentEntry.map { cal.component(.minute, from: $0.end) } ?? 0

            _start = State(initialValue: cal.date(bySettingHour: defaultStartHour, minute: defaultStartMinute, second: 0, of: now) ?? now)
            _end = State(initialValue: cal.date(bySettingHour: defaultEndHour, minute: defaultEndMinute, second: 0, of: now) ?? now)
            _breakMinutes = State(initialValue: mostRecentEntry?.breakMinutes ?? 0)

            _locationLabel = State(initialValue: "")
            _notes = State(initialValue: "")
            _shiftKind = State(initialValue: .work)
            _offDayReason = State(initialValue: Self.offDayReasons[0])
            _showCustomBreak = State(initialValue: false)

            yesterdayPreset = EntryShiftPreset.yesterday(in: store.entries, calendar: cal)
            usualPreset = EntryShiftPreset.usual(in: store.entries, calendar: cal)

        case .edit(let entry):
            _date = State(initialValue: entry.date)
            _start = State(initialValue: entry.start)
            _end = State(initialValue: entry.end)
            _breakMinutes = State(initialValue: entry.breakMinutes)

            _locationLabel = State(initialValue: entry.locationName)
            _notes = State(initialValue: entry.notes)

            if entry.isOffDay {
                _shiftKind = State(initialValue: entry.offDayReason == Self.holidayReason ? .holiday : .offDay)
            } else {
                _shiftKind = State(initialValue: .work)
            }
            _offDayReason = State(initialValue: Self.offDayReasons.contains(entry.offDayReason) ? entry.offDayReason : Self.offDayReasons[0])
            _showCustomBreak = State(initialValue: entry.breakMinutes > 0 && ![15, 30, 45, 60].contains(entry.breakMinutes))

            yesterdayPreset = nil
            usualPreset = nil
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.sm)

                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        if !isEditing { presetsRow }
                        dateCard
                        if shiftKind == .work {
                            timesCard
                            EntryBreakSection(breakMinutes: $breakMinutes, showCustom: $showCustomBreak)
                        }
                        EntryShiftTypeSection(kind: $shiftKind, offDayReason: $offDayReason, reasons: Self.offDayReasons)
                        if shiftKind == .work { summarySection }
                        EntryDetailsSection(locationLabel: $locationLabel, notes: $notes)
                        if isEditing {
                            EntryDeleteRow { showDeleteConfirm = true }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xxs)
                    .padding(.bottom, AppSpacing.xl)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
            }
        }
        .toast(isPresented: $showToast, message: toastMessage, showsCheckmark: false)
        .alert("Delete this shift?", isPresented: $showDeleteConfirm) {
            Button("Delete Shift", role: .destructive) { deleteEntry() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
        .onChange(of: date) { _, newDate in
            let applying = isApplyingPreset
            isApplyingPreset = true
            start = merge(day: newDate, with: start)
            end = merge(day: newDate, with: end)
            DispatchQueue.main.async { isApplyingPreset = applying }
        }
        .onChange(of: start) { _, _ in invalidatePresetIfNeeded() }
        .onChange(of: end) { _, _ in invalidatePresetIfNeeded() }
        .onChange(of: breakMinutes) { _, _ in invalidatePresetIfNeeded() }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    Text("Editing")
                        .appText(.eyebrow)
                        .foregroundStyle(AppColors.accent)
                }
                Text(isEditing ? "Edit Shift" : "Add Shift")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
            }
            Spacer()
            Button("Cancel") {
                Haptics.lightTap()
                dismiss()
            }
            .appText(.subheadline)
            .foregroundStyle(AppColors.subtext)
            .padding(.vertical, AppSpacing.xxs)
        }
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.sm) {
            EntryValidationLine(isValid: canSave, message: validationMessage)
            Button(isEditing ? "Save Changes" : "Save Shift") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave || showSaveSuccess)
                .opacity(canSave ? 1 : 0.55)
        }
    }

    // MARK: - Presets (add mode only)

    private var presetsRow: some View {
        HStack(spacing: AppSpacing.xs) {
            if let yesterdayPreset {
                EntryPresetCard(
                    title: "Same as yesterday",
                    caption: yesterdayPreset.caption,
                    isSelected: selectedPreset == .yesterday
                ) { apply(preset: yesterdayPreset, kind: .yesterday) }
            }
            if let usualPreset {
                EntryPresetCard(
                    title: "Usual shift",
                    caption: usualPreset.caption,
                    isSelected: selectedPreset == .usual
                ) { apply(preset: usualPreset, kind: .usual) }
            }
            EntryPresetCard(
                title: "Custom",
                caption: "Set your own times",
                isSelected: selectedPreset == .custom
            ) {
                Haptics.lightTap()
                withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                    selectedPreset = .custom
                }
            }
        }
    }

    private func apply(preset: EntryShiftPreset, kind: EditorPreset) {
        Haptics.lightTap()
        isApplyingPreset = true
        withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
            selectedPreset = kind
            shiftKind = .work
            start = merge(day: date, with: preset.start)
            end = merge(day: date, with: preset.end)
            breakMinutes = preset.breakMinutes
            showCustomBreak = preset.breakMinutes > 0 && ![15, 30, 45, 60].contains(preset.breakMinutes)
        }
        DispatchQueue.main.async { isApplyingPreset = false }
    }

    private func invalidatePresetIfNeeded() {
        guard !isApplyingPreset, selectedPreset != .custom else { return }
        selectedPreset = .custom
    }

    // MARK: - Date / times

    private var dateCard: some View {
        EntryEditorCard {
            EntryFieldRow(
                title: "Date",
                dayText: "",
                valueText: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                isExpanded: expandedField == .date
            ) { toggleField(.date) }
            if expandedField == .date {
                EntryRowDivider()
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(AppColors.accent)
                    .padding(.top, AppSpacing.xxs)
            }
        }
    }

    private var timesCard: some View {
        EntryEditorCard {
            EntryFieldRow(
                title: "Start",
                dayText: dayCaption(offsetDay: false),
                valueText: start.formatted(date: .omitted, time: .shortened),
                isExpanded: expandedField == .start
            ) { toggleField(.start) }
            if expandedField == .start {
                inlineTimePicker($start)
            }
            EntryRowDivider()
            EntryFieldRow(
                title: "End",
                dayText: dayCaption(offsetDay: isOvernight),
                valueText: end.formatted(date: .omitted, time: .shortened),
                isExpanded: expandedField == .end
            ) { toggleField(.end) }
            if expandedField == .end {
                inlineTimePicker($end)
            }
        }
    }

    private func inlineTimePicker(_ selection: Binding<Date>) -> some View {
        DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(AppColors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
    }

    private func toggleField(_ field: ExpandableField) {
        Haptics.lightTap()
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            expandedField = expandedField == field ? nil : field
        }
    }

    private var isOvernight: Bool {
        end.timeIntervalSince(start) < 0
    }

    private func dayCaption(offsetDay: Bool) -> String {
        let cal = Calendar.current
        let day = offsetDay ? (cal.date(byAdding: .day, value: 1, to: date) ?? date) : date
        let label = day.formatted(.dateTime.weekday(.abbreviated))
        return offsetDay ? "\(label) +1" : label
    }

    // MARK: - Summary (hours only — never money)

    private var summarySection: some View {
        let breakdown = store.payBreakdown(for: draftEntry)
        return EntrySummaryCard(
            totalHours: paidHours,
            regularHours: breakdown.regularHours,
            overtimeHours: breakdown.overtimeHoursAt1_5,
            doubleTimeHours: breakdown.overtimeHoursAt2_0,
            start: start,
            end: end,
            breakMinutes: breakMinutes
        )
    }

    /// The entry as currently drafted, for live breakdown math. Keeps the
    /// edited entry's identity so weekly-overtime lookups stay coherent.
    private var draftEntry: WorkEntry {
        var entry: WorkEntry
        if case .edit(let old) = mode {
            entry = old
        } else {
            entry = WorkEntry(date: date, start: start, end: end, breakMinutes: breakMinutes, notes: "")
        }
        entry.date = date
        entry.start = start
        entry.end = end
        entry.breakMinutes = breakMinutes
        entry.isOffDay = false
        entry.isHoliday = false
        return entry
    }

    // MARK: - Validation & save (unchanged semantics)

    private var isOffKind: Bool { shiftKind != .work }

    private var canSave: Bool {
        if isOffKind { return true }
        return isValid
    }

    private var isValid: Bool {
        if isOffKind { return true }
        return paidHours > 0 && paidHours <= 48
    }

    private var paidHours: Double {
        var raw = end.timeIntervalSince(start) / 3600.0
        if raw < 0 {
            raw += 24
        }
        let breakHrs = Double(max(0, breakMinutes)) / 60.0
        return max(0, raw - breakHrs)
    }

    private var validationMessage: String {
        switch shiftKind {
        case .offDay:
            return "Off day — no hours logged"
        case .holiday:
            return "Holiday — no hours logged"
        case .work:
            if paidHours > 48 { return "Shift too long (max 48 hours)" }
            if paidHours <= 0 {
                let rawSpan = end.timeIntervalSince(start)
                if rawSpan > 0 && breakMinutes > 0 { return "Break is longer than the shift" }
                return "End time must be after start time"
            }
            return "Looks good — \(AppTheme.Format.hours(paidHours, suffix: "")) hours"
        }
    }

    private func merge(day: Date, with time: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        let timeComps = cal.dateComponents([.hour, .minute], from: time)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = 0
        return cal.date(from: comps) ?? day
    }

    private func save() {
        if !isValid {
            Haptics.error()
            toastMessage = paidHours > 48 ? "Shift too long (max 48 hours)" : "Invalid hours"
            showToast = true
            return
        }

        let cal = Calendar.current
        let (s, e, br) = isOffKind
            ? (cal.startOfDay(for: date), cal.startOfDay(for: date), 0)
            : (start, end, breakMinutes)

        let reason: String
        switch shiftKind {
        case .work: reason = ""
        case .offDay: reason = offDayReason
        case .holiday: reason = Self.holidayReason
        }

        let trimmedLabel = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .add:
            var entry = WorkEntry(date: date, start: s, end: e, breakMinutes: br, notes: trimmedNotes,
                                  isOffDay: isOffKind, offDayReason: reason, isHoliday: false)
            entry.locationName = trimmedLabel
            entry.locationURL = ""
            entry.latitude = nil
            entry.longitude = nil
            withAnimation(AppMotion.Spring.smooth) { store.add(entry) }
        case .edit(let old):
            var updated = old
            updated.date = date
            updated.start = s
            updated.end = e
            updated.breakMinutes = br
            updated.notes = trimmedNotes
            updated.locationName = trimmedLabel
            updated.locationURL = ""
            updated.latitude = nil
            updated.longitude = nil
            updated.isOffDay = isOffKind
            updated.offDayReason = reason
            updated.isHoliday = false
            withAnimation(AppMotion.Spring.smooth) { store.update(updated) }
        }
        Haptics.success()
        showSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            dismiss()
        }
    }

    private func deleteEntry() {
        guard case .edit(let entry) = mode else { return }
        Haptics.mediumTap()
        withAnimation(AppMotion.Spring.smooth) { store.delete(entry) }
        toastMessage = "Shift deleted"
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            dismiss()
        }
    }
}
