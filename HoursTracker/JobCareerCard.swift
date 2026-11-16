import SwiftUI

/// You screen: one card per job, the main job first, all in the same shape —
/// start date, time at the company, years worked, next anniversary, then
/// hours, shifts and days worked there — each with "Edit job", which opens
/// the one editor for that job's company details and pay rules.
struct JobCareerCards: View {
    @ObservedObject var store: HoursStore
    /// Main job's hours when it's the only job (server total, so Career and
    /// the leaderboard agree); nil to count its shifts locally.
    let soleJobHours: Double?

    @AppStorage("company_name") private var companyName = ""
    @AppStorage("company_occupation") private var companyOccupation = ""
    @AppStorage("company_start_date_ts") private var companyStartTS: Double = 0

    var body: some View {
        let all = store.allEntriesIncludingArchive().filter { !$0.isOffDay }
        let multiple = store.hasMultipleJobs
        VStack(spacing: AppSpacing.xl) {
            BoardTitlePickerCard(store: store)
            ForEach(store.jobs) { job in
                let isMain = job.id == JobProfile.primaryID
                let entries = multiple ? all.filter { store.jobID(of: $0) == job.id } : all
                if isMain, !hasMainDetails {
                    MainJobSetupCard(store: store, job: job)
                } else {
                    JobCareerCard(
                        store: store,
                        job: job,
                        info: info(for: job),
                        entries: entries,
                        hoursOverride: isMain && !multiple ? soleJobHours : nil
                    )
                }
            }
        }
    }

    private var hasMainDetails: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companyStartTS > 0
    }

    private func info(for job: JobProfile) -> JobCareerCard.Info {
        if job.id == JobProfile.primaryID {
            let name = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let role = companyOccupation.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(
                title: name.isEmpty ? job.name : name,
                role: role.isEmpty ? (store.hasMultipleJobs ? "Main job" : "Your workplace") : role,
                start: companyStartTS > 0 ? Date(timeIntervalSince1970: companyStartTS) : nil
            )
        }
        let role = (job.occupation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(title: job.name, role: role.isEmpty ? "Other job" : role, start: job.startDate)
    }
}

struct JobCareerCard: View {
    struct Info {
        let title: String
        let role: String
        let start: Date?
    }

    @ObservedObject var store: HoursStore
    let job: JobProfile
    let info: Info
    let entries: [WorkEntry]
    let hoursOverride: Double?

    /// Counted from the start date when there is one (shifts logged for an
    /// earlier job at the same place don't belong to this stint).
    private var counted: [WorkEntry] {
        guard let start = info.start else { return entries }
        let day = Calendar.current.startOfDay(for: start)
        return entries.filter { $0.date >= day }
    }

    private var hours: Double {
        if let hoursOverride, info.start == nil { return hoursOverride }
        return counted.reduce(0) { $0 + $1.paidHours }
    }

