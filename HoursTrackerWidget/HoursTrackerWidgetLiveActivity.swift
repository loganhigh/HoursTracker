import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Shift Live Activity
//
// Lock Screen card + Dynamic Island for a running clocked-in shift. The
// elapsed-time text never gets a per-second push from the app — the
// worked-time start date is shifted forward by `completedBreakSeconds`, and
// SwiftUI's `Text(timerInterval:)` ticks natively off that adjusted range.
// Money can't tick natively, so the app refreshes `earned` once a minute
// while it's running and on every break / clock-out.

struct HoursTrackerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveShiftActivityAttributes.self) { context in
            LiveShiftLockScreenView(state: context.state)
                .activityBackgroundTint(LiveShiftStyle.night)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        LiveShiftStatusLabel(state: context.state, compact: true)
                        Text("Since \(LiveShiftStyle.time(context.state.startDate))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveShiftTimer(state: context.state)
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let earned = context.state.earned {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LiveShiftStyle.money(earned, code: context.state.currencyCode))
                                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(LiveShiftStyle.money)
                            Text("earned so far")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            if let rate = context.state.currentRate {
                                Text("\(LiveShiftStyle.money(rate, code: context.state.currencyCode))/hr")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isOnBreak ? "pause.circle.fill" : "clock.fill")
                    .foregroundStyle(context.state.isOnBreak ? LiveShiftStyle.pause : LiveShiftStyle.accent)
            } compactTrailing: {
                LiveShiftTimer(state: context.state)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: context.state.isOnBreak ? "pause.circle.fill" : "clock.fill")
                    .foregroundStyle(context.state.isOnBreak ? LiveShiftStyle.pause : LiveShiftStyle.accent)
            }
            .keylineTint(LiveShiftStyle.accent)
        }
    }
}

// MARK: - Lock Screen card

private struct LiveShiftLockScreenView: View {
    let state: LiveShiftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LiveShiftStatusLabel(state: state, compact: false)
                Spacer()
                Text("HOUR TRACKER")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    LiveShiftTimer(state: state)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(state.isOnBreak ? "on break" : "worked · since \(LiveShiftStyle.time(state.startDate))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                if let earned = state.earned {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(LiveShiftStyle.money(earned, code: state.currencyCode))
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(LiveShiftStyle.money)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(rateCaption)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [LiveShiftStyle.night, LiveShiftStyle.accent.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var rateCaption: String {
        guard let rate = state.currentRate else { return "earned so far" }
        return "earned · \(LiveShiftStyle.money(rate, code: state.currencyCode))/hr"
    }
}

// MARK: - Pieces

/// "Clocked in" / "On break" with a status dot.
private struct LiveShiftStatusLabel: View {
    let state: LiveShiftActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isOnBreak ? LiveShiftStyle.pause : LiveShiftStyle.live)
                .frame(width: 8, height: 8)
                .shadow(color: (state.isOnBreak ? LiveShiftStyle.pause : LiveShiftStyle.live).opacity(0.8), radius: 4)
            Text(state.isOnBreak ? "On break" : "Clocked in")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Native ticking timer. While on break it ticks the break duration
/// instead of worked time (which is frozen).
private struct LiveShiftTimer: View {
    let state: LiveShiftActivityAttributes.ContentState

    var body: some View {
        if state.isOnBreak, let breakStart = state.breakStartDate {
            Text(timerInterval: breakStart...Date.distantFuture, countsDown: false)
        } else {
            let workStart = state.startDate.addingTimeInterval(TimeInterval(state.completedBreakSeconds))
            Text(timerInterval: workStart...Date.distantFuture, countsDown: false)
        }
    }
}

private enum LiveShiftStyle {
    static let night = Color(red: 0.07, green: 0.06, blue: 0.13)
    static let accent = WidgetPrestigeTheme.gradientColors(for: 0).first ?? .indigo
    static let money = Color(red: 0.36, green: 0.89, blue: 0.62)
    static let live = Color(red: 0.36, green: 0.89, blue: 0.62)
    static let pause = Color(red: 1.0, green: 0.72, blue: 0.30)

    static func money(_ amount: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
