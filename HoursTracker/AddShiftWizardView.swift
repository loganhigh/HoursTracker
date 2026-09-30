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

    @State private var step: Step = .when
    @State private var direction: Int = 1

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
    /// Stat holiday pay on a "Work" day; nil = an ordinary shift.
    @State private var holidayRule: HolidayPayRule? = nil
    /// The days picked for the "Holiday" shift type — any number, past or
    /// future. Each saves as its own holiday day.
    @State private var holidayDays: Set<DateComponents> = []

    @State private var expandedField: ExpandableField?

    /// "Split at midnight" — remembered across shifts since night workers
    /// need it every time. Only consulted when the times actually cross
    /// midnight, so it's inert for day shifts.
    @AppStorage("split_overnight_at_midnight") private var splitOvernightAtMidnight = false

    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showSaveSuccess = false
    /// Set after a work shift saves; swaps the wizard for the earnings card.
    @State private var earnings: ShiftEarnings?
    /// The saved entries, held while the wage prompt is up so the earnings
    /// card can be built once a wage comes in.
    @State private var savedForPrompt: [WorkEntry] = []
    @State private var showWagePrompt = false

    // MARK: - Init (defaults mirror EntryEditorView's add mode)

    /// `initialDate` pre-selects a day other than today (the times keep the
    /// most-recent-shift defaults, placed on that day).
    init(store: HoursStore, initialDate: Date? = nil) {
        self.store = store

        let cal = Calendar.current
        let today = Date()
        let now = initialDate.map { day in
            min(cal.startOfDay(for: day), cal.startOfDay(for: today))
        } ?? today
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
        if let earnings {
            ShiftEarningsView(store: store, earnings: earnings) { dismiss() }
                .transition(.opacity)
        } else {
            wizardBody
        }
    }

    private var wizardBody: some View {
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

                if step == .review {
                    footer
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.xl)
                }
            }
        }
        .toast(isPresented: $showToast, message: toastMessage, showsCheckmark: false)
        .onChange(of: date) { _, newDate in
            // Keep the times on the selected day (same as EntryEditorView).
            start = merge(day: newDate, with: start)
            end = merge(day: newDate, with: end)
        }
        .onChange(of: shiftKind) { _, kind in
            // Holiday starts from the day already chosen above.
            if kind == .holiday, holidayDays.isEmpty {
                holidayDays = [Calendar.current.dateComponents([.calendar, .era, .year, .month, .day], from: date)]
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            AddShiftLocationPickerSheet(
                store: store,
                selectedSiteID: $selectedSiteID,
                locationLabel: $locationLabel
            )
        }
        .sheet(isPresented: $showWagePrompt, onDismiss: afterWagePrompt) {
            WagePromptSheet(store: store)
        }
    }

    /// Times, break and location are asked for on anything that was worked:
    /// a shift, or a stat holiday paid for hours on the clock.
    private var needsTimes: Bool {
        shiftKind == .work && (holidayRule?.isWorked ?? true)
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

    /// Review step only — the When step's Continue sits inline under Total Time.
    private var footer: some View {
        Button("Save Shift") { save() }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave || showSaveSuccess)
            .opacity(canSave ? 1 : 0.55)
    }

    // MARK: - Screen 1 · When & Where

    @ViewBuilder
    private var whenStep: some View {
        entryModeToggle

        if shiftKind == .work, !store.shiftTemplates.isEmpty {
            templateStrip
        }

        if shiftKind == .holiday {
            holidayDaysPanel
        } else {
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
        }

        if needsTimes {
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

        // A day you didn't work has no job site — asking for one on an off
        // day or holiday was just a question with no right answer.
        if needsTimes {
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

            EntryBreakSection(breakMinutes: $breakMinutes, showCustom: $showCustomBreak)
        }

        EntryShiftTypeSection(
            kind: $shiftKind,
            offDayReason: $offDayReason,
            reasons: EntryEditorView.offDayReasons,
            holidayRule: $holidayRule,
            statHours: store.paySettings.statHolidayPaidHours,
            showsStatHoliday: store.paySettings.statHolidayOptionsEnabled
        )

        if needsTimes {
            AddShiftTotalTimePanel(hours: paidHours, caption: totalCaption)
        }
        if let rule = holidayRule, shiftKind == .work {
            holidayPayPanel(rule)
        }

        if shiftKind == .work && isOvernight {
            splitAtMidnightToggle
        }

        // Sits in the content flow right under Total Time rather than in a
        // pinned footer bar, and carries no panel or card behind it.
        Button("Continue") { advance() }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.55)
    }

    /// "Manual" / "Clock In" pill — manual is always the selected state here
    /// (this screen only exists for manual entry); tapping Clock In starts a
    /// live shift, and the parent router swaps this sheet for
    /// `LiveShiftTrackingView` once `LiveShiftManager.activeShift` is set.
    private var entryModeToggle: some View {
        HStack(spacing: 4) {
            Text("Manual")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppColors.textOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(AppColors.accentGradient))

            Button {
                Haptics.mediumTap()
                liveShift.clockIn()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12, weight: .bold))
                    Text("Clock In")
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

    /// Saved templates as one-tap chips. Applying one fills times, break, and
    /// location — the whole point of the feature is that the usual shift takes
    /// a single tap instead of four pickers.
    private var templateStrip: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            EntrySectionLabel("Templates")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(store.shiftTemplatesByRecency) { template in
                        Button {
                            apply(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .appText(.headline)
                                    .foregroundStyle(AppColors.text)
                                    .lineLimit(1)
                                Text(template.timeRangeText)
                                    .appText(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppColors.subtext)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .fill(matchingTemplateID == template.id
                                          ? AppColors.accent.opacity(0.16)
                                          : AppColors.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                            .stroke(
                                                matchingTemplateID == template.id
                                                    ? AppColors.accent.opacity(0.5)
                                                    : AppColors.stroke,
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// Fills the form from a template. The date is left alone — a template
    /// describes a shift's shape, not which day it happened.
    private func apply(_ template: ShiftTemplate) {
        Haptics.lightTap()
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            start = template.date(template.startMinutes, on: date)
            end = template.date(template.endMinutes, on: date)
            breakMinutes = template.breakMinutes
            showCustomBreak = template.breakMinutes > 0 && ![15, 30, 45, 60].contains(template.breakMinutes)
            if !template.locationName.isEmpty {
                locationLabel = template.locationName
                selectedSiteID = store.jobSites.first {
                    $0.name.caseInsensitiveCompare(template.locationName) == .orderedSame
                }?.id
            }
            expandedField = nil
        }
        store.markShiftTemplateUsed(id: template.id)
    }

    /// The template the form currently matches, if any. Derived rather than
    /// stored: setting an "applied" flag inside `apply` would be cleared by
    /// the very `onChange` handlers that `apply`'s own writes trigger.
    private var matchingTemplateID: String? {
        let s = ShiftTemplate.minutes(from: start)
        let e = ShiftTemplate.minutes(from: end)
        return store.shiftTemplates.first {
            $0.startMinutes == s && $0.endMinutes == e && $0.breakMinutes == breakMinutes
        }?.id
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

    /// Holiday: tap every day you're away. Past or future — a holiday is
    /// often booked ahead.
    private var holidayDaysPanel: some View {
        AddShiftPanel {
            AddShiftFieldRow(icon: "calendar", label: "Days", value: holidayDaysText, accessory: .hidden)
            EntryRowDivider()
            MultiDatePicker("Holiday days", selection: $holidayDays)
                .labelsHidden()
                .tint(AppColors.accent)
                .padding(.top, AppSpacing.xxs)
            Text("Tap each day you're off. Days already logged are skipped.")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The picked holiday days as real dates, oldest first.
    private var holidayDates: [Date] {
        let cal = Calendar.current
        return holidayDays.compactMap { cal.date(from: $0) }.map { cal.startOfDay(for: $0) }.sorted()
    }

    private var holidayDaysText: String {
        let days = holidayDates
        guard let first = days.first, let last = days.last else { return "Pick the days" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        if days.count == 1 { return f.string(from: first) }
        return "\(days.count) days · \(f.string(from: first)) → \(f.string(from: last))"
    }

    // MARK: - Screen 2 · Review

    @ViewBuilder
    private var reviewStep: some View {
        AddShiftPanel {
            AddShiftFieldRow(icon: "calendar", label: shiftKind == .holiday ? "Days" : "Date",
                             value: shiftKind == .holiday ? holidayDaysText : dateText, accessory: .hidden)
            if let rule = holidayRule, shiftKind == .work {
                EntryRowDivider()
                AddShiftFieldRow(icon: "star.circle", label: "Stat holiday", value: rule.title, accessory: .hidden)
            }
            if needsTimes {
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
            } else if shiftKind != .work {
                EntryRowDivider()
                AddShiftFieldRow(
                    icon: shiftKind == .holiday ? "airplane" : "moon.zzz",
                    label: "Shift Type",
                    value: shiftKind == .holiday ? "Holiday" : "Off day · \(offDayReason)",
                    accessory: .hidden
                )
            }
            if needsTimes {
                EntryRowDivider()
                AddShiftFieldRow(
                    icon: "mappin.and.ellipse",
                    label: "Location / Job",
                    value: locationValueText,
                    isPlaceholder: locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    accessory: .hidden
                )
            }
        }

        if needsTimes {
            AddShiftTotalTimePanel(hours: paidHours, caption: totalCaption)
        }
        if let rule = holidayRule, shiftKind == .work {
            holidayPayPanel(rule)
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

    private func holidayPayPanel(_ rule: HolidayPayRule) -> some View {
        AddShiftHolidayPayPanel(
            rule: rule,
            workedHours: rule.isWorked ? paidHours : 0,
            statHours: store.paySettings.statHolidayPaidHours,
            wage: store.paySettings.hourlyRateSet ? store.paySettings.hourlyWage : nil,
            currencyCode: store.paySettings.currencyCode
        )
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
        var span = isOvernight ? "\(s) – \(e) +1" : "\(s) – \(e)"
        if willSplitAtMidnight { span += " · splits at 12 AM" }
        return breakMinutes > 0 ? "\(span) · \(breakMinutes)m break" : span
    }

    private var isOvernight: Bool {
        end.timeIntervalSince(start) < 0
    }

    /// Shown only for overnight work shifts. When on, saving creates two
    /// entries split at midnight so each day's pay rules (weekend premiums,
    /// per-day overtime) apply to the hours actually worked on that day.
    private var splitAtMidnightToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $splitOvernightAtMidnight) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.haze.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                    Text("Night shift")
                        .appText(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.text)
                }
            }
            .tint(AppColors.accent)

            Text(splitOvernightAtMidnight
                 ? "Saves as two shifts — hours after midnight count on the next day's rates."
                 : "Off: the whole shift counts on \(date.formatted(.dateTime.weekday(.wide)))'s rates.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.card)
        )
    }

    /// Whether this save will actually produce two entries.
    private var willSplitAtMidnight: Bool {
        shiftKind == .work && isOvernight && splitOvernightAtMidnight
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

    private var isOffKind: Bool { !needsTimes }

    private var canSave: Bool {
        if shiftKind == .holiday { return !holidayDays.isEmpty }
        if isOffKind { return true }
        return isValid
    }

    private var isValid: Bool {
        if shiftKind == .holiday { return !holidayDays.isEmpty }
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
            let n = holidayDays.count
            return n == 0 ? "Pick at least one day" : "\(n) holiday \(n == 1 ? "day" : "days") — no hours logged"
        case .work where holidayRule == .statPayOnly:
            return "Stat holiday — \(HolidayPayRule.hoursText(store.paySettings.statHolidayPaidHours)) stat pay, no hours worked"
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
        // The Save button disables on showSaveSuccess, but a second tap can be
        // in flight before that re-render lands — each tap built a fresh
        // WorkEntry with its own UUID, which is exactly the identical-content
        // duplicate pairs found in user data. Idempotent at the source.
        guard !showSaveSuccess else { return }
        if !isValid {
            Haptics.error()
            toastMessage = paidHours > 48 ? "Shift too long (max 48 hours)" : "Invalid hours"
            showToast = true
            return
        }

        let cal = Calendar.current

        // Holiday: one off day per picked day; days already logged are left alone.
        if shiftKind == .holiday {
            let sharedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            var saved: [WorkEntry] = []
            for day in holidayDates {
                if store.entries.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) { continue }
                let entry = WorkEntry(date: day, start: day, end: day, breakMinutes: 0, notes: sharedNotes,
                                      isOffDay: true, offDayReason: EntryEditorView.holidayReason)
                withAnimation(AppMotion.Spring.smooth) { store.add(entry) }
                saved.append(entry)
            }
            finishSave(saved: saved)
            return
        }

        let (s, e, br) = isOffKind
            ? (cal.startOfDay(for: date), cal.startOfDay(for: date), 0)
            : (start, end, breakMinutes)

        let reason: String
        switch shiftKind {
        // A stat holiday that wasn't worked is saved as a "Holiday" off day
        // (with stat pay); a worked one is a work entry flagged isHoliday.
        case .work: reason = holidayRule == .statPayOnly ? EntryEditorView.holidayReason : ""
        case .offDay: reason = offDayReason
        case .holiday: reason = EntryEditorView.holidayReason
        }

        // Split-at-midnight: an overnight work shift becomes two entries so
        // each day's pay rules apply to the hours actually worked on it.
        // Falls through to the single-entry path if the split comes back nil
        // (e.g. the shift ends exactly at midnight — nothing to split).
        if willSplitAtMidnight,
           let portions = OvernightSplit.split(date: date, start: s, end: e, breakMinutes: br) {
            let sharedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let sharedLocation = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            var saved: [WorkEntry] = []
            for portion in [portions.first, portions.second] {
                var entry = WorkEntry(date: portion.date, start: portion.start, end: portion.end,
                                      breakMinutes: portion.breakMinutes, notes: sharedNotes,
                                      isOffDay: false, offDayReason: "", isHoliday: false)
                entry.locationName = sharedLocation
                attachWeatherIfToday(to: &entry)
                withAnimation(AppMotion.Spring.smooth) { store.add(entry) }
                saved.append(entry)
            }
            finishSave(saved: saved)
            return
        }

        var entry = WorkEntry(date: date, start: s, end: e, breakMinutes: br,
                              notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                              isOffDay: isOffKind, offDayReason: reason,
                              isHoliday: shiftKind == .work && (holidayRule?.isWorked ?? false))
        if shiftKind == .work, let rule = holidayRule {
            entry.holidayPayRule = rule
            entry.statPayHours = rule.includesStatPay ? store.paySettings.statHolidayPaidHours : 0
        }
        entry.locationName = isOffKind ? "" : locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.locationURL = ""
        entry.latitude = nil
        entry.longitude = nil
        // Only attach weather for same-day work shifts — a cached "now"
        // reading has no bearing on a backdated or off-day entry.
        if !isOffKind {
            attachWeatherIfToday(to: &entry)
        }
        withAnimation(AppMotion.Spring.smooth) { store.add(entry) }
        finishSave(saved: [entry])
    }

    /// Attaches the cached weather snapshot when the entry is dated today,
    /// then upgrades it to the day's forecast high in the background. Shared
    /// by the single-entry and split-at-midnight save paths.
    private func attachWeatherIfToday(to entry: inout WorkEntry) {
        let cal = Calendar.current
        guard cal.isDateInToday(entry.date), let snapshot = WeatherService.shared.snapshot else { return }
        entry.weather = snapshot
        let entryId = entry.id
        Task {
            let highSnapshot = await WeatherService.shared.dailyHighSnapshot(for: snapshot)
            guard var stored = store.entries.first(where: { $0.id == entryId }) else { return }
            stored.weather = highSnapshot
            store.update(stored)
        }
    }

    /// After the save tick, a work shift shows its earnings card in place of
    /// the wizard. With no wage set it asks for one first (now and then, not
    /// every shift); anything else (off day) just closes.
    private func finishSave(saved: [WorkEntry]) {
        Haptics.success()
        showSaveSuccess = true
        // Only entries the store actually accepted (it drops duplicates).
        let accepted = saved.compactMap { entry in store.entries.first { $0.id == entry.id } }
        let result = store.shiftEarnings(for: accepted)
        let paid = accepted.contains { ($0.isOffDay ? $0.statPayHours : $0.paidHours) > 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if let result {
                withAnimation(.easeInOut(duration: 0.35)) { earnings = result }
            } else if paid, !store.paySettings.hourlyRateSet, WagePromptSheet.shouldOffer() {
                savedForPrompt = accepted
                showWagePrompt = true
            } else {
                dismiss()
            }
        }
    }

    /// Wage entered → the earnings card for the shift just saved; skipped → close.
    private func afterWagePrompt() {
        if let result = store.shiftEarnings(for: savedForPrompt) {
            withAnimation(.easeInOut(duration: 0.35)) { earnings = result }
        } else {
            dismiss()
        }
    }
}
