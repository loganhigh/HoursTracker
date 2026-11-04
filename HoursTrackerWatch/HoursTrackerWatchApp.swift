import SwiftUI

@main
struct HoursTrackerWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = WatchSession.shared

    init() {
        WatchSession.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(session)
                .tint(WatchStyle.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refresh() }
        }
    }
}

/// The phone app's palette, trimmed to what the watch uses.
enum WatchStyle {
    static let accent = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
    static let clockIn = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let breakTint = Color(red: 0.98, green: 0.74, blue: 0.24)
    static let clockOut = Color(red: 0.94, green: 0.33, blue: 0.33)

    static func hours(_ value: Double) -> String {
        // "8h", "8.5h", "8.25h" — no trailing zeros.
        var text = String(format: "%.2f", max(0, value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "h"
    }

    /// "6:30 AM" for minutes after midnight.
    static func time(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
