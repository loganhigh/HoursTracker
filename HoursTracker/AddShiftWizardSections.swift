import SwiftUI

// MARK: - Add Shift wizard building blocks
//
// Token-pure pieces for `AddShiftWizardView`: the icon-square field rows,
// the quiet panels (total time / confirmation), and the location row used by
// the saved-locations picker sheet. Dark theme only — flat fills, hairline
// strokes, `tint.opacity(0.14)` icon squares, no glows.

// MARK: - Formatting

enum AddShiftFormat {
    /// "10h 0m" — the wizard's duration voice (the rest of the app uses decimal hours).
    static func duration(_ hours: Double) -> String {
        let totalMinutes = Int((max(0, hours) * 60).rounded())
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
}

// MARK: - Quiet panel (radius 20 card; tinted variant for summaries)

struct AddShiftPanel<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = AppSpacing.md
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            shape
                .fill(tint.map { $0.opacity(0.12) } ?? AppColors.card)
                .overlay(shape.stroke(tint.map { $0.opacity(0.25) } ?? AppColors.stroke, lineWidth: 1))
        )
    }
}

// MARK: - Field row (icon square + label above value)

struct AddShiftFieldRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = AppColors.accent
    var isPlaceholder: Bool = false
    var isExpanded: Bool = false
    var accessory: Accessory = .chevron
    var action: (() -> Void)? = nil

    enum Accessory {
        case chevron, disclosure, hidden
    }

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: AppSpacing.sm) {
            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                Text(value)
                    .font(.system(.headline, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(valueTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: AppSpacing.xs)

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
            case .disclosure:
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isExpanded ? AppColors.accent : AppColors.faint)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            case .hidden:
                EmptyView()
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var valueTint: Color {
        if isPlaceholder { return AppColors.faint }
        return isExpanded ? AppColors.accent : AppColors.text
    }
}

// MARK: - Total time panel

struct AddShiftTotalTimePanel: View {
    let hours: Double
    var caption: String?

    var body: some View {
        AddShiftPanel(tint: AppColors.accent) {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Time")
                        .appText(.eyebrow)
                        .foregroundStyle(AppColors.subtext)
                    if let caption {
                        Text(caption)
                            .appText(.caption)
                            .foregroundStyle(AppColors.faint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: AppSpacing.xs)
                AnimatedMetricText(value: hours) { AddShiftFormat.duration($0) }
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(AppColors.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Confirmation panel (step 3)

struct AddShiftConfirmationPanel: View {
    let isValid: Bool
    let title: String
    let message: String

    var body: some View {
        AddShiftPanel(tint: isValid ? AppColors.positive : AppColors.warning) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isValid ? AppColors.positive : AppColors.warning)
                VStack(spacing: 2) {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Location row (icon + name + subtitle + radio)

struct AddShiftLocationRow: View {
    var icon: String = JobSite.defaultIcon
    let name: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .fill(AppColors.accent.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.xs)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.faint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
