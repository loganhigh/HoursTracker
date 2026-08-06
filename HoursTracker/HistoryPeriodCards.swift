import SwiftUI

// MARK: - History cheque preview card (Phase 5)
//
// One row shape for the whole History tab: every cheque gets the same compact
// card so the list stays scannable. Quiet card language — radius 20,
// card.opacity(0.55), hairline stroke, flat accent tint, no glows.

struct ChequePreviewCard<Destination: View>: View {
    /// Work window for the cheque, e.g. "Aug 5 – Aug 18".
    let title: String
    /// Small secondary line, e.g. "12 shifts" (or "In progress").
    let caption: String
    let hours: Double
    /// The in-progress cheque: accent-tinted value + stronger hairline, same size.
    var isCurrent: Bool = false
    @ViewBuilder var destination: () -> Destination

    private var valueColor: Color { isCurrent ? AppColors.accent : AppColors.text }
    private var captionColor: Color { isCurrent ? AppColors.accent : AppColors.subtext }
    private var strokeColor: Color { isCurrent ? AppColors.accent.opacity(0.35) : AppColors.stroke }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(caption)
                        .appText(.caption)
                        .foregroundStyle(captionColor)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.xs)

                Text(AppTheme.Format.hours(hours))
                    .appText(.metricValue)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(strokeColor, lineWidth: isCurrent ? 1 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(PremiumPressStyle())
        .accessibilityLabel("\(title), \(AppTheme.Format.hours(hours)) hours, \(caption)")
    }
}
