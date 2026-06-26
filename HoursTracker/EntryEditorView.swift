import SwiftUI

struct EntryEditorView: View {
    enum Mode {
        case add
        case edit(WorkEntry)
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

    // Off day
    @State private var isOffDay: Bool
    @State private var offDayReason: String

    // Add flow
    @State private var addStep: AddEntryStep = .date
    @State private var glowPulse: CGFloat = 0.4
    @State private var iconScale: CGFloat = 0.82
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 18

    // Edit flow
    @State private var showingDatePicker = false

    // Shared
    @State private var showDeleteConfirm = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showSaveSuccess = false

    private static let offDayReasons = ["Sick", "Appointment", "Vacation", "Holiday", "Personal", "Other"]

    private enum AddEntryStep: Int, CaseIterable {
        case date
        case time
        case location

        var icon: String {
            switch self {
            case .date: return "calendar"
            case .time: return "clock.fill"
            case .location: return "briefcase.fill"
            }
        }

        var title: String {
            switch self {
            case .date: return "Which day?"
            case .time: return "What were your hours?"
            case .location: return "Location & job"
            }
        }

        var message: String {
            switch self {
            case .date: return "Pick the date for this shift."
            case .time: return "Set your start, end, and break — or mark the day off."
            case .location: return "Add an optional label like “Landscaping”."
            }
        }
    }

    init(store: HoursStore, mode: Mode) {
        self.store = store
        self.mode = mode

        let now = Date()
        let cal = Calendar.current

        switch mode {
        case .add:
            let d = cal.startOfDay(for: now)
            _date = State(initialValue: d)

            let mostRecentEntry = store.entries.filter { !$0.isOffDay }.sorted { $0.date > $1.date }.first
            let defaultStartHour = mostRecentEntry.map { cal.component(.hour, from: $0.start) } ?? 7
            let defaultStartMinute = mostRecentEntry.map { cal.component(.minute, from: $0.start) } ?? 0
            let defaultEndHour = mostRecentEntry.map { cal.component(.hour, from: $0.end) } ?? 17
            let defaultEndMinute = mostRecentEntry.map { cal.component(.minute, from: $0.end) } ?? 0

            _start = State(initialValue: cal.date(bySettingHour: defaultStartHour, minute: defaultStartMinute, second: 0, of: now) ?? now)
            _end = State(initialValue: cal.date(bySettingHour: defaultEndHour, minute: defaultEndMinute, second: 0, of: now) ?? now)
            _breakMinutes = State(initialValue: mostRecentEntry?.breakMinutes ?? 0)

            _locationLabel = State(initialValue: "")

            _isOffDay = State(initialValue: false)
            _offDayReason = State(initialValue: Self.offDayReasons[0])

        case .edit(let entry):
            _date = State(initialValue: entry.date)
            _start = State(initialValue: entry.start)
            _end = State(initialValue: entry.end)
            _breakMinutes = State(initialValue: entry.breakMinutes)

            _locationLabel = State(initialValue: entry.locationName)

            _isOffDay = State(initialValue: entry.isOffDay)
            _offDayReason = State(initialValue: Self.offDayReasons.contains(entry.offDayReason) ? entry.offDayReason : Self.offDayReasons[0])
        }
    }

    var body: some View {
        switch mode {
        case .add:
            addEntryWizard
        case .edit:
            editEntryForm
        }
    }

    // MARK: - Add wizard

