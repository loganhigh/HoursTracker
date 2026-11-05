import SwiftUI
import WidgetKit

// MARK: - Watch face complications
//
// One widget in every watch-face slot (corner, circular, rectangular, inline)
// plus the Smart Stack. On shift it shows a live timer (WidgetKit counts it
// up on its own, so it is always exact); off shift, this cheque's and this
// month's hours. Data is the snapshot the watch app saved to the app group;
// the watch app reloads these whenever the shift or totals change.

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), snapshot: context.isPreview ? .preview : (WatchComplicationStore.load() ?? .preview)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let entry = ComplicationEntry(date: now, snapshot: WatchComplicationStore.load() ?? .empty)
        // Totals only change when the app reloads us; refresh at midnight so
        // a new month (or cheque) never shows yesterday's numbers for long.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

private let accent = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
private let breakTint = Color(red: 0.98, green: 0.74, blue: 0.24)

private func hours(_ value: Double) -> String {
    var text = String(format: "%.1f", max(0, value))
    if text.hasSuffix(".0") { text.removeLast(2) }
    return text + "h"
}

private extension WatchLiveShift {
    /// The moment a stopwatch would have started for the time worked so far,
    /// so `Text(_, style: .timer)` shows worked time, not wall-clock time.
    func timerStart(at now: Date) -> Date { now.addingTimeInterval(-workedSeconds(at: now)) }

    func workedText(at now: Date) -> String {
        let minutes = Int(workedSeconds(at: now) / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var snapshot: WatchSnapshot { entry.snapshot }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryCorner: corner
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: Families

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if let live = snapshot.liveShift {
                    Image(systemName: live.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(live.isOnBreak ? breakTint : accent)
                    if live.isOnBreak {
                        Text(live.workedText(at: entry.date))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    } else {
                        Text(live.timerStart(at: entry.date), style: .timer)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    }
                } else {
                    Text(hours(snapshot.chequeHours))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text("CHEQUE")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .padding(4)
        }
        .widgetAccentable()
    }

    private var corner: some View {
        Group {
            if let live = snapshot.liveShift, !live.isOnBreak {
                Text(live.timerStart(at: entry.date), style: .timer)
                    .widgetCurvesContent()
                    .widgetLabel { Text("On shift") }
            } else {
                Image(systemName: snapshot.liveShift == nil ? "clock" : "cup.and.saucer.fill")
                    .font(.title3.weight(.semibold))
                    .widgetLabel {
                        Text(snapshot.liveShift.map { "Break · \($0.workedText(at: entry.date))" }
                             ?? "\(hours(snapshot.chequeHours)) cheque")
                    }
            }
        }
        .widgetAccentable()
    }

    private var inline: some View {
        Group {
            if let live = snapshot.liveShift {
                if live.isOnBreak {
                    Text("☕ Break · \(live.workedText(at: entry.date)) worked")
                } else {
                    Text("⏱ \(live.timerStart(at: entry.date), style: .timer) on shift")
                }
            } else if snapshot.signedIn {
                Text("\(hours(snapshot.chequeHours)) this cheque")
            } else {
                Text("Hour Tracker")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let live = snapshot.liveShift {
                Label(live.isOnBreak ? "On break" : "On shift",
                      systemImage: live.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(live.isOnBreak ? breakTint : accent)
                    .widgetAccentable()
                if live.isOnBreak {
                    Text(live.workedText(at: entry.date))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                } else {
                    Text(live.timerStart(at: entry.date), style: .timer)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text("Since \(live.startDate.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Hour Tracker")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                    .widgetAccentable()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    stat(hours(snapshot.chequeHours), "Cheque")
                    stat(hours(snapshot.monthHours), "Month")
                }
                Text(snapshot.signedIn ? "Tap to clock in" : "Open on iPhone to sign in")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct HoursTrackerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursTrackerComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Hour Tracker")
        .description("Your shift timer, or this cheque's hours.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct HoursTrackerWatchWidgets: WidgetBundle {
    var body: some Widget {
        HoursTrackerComplication()
    }
}

extension WatchSnapshot {
    /// What the face gallery shows before the app has synced.
    static var preview: WatchSnapshot {
        var snapshot = WatchSnapshot.empty
        snapshot.signedIn = true
        snapshot.chequeHours = 59.5
        snapshot.monthHours = 140
        return snapshot
    }
}
