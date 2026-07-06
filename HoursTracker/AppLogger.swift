import Foundation
import os.log

/// Centralized logging for freeze diagnosis and lifecycle tracking.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "HoursTracker"

    static let lifecycle = Logger(subsystem: subsystem, category: "app.lifecycle")
    static let db = Logger(subsystem: subsystem, category: "db")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
