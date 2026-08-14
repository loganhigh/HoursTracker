import SwiftUI

// MARK: - History table pieces
//
// A year of cheques rendered as a bordered card with a table inside: a
// header strip, then one row per cheque with its number, work range, and a
// status pill. Rows fade up in sequence as the card appears.

/// Where a cheque sits in the pay lifecycle.
enum ChequeStatus {
    /// Still accruing hours — this is the live pay period.
    case inProgress
    /// Work window closed, payday hasn't arrived yet.
    case pending
    /// Payday has passed.
    case paid

    var label: String {
        switch self {
        case .inProgress: return "In Progress"
        case .pending: return "Pending"
        case .paid: return "Paid"
        }
    }

    var tint: Color {
        switch self {
        case .inProgress: return AppColors.warning
        case .pending: return AppColors.subtext
        case .paid: return AppColors.positive
        }
    }
}

/// Pill badge — tinted fill behind matching text, one per status.
struct ChequeStatusBadge: View {
    let status: ChequeStatus

    var body: some View {
        Text(status.label)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(status.tint.opacity(0.16)))
            .fixedSize()
    }
}

/// One cheque row: number, work range + shift summary, status pill.
struct ChequeTableRow<Destination: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    let status: ChequeStatus
    /// Optional third line: recorded cheque total on paid rows, the live
    /// projection on the In Progress row. Tinted by the caller.
    var accentLine: (text: String, tint: Color)? = nil
    /// Staggers this row's entrance so a card's rows arrive in sequence.
    let index: Int
    @ViewBuilder let destination: () -> Destination

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: AppSpacing.sm) {
                Text("\(number)")
                    .appText(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.faint)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(1)
                    if let accentLine {
                        Text(accentLine.text)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accentLine.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                ChequeStatusBadge(status: status)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(
                .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(Double(min(index, 8)) * 0.06)
            ) {
                appeared = true
            }
        }
    }
}

/// The bordered card wrapping one year's table, titled with the year.
struct ChequeYearCard<Content: View>: View {
    let year: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(year))
                .appText(.title)
                .foregroundStyle(AppColors.text)
                .padding(.bottom, AppSpacing.sm)

            // Column header strip — the row layout's labels.
            HStack(spacing: AppSpacing.sm) {
                Text("No")
                    .frame(width: 22, alignment: .leading)
                Text("Cheque")
                Spacer(minLength: AppSpacing.xs)
                Text("Status")
            }
            .appText(.caption)
            .foregroundStyle(AppColors.subtext)
            .padding(.bottom, AppSpacing.xs)

            Divider().overlay(AppColors.stroke)

            content()
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
        )
    }
}
