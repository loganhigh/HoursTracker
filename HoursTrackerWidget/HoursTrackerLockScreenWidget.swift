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
        .description("This week's hours and whether today is logged.")
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
        let state = entry.dayState
        Group {
            switch family {
            case .accessoryCircular:
                CircularLockScreenView(state: state)
            case .accessoryRectangular:
                RectangularLockScreenView(entry: entry, state: state)
            case .accessoryInline:
                InlineLockScreenView(state: state, data: entry.widgetData)
            default:
                CircularLockScreenView(state: state)
            }
        }
        .logTodayURL(state)
    }
}

// MARK: - Circular Lock Screen View
//
// With a weekly overtime threshold: a ring filling toward it. Without one:
// just the week's hours. The bottom glyph is today's status — a check once
// logged, a plus (tap to log) when not.

@available(iOS 16.0, *)
struct CircularLockScreenView: View {
    let state: WidgetDayState

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let progress = state.weekProgress {
                Circle()
                    .stroke(.primary.opacity(0.25), lineWidth: 3.5)
                    .padding(3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
            }

            VStack(spacing: 0) {
                Text("WEEK")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .opacity(0.7)
                    .widgetFittingText(minScale: 0.6)

                Text(WidgetFormatting.hours(state.weekHours, suffix: ""))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .widgetFittingText(minScale: 0.45)

                Image(systemName: state.todayLogged ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(state.todayLogged ? 0.7 : 1)
            }
            .padding(.horizontal, 6)
        }
        .widgetAccentable()
    }
}

// MARK: - Rectangular Lock Screen View

@available(iOS 16.0, *)
struct RectangularLockScreenView: View {
    var entry: Provider.Entry
    let state: WidgetDayState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: state.todayLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(state.todayLogged ? state.loggedCaption : "Log today")
                    .font(.system(size: 12, weight: .bold))
                    .widgetFittingText(minScale: 0.65)
            }
            .widgetAccentable()

            HStack(spacing: 6) {
                lockStatColumn(label: "Week", value: weekValue)
                lockStatColumn(label: "Cheque", value: formatHours(entry.widgetData.hoursThisCheque))
                // Projected cheque pay when there is one; month hours otherwise.
                if let pay = projectedPay {
                    lockStatColumn(label: "Projected", value: pay)
                } else {
                    lockStatColumn(label: "Month", value: formatHours(entry.widgetData.hoursThisMonth))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var projectedPay: String? {
        guard let amount = entry.widgetData.projectedPay, amount > 0 else { return nil }
        return "~" + WidgetFormatting.money(amount, currencyCode: entry.widgetData.currencyCode)
    }

    /// "32h", or "32/40h" against the weekly overtime threshold.
    private var weekValue: String {
        guard let target = state.weeklyTarget else { return formatHours(state.weekHours) }
        return "\(formatHours(state.weekHours).dropLast())/\(formatHours(target))"
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
    let state: WidgetDayState
    var data: WidgetData

    var body: some View {
        // Inline renders one image + one text; anything more is dropped.
        let week = WidgetFormatting.hours(state.weekHours)
        if state.todayLogged {
            Label("\(state.loggedCaption) · \(pay ?? "\(week) wk")", systemImage: "checkmark.circle.fill")
        } else {
            Label("Log today · \(pay ?? "\(week) this wk")", systemImage: "plus.circle.fill")
        }
    }

    /// "~$2,140 cheque" when there's a projection.
    private var pay: String? {
        guard let amount = data.projectedPay, amount > 0 else { return nil }
        return "~\(WidgetFormatting.money(amount, currencyCode: data.currencyCode)) cheque"
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
            prestige: 1,
            todayHours: 8,
            todayLogged: true,
            dataDay: Calendar.current.startOfDay(for: .now),
            weeklyTarget: 40,
            projectedPay: 2140,
            currencyCode: "CAD"
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
