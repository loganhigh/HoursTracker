import WidgetKit
import SwiftUI

// MARK: - Lock Screen Widget

@available(iOS 16.0, *)
struct HoursTrackerLockScreenWidget: Widget {
    let kind: String = "HoursTrackerLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HoursTrackerLockScreenWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Work Hours")
        .description("Quick view of your work hours.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@available(iOS 16.0, *)
struct HoursTrackerLockScreenWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularLockScreenView(entry: entry)
        case .accessoryRectangular:
            RectangularLockScreenView(entry: entry)
        case .accessoryInline:
            InlineLockScreenView(entry: entry)
        default:
            CircularLockScreenView(entry: entry)
        }
    }
}

// MARK: - Circular Lock Screen View

@available(iOS 16.0, *)
struct CircularLockScreenView: View {
    var entry: Provider.Entry
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            VStack(spacing: 1) {
                Text("This")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .opacity(0.7)
                    .widgetFittingText(minScale: 0.6)

                Text(formatHours(entry.widgetData.hoursThisCheque, suffix: ""))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .widgetFittingText(minScale: 0.45)

                Text("Cheque")
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.7)
                    .widgetFittingText(minScale: 0.6)
            }
        }
    }
    
    private func formatHours(_ hours: Double, suffix: String) -> String {
        WidgetFormatting.hours(hours, suffix: suffix)
    }
}

// MARK: - Rectangular Lock Screen View

@available(iOS 16.0, *)
struct RectangularLockScreenView: View {
    var entry: Provider.Entry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Hours Tracker")
                    .font(.system(size: 11, weight: .semibold))
                    .widgetFittingText(minScale: 0.65)
            }

            HStack(spacing: 6) {
                lockStatColumn(label: "Week", value: formatHours(entry.widgetData.hoursThisWeek))
                lockStatColumn(label: "Cheque", value: formatHours(entry.widgetData.hoursThisCheque))
                lockStatColumn(label: "Month", value: formatHours(entry.widgetData.hoursThisMonth))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func lockStatColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .opacity(0.75)
                .widgetFittingText(minScale: 0.45)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .widgetFittingText(minScale: 0.45)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatHours(_ hours: Double) -> String {
        WidgetFormatting.hours(hours)
    }
}

// MARK: - Inline Lock Screen View

@available(iOS 16.0, *)
struct InlineLockScreenView: View {
    var entry: Provider.Entry
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text("Week: \(formatHours(entry.widgetData.hoursThisWeek))")
            if entry.widgetData.currentStreak > 0 {
                Text("🔥\(entry.widgetData.currentStreak)")
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .widgetFittingText(minScale: 0.55)
    }
    
    private func formatHours(_ hours: Double) -> String {
        WidgetFormatting.hours(hours)
    }
}

// MARK: - Previews

@available(iOS 16.0, *)
struct HoursTrackerLockScreenWidget_Previews: PreviewProvider {
    static var previews: some View {
        let sampleData = WidgetData(
            hoursThisCheque: 70,
            hoursThisMonth: 109,
            hoursThisWeek: 42,
            nextPayday: Date(),
            lastUpdated: Date(),
            currentStreak: 9,
            prestige: 1
        )
        let entry = SimpleEntry(date: .now, widgetData: sampleData)
        
        Group {
            HoursTrackerLockScreenWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Circular")
            
            HoursTrackerLockScreenWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular")
            
            HoursTrackerLockScreenWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("Inline")
        }
    }
}
