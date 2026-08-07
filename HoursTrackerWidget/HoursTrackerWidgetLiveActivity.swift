import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Shift Live Activity (Hour Tracker Pro)
//
// Lock Screen banner + Dynamic Island for a running clocked-in shift. The
// elapsed-time text never gets a per-second push from the app — instead the
// worked-time start date is shifted forward by `completedBreakSeconds`, and
// SwiftUI's `Text(timerInterval:)` ticks natively off that adjusted range.
// The app only calls `Activity.update` on real state changes (break
// start/end, clock out), not on a timer.

struct HoursTrackerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveShiftActivityAttributes.self) { context in
            LiveShiftLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.isOnBreak ? "On Break" : "Clocked In")
                            .font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: context.state.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                    }
                    .foregroundStyle(accentColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedText(context.state, font: .title3.monospacedDigit().bold())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isOnBreak ? "Worked time is paused" : "Worked time is running")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } compactLeading: {
                Image(systemName: context.state.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundStyle(accentColor)
            } compactTrailing: {
                elapsedText(context.state, font: .caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.state.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundStyle(accentColor)
            }
            .keylineTint(accentColor)
        }
    }

    private var accentColor: Color {
        WidgetPrestigeTheme.gradientColors(for: 0).first ?? .indigo
    }

    /// Native ticking timer text. While on break it ticks the break
    /// duration instead of worked time (which is frozen).
    @ViewBuilder
    private func elapsedText(_ state: LiveShiftActivityAttributes.ContentState, font: Font) -> some View {
        if state.isOnBreak, let breakStart = state.breakStartDate {
            Text(timerInterval: breakStart...Date.distantFuture, countsDown: false)
                .font(font)
        } else {
            let workStart = state.startDate.addingTimeInterval(TimeInterval(state.completedBreakSeconds))
            Text(timerInterval: workStart...Date.distantFuture, countsDown: false)
                .font(font)
        }
    }
}

private struct LiveShiftLockScreenView: View {
    let state: LiveShiftActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                .font(.title2)
                .foregroundStyle(WidgetPrestigeTheme.gradientColors(for: 0).first ?? .indigo)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.isOnBreak ? "On Break" : "Clocked In")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Hour Tracker")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            elapsedText
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(16)
    }

    @ViewBuilder
    private var elapsedText: some View {
        if state.isOnBreak, let breakStart = state.breakStartDate {
            Text(timerInterval: breakStart...Date.distantFuture, countsDown: false)
        } else {
            let workStart = state.startDate.addingTimeInterval(TimeInterval(state.completedBreakSeconds))
            Text(timerInterval: workStart...Date.distantFuture, countsDown: false)
        }
    }
}
