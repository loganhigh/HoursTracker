import SwiftUI

// MARK: - History period cards (Phase 5)
//
// Shared building blocks for the History tab's period cards: a day-by-day
// mini bar strip plus the current-period and compact previous-period cards.
// Quiet card language throughout — radius 20, card.opacity(0.55), hairline
// strokes, flat accent fills, no glows.

// MARK: - Day strip model

/// One day inside a period strip.
enum DayStripState: Equatable {
    /// Worked day — accent bar sized by hours.
    case worked(Double)
    /// Past day with nothing logged — faint stub.
    case rest
    /// Logged off day — quiet muted stub.
    case off
    /// Future day — faint hollow slot.
    case future
}

struct DayStripCell: Identifiable {
    let id: Date
    let state: DayStripState
}

// MARK: - PeriodDayStrip
//
// Mini version of the Home yearly chart: bottom-aligned accent bars for
// worked days, faint stubs for empty past days, hollow slots for the future.

struct PeriodDayStrip: View {
    let cells: [DayStripCell]
    var barHeight: CGFloat = 34

    private var maxHours: Double {
        let worked = cells.compactMap { cell -> Double? in
            if case .worked(let h) = cell.state { return h }
            return nil
        }
        return max(worked.max() ?? 8, 8)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: cells.count > 16 ? 2 : 4) {
            ForEach(cells) { cell in
                bar(for: cell)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barHeight)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bar(for cell: DayStripCell) -> some View {
        switch cell.state {
        case .worked(let hours):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.accent)
                .frame(height: max(6, CGFloat(hours / maxHours) * barHeight))
        case .rest:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.faint.opacity(0.35))
                .frame(height: 4)
        case .off:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.negative.opacity(0.35))
                .frame(height: 4)
        case .future:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(AppColors.faint.opacity(0.5), lineWidth: 0.75)
                .frame(height: 12)
        }
    }
}

// MARK: - CurrentPeriodCard
//
// The dominant top card for the in-progress cheque / month: range, quiet
// "In progress" capsule, hero hours numeral, shifts/days caption, day strip.

struct CurrentPeriodCard<Destination: View>: View {
    let title: String
    var badge: String? = nil
    let hours: Double
    let caption: String
    let cells: [DayStripCell]
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .center) {
                    Text(title)
                        .appText(.subheadline)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: AppSpacing.xs)
                    if let badge {
                        Text(badge)
                            .appText(.caption)
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(AppColors.accent.opacity(0.12))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppTheme.Format.hours(hours))
                        .appText(.heroNumber)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(caption)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }

                PeriodDayStrip(cells: cells)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(AppColors.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColors.strokeStrong, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(PremiumPressStyle())
        .accessibilityLabel("\(title), \(AppTheme.Format.hours(hours)) hours, \(caption)")
    }
}

// MARK: - CompactPeriodCard
//
// Previous cheque / month card: title + caption on the left, hours numeral
// on the right, optional small sparkline underneath (months only).

struct CompactPeriodCard<Destination: View>: View {
    let title: String
    let caption: String
    let hours: Double
    var cells: [DayStripCell]? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .appText(.headline)
                            .foregroundStyle(AppColors.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(caption)
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }

                    Spacer(minLength: AppSpacing.xs)

                    Text(AppTheme.Format.hours(hours))
                        .appText(.metricValue)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.faint)
                }

                if let cells {
                    PeriodDayStrip(cells: cells, barHeight: 18)
                        .padding(.top, 2)
                }
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
                    .stroke(AppColors.stroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(PremiumPressStyle())
        .accessibilityLabel("\(title), \(AppTheme.Format.hours(hours)) hours, \(caption)")
    }
}
