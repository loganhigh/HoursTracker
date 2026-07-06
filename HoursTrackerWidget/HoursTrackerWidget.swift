import WidgetKit
import SwiftUI

// MARK: - Shared Timeline Entry & Provider (used by all widgets in this extension)

struct SimpleEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), widgetData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), widgetData: WidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date(), widgetData: WidgetData.load())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Home Screen Widget View

struct HoursTrackerWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("HOURS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .widgetFittingText(minScale: 0.7)
            }
            .foregroundStyle(.white.opacity(0.7))

            Text(formatHours(entry.widgetData.hoursThisCheque))
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .widgetFittingText(minScale: 0.45)

            Text("this pay period")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .widgetFittingText(minScale: 0.7)

            if entry.widgetData.currentStreak > 0 {
                HStack(spacing: 3) {
                    Text("🔥")
                        .font(.system(size: 11))
                    Text("\(entry.widgetData.currentStreak)d streak")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .widgetFittingText(minScale: 0.7)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("PAY PERIOD")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1)
                        .widgetFittingText(minScale: 0.7)
                }
                .foregroundStyle(.white.opacity(0.7))

                Text(formatHours(entry.widgetData.hoursThisCheque))
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .widgetFittingText(minScale: 0.45)

                if entry.widgetData.currentStreak > 0 {
                    Text("🔥 \(entry.widgetData.currentStreak) day streak")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .widgetFittingText(minScale: 0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                mediumStat(label: "This Week", value: formatHours(entry.widgetData.hoursThisWeek))
                mediumStat(label: "Month", value: formatHours(entry.widgetData.hoursThisMonth))
                if let payday = entry.widgetData.nextPayday {
                    let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: payday).day ?? 0)
                    mediumStat(label: "Payday", value: days == 0 ? "Today!" : "\(days)d")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
        }
        .padding(16)
    }

    private func mediumStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.6))
                .widgetFittingText(minScale: 0.7)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .widgetFittingText(minScale: 0.45)
        }
    }
}

// MARK: - Widget Definition

struct HoursTrackerWidget: Widget {
    let kind: String = "HoursTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HoursTrackerWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    ZStack {
                        WidgetPrestigeTheme.backgroundGradient(for: entry.widgetData.prestige)
                        LinearGradient(
                            colors: [Color.black.opacity(0.18), Color.black.opacity(0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
        }
        .configurationDisplayName("Work Hours")
        .description("Track your hours at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Helpers

func formatHours(_ hours: Double) -> String {
    WidgetFormatting.hours(hours)
}
