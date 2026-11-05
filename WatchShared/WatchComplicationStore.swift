import Foundation

// MARK: - Watch face complications' copy of the snapshot
//
// The watch app saves every snapshot it receives here (the shared app group)
// so the complication extension can draw the watch face without asking the
// phone itself.

enum WatchComplicationStore {
    static let appGroup = "group.com.loganh.HourTracker"
    private static let key = "watch_complication_snapshot_v1"

    static func save(_ snapshot: WatchSnapshot) {
        UserDefaults(suiteName: appGroup)?.set(WatchCoding.encode(snapshot), forKey: key)
    }

    static func load() -> WatchSnapshot? {
        WatchCoding.decode(WatchSnapshot.self, from: UserDefaults(suiteName: appGroup)?.data(forKey: key))
    }
}
