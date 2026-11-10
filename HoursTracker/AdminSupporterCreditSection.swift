import SwiftUI
import FirebaseFunctions

/// Edit-user sheet section: set how much someone has tipped in total, for
/// tips made before the ledger existed or paid outside the App Store. The
/// supporter tiers read this total ($5 name colour, $20 photo ring).
/// 0 removes supporter status. Applies immediately.
struct AdminSupporterCreditSection: View {
    let uid: String
    let passcode: String
    let currentTotal: Double
    var onSaved: (Double) -> Void = { _ in }

    @State private var amountText: String
    @State private var isSaving = false
    @State private var message: String?
    @State private var failed = false

    private let functions = Functions.functions(region: "us-central1")

    init(uid: String, passcode: String, currentTotal: Double, onSaved: @escaping (Double) -> Void = { _ in }) {
        self.uid = uid
        self.passcode = passcode
        self.currentTotal = currentTotal
        self.onSaved = onSaved
        _amountText = State(initialValue: currentTotal > 0 ? String(format: "%.2f", currentTotal) : "")
    }

    private var amount: Double? {
        let cleaned = amountText.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value >= 0, value <= 10_000 else { return nil }
        return value
    }

    var body: some View {
        Section {
            HStack {
                Text("Total tipped")
                Spacer()
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            HStack(spacing: 8) {
                ForEach([4.99, 20.0], id: \.self) { preset in
                    Button(String(format: "$%.2f", preset)) { amountText = String(format: "%.2f", preset) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) } else { Text("Save credit") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSaving || amount == nil)
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(failed ? AppTheme.Colors.danger : AppTheme.Colors.success)
            }
        } header: {
            Text("Supporter credit")
        } footer: {
            Text("Sets their total tipped. Any amount = supporter name, badge, chat heart and thanks wall. $4.99+ unlocks name colours, $20+ the photo ring. 0 removes supporter status. Applies immediately.")
        }
    }

    private func save() async {
        guard let amount else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            _ = try await functions.httpsCallable("adminSetSupporterTotal")
                .call(["passcode": passcode, "targetUid": uid, "total": amount])
            Haptics.success()
            failed = false
            message = amount > 0 ? String(format: "Saved: $%.2f tipped.", amount) : "Supporter status removed."
            onSaved(amount)
        } catch {
            Haptics.error()
            failed = true
            message = error.localizedDescription
        }
    }
}
