import SwiftUI

/// Regular living costs (rent, car, phone) that Goals subtracts before
/// estimating how many shifts a goal takes. Tap an expense to edit it,
/// swipe to remove it.
struct GoalExpensesSheet: View {
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalStore = EarningsGoalStore.shared

    @State private var editingID: UUID?
    @State private var name = ""
    @State private var amountText = ""
    @State private var frequency: GoalExpense.Frequency = .monthly
    @FocusState private var focused: Field?

    private enum Field { case name, amount }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parsedAmount: Double? {
        guard let value = ChequeAmountParser.parse(amountText), value > 0, value.isFinite else { return nil }
        return value
    }

    private var canSave: Bool { !trimmedName.isEmpty && parsedAmount != nil }

    private var currencySymbol: String { CurrencyCatalog.option(for: currencyCode).symbol }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Per month")
                            .foregroundStyle(AppColors.subtext)
                        Spacer()
                        Text(EarningsGoalFormat.money(goalStore.monthlyExpenses, code: currencyCode))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.text)
                    }
                    .listRowBackground(AppColors.card)
                } footer: {
                    Text("Your goals only count what a shift leaves after these are paid, so the shift estimate stays realistic.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if !goalStore.expenses.isEmpty {
                    Section("Your expenses") {
                        ForEach(goalStore.expenses) { expense in
                            Button { beginEditing(expense) } label: { expenseRow(expense) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Remove", role: .destructive) {
                                        if editingID == expense.id { resetForm() }
                                        goalStore.deleteExpense(id: expense.id)
                                        Haptics.warning()
                                    }
                                }
                        }
                    }
                    .listRowBackground(AppColors.card)
                }

                Section(editingID == nil ? "Add an expense" : "Edit expense") {
                    TextField("e.g. Rent, Car payment, Phone", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .amount }
                        .onChange(of: name) { _, newValue in
                            if newValue.count > 40 { name = String(newValue.prefix(40)) }
                        }
                    HStack(spacing: 6) {
                        Text(currencySymbol).foregroundStyle(AppColors.subtext)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($focused, equals: .amount)
                            .onChange(of: amountText) { _, newValue in
                                let grouped = EarningsGoalEditorSheet.groupedAmountText(newValue)
                                if grouped != newValue { amountText = grouped }
                            }
                    }
                    Picker("How often", selection: $frequency) {
                        ForEach(GoalExpense.Frequency.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    HStack {
                        if editingID != nil {
                            Button("Cancel", action: resetForm)
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button(editingID == nil ? "Add expense" : "Save changes", action: save)
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.accent)
                            .disabled(!canSave)
                    }
                }
                .listRowBackground(AppColors.card)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func expenseRow(_ expense: GoalExpense) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.name)
                    .foregroundStyle(AppColors.text)
                Text(expense.frequency.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.subtext)
            }
            Spacer()
            Text(EarningsGoalFormat.money(expense.amount, code: currencyCode))
                .monospacedDigit()
                .foregroundStyle(AppColors.text)
        }
        .contentShape(Rectangle())
    }

    private func beginEditing(_ expense: GoalExpense) {
        Haptics.lightTap()
        editingID = expense.id
        name = expense.name
        amountText = EarningsGoalEditorSheet.editableAmount(expense.amount)
        frequency = expense.frequency
        focused = .amount
    }

    private func resetForm() {
        editingID = nil
        name = ""
        amountText = ""
        frequency = .monthly
        focused = nil
    }

    private func save() {
        guard let amount = parsedAmount, !trimmedName.isEmpty else {
            Haptics.error()
            return
        }
        if let editingID, var existing = goalStore.expenses.first(where: { $0.id == editingID }) {
            existing.name = trimmedName
            existing.amount = amount
            existing.frequency = frequency
            goalStore.updateExpense(existing)
        } else {
            goalStore.addExpense(GoalExpense(name: trimmedName, amount: amount, frequency: frequency))
        }
        Haptics.success()
        resetForm()
    }
}