    private var daysWorked: Int {
        let cal = Calendar.current
        return Set(counted.map { cal.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        SectionCard(title: info.title, subtitle: info.role, trailing: nil, centerHeader: true) {
            VStack(spacing: 10) {
                if let start = info.start {
                    FriendRecordRow(
                        icon: "building.2.fill",
                        title: "Started",
                        value: FriendProfileFormat.companyStartedString(from: start),
                        tint: AppColors.accent
                    )
                    FriendRecordRow(
                        icon: "briefcase.fill",
                        title: "Time at company",
                        value: FriendProfileFormat.tenureAtCompanyString(from: start),
                        tint: AppColors.accent2
                    )
                    let years = FriendProfileFormat.yearsAtCompany(from: start)
                    if years >= 0.1 {
                        FriendRecordRow(
                            icon: "star.circle.fill",
                            title: "Years worked",
                            value: String(format: "%.1f", years),
                            tint: AppColors.gold
                        )
                    }
                    if let anniversary = FriendProfileFormat.nextWorkAnniversary(from: start) {
                        FriendRecordRow(
                            icon: "gift.fill",
                            title: "Next anniversary",
                            value: FriendProfileFormat.anniversaryCountdownString(to: anniversary),
                            detail: FriendProfileFormat.anniversaryDateString(anniversary),
                            tint: AppColors.accentHighlight
                        )
                    }
                }
                FriendRecordRow(
                    icon: "clock.fill",
                    title: "Hours logged",
                    value: FriendProfileFormat.hoursDisplay(hours),
                    detail: info.start == nil ? nil : "Since start date",
                    tint: AppColors.streak
                )
                FriendRecordRow(
                    icon: "checkmark.circle.fill",
                    title: "Shifts",
                    value: "\(counted.count)",
                    tint: AppColors.positive
                )
                FriendRecordRow(
                    icon: "calendar",
                    title: "Days worked",
                    value: "\(daysWorked)",
                    tint: AppColors.accent
                )
                if info.start == nil {
                    Text("Add your start date to see time at the company and anniversaries.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                EditJobButton(store: store, job: job)
                    .padding(.top, AppSpacing.xxs)
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }
}

/// Main job with no company details yet: invite to fill them in.
private struct MainJobSetupCard: View {
    @ObservedObject var store: HoursStore
    let job: JobProfile

    var body: some View {
        SectionCard(
            title: "Company",
            subtitle: "Track your start date, anniversaries, and hours at work",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "building.2.fill")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppColors.accent.opacity(0.85))
                Text("Add your company to see start date, time worked, and work anniversaries here.")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xs)
                NavigationLink {
                    JobEditorView(store: store, job: job)
                } label: {
                    Label("Set up company profile", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }
}

private struct EditJobButton: View {
    @ObservedObject var store: HoursStore
    let job: JobProfile

    var body: some View {
        NavigationLink {
            JobEditorView(store: store, job: job)
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "pencil.circle.fill")
                    .font(.callout.weight(.semibold))
                Text("Edit job")
                    .appText(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .foregroundStyle(AppColors.accent)
            .padding(.vertical, 10)
            .padding(.horizontal, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(AppColors.accent.opacity(0.1))
            )
        }
        .buttonStyle(PremiumPressStyle())
    }
}

/// "Shown on the leaderboard": pick which job's role sits under your name on
/// the global board — say asphalt in summer, rigging in winter. Only shown
/// once two or more jobs have a role.
struct BoardTitlePickerCard: View {
    @ObservedObject var store: HoursStore
    @AppStorage("company_occupation") private var mainRole = ""

    private var options: [(id: String, role: String, company: String)] {
        _ = mainRole // re-render when the main role changes
        return store.jobs.compactMap { job in
            let role = store.role(ofJob: job.id)
            return role.isEmpty ? nil : (job.id, role, job.name)
        }
    }

    var body: some View {
        let options = options
        if options.count > 1 {
            let selected = store.boardTitleJobID
            SectionCard(
                title: "Leaderboard title",
                subtitle: "Shown under your name on the global leaderboard",
                trailing: nil,
                centerHeader: true
            ) {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(options, id: \.id) { option in
                        let isOn = option.id == selected
                        Button {
                            guard !isOn else { return }
                            Haptics.lightTap()
                            withAnimation(AppMotion.Spring.snappy) { store.boardTitleJobID = option.id }
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(isOn ? AppColors.accent : AppColors.faint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.role)
                                        .appText(.headline)
                                        .foregroundStyle(AppColors.text)
                                    Text(option.company)
                                        .appText(.caption)
                                        .foregroundStyle(AppColors.subtext)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, AppSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                    .fill(isOn ? AppColors.accent.opacity(0.12) : AppColors.card2.opacity(0.6))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PremiumPressStyle())
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                    Text("Changes show on the leaderboard within about 15 minutes.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.faint)
                        .padding(.top, 2)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }
}
