import SwiftUI
import FirebaseAuth

// MARK: - First-week goal
//
// New users who log on 3+ different days in their first week are retained
// ~35% of the time vs ~1% otherwise (Nov 2026 baseline). So for the first 7
// days of an account, Home shows a "Log 3 days this week" card: one dot per
// day of the account's first week, filled when a shift was logged that day.

enum FirstWeekGoal {
    static let goalDays = 3
    static let windowDays = 7

    struct Progress: Equatable {
        /// Day starts of the account's first 7 days.
        let days: [Date]
        /// Which of `days` have a logged (non-off) shift.
        let logged: [Bool]
        /// Index of today in `days`.
        let todayIndex: Int

        var loggedCount: Int { logged.filter { $0 }.count }
        var isComplete: Bool { loggedCount >= FirstWeekGoal.goalDays }
        var daysLeft: Int { days.count - todayIndex }
    }

    /// nil once the account is past its first week (or before it starts).
    static func progress(
        accountCreated: Date,
        shiftDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Progress? {
        let start = calendar.startOfDay(for: accountCreated)
        let today = calendar.startOfDay(for: now)
        guard let offset = calendar.dateComponents([.day], from: start, to: today).day,
              (0..<windowDays).contains(offset) else { return nil }
        let days = (0..<windowDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let loggedDays = Set(shiftDates.map { calendar.startOfDay(for: $0) })
        return Progress(days: days, logged: days.map { loggedDays.contains($0) }, todayIndex: offset)
    }

    /// Account creation from Firebase Auth (nil when signed out).
    static var accountCreated: Date? {
        Auth.auth().currentUser?.metadata.creationDate
    }
}

struct FirstWeekGoalCard: View {
    let progress: FirstWeekGoal.Progress
    let onLogToday: () -> Void

    @AppStorage("first_week_goal_celebrated_v1") private var celebrated = false

    private var todayLogged: Bool { progress.logged[progress.todayIndex] }

    private var title: String {
        if progress.isComplete { return "Week-one goal done" }
        return "Log \(FirstWeekGoal.goalDays) days this week"
    }

    private var subtitle: String {
        if progress.isComplete {
            return "You logged \(progress.loggedCount) days. That's the habit. Keep it going."
        }
        let remaining = FirstWeekGoal.goalDays - progress.loggedCount
        let dayWord = remaining == 1 ? "day" : "days"
        let left = progress.daysLeft == 1 ? "today is the last day" : "\(progress.daysLeft) days left"
        return "\(remaining) more \(dayWord) to go · \(left)"
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("\(min(progress.loggedCount, FirstWeekGoal.goalDays))/\(FirstWeekGoal.goalDays)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(progress.isComplete ? AppColors.positive : AppColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((progress.isComplete ? AppColors.positive : AppColors.accent).opacity(0.15)))
            }

            HStack(spacing: 0) {
                ForEach(progress.days.indices, id: \.self) { index in
                    dayDot(index)
                        .frame(maxWidth: .infinity)
                }
            }

            if !progress.isComplete && !todayLogged {
                Button {
                    Haptics.lightTap()
                    onLogToday()
                } label: {
                    Label("Log today's shift", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppColors.accent.opacity(0.15)))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(PremiumPressStyle())
            }
        }
        .padding(AppSpacing.md)
        .homeCard()
        .overlay(alignment: .topTrailing) {
            if progress.isComplete {
                OwlView(pose: .cheer, size: .peek)
                    .offset(x: -6, y: -34)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .onAppear(perform: celebrateIfNeeded)
        .onChange(of: progress.isComplete) { _, _ in celebrateIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    private func dayDot(_ index: Int) -> some View {
        let logged = progress.logged[index]
        let isToday = index == progress.todayIndex
        let isPast = index < progress.todayIndex
        return VStack(spacing: 5) {
            Text(progress.days[index].formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 11, weight: isToday ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(isToday ? AppColors.text : AppColors.faint)
            ZStack {
                Circle()
                    .strokeBorder(
                        logged ? Color.clear : (isToday ? AppColors.accent : AppColors.faint.opacity(isPast ? 0.5 : 0.35)),
                        style: StrokeStyle(lineWidth: isToday ? 2 : 1.5, dash: isPast || isToday || logged ? [] : [3, 3])
                    )
                    .background(Circle().fill(logged ? AppColors.accent : Color.clear))
                if logged {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(AppColors.textOnAccent)
                }
            }
            .frame(width: 30, height: 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.days[index].formatted(.dateTime.weekday(.wide)))
        .accessibilityValue(logged ? "Logged" : "Not logged")
    }

    private func celebrateIfNeeded() {
        guard progress.isComplete, !celebrated else { return }
        celebrated = true
        Haptics.success()
    }
}
