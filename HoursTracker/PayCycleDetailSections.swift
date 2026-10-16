import SwiftUI

// MARK: - Cheque detail sections
//
// Pieces of PayCycleDetailView split out to keep it under the 500-line limit.

/// Records what the cheque really paid. This is the training data for the
/// projection on History's In Progress row: each recorded total teaches the
/// predictor the real net rate — taxes, tips, and bonuses included — that the
/// in-app estimate can't see. Only shown once the payday has passed.
struct ChequeTotalSection: View {
    @ObservedObject var store: HoursStore
    let cycle: PayCycle

    @State private var showingPayoutEntry = false
    @State private var payoutDraft = ""

    private var recordedPayout: Double? { store.actualPayout(for: cycle) }

    var body: some View {
        if cycle.payday <= Date() {
            Button {
                Haptics.lightTap()
                payoutDraft = recordedPayout.map { String(format: "%.2f", $0) } ?? ""
                showingPayoutEntry = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "banknote")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                                .fill(AppColors.accent.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(recordedPayout == nil ? "Add cheque total" : "Cheque total")
                            .appText(.headline)
                            .foregroundStyle(AppColors.text)
                        Text(recordedPayout == nil
                             ? "Enter what this cheque actually paid — it teaches your pay projection."
                             : "Tap to edit. Powers the projection on your live cheque.")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if let recordedPayout {
                        Text(currency(recordedPayout))
                            .font(AppTypography.headline.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.positive)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(AppColors.card.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(AppColors.stroke, lineWidth: 0.5)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alert("Cheque total", isPresented: $showingPayoutEntry) {
                TextField("Amount", text: $payoutDraft)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    // Locale-aware: "1,540.25", "$1540" and fr_CA "1540,25" all
                    // parse to what the paystub says. Unparseable input keeps
                    // whatever was recorded — passing nil here used to silently
                    // DELETE the existing total on a typo.
                    if let amount = ChequeAmountParser.parse(payoutDraft) {
                        store.setActualPayout(amount, for: cycle)
                        Haptics.success()
                    } else {
                        Haptics.error()
                    }
                }
                if recordedPayout != nil {
                    Button("Remove", role: .destructive) {
                        store.setActualPayout(nil, for: cycle)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What this cheque actually paid, after tax and including tips or bonuses.")
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = store.paySettings.currencyCode
        return f.string(from: NSNumber(value: value)) ?? "—"
    }
}
