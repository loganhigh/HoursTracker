import SwiftUI
import WidgetKit

// MARK: - Deep link

enum WidgetLinks {
    /// Opens the app straight into Add Shift for today. The app registers a
    /// single URL scheme (shared with Google Sign-In and crew invites) and
    /// routes by host — see `WidgetDeepLink.handleIncomingURL` in the app.
    static let logToday = URL(
        string: "com.googleusercontent.apps.883698344524-mqmpr0spvoqu758103dg63297a4u8gqq://log-today"
    )!
}

// MARK: - Day state

/// What the widget should show for `date`, derived from the last snapshot the
/// app wrote. Timelines carry an entry at the next midnight, so a snapshot
/// from yesterday must read as "today not logged" (and, across a week
/// boundary, as a fresh week) without the app having to run.
struct WidgetDayState {
    let weekHours: Double
    let weeklyTarget: Double?
    let todayHours: Double
    let todayLogged: Bool
    let todayIsOffDay: Bool

    init(data: WidgetData, at date: Date, calendar: Calendar = .current) {
        let sameDay = data.dataDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        todayLogged = sameDay && data.todayLogged
        todayHours = sameDay ? data.todayHours : 0
        todayIsOffDay = sameDay && data.todayIsOffDay
        if let weekEnd = data.weekEnd, date >= weekEnd {
            weekHours = 0
        } else {
            weekHours = data.hoursThisWeek
        }
        weeklyTarget = data.weeklyTarget.flatMap { $0 > 0 ? $0 : nil }
    }

    /// 0...1 progress toward the weekly target, nil without a target.
    var weekProgress: Double? {
        guard let target = weeklyTarget else { return nil }
        return min(1, max(0, weekHours / target))
    }

    /// "8h today", "Day off" — the logged-state caption.
    var loggedCaption: String {
        todayIsOffDay && todayHours == 0 ? "Day off" : "\(WidgetFormatting.hours(todayHours)) today"
    }
}

extension SimpleEntry {
    var dayState: WidgetDayState { WidgetDayState(data: widgetData, at: date) }
}

// MARK: - Tap target

extension View {
    /// Not logged yet: the whole widget becomes the "Log today" button.
    /// Logged: no URL, so a tap just opens the app.
    @ViewBuilder
    func logTodayURL(_ state: WidgetDayState) -> some View {
        if state.todayLogged {
            self
        } else {
            widgetURL(WidgetLinks.logToday)
        }
    }
}

// MARK: - Home Screen pill

/// Today's status on the prestige gradient: a solid white "Log today" call to
/// action, or a quiet check with today's hours once logged.
struct TodayStatusPill: View {
    let state: WidgetDayState
    var fontSize: CGFloat = 11

    var body: some View {
        if state.todayLogged {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: fontSize + 1, weight: .bold))
                Text(state.loggedCaption)
                    .font(.system(size: fontSize, weight: .semibold))
                    .widgetFittingText(minScale: 0.7)
            }
            .foregroundStyle(.white.opacity(0.9))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: fontSize + 1, weight: .bold))
                Text("Log today")
                    .font(.system(size: fontSize, weight: .bold))
                    .widgetFittingText(minScale: 0.7)
            }
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white))
        }
    }
}
