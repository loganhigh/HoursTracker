import SwiftUI

struct MonthSummaryRow: View {
    let title: String
    let hours: Double
    let pay: Double
    let currencyCode: String
    let showPay: Bool

    private var hoursString: String {
        AppTheme.Format.hours(hours, suffix: "")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.text)
            }

            Spacer()

            if showPay {
                HStack(spacing: 8) {
                    AnimatedMetricText(value: hours) { AppTheme.Format.hours($0, suffix: "") + " hrs" }
                        .font(AppDesignSystem.Typography.heroNumerals(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.text)

                    Text("•")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))

                    AnimatedMetricText(currency: pay, code: currencyCode)
                        .font(AppDesignSystem.Typography.heroNumerals(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            } else {
                AnimatedMetricText(value: hours) { AppTheme.Format.hours($0, suffix: "") + " hrs" }
                    .font(AppDesignSystem.Typography.heroNumerals(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.text)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext.opacity(0.5))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.card2.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.stroke, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showPay ? "\(title), \(hoursString) hours, \(pay)" : "\(title), \(hoursString) hours")
    }
}

#Preview("MonthSummaryRow") {
    MonthSummaryRow(
        title: "September 2025",
        hours: 128.5,
        pay: 2450.75,
        currencyCode: "USD",
        showPay: true
    )
    .padding()
    .background(AppTheme.Colors.bg)
}
