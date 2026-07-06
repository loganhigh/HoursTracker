import SwiftUI

// MARK: - Insight Card (vertical list cell)
struct InsightCardView: View {
    let insight: InsightsEngine.Insight

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.accent)
            if let t = insight.title, !t.isEmpty {
                Text(t)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
                    .multilineTextAlignment(.center)
            }
            Text(insight.message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.Colors.text)
                .lineLimit(6)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(minHeight: 47)
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.Colors.cardGradient)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Empty state card (when no insights)
private struct InsightsEmptyCardView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(AppTheme.Colors.accent.opacity(0.8))
            Text("Log a few shifts to see insights here.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 140)
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.Colors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Main Insights View

struct InsightsView: View {
    @ObservedObject var store: HoursStore
    @State private var selectedTimeRange: InsightsTimeRange = .last30
    @State private var selectedIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [InsightsEngine.Insight] {
        InsightsEngine.compute(
            entries: store.allEntriesIncludingArchive(),
            timeRange: selectedTimeRange,
            monthRange: nil
        )
    }

    var body: some View {
        GeometryReader { geo in
            let cardHeight = min(220, geo.size.height * 0.32)
            VStack(spacing: 0) {
                header
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                timeRangeSelector
                    .padding(.horizontal, 4)
                    .padding(.bottom, 16)

                cardsSection(cardHeight: cardHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !items.isEmpty {
                    Text("\(selectedIndex + 1) of \(items.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.subtext)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .onChange(of: selectedIndex) { _, _ in
            Haptics.lightTap()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                selectedIndex = 0
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Insights")
                .font(AppTheme.Typography.h3)
                .foregroundStyle(AppTheme.Colors.text)
                .multilineTextAlignment(.center)
            Text("What your data shows")
                .font(AppTheme.Typography.sub)
                .foregroundStyle(AppTheme.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var timeRangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach([InsightsTimeRange.last7, .last30, .last90, .thisYear], id: \.rawValue) { range in
                    Button {
                        Haptics.lightTap()
                        withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                            selectedTimeRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedTimeRange == range ? .white : AppTheme.Colors.subtext)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedTimeRange == range ? AppTheme.Colors.accent : AppTheme.Colors.card2)
                            )
                            .scaleEffect(selectedTimeRange == range && !reduceMotion ? 1.03 : 1)
                    }
                    .buttonStyle(PremiumPressStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func cardsSection(cardHeight: CGFloat) -> some View {
        if items.isEmpty {
            InsightsEmptyCardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gentleFadeIn()
        } else {
            TabView(selection: $selectedIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, insight in
                    InsightCardView(insight: insight)
                        .frame(maxWidth: .infinity)
                        .frame(height: cardHeight)
                        .padding(.horizontal, 16)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity)
            .animation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion), value: selectedIndex)
        }
    }
}
