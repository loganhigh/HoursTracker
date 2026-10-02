import SwiftUI

/// Add / edit sheet for a savings goal: name, target, an optional amount
/// already put aside, and an optional monthly amount for the timeline.
struct EarningsGoalEditorSheet: View {
    let existing: EarningsGoal?
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalStore = EarningsGoalStore.shared

    @State private var name: String = ""
    @State private var targetText: String = ""
    @State private var savedText: String = ""
    @State private var monthlyText: String = ""
    @State private var showingDeleteConfirm = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, target, saved, monthly }

    init(existing: EarningsGoal?, currencyCode: String) {
        self.existing = existing
        self.currencyCode = currencyCode
        _name = State(initialValue: existing?.name ?? "")
        _targetText = State(initialValue: existing.map { Self.editableAmount($0.targetAmount) } ?? "")
        _savedText = State(initialValue: existing.flatMap {
            $0.alreadySaved > 0 ? Self.editableAmount($0.alreadySaved) : nil
        } ?? "")
        _monthlyText = State(initialValue: existing.flatMap {
            $0.monthlyContribution > 0 ? Self.editableAmount($0.monthlyContribution) : nil
        } ?? "")
    }

    // MARK: - Validation

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedTarget: Double? {
        guard let value = ChequeAmountParser.parse(targetText), value > 0, value.isFinite else { return nil }
        return value
    }

    /// Empty means zero; anything typed must parse.
    private var parsedSaved: Double? {
        let raw = savedText.trimmingCharacters(in: .whitespacesAndNewlines)
        // ChequeAmountParser rejects zero (a cheque can't be $0); here "0" just means nothing saved yet.
        if raw.isEmpty || raw.allSatisfy({ !$0.isNumber || $0 == "0" }) { return 0 }
        guard let value = ChequeAmountParser.parse(raw), value >= 0, value.isFinite else { return nil }
        return value
    }

    /// Empty or zero means no plan; anything else typed must parse.
    private var parsedMonthly: Double? {
        let raw = monthlyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.allSatisfy({ !$0.isNumber || $0 == "0" }) { return 0 }
        guard let value = ChequeAmountParser.parse(raw), value >= 0, value.isFinite else { return nil }
        return value
    }

    private var monthlyError: String? {
        parsedMonthly == nil ? "Enter a valid amount, or leave it blank." : nil
    }

    private var nameError: String? {
        trimmedName.isEmpty && !name.isEmpty ? "Give your goal a name." : nil
    }

    private var targetError: String? {
        guard !targetText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return parsedTarget == nil ? "Enter an amount greater than zero." : nil
    }

    private var savedError: String? {
        parsedSaved == nil ? "Enter a valid amount, or leave it blank." : nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && parsedTarget != nil && parsedSaved != nil && parsedMonthly != nil
    }

    private var currencySymbol: String {
        CurrencyCatalog.option(for: currencyCode).symbol
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        textField(
                            title: "Goal",
                            placeholder: "e.g. Vacation, Down payment",
                            text: $name,
                            field: .name,
                            error: nameError
                        )
                        amountField(
                            title: "Target amount",
                            text: $targetText,
                            field: .target,
                            error: targetError
                        )
                        amountField(
                            title: "Already saved (optional)",
                            text: $savedText,
                            field: .saved,
                            error: savedError
                        )
                        amountField(
                            title: "Plan to save each month (optional)",
                            text: $monthlyText,
                            field: .monthly,
                            error: monthlyError
                        )
                        Text("Add a monthly amount and the goal shows about how many months are left. Tap the goal any time to add what you've put aside.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.faint)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .fill(AppColors.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                    .stroke(AppColors.stroke, lineWidth: 1)
                            )
                    )

                    Button(existing == nil ? "Add goal" : "Save changes", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)

                    if existing != nil {
                        Button("Delete goal", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .font(AppTypography.button)
                        .foregroundStyle(AppColors.negative)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this goal?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete goal", role: .destructive) {
                    if let existing {
                        goalStore.delete(id: existing.id)
                        Haptics.warning()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your shifts and pay aren't affected.")
            }
            .onAppear {
                if existing == nil { focusedField = .name }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func save() {
        guard canSave, let target = parsedTarget, let saved = parsedSaved, let monthly = parsedMonthly else {
            Haptics.error()
            return
        }
        // Start from the stored copy, not the snapshot this sheet opened
        // with, so deposits added meanwhile aren't overwritten.
        if let existing {
            var goal = goalStore.goals.first(where: { $0.id == existing.id }) ?? existing
            goal.name = trimmedName
            goal.targetAmount = target
            goal.alreadySaved = saved
            goal.monthlyContribution = monthly
            goalStore.update(goal)
        } else {
            goalStore.add(EarningsGoal(name: trimmedName, targetAmount: target, alreadySaved: saved, monthlyContribution: monthly))
        }
        Haptics.success()
        dismiss()
    }

    // MARK: - Fields

    private func textField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        error: String?
    ) -> some View {
        fieldContainer(title: title, error: error) {
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focusedField, equals: field)
                .onSubmit { focusedField = .target }
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.count > 40 { text.wrappedValue = String(newValue.prefix(40)) }
                }
        }
    }

    private func amountField(
        title: String,
        text: Binding<String>,
        field: Field,
        error: String?
    ) -> some View {
        fieldContainer(title: title, error: error) {
            HStack(spacing: 6) {
                Text(currencySymbol)
                    .foregroundStyle(AppColors.subtext)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: field)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        let grouped = Self.groupedAmountText(newValue)
                        if grouped != newValue { text.wrappedValue = grouped }
                    }
            }
        }
    }

    private func fieldContainer<Content: View>(
        title: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppColors.subtext)
            content()
                .foregroundStyle(AppColors.text)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.card2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(error == nil ? AppColors.stroke : AppColors.negative.opacity(0.6), lineWidth: 1)
                        )
                )
            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.negative)
            }
        }
    }

    /// Editable text for a stored amount ("2,400", "1,599.5"), in the same
    /// grouped form the field produces while typing.
    static func editableAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        return groupedAmountText(f.string(from: NSNumber(value: value)) ?? String(value))
    }

    /// Re-groups an amount as it's typed: "25000" → "25,000", "1234.5" →
    /// "1,234.5", using the locale's separators. Grouping separators already
    /// in the text (the field's own, or pasted) are dropped and rebuilt; the
    /// first decimal separator is kept with at most two digits after it.
    /// Idempotent, so writing the result back doesn't loop.
    static func groupedAmountText(_ raw: String, locale: Locale = .current) -> String {
        let decimal = Character(locale.decimalSeparator ?? ".")
        let grouping = locale.groupingSeparator ?? ","
        var whole = ""
        var fraction: String?
        for ch in raw {
            if ch.isASCII, ch.isNumber {
                if fraction == nil {
                    whole.append(ch)
                } else if fraction!.count < 2 {
                    fraction!.append(ch)
                }
            } else if ch == decimal, fraction == nil {
                fraction = ""
            }
        }
        whole = String(whole.drop(while: { $0 == "0" }))
        if whole.isEmpty, fraction != nil || raw.contains("0") { whole = "0" }

        var grouped = ""
        for (i, ch) in whole.enumerated() {
            if i > 0, (whole.count - i) % 3 == 0 { grouped += grouping }
            grouped.append(ch)
        }
        guard let fraction else { return grouped }
        return grouped + String(decimal) + fraction
    }
}
