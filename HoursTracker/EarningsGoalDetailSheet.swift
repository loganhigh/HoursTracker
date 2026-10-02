import SwiftUI

/// Opened by tapping a goal: record money put toward it, see what's been
/// added (swipe a deposit away to correct a mistake), or edit the goal.
struct EarningsGoalDetailSheet: View {
    let goalID: UUID
    @ObservedObject var store: HoursStore

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalStore = EarningsGoalStore.shared

    @State private var amountText = ""
    @State private var showingEditor = false
    @FocusState private var amountFocused: Bool

    private var currencyCode: String { store.paySettings.currencyCode }

    /// Live row from the store, so deposits and edits show immediately.
    private var row: EarningsGoalProgress? {
        guard let goal = goalStore.goals.first(where: { $0.id == goalID }) else { return nil }
        return EarningsGoalCalculator.progress(for: [goal]).first
    }

    private var parsedAmount: Double? {
        guard let value = ChequeAmountParser.parse(amountText), value > 0, value.isFinite else { return nil }
        return value
    }

    private var currencySymbol: String {
        CurrencyCatalog.option(for: currencyCode).symbol
    }

    var body: some View {
        NavigationStack {
            Group {
                if let row {
                    content(row)
                } else {
                    // Deleted from the editor.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle(row?.goal.name ?? "Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEditor = true }
                        .disabled(row == nil)
                }
            }
            .sheet(isPresented: $showingEditor) {
                if let goal = row?.goal {
                    EarningsGoalEditorSheet(existing: goal, currencyCode: currencyCode)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func content(_ row: EarningsGoalProgress) -> some View {
        List {
            Section {
                summary(row)
                    .listRowBackground(AppColors.card)
            }

            Section {
                HStack(spacing: 8) {
                    Text(currencySymbol)
                        .foregroundStyle(AppColors.subtext)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .onChange(of: amountText) { _, newValue in
                            let grouped = EarningsGoalEditorSheet.groupedAmountText(newValue)
                            if grouped != newValue { amountText = grouped }
                        }
                    Button("Add") { addDeposit(row) }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                        .disabled(parsedAmount == nil)
                }
                .listRowBackground(AppColors.card)
            } header: {
                Text("Add to savings")
            } footer: {
                Text("Record what you actually put aside for this goal so it stays accurate.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !row.goal.deposits.isEmpty || row.goal.alreadySaved > 0 {
                Section("History") {
                    ForEach(row.goal.deposits.reversed()) { deposit in
                        historyRow(
                            title: deposit.date.formatted(date: .abbreviated, time: .omitted),
                            amount: deposit.amount
                        )
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                goalStore.deleteDeposit(deposit.id, from: row.goal.id)
                                Haptics.warning()
                            }
                        }
                    }
                    if row.goal.alreadySaved > 0 {
                        historyRow(title: "Saved before the goal", amount: row.goal.alreadySaved)
                    }
                }
                .listRowBackground(AppColors.card)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func summary(_ row: EarningsGoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(EarningsGoalFormat.money(row.progress, code: currencyCode))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.text)
                Text("of \(EarningsGoalFormat.money(row.goal.targetAmount, code: currencyCode))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.subtext)
                Spacer(minLength: 0)
            }
            ProgressView(value: row.fraction)
                .tint(row.isComplete ? AppColors.positive : AppColors.accent)
            Text(row.isComplete
                 ? "Goal reached — nicely done."
                 : "\(EarningsGoalFormat.money(row.remaining, code: currencyCode)) remaining")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.isComplete ? AppColors.positive : AppColors.subtext)
            if let months = row.monthsToGo {
                Text("\(EarningsGoalCalculator.timelineText(months: months)) at \(EarningsGoalFormat.money(row.goal.monthlyContribution, code: currencyCode)) a month")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
            }
        }
        .padding(.vertical, 6)
    }

    private func historyRow(title: String, amount: Double) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColors.subtext)
            Spacer()
            Text("+\(EarningsGoalFormat.money(amount, code: currencyCode))")
                .monospacedDigit()
                .foregroundStyle(AppColors.positive)
        }
        .font(.system(size: 15, weight: .medium))
    }

    private func addDeposit(_ row: EarningsGoalProgress) {
        guard let amount = parsedAmount else {
            Haptics.error()
            return
        }
        goalStore.addDeposit(amount, to: row.goal.id)
        amountText = ""
        amountFocused = false
        Haptics.success()
    }
}
