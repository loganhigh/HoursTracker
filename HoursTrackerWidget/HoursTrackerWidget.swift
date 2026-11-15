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
        let now = Date()
        let data = WidgetData.load()
        let cal = Calendar.current
        // A second entry at the next midnight flips "today" to not-logged
        // (and resets the week across a week boundary) on time, even if the
        // app doesn't run. The app reloads timelines whenever shifts change.
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let entries = [
            SimpleEntry(date: now, widgetData: data),
            SimpleEntry(date: midnight, widgetData: data)
        ]
        let refresh = min(cal.date(byAdding: .minute, value: 30, to: now) ?? midnight, midnight)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Home Screen Widget View
//
// NOTE on hardcoded whites: the widget always renders on the prestige-tier
// gradient + black scrim (see `containerBackground` below), which is identical
// in light and dark appearance. Every `.white` here is therefore
// "text on accent fill" (the app target's AppColors.textOnAccent) — do not
// convert them to scheme-adaptive tokens.

struct HoursTrackerWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  SmallWidgetView(entry: entry)
            case .systemMedium: MediumWidgetView(entry: entry)
            default:            SmallWidgetView(entry: entry)
            }
        }
        .logTodayURL(entry.dayState)
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        let state = entry.dayState
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("HOURS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .widgetFittingText(minScale: 0.7)
                Spacer(minLength: 2)
                if entry.widgetData.currentStreak > 0 {
                    Text("🔥\(entry.widgetData.currentStreak)")
                        .font(.system(size: 11, weight: .semibold))
                        .widgetFittingText(minScale: 0.7)
                }
            }
            .foregroundStyle(.white.opacity(0.7))

            Text(formatHours(state.weekHours))
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .widgetFittingText(minScale: 0.45)

            Text(weekCaption(state))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .widgetFittingText(minScale: 0.7)

            Spacer(minLength: 0)

            TodayStatusPill(state: state)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func weekCaption(_ state: WidgetDayState) -> String {
        if let target = state.weeklyTarget {
            return "of \(formatHours(target)) this week"
        }
        return "this week"
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        let state = entry.dayState
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("PAY CHEQUE")
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

                Spacer(minLength: 0)

                TodayStatusPill(state: state, fontSize: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                mediumStat(label: "This Week", value: weekValue(state))
                mediumStat(label: "Month", value: formatHours(entry.widgetData.hoursThisMonth))
                if let payday = entry.widgetData.nextPayday {
                    // Calendar days, not elapsed 24h intervals: counting from
                    // "now" to a midnight payday truncated the last partial
                    // day and showed "1d" when payday was 2 days away.
                    let cal = Calendar.current
                    let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: payday)).day ?? 0)
                    mediumStat(label: "Payday", value: days == 0 ? "Today!" : "\(days)d")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
        }
        .padding(16)
    }

    /// "32h", or "32/40h" against the weekly overtime threshold.
    private func weekValue(_ state: WidgetDayState) -> String {
        guard let target = state.weeklyTarget else { return formatHours(state.weekHours) }
        return "\(formatHours(state.weekHours).dropLast())/\(formatHours(target))"
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
        .description("This week's hours, with a one-tap reminder to log today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Helpers

func formatHours(_ hours: Double) -> String {
    WidgetFormatting.hours(hours)
}
