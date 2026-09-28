import SwiftUI

/// Add / edit sheet for an earnings goal: name, target, and an optional
/// amount already put aside. Editing keeps the goal's creation date, so the
/// shifts already counted toward it stay counted.
struct EarningsGoalEditorSheet: View {
    let existing: EarningsGoal?
    let currencyCode: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var goalStore = EarningsGoalStore.shared

    @State private var name: String = ""
    @State private var targetText: String = ""
    @State private var savedText: String = ""
    @State private var showingDeleteConfirm = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, target, saved }

    init(existing: EarningsGoal?, currencyCode: String) {
        self.existing = existing
        self.currencyCode = currencyCode
        _name = State(initialValue: existing?.name ?? "")
        _targetText = State(initialValue: existing.map { Self.editableAmount($0.targetAmount) } ?? "")
        _savedText = State(initialValue: existing.flatMap {
            $0.alreadySaved > 0 ? Self.editableAmount($0.alreadySaved) : nil
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
        if raw.isEmpty { return 0 }
        guard let value = ChequeAmountParser.parse(raw), value >= 0, value.isFinite else { return nil }
        return value
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
        !trimmedName.isEmpty && parsedTarget != nil && parsedSaved != nil
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
                        Text("Shifts you log from the day you set this goal count toward it.")
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
        guard canSave, let target = parsedTarget, let saved = parsedSaved else {
            Haptics.error()
            return
        }
        if var goal = existing {
            goal.name = trimmedName
            goal.targetAmount = target
            goal.alreadySaved = saved
            goalStore.update(goal)
        } else {
            goalStore.add(EarningsGoal(name: trimmedName, targetAmount: target, alreadySaved: saved))
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

    /// Plain editable text for a stored amount ("2400", "1599.5"), in the
    /// locale's decimal separator so ChequeAmountParser reads it back.
    private static func editableAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
