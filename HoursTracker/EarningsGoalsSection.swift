import SwiftUI

/// "Goals" card on the You tab, directly under Tracking history. Each goal
/// tracks what the user records putting aside (tap a goal to add to it) and,
/// if they set a monthly amount, how many months that leaves.
struct EarningsGoalsCard: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var goalStore = EarningsGoalStore.shared

    @State private var showingNewGoal = false
    @State private var openGoal: OpenGoal?

    private struct OpenGoal: Identifiable { let id: UUID }

    private var rows: [EarningsGoalProgress] {
        // Unfinished goals first (oldest first), reached goals at the bottom.
        EarningsGoalCalculator.progress(for: goalStore.goals)
            .sorted { lhs, rhs in
                if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
                return lhs.goal.createdAt < rhs.goal.createdAt
            }
    }

    var body: some View {
        SectionCard(
            title: "Goals",
            subtitle: "Save toward what matters",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                let rows = rows
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows) { row in
                        Button {
                            Haptics.lightTap()
                            openGoal = OpenGoal(id: row.goal.id)
                        } label: {
                            EarningsGoalRow(row: row, currencyCode: store.paySettings.currencyCode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Add savings or edit goal")
                    }
                    Button {
                        Haptics.lightTap()
                        showingNewGoal = true
                    } label: {
                        Label("Add goal", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .sheet(item: $openGoal) { item in
            EarningsGoalDetailSheet(goalID: item.id, store: store)
        }
        .sheet(isPresented: $showingNewGoal) {
            EarningsGoalEditorSheet(existing: nil, currencyCode: store.paySettings.currencyCode)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "target")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.accent)
            }
            Text("Save toward something")
                .appText(.headline)
                .foregroundStyle(AppColors.text)
            Text("Add a goal like a vacation or a down payment, then record what you put aside and watch it fill up.")
                .appText(.metricLabel)
                .foregroundStyle(AppColors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xs)
            Button {
                Haptics.lightTap()
                showingNewGoal = true
            } label: {
                Label("Add a goal", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, AppSpacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Row

private struct EarningsGoalRow: View {
    let row: EarningsGoalProgress
    let currencyCode: String

    private var tint: Color { row.isComplete ? AppColors.positive : AppColors.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.goal.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if row.isComplete {
                    Label("Goal reached", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.positive)
                } else {
                    Text("\(EarningsGoalFormat.money(row.remaining, code: currencyCode)) remaining")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.text)
                }
            }

            progressBar

            HStack(spacing: 6) {
                Text(EarningsGoalFormat.money(row.progress, code: currencyCode))
                    .foregroundStyle(AppColors.subtext)
                Text("of \(EarningsGoalFormat.money(row.goal.targetAmount, code: currencyCode))")
                    .foregroundStyle(AppColors.faint)
                Spacer(minLength: 0)
                Text("\(Int((row.fraction * 100).rounded(.down)))%")
                    .foregroundStyle(tint)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            Text(footnote)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(row.isComplete ? AppColors.positive : AppColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(row.isComplete ? AppColors.positive.opacity(0.35) : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.stroke.opacity(0.6))
                Capsule()
                    .fill(tint)
                    .frame(width: max(row.fraction > 0 ? 6 : 0, geo.size.width * row.fraction))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.35), value: row.fraction)
    }

    private var footnote: String {
        if row.isComplete {
            return "You did it. Goal fully saved."
        }
        if let months = row.monthsToGo {
            let monthly = EarningsGoalFormat.money(row.goal.monthlyContribution, code: currencyCode)
            return "\(EarningsGoalCalculator.timelineText(months: months)) at \(monthly) a month."
        }
        return "Tap to add savings, or set a monthly amount to see how long it'll take."
    }
}

// MARK: - Formatting

enum EarningsGoalFormat {
    /// Currency in the user's pay-settings currency. Whole amounts drop the
    /// cents ("$2,400"); fractional ones keep them ("$1,599.50").
    static func money(_ value: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        let isWhole = abs(value - value.rounded()) < 0.005
        f.minimumFractionDigits = isWhole ? 0 : 2
        f.maximumFractionDigits = isWhole ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}