    private var addEntryWizard: some View {
        ZStack {
            AppTheme.Colors.bg.ignoresSafeArea()

            wizardAmbientGlow

            VStack(spacing: 0) {
                wizardTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                wizardStepDots
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 24) {
                        wizardStepHeader
                        wizardStepFields
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .opacity(contentOpacity)
                    .offset(y: contentOffset)
                    .id(addStep)
                }
                .scrollDismissesKeyboard(.interactively)

                wizardBottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
        .onAppear {
            glowPulse = 1.0
            animateWizardContentIn()
        }
        .toast(isPresented: $showToast, message: toastMessage, showsCheckmark: false)
    }

    private var wizardAmbientGlow: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: -90, y: -220)
                .scaleEffect(glowPulse)
            Circle()
                .fill(AppTheme.Colors.accentHighlight.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 110, y: 180)
                .scaleEffect(glowPulse)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true), value: glowPulse)
    }

    private var wizardTopBar: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                Haptics.lightTap()
                dismiss()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.subtext)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private var wizardStepDots: some View {
        HStack(spacing: 8) {
            ForEach(AddEntryStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(
                        step.rawValue == addStep.rawValue
                            ? LinearGradient(
                                colors: [AppTheme.Colors.accent, AppTheme.Colors.accentHighlight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [AppTheme.Colors.stroke, AppTheme.Colors.stroke],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: step.rawValue == addStep.rawValue ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: addStep)
            }
        }
    }

    private var wizardStepHeader: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.Colors.accent.opacity(0.22), AppTheme.Colors.accentHighlight.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 2)

                Circle()
                    .fill(AppTheme.Colors.card2)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.Colors.accent.opacity(0.55), AppTheme.Colors.accentHighlight.opacity(0.45)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )

                Image(systemName: addStep.icon)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.Colors.accent, AppTheme.Colors.accentHighlight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(iconScale)

            VStack(spacing: 14) {
                Text(addStep.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(addStep.message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var wizardStepFields: some View {
        switch addStep {
        case .date:
            wizardCard {
                DatePicker(
                    "Date",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(AppTheme.Colors.accent)
                .onChange(of: date) { _, newDate in
                    start = merge(day: newDate, with: start)
                    end = merge(day: newDate, with: end)
                }
            }

        case .time:
            VStack(spacing: 12) {
                wizardCard {
                    VStack(spacing: 0) {
                        wizardTimeRow(title: "Start", selection: $start)
                        wizardDivider
                        wizardTimeRow(title: "End", selection: $end)
                        wizardDivider
                        HStack {
                            Text("Break")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.text)
                            Spacer()
                            Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                                Text("\(breakMinutes) min")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .monospacedDigit()
                            }
                            .tint(AppTheme.Colors.accent)
                        }
                        .padding(.vertical, 12)
                    }
                }

                if !isValid {
                    Text("End time must be after start time (or an overnight shift).")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.danger)
                        .multilineTextAlignment(.center)
                }
            }

        case .location:
            wizardCard {
                TextField("Location or job (optional)", text: $locationLabel, axis: .vertical)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
                    .lineLimit(1...3)
                    .tint(AppTheme.Colors.accent)
            }
        }
    }

    private var wizardBottomButtons: some View {
        VStack(spacing: 12) {
            PrimaryButton(
                wizardPrimaryTitle,
                systemImage: addStep == .location ? "checkmark" : "chevron.right",
                isSuccess: showSaveSuccess && addStep == .location
            ) {
                handleWizardPrimary()
            }
            .disabled(!canAdvanceFromCurrentStep || showSaveSuccess)

            if addStep != .date {
                Button {
                    Haptics.lightTap()
                    goBackWizardStep()
                } label: {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var wizardPrimaryTitle: String {
        addStep == .location ? "Save Entry" : "Next"
    }

    private var canAdvanceFromCurrentStep: Bool {
        switch addStep {
        case .date:
            return true
        case .time:
            return canSave
        case .location:
            return canSave
        }
    }

    private func handleWizardPrimary() {
        Haptics.lightTap()
        switch addStep {
        case .date:
            advanceWizardStep()
        case .time:
            guard canSave else {
                Haptics.error()
                toastMessage = paidHours > 48 ? "Shift too long (max 48 hours)" : "Invalid hours"
                showToast = true
                return
            }
            advanceWizardStep()
        case .location:
            save()
        }
    }

    private func advanceWizardStep() {
        guard let next = AddEntryStep(rawValue: addStep.rawValue + 1) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            contentOpacity = 0
            contentOffset = 12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            addStep = next
            animateWizardContentIn()
        }
    }

    private func goBackWizardStep() {
        guard let previous = AddEntryStep(rawValue: addStep.rawValue - 1) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            contentOpacity = 0
            contentOffset = -12
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            addStep = previous
            animateWizardContentIn()
        }
    }

    private func animateWizardContentIn() {
        iconScale = 0.82
        contentOpacity = 0
        contentOffset = 18

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            iconScale = 1.0
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
            contentOpacity = 1.0
            contentOffset = 0
        }
    }

    private func wizardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.card2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.Colors.accent.opacity(0.35), AppTheme.Colors.stroke],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
    }

    private func wizardTimeRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(AppTheme.Colors.accent)
        }
        .padding(.vertical, 8)
    }

    private var wizardDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.stroke.opacity(0.6))
            .frame(height: 1)
    }

    // MARK: - Edit form

    private var editEntryForm: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    Button {
                        showingDatePicker = true
                    } label: {
                        HStack {
                            Text("Date")
                                .foregroundStyle(Color(uiColor: .systemBlue))
                            Spacer()
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(Color(uiColor: .systemBlue))
                        }
                    }
                }

                Section("Time") {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)

                    Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                        Text("Break: \(breakMinutes) min")
                    }

                    Toggle("Off today", isOn: $isOffDay)
                    if isOffDay {
                        Picker("Reason", selection: $offDayReason) {
                            ForEach(Self.offDayReasons, id: \.self) { reason in
                                Text(reason).tag(reason)
                            }
                        }
                    }
                }

                Section {
                    TextField("Location or job (optional)", text: $locationLabel, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Location & job")
                } footer: {
                    Text("Add a quick label like “Landscaping”.")
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete Entry")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.bg.ignoresSafeArea())
            .navigationTitle("Edit Entry")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(showSaveSuccess ? AppTheme.Colors.success : Color(uiColor: .systemBlue))
                        .disabled(!canSave || showSaveSuccess)
                }
            }
            .toast(isPresented: $showToast, message: toastMessage, showsCheckmark: false)
            .sheet(isPresented: $showingDatePicker) {
                AutoDismissDatePickerSheet(date: $date, title: "Select Date") {
                    showingDatePicker = false
                }
            }
            .alert("Delete this entry?", isPresented: $showDeleteConfirm) {
                Button("Delete Entry", role: .destructive) {
                    deleteEntry()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    // MARK: - Validation & save

    private var canSave: Bool {
        if isOffDay { return true }
        return isValid
    }

    private var isValid: Bool {
        if isOffDay { return true }
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
            if paidHours > 48 {
                toastMessage = "Shift too long (max 48 hours)"
            } else {
                toastMessage = "Invalid hours"
            }
            showToast = true
            return
        }

        let cal = Calendar.current
        let (s, e, br) = isOffDay
            ? (cal.startOfDay(for: date), cal.startOfDay(for: date), 0)
            : (start, end, breakMinutes)

        let trimmedLabel = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .add:
            var entry = WorkEntry(date: date, start: s, end: e, breakMinutes: br, notes: "",
                                 isOffDay: isOffDay, offDayReason: isOffDay ? offDayReason : "", isHoliday: false)
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
            updated.notes = ""
            updated.locationName = trimmedLabel
            updated.locationURL = ""
            updated.latitude = nil
            updated.longitude = nil
            updated.isOffDay = isOffDay
            updated.offDayReason = isOffDay ? offDayReason : ""
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
        toastMessage = "Entry deleted"
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            dismiss()
        }
    }
}
