import SwiftUI

/// The five ways a stat holiday can be paid, as a radio list under the
/// "Holiday" shift type in the add and edit editors.
struct HolidayPayPicker: View {
    @Binding var rule: HolidayPayRule
    /// Hours of stat pay from Settings, for the option copy.
    let statHours: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel("Holiday pay")
            EntryEditorCard {
                VStack(spacing: 0) {
                    ForEach(Array(HolidayPayRule.allCases.enumerated()), id: \.element) { index, option in
                        if index > 0 { EntryRowDivider() }
                        row(option)
                    }
                }
            }
        }
    }

    private func row(_ option: HolidayPayRule) -> some View {
        let isSelected = rule == option
        return Button {
            guard !isSelected else { return }
            Haptics.lightTap()
            withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                rule = option
            }
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: option.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.subtext)
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .appText(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.text)
                    Text(option.detail(statHours: statHours))
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.faint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "10h × 2 + 8h stat = 28h paid" — what the holiday is worth, worked out
/// from the option picked, with the dollar figure once a wage is set.
struct AddShiftHolidayPayPanel: View {
    let rule: HolidayPayRule
    let workedHours: Double
    let statHours: Double
    let wage: Double?
    let currencyCode: String

    private var paidHours: Double {
        rule.paidHourEquivalent(workedHours: workedHours, statHours: statHours)
    }

    var body: some View {
        AddShiftPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Paid as")
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                    Spacer()
                    Text(HolidayPayRule.hoursText(paidHours))
                        .appText(.title)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.text)
                }
                Text(rule.formula(workedHours: workedHours, statHours: statHours))
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                if let wage, wage > 0 {
                    Text("≈ \(money(paidHours * wage)) before deductions")
                        .appText(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
    }

    private func money(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}
