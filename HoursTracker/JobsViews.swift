import SwiftUI

// MARK: - Jobs screens
//
// Settings → Jobs lists every job with its shift count; each opens an editor
// for that job's name, wage, pay schedule and overtime rules. The pickers
// below let a shift (logged, edited or live) say which job it was for, and
// let Home's cheque switch between jobs.

/// "Job: Main job ▾" — only shown once someone has more than one job.
struct JobPickerMenu: View {
    @ObservedObject var store: HoursStore
    let selection: String
    var includesAll = false
    var title = "Job"
    let onSelect: (String) -> Void

    private var label: String {
        selection == HoursStore.allJobsScope ? "All jobs" : store.job(id: selection).name
    }

    var body: some View {
        Menu {
            ForEach(store.jobs) { job in
                Button {
                    Haptics.lightTap()
                    onSelect(job.id)
                } label: {
                    if job.id == selection { Label(job.name, systemImage: "checkmark") } else { Text(job.name) }
                }
            }
            if includesAll {
                Divider()
                Button {
                    Haptics.lightTap()
                    onSelect(HoursStore.allJobsScope)
                } label: {
                    if selection == HoursStore.allJobsScope {
                        Label("All jobs", systemImage: "checkmark")
                    } else {
                        Text("All jobs")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("\(title): \(label)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(AppColors.accentMuted))
            .fixedSize()
        }
        // iOS keeps a Menu's label at the size it first laid out, so switching
        // to a longer job name clipped the pill ("heque: Big Country…").
        // A fresh identity per selection makes it re-measure.
        .id(label)
        .accessibilityLabel("\(title), \(label)")
    }
}

// MARK: - Settings → Jobs

struct JobsSettingsView: View {
    @ObservedObject var store: HoursStore
    @State private var showingNewJob = false
    @State private var newJobName = ""
    @State private var editingJob: JobProfile?

    var body: some View {
        Form {
            Section {
                ForEach(store.jobs) { job in
                    Button {
                        editingJob = job
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.name)
                                    .foregroundStyle(AppColors.text)
                                Text(summary(job))
                                    .appText(.caption)
                                    .foregroundStyle(AppColors.subtext)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.faint)
                        }
                    }
                }
                Button {
                    showingNewJob = true
                } label: {
                    Label("Add a job", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppColors.accent)
                }
            } header: {
                SectionEyebrow("Your jobs")
            } footer: {
                Text("Each job has its own wage, pay schedule and overtime rules. When you log a shift you pick the job, and it counts toward that job's cheque.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            .listRowBackground(AppColors.card.opacity(0.55))
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editingJob) { job in
            JobEditorView(store: store, job: job)
        }
        .alert("New job", isPresented: $showingNewJob) {
            TextField("Job name", text: $newJobName)
            Button("Add") {
                let name = newJobName.trimmingCharacters(in: .whitespacesAndNewlines)
                newJobName = ""
                guard !name.isEmpty else { return }
                editingJob = store.addJob(named: name)
            }
            Button("Cancel", role: .cancel) { newJobName = "" }
        } message: {
            Text("It starts with your main job's pay rules — change anything that's different next.")
        }
    }

    private func summary(_ job: JobProfile) -> String {
        let shifts = store.shiftCount(forJob: job.id)
        let wage = job.settings.hourlyRateSet
            ? (job.settings.hourlyWage.formatted(.currency(code: job.settings.currencyCode)) + "/h")
            : "No wage set"
        return "\(wage) · \(job.settings.payPeriodType.displayName) · \(shifts) shift\(shifts == 1 ? "" : "s")"
    }
}

// MARK: - One job's settings

struct JobEditorView: View {
    @ObservedObject var store: HoursStore
    @State private var draft: JobProfile
    @State private var wageText: String
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(store: HoursStore, job: JobProfile) {
        self.store = store
        _draft = State(initialValue: job)
        _wageText = State(initialValue: job.settings.hourlyRateSet
                          ? String(format: "%.2f", job.settings.hourlyWage) : "")
    }

    private var isMain: Bool { draft.id == JobProfile.primaryID }

    var body: some View {
        Form {
            Section {
                TextField("Job name", text: $draft.name)
                HStack {
                    Text("Hourly wage")
                    Spacer()
                    TextField("Not set", text: $wageText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 120)
                        .onChange(of: wageText) { _, text in
                            let value = Double(text.replacingOccurrences(of: ",", with: "."))
                            if let value, value > 0, value < 10_000 {
                                draft.settings.hourlyRate = value
                                draft.settings.hourlyRateSet = true
                            } else if text.isEmpty {
                                draft.settings.hourlyRateSet = false
                            }
                        }
                }
            } header: {
                SectionEyebrow(isMain ? "Main job" : "Job")
            }
            .listRowBackground(AppColors.card.opacity(0.55))

            Section {
                Picker("Pay period", selection: $draft.settings.payPeriodType) {
                    ForEach(PayPeriodType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Next payday", selection: Binding(
                    get: { draft.settings.nextPayday ?? PayCycleEngine.fallbackNextPayday(settings: draft.settings) },
                    set: { draft.settings.nextPayday = Calendar.current.startOfDay(for: $0) }
                ), displayedComponents: .date)
                Toggle("Hours cutoff", isOn: Binding(
                    get: { draft.settings.payPeriodUsesCutoff },
                    set: { on in
                        draft.settings.payPeriodUsesCutoff = on
                        if on {
                            draft.settings.nextCutoff = draft.settings.nextCutoff ?? draft.settings.nextPayday
                        } else {
                            draft.settings.nextCutoff = nil
                        }
                    }
                ))
                .tint(AppColors.accent)
                if draft.settings.payPeriodUsesCutoff {
                    DatePicker("Cutoff date", selection: Binding(
                        get: { draft.settings.nextCutoff ?? Date() },
                        set: { draft.settings.nextCutoff = Calendar.current.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                } else {
                    Picker("Week starts on", selection: Binding(
                        get: { draft.settings.weekStartWeekday ?? 0 },
                        set: { draft.settings.weekStartWeekday = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Payday").tag(0)
                        ForEach(1...7, id: \.self) { Text(PayCycleEngine.weekdayName($0)).tag($0) }
                    }
                }
            } header: {
                SectionEyebrow("Pay cycle")
            } footer: {
                Text(cycleFooter)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            .listRowBackground(AppColors.card.opacity(0.55))

            OvertimeRulesSettingsSection(store: store, settings: $draft.settings)

            if !isMain {
                Section {
                    Button("Delete job", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("Its shifts move to your main job — no hours are lost.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle(draft.name.isEmpty ? "Job" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: save)
        .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete job", role: .destructive) {
                store.deleteJob(id: draft.id)
                dismiss()
            }
        } message: {
            Text("\(store.shiftCount(forJob: draft.id)) shifts will move to your main job.")
        }
    }

    private var cycleFooter: String {
        let cycle = PayCycleEngine.currentCycle(settings: draft.settings)
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        return "Current period: \(df.string(from: cycle.start)) – \(df.string(from: cycle.cutoff)) · paid \(df.string(from: cycle.payday))."
    }

    private func save() {
        // Deleted while open: nothing to save.
        guard isMain || store.paySettings.additionalJobs.contains(where: { $0.id == draft.id }) else { return }
        var job = draft
        job.name = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if job.name.isEmpty { job.name = isMain ? "" : store.job(id: job.id).name }
        store.updateJob(job)
    }
}
