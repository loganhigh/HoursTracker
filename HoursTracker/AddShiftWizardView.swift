import SwiftUI

// MARK: - Add Shift wizard (two screens)
//
// The ADD path only. Editing an existing shift keeps the single-screen
// `EntryEditorView` — edit is meant to feel different from add.
//
// Screen 1 "When & Where" — date / start / end / location rows, break, shift
//   type, and a live Total Time panel. Tapping the Location / Job row opens
//   the saved-locations picker as a sheet (search + Recent + All + add new)
//   rather than as a separate wizard step.
// Screen 2 "Review" — read-only summary, notes, and Save Shift.
//
// Everything load-bearing is carried over from `EntryEditorView` unchanged:
// the same validation (paid hours > 0 and <= 48, overnight +24h, break longer
// than shift), the same off-day / holiday handling, and the same `store.add`
// save path.

struct AddShiftWizardView: View {
    enum Step: Int, CaseIterable {
        case when = 0, review = 1
    }

    private enum ExpandableField: Hashable {
        case date, start, end
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: HoursStore
    @EnvironmentObject private var liveShift: LiveShiftManager
    @EnvironmentObject private var premium: PremiumManager

    @State private var step: Step = .when
    @State private var direction: Int = 1
    @State private var showingClockInPaywall = false

    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int
    @State private var showCustomBreak: Bool = false

    /// The saved `JobSite` picked from the location sheet, if any.
    @State private var selectedSiteID: String?
    /// The label written to `WorkEntry.locationName` (the chosen site's name).
    @State private var locationLabel: String = ""
    @State private var notes: String = ""

    /// Presents the saved-locations picker as a sheet from screen 1's Location row.
    @State private var showLocationPicker = false

    @State private var shiftKind: EntryEditorView.ShiftKind = .work
    @State private var offDayReason: String = EntryEditorView.offDayReasons[0]

    @State private var expandedField: ExpandableField?

    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showSaveSuccess = false

    // MARK: - Init (defaults mirror EntryEditorView's add mode)

    init(store: HoursStore) {
        self.store = store

        let now = Date()
        let cal = Calendar.current
        let mostRecent = store.entries.filter { !$0.isOffDay }.sorted { $0.date > $1.date }.first

        _date = State(initialValue: cal.startOfDay(for: now))
        _start = State(initialValue: cal.date(
            bySettingHour: mostRecent.map { cal.component(.hour, from: $0.start) } ?? 7,
            minute: mostRecent.map { cal.component(.minute, from: $0.start) } ?? 0,
            second: 0, of: now) ?? now)
        _end = State(initialValue: cal.date(
            bySettingHour: mostRecent.map { cal.component(.hour, from: $0.end) } ?? 17,
            minute: mostRecent.map { cal.component(.minute, from: $0.end) } ?? 0,
            second: 0, of: now) ?? now)
        _breakMinutes = State(initialValue: mostRecent?.breakMinutes ?? 0)
        _showCustomBreak = State(initialValue: {
            let minutes = mostRecent?.breakMinutes ?? 0
            return minutes > 0 && ![15, 30, 45, 60].contains(minutes)
        }())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)

                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        stepContent
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
        .onChange(of: date) { _, newDate in
            // Keep the times on the selected day (same as EntryEditorView).
            start = merge(day: newDate, with: start)
            end = merge(day: newDate, with: end)
        }
        .sheet(isPresented: $showLocationPicker) {
            AddShiftLocationPickerSheet(
                store: store,
                selectedSiteID: $selectedSiteID,
                locationLabel: $locationLabel
            )
        }
        .sheet(isPresented: $showingClockInPaywall) {
            PremiumUpgradeView()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch step {
            case .when: whenStep
            case .review: reviewStep
            }
        }
        .id(step)
        .transition(stepTransition)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let forward = direction >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                Haptics.lightTap()
                if step == .when { dismiss() } else { goBack() }
            } label: {
                Image(systemName: step == .when ? "xmark" : "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.subtext)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppColors.card)
                            .overlay(Circle().stroke(AppColors.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step == .when ? "Close" : "Back")

            Text("Add Shift")
                .appText(.title)
                .foregroundStyle(AppColors.text)

            Spacer()
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .when:
            VStack(spacing: AppSpacing.sm) {
                EntryValidationLine(isValid: canSave, message: validationMessage)
                Button("Continue") { advance() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.55)
            }
        case .review:
            Button("Save Shift") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave || showSaveSuccess)
                .opacity(canSave ? 1 : 0.55)
        }
    }

    // MARK: - Screen 1 · When & Where

