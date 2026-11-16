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

/// Every job (main first) with its pay summary, each opening the job
/// editor, plus "Add a job". Lives right in Settings; the same editor opens
/// from each job's card on the You page.
struct JobsListSection: View {
    @ObservedObject var store: HoursStore
    @State private var showingNewJob = false
    @State private var newJobName = ""
    @State private var editingJob: JobProfile?

    var body: some View {
        Section {
            ForEach(store.jobs) { job in
                Button {
                    editingJob = job
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: job.id == JobProfile.primaryID ? "building.2.fill" : "briefcase.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppColors.accentMuted))
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
            SectionEyebrow("Jobs")
        } footer: {
            Text("Each job has its own company details, wage, pay cycle and overtime rules. When you log a shift you pick the job, and it counts toward that job's cheque.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
        .listRowSeparatorTint(AppColors.stroke)
        .navigationDestination(item: $editingJob) { job in
            JobEditorView(store: store, job: job)
        }
        .alert("New job", isPresented: $showingNewJob) {
            TextField("Company name", text: $newJobName)
            Button("Add") {
                let name = newJobName.trimmingCharacters(in: .whitespacesAndNewlines)
                newJobName = ""
                guard !name.isEmpty else { return }
                editingJob = store.addJob(named: name)
            }
            Button("Cancel", role: .cancel) { newJobName = "" }
        } message: {
            Text("It starts with your main job's pay rules. Change anything that's different next.")
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

// MARK: - One job: company profile + pay rules

/// The single editor for any job, main or extra: company details (name,
/// role, start date) on top, then wage, pay cycle and overtime. The main
/// job's company fields live in the company_* app storage keys (cloud
/// profile, anniversaries, leaderboard title); extra jobs keep them on
/// their JobProfile.
struct JobEditorView: View {
    @ObservedObject var store: HoursStore
    @State private var draft: JobProfile
    @State private var wageText: String
    @State private var occupation: String
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    @AppStorage("company_name") private var mainCompanyName = ""
    @AppStorage("company_occupation") private var mainOccupation = ""
    @AppStorage("company_start_date_ts") private var mainStartTS: Double = 0

    init(store: HoursStore, job: JobProfile) {
        self.store = store
        var job = job
        let isMain = job.id == JobProfile.primaryID
        let defaults = UserDefaults.standard
        if isMain {
            let company = (defaults.string(forKey: "company_name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !company.isEmpty { job.name = company }
            if job.name == "Main job" { job.name = "" }
        }
        let ts = defaults.double(forKey: "company_start_date_ts")
        let start: Date? = isMain ? (ts > 0 ? Date(timeIntervalSince1970: ts) : nil) : job.startDate
        _draft = State(initialValue: job)
        _wageText = State(initialValue: job.settings.hourlyRateSet
                          ? String(format: "%.2f", job.settings.hourlyWage) : "")
        _occupation = State(initialValue: isMain ? (defaults.string(forKey: "company_occupation") ?? "") : (job.occupation ?? ""))
        _hasStartDate = State(initialValue: start != nil)
        _startDate = State(initialValue: start ?? Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date())
    }

    private var isMain: Bool { draft.id == JobProfile.primaryID }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            companySection
            if isMain, !jobTitles.isEmpty { leaderboardTitleSection }

            Section {
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
                SectionEyebrow("Pay")
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
                    Text("Its shifts move to your main job, so no hours are lost.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle(trimmedName.isEmpty ? "Edit job" : trimmedName)
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

    // MARK: Company

    private var companySection: some View {
        Section {
            LabeledContent("Company") {
                TextField("Company name", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Role") {
                TextField("e.g. Foreman", text: $occupation)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Start date", isOn: $hasStartDate.animation())
                .tint(AppColors.accent)
            if hasStartDate {
                DatePicker("First day", selection: $startDate, in: ...Date(), displayedComponents: .date)
                Label {
                    Text(tenureLine)
                        .foregroundStyle(AppColors.subtext)
                } icon: {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .foregroundStyle(AppColors.accent)
                }
                .appText(.subheadline)
            }
        } header: {
            SectionEyebrow(isMain ? "Main job" : "Other job")
        } footer: {
            Text(isMain
                 ? "Your start date powers time at the company and work anniversary reminders."
                 : "Your start date powers time at the company on your You page.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
    }

    private var tenureLine: String {
        let tenure = FriendProfileFormat.tenureAtCompanyString(from: startDate)
        return trimmedName.isEmpty ? tenure : "\(tenure) at \(trimmedName)"
    }

    // MARK: Leaderboard title (main job's role is the board title)

    /// Roles across all your jobs; only worth offering when there's a choice.
    private var jobTitles: [String] {
        var seen = Set<String>()
        let roles = ([occupation] + store.paySettings.additionalJobs.map { $0.occupation ?? "" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return roles.count > 1 ? roles : []
    }

    private var leaderboardTitleSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(jobTitles, id: \.self) { title in
                        let selected = occupation.trimmingCharacters(in: .whitespacesAndNewlines)
                            .caseInsensitiveCompare(title) == .orderedSame
                        Button {
                            Haptics.lightTap()
                            occupation = String(title.prefix(80))
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: selected ? "checkmark" : "briefcase.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(title).lineLimit(1)
                            }
                            .appText(.subheadline)
                            .foregroundStyle(selected ? AppColors.textOnAccent : AppColors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(selected ? AppColors.accent : AppColors.accentMuted))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            SectionEyebrow("Leaderboard title")
        } footer: {
            Text("Your role shows under your name on the global leaderboard. Tap another job's role to show that instead.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
        }
        .listRowBackground(AppColors.card.opacity(0.55))
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
        job.name = trimmedName
        let role = occupation.trimmingCharacters(in: .whitespacesAndNewlines)
        if isMain {
            let startChanged = mainStartTS != (hasStartDate ? startDate.timeIntervalSince1970 : 0)
            let nameChanged = mainCompanyName != job.name
            mainCompanyName = job.name
            mainOccupation = String(role.prefix(80))
            mainStartTS = hasStartDate ? startDate.timeIntervalSince1970 : 0
            if (startChanged || nameChanged), hasStartDate, !job.name.isEmpty {
                let name = job.name, start = startDate
                Task {
                    if await NotificationManager.shared.hasPermission() {
                        SmartNotifier.shared.scheduleWorkAnniversaryNotification(companyName: name, startDate: start)
                    }
                }
            }
        } else {
            if job.name.isEmpty { job.name = store.job(id: job.id).name }
            job.occupation = role.isEmpty ? nil : role
            job.startDate = hasStartDate ? Calendar.current.startOfDay(for: startDate) : nil
        }
        store.updateJob(job)
        if isMain { store.syncProfileSnapshotToCloud() }
    }
}
