import SwiftUI
import UIKit

// MARK: - Theme (match reference)

private enum ShareAnalyticsTheme {
    static let background = AppTheme.Colors.bg
    static let card = AppTheme.Colors.card
    static let accent = AppTheme.Colors.accent
    static let accent2 = AppTheme.Colors.accentHighlight
    static let text = AppTheme.Colors.text
    static let subtext = AppTheme.Colors.subtext
    static let radius: CGFloat = 16
}

// MARK: - Sheet

struct HoursShareAnalyticsSheet: View {
    @ObservedObject var store: HoursStore
    var achievementTitle: String?
    /// When set, "This Pay Period" analytics use this interval instead of the live current cycle.
    var payPeriodOverride: (start: Date, end: Date)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var selectedRange: HoursAnalyticsCalculator.TimeRange = .thisMonth
    @State private var shareItem: ShareableImage?

    private var payPeriodInterval: (start: Date, end: Date)? {
        if let o = payPeriodOverride { return o }
        let c = PayCycleEngine.currentCycle(settings: store.paySettings)
        return (c.start, c.end)
    }

    private var result: HoursAnalyticsCalculator.Result {
        HoursAnalyticsCalculator.compute(
            entries: store.entries,
            range: selectedRange,
            overtimeHours: { store.payBreakdown(for: $0).overtimeHours },
            payPeriodInterval: selectedRange == .thisPayPeriod ? payPeriodInterval : nil,
            payPeriodFallbackDays: PayCycleEngine.spanDays(for: store.paySettings.payPeriodType)
        )
    }

    var body: some View {
        ZStack {
            ShareAnalyticsTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xl) {
                        heroSummary

                        timeRangePills

                        SectionCard(
                            title: "Breakdown",
                            subtitle: "Stats for \(selectedRange.rawValue.lowercased())",
                            trailing: nil,
                            centerHeader: true
                        ) {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                WorkSummaryStatTile(
                                    label: "Avg Shift",
                                    value: metricValue(result.averageShiftHours, suffix: "h", isHours: true),
                                    icon: "chart.bar.fill"
                                )
                                WorkSummaryStatTile(
                                    label: "Days Worked",
                                    value: metricValue(Double(result.shiftsCount), suffix: "", isHours: false),
                                    icon: "calendar"
                                )
                                WorkSummaryStatTile(
                                    label: "Overtime",
                                    value: metricValue(result.overtimeHours, suffix: "h", isHours: true),
                                    icon: "bolt.fill"
                                )
                                WorkSummaryStatTile(
                                    label: "Regular",
                                    value: metricValue(max(0, result.totalHours - result.overtimeHours), suffix: "h", isHours: true),
                                    icon: "clock.fill"
                                )
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }

                bottomActions
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image]) {
                shareItem = nil
            }
        }
    }

    // MARK: - Hero

    private var heroSummary: some View {
        VStack(spacing: 6) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accentGradient)
            Text(heroValue)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.Colors.text)
                .monospacedDigit()
            Text("Hours logged • \(selectedRange.rawValue)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var heroValue: String {
        if result.shiftsCount == 0 { return "0h" }
        return formatHours(result.totalHours) + "h"
    }

    // MARK: - Range pills

    private var timeRangePills: some View {
        HStack(spacing: 8) {
            ForEach(HoursAnalyticsCalculator.TimeRange.allCases) { r in
                Button {
                    selectedRange = r
                } label: {
                    Text(r.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedRange == r ? .white : ShareAnalyticsTheme.subtext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedRange == r ? ShareAnalyticsTheme.accent : ShareAnalyticsTheme.card)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metricValue(_ value: Double, suffix: String, isHours: Bool) -> String {
        if result.shiftsCount == 0 { return "—" }
        if !isHours && value == 0 { return "—" }
        return (isHours ? formatHours(value) : "\(Int(value))") + suffix
    }

    private var bottomActions: some View {
        VStack(spacing: 12) {
            Text("Generates an image of this summary.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ShareAnalyticsTheme.subtext)
            Button {
                captureAndShare()
            } label: {
                Text("Share Work Report")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(ShareAnalyticsTheme.accent)
                    )
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ShareAnalyticsTheme.subtext)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(ShareAnalyticsTheme.background)
    }

    private func formatHours(_ h: Double) -> String {
        AppTheme.Format.hours(h, suffix: "")
    }

    @MainActor
    private func captureAndShare() {
        let card = ShareableAnalyticsCardView(
            result: result,
            range: selectedRange,
            achievementTitle: achievementTitle
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let img = renderer.uiImage {
            shareItem = ShareableImage(image: img)
        }
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Stat tile (matches CareerStatTile)

private struct WorkSummaryStatTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.card2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Shareable card (for ImageRenderer)

private struct ShareableAnalyticsCardView: View {
    let result: HoursAnalyticsCalculator.Result
    let range: HoursAnalyticsCalculator.TimeRange
    var achievementTitle: String?

    private func shareMetricValue(_ value: Double, suffix: String, isHours: Bool) -> String {
        if result.shiftsCount == 0 { return "—" }
        if !isHours && value == 0 { return "—" }
        return (isHours ? formatH(value) : "\(Int(value))") + suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Work Summary")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(ShareAnalyticsTheme.text)
                Text("Hours logged • \(range.rawValue)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ShareAnalyticsTheme.subtext)
            }

            HStack(spacing: 10) {
                ForEach(HoursAnalyticsCalculator.TimeRange.allCases) { r in
                    Text(r.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(r == range ? .white : ShareAnalyticsTheme.subtext)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(r == range ? ShareAnalyticsTheme.accent : ShareAnalyticsTheme.card)
                        )
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                shareMetricCard("Total Hours", value: shareMetricValue(result.totalHours, suffix: " hrs", isHours: true), trend: result.trendTotal)
                shareMetricCard("Avg Shift Length", value: shareMetricValue(result.averageShiftHours, suffix: " hrs", isHours: true), trend: result.trendAverage)
                shareMetricCard("Overtime", value: shareMetricValue(result.overtimeHours, suffix: " hrs", isHours: true), trend: result.trendOvertime)
                shareMetricCard("Days Worked", value: shareMetricValue(Double(result.shiftsCount), suffix: result.shiftsCount == 1 ? " day" : " days", isHours: false), trend: result.trendShifts)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(ShareAnalyticsTheme.background)
    }

    private func shareMetricCard(_ title: String, value: String, trend: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(ShareAnalyticsTheme.subtext)
            HStack(spacing: 4) {
                Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(ShareAnalyticsTheme.text)
                if let t = trend {
                    Text(t >= 0 ? "+\(t)%" : "\(t)%").font(.system(size: 10, weight: .semibold)).foregroundStyle(t >= 0 ? Color.green : Color.orange)
                } else {
                    Text("—").font(.system(size: 10)).foregroundStyle(ShareAnalyticsTheme.subtext)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ShareAnalyticsTheme.card))
    }

    private func formatH(_ h: Double) -> String {
        AppTheme.Format.hours(h, suffix: "")
    }
}

// MARK: - ShareSheet (UIActivityViewController)

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
