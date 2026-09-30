import SwiftUI

/// Asked once after saving a paid shift when no hourly wage is set: the
/// earnings card can't show real dollars on the $35 placeholder. Saving here
/// is the same as typing the wage in Settings; "Not now" snoozes the prompt
/// for a week so it never nags every shift.
struct WagePromptSheet: View {
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @FocusState private var focused: Bool

    private static let snoozeKey = "wage_prompt_snoozed_until"
    private static let snooze: TimeInterval = 7 * 86400

    static func shouldOffer(now: Date = Date()) -> Bool {
        let until = UserDefaults.standard.double(forKey: snoozeKey)
        return now.timeIntervalSince1970 >= until
    }

    /// Accepts "46.61", "46,61" or "$46.61".
    private var parsed: Double? {
        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0, value.isFinite, value < 10_000 else { return nil }
        return (value * 100).rounded() / 100
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            VStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                Text("What's your hourly wage?")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
                Text("Set it once and every shift you save shows what it earned — gross, take-home and how this cheque is shaping up.")
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, AppSpacing.md)

            HStack(spacing: AppSpacing.xs) {
                Text(currencySymbol)
                    .appText(.title)
                    .foregroundStyle(AppColors.subtext)
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.text)
                    .focused($focused)
                    .tint(AppColors.accent)
                Text("/ hr")
                    .appText(.headline)
                    .foregroundStyle(AppColors.subtext)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.stroke, lineWidth: 1)
                    )
            )

            VStack(spacing: AppSpacing.sm) {
                Button("Save wage") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(parsed == nil)
                    .opacity(parsed == nil ? 0.55 : 1)
                Button("Not now") {
                    Haptics.lightTap()
                    UserDefaults.standard.set(Date().timeIntervalSince1970 + Self.snooze, forKey: Self.snoozeKey)
                    dismiss()
                }
                .appText(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.subtext)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.lg)
        .background(AppColors.bg.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .onAppear { focused = true }
    }

    private var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = store.paySettings.currencyCode
        return f.currencySymbol ?? "$"
    }

    private func save() {
        guard let value = parsed else { return }
        Haptics.success()
        store.paySettings.hourlyRate = value
        store.paySettings.hourlyRateSet = true
        store.persist()
        dismiss()
    }
}