    @ViewBuilder
    private var whenStep: some View {
        entryModeToggle

        AddShiftPanel {
            AddShiftFieldRow(
                icon: "calendar",
                label: "Date",
                value: dateText,
                isExpanded: expandedField == .date,
                accessory: .disclosure
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

        if shiftKind == .work {
            AddShiftPanel {
                AddShiftFieldRow(
                    icon: "sunrise",
                    label: "Start Time",
                    value: start.formatted(date: .omitted, time: .shortened),
                    isExpanded: expandedField == .start,
                    accessory: .disclosure
                ) { toggleField(.start) }
                if expandedField == .start { inlineTimePicker($start) }
                EntryRowDivider()
                AddShiftFieldRow(
                    icon: "sunset",
                    label: "End Time",
                    value: endValueText,
                    isExpanded: expandedField == .end,
                    accessory: .disclosure
                ) { toggleField(.end) }
                if expandedField == .end { inlineTimePicker($end) }
            }
        }

        AddShiftPanel {
            AddShiftFieldRow(
                icon: "mappin.and.ellipse",
                label: "Location / Job",
                value: locationValueText,
                isPlaceholder: locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessory: .chevron
            ) {
                Haptics.lightTap()
                showLocationPicker = true
            }
        }

        if shiftKind == .work {
            EntryBreakSection(breakMinutes: $breakMinutes, showCustom: $showCustomBreak)
        }

        EntryShiftTypeSection(
            kind: $shiftKind,
            offDayReason: $offDayReason,
            reasons: EntryEditorView.offDayReasons
        )

        if shiftKind == .work {
            AddShiftTotalTimePanel(hours: paidHours, caption: totalCaption)
        }
    }

    /// "Manual" / "Clock In" pill — manual is always the selected state here
    /// (this screen only exists for manual entry); tapping Clock In starts a
    /// live shift instead (Pro-gated), and the parent router swaps this
    /// sheet for `LiveShiftTrackingView` once `LiveShiftManager.activeShift`
    /// is set.
    private var entryModeToggle: some View {
        HStack(spacing: 4) {
            Text("Manual")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppColors.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(AppColors.accentGradient))

            Button {
                Haptics.lightTap()
                if premium.isPremium {
                    liveShift.clockIn()
                } else {
                    showingClockInPaywall = true
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Clock In")
                    if !premium.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(AppColors.subtext)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(
            Capsule()
                .fill(AppColors.card)
                .overlay(Capsule().stroke(AppColors.stroke, lineWidth: 1))
        )
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

    // MARK: - Screen 2 · Review

    @ViewBuilder
    private var reviewStep: some View {
        AddShiftPanel {
            AddShiftFieldRow(icon: "calendar", label: "Date", value: dateText, accessory: .hidden)
            if shiftKind == .work {
                EntryRowDivider()
                AddShiftFieldRow(
                    icon: "sunrise",
                    label: "Start Time",
                    value: start.formatted(date: .omitted, time: .shortened),
                    accessory: .hidden
                )
                EntryRowDivider()
                AddShiftFieldRow(icon: "sunset", label: "End Time", value: endValueText, accessory: .hidden)
                if breakMinutes > 0 {
                    EntryRowDivider()
                    AddShiftFieldRow(
                        icon: "cup.and.saucer",
                        label: "Break",
                        value: "\(breakMinutes) min",
                        accessory: .hidden
                    )
                }
            } else {
                EntryRowDivider()
                AddShiftFieldRow(
                    icon: shiftKind == .holiday ? "airplane" : "moon.zzz",
                    label: "Shift Type",
                    value: shiftKind == .holiday ? "Holiday" : "Off day · \(offDayReason)",
                    accessory: .hidden
                )
            }
            EntryRowDivider()
            AddShiftFieldRow(
                icon: "mappin.and.ellipse",
                label: "Location / Job",
                value: locationValueText,
                isPlaceholder: locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessory: .hidden
            )
        }

        if shiftKind == .work {
            AddShiftTotalTimePanel(hours: paidHours, caption: totalCaption)
        }

        AddShiftConfirmationPanel(
            isValid: canSave,
            title: canSave ? "Looks good!" : "Check the times",
            message: canSave ? "This shift will be saved to your log." : validationMessage
        )

        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel("Notes")
            AddShiftPanel {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .appText(.body)
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1...4)
                    .tint(AppColors.accent)
            }
        }
    }

    // MARK: - Derived text

    private var dateText: String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private var endValueText: String {
        let text = end.formatted(date: .omitted, time: .shortened)
        return isOvernight ? "\(text) (+1 day)" : text
    }

    private var locationValueText: String {
        let trimmed = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Select location or job" : trimmed
    }

    private var totalCaption: String {
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        let span = isOvernight ? "\(s) – \(e) +1" : "\(s) – \(e)"
        return breakMinutes > 0 ? "\(span) · \(breakMinutes)m break" : span
    }

    private var isOvernight: Bool {
        end.timeIntervalSince(start) < 0
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        Haptics.lightTap()
        direction = 1
        expandedField = nil
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        direction = -1
        expandedField = nil
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            step = previous
        }
    }

    private func toggleField(_ field: ExpandableField) {
        Haptics.lightTap()
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            expandedField = expandedField == field ? nil : field
        }
    }

    // MARK: - Validation & save (identical semantics to EntryEditorView)

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
        case .holiday: reason = EntryEditorView.holidayReason
        }

        var entry = WorkEntry(date: date, start: s, end: e, breakMinutes: br,
                              notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                              isOffDay: isOffKind, offDayReason: reason, isHoliday: false)
        entry.locationName = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.locationURL = ""
        entry.latitude = nil
        entry.longitude = nil
        withAnimation(AppMotion.Spring.smooth) { store.add(entry) }

        Haptics.success()
        showSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            dismiss()
        }
    }
}
