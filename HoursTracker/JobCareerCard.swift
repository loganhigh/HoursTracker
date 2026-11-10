import SwiftUI

/// You screen: one card per extra job, directly under the main company
/// card. Shows only that job's shifts (hours, shifts, days, first and last
/// shift) and links to the job's pay settings.
struct OtherJobCareerCards: View {
    @ObservedObject var store: HoursStore

    var body: some View {
        if store.hasMultipleJobs {
            let all = store.allEntriesIncludingArchive().filter { !$0.isOffDay }
            ForEach(store.paySettings.additionalJobs) { job in
                OtherJobCareerCard(
                    store: store,
                    job: job,
                    entries: all.filter { store.jobID(of: $0) == job.id }
                )
            }
        }
    }
}

private struct OtherJobCareerCard: View {
    @ObservedObject var store: HoursStore
    let job: JobProfile
    let entries: [WorkEntry]

    private var hours: Double { entries.reduce(0) { $0 + $1.paidHours } }

    private var daysWorked: Int {
        let cal = Calendar.current
        return Set(entries.map { cal.startOfDay(for: $0.date) }).count
    }

    private var firstShift: Date? { entries.map(\.date).min() }
    private var lastShift: Date? { entries.map(\.date).max() }

    private var title: String {
        let name = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Other job" : name
    }

    var body: some View {
        SectionCard(
            title: title,
            subtitle: "Other job",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                FriendRecordRow(
                    icon: "clock.fill",
                    title: "Hours logged",
                    value: FriendProfileFormat.hoursDisplay(hours),
                    tint: AppColors.streak
                )
                FriendRecordRow(
                    icon: "checkmark.circle.fill",
                    title: "Shifts",
                    value: "\(entries.count)",
                    tint: AppColors.accent2
                )
                FriendRecordRow(
                    icon: "calendar",
                    title: "Days worked",
                    value: "\(daysWorked)",
                    tint: AppColors.accent
                )
                if let firstShift {
                    FriendRecordRow(
                        icon: "hourglass",
                        title: "First shift",
                        value: FriendProfileFormat.companyStartedString(from: firstShift),
                        tint: AppColors.gold
                    )
                }
                if let lastShift, lastShift != firstShift {
                    FriendRecordRow(
                        icon: "calendar.badge.checkmark",
                        title: "Last shift",
                        value: FriendProfileFormat.companyStartedString(from: lastShift),
                        tint: AppColors.positive
                    )
                }

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
                .padding(.top, AppSpacing.xxs)
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }
}
