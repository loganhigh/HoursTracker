import SwiftUI

/// "Milestones" card on the You tab, directly under Goals. Every lifetime
/// milestone is listed: reached ones with the day they were crossed (tap to
/// share an image of it), unreached ones with a progress bar. Crossing one
/// sends a notification (IncomeMilestoneNotifier).
struct IncomeMilestonesCard: View {
    @ObservedObject var store: HoursStore

    @State private var shareImage: MilestoneShareImage?

    private var currencyCode: String { store.paySettings.currencyCode }

    var body: some View {
        let rows = IncomeMilestoneCalculator.progress(store: store)
        SectionCard(
            title: "Milestones",
            subtitle: "Lifetime markers worth celebrating",
            trailing: nil,
            centerHeader: true
        ) {
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    if row.isReached {
                        Button {
                            Haptics.lightTap()
                            if let image = IncomeMilestoneShareStory.render(row: row, currencyCode: currencyCode) {
                                shareImage = MilestoneShareImage(image: image)
                            }
                        } label: {
                            IncomeMilestoneRow(row: row, currencyCode: currencyCode)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Share this milestone")
                    } else {
                        IncomeMilestoneRow(row: row, currencyCode: currencyCode)
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .sheet(item: $shareImage) { item in
            ShareSheet(items: [item.image]) { shareImage = nil }
        }
    }
}

// MARK: - Row

private struct IncomeMilestoneRow: View {
    let row: IncomeMilestoneProgress
    let currencyCode: String

    private var tint: Color {
        switch row.milestone.kind {
        case .earnings: return AppColors.positive
        case .hours: return AppColors.accent
        case .shifts: return AppColors.accent2
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(row.isReached ? AppColors.gold.opacity(0.18) : tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: row.isReached ? "checkmark.seal.fill" : row.milestone.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(row.isReached ? AppColors.gold : tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.milestone.title(currencyCode: currencyCode))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    if row.isReached {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.subtext)
                    } else {
                        Text("\(Int((row.fraction * 100).rounded(.down)))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                }

                if let date = row.reachedDate {
                    Text("Reached \(IncomeMilestoneFormat.date(date))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.gold)
                } else {
                    progressBar
                    Text(IncomeMilestoneFormat.remaining(row, currencyCode: currencyCode))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.subtext)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(row.isReached ? AppColors.gold.opacity(0.08) : AppColors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(row.isReached ? AppColors.gold.opacity(0.4) : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.stroke.opacity(0.6))
                Capsule()
                    .fill(tint)
                    .frame(width: max(row.fraction > 0 ? 6 : 0, geo.size.width * row.fraction))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.35), value: row.fraction)
    }
}
