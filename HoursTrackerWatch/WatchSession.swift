import Foundation
import WatchConnectivity
import WatchKit

// MARK: - Watch side of the phone bridge
//
// Holds the last snapshot the phone sent (persisted, so the watch opens
// showing real numbers even with the phone out of reach) and sends
// commands. Every command is applied to the local snapshot right away so
// the buttons feel instant; the phone's reply then replaces it with the
// real state. With the phone unreachable the command is queued with
// `transferUserInfo`, which the system delivers once they reconnect — and
// because each command carries the time it was pressed, a late delivery
// still logs the right clock-in or clock-out.

@MainActor
final class WatchSession: NSObject, ObservableObject {
    static let shared = WatchSession()

    @Published private(set) var snapshot: WatchSnapshot
    @Published private(set) var isReachable = false
    /// Short confirmation shown at the top of the screen.
    @Published var banner: String?

    private static let snapshotKey = "watch_snapshot_v1"

    private override init() {
        snapshot = WatchCoding.decode(WatchSnapshot.self, from: UserDefaults.standard.data(forKey: Self.snapshotKey)) ?? .empty
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks for fresh numbers (on launch and when the app comes forward).
    func refresh() {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable,
              let data = WatchCoding.encode(WatchCommand.requestSnapshot) else { return }
        WCSession.default.sendMessage([WatchKeys.command: data], replyHandler: { [weak self] reply in
            let snapshot = WatchCoding.decode(WatchSnapshot.self, from: reply[WatchKeys.snapshot])
            Task { @MainActor in if let snapshot { self?.store(snapshot) } }
        }, errorHandler: nil)
    }

    func send(_ command: WatchCommand) {
        applyLocally(command)
        guard let data = WatchCoding.encode(command) else { return }
        let payload: [String: Any] = [WatchKeys.command: data]
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                let snapshot = WatchCoding.decode(WatchSnapshot.self, from: reply[WatchKeys.snapshot])
                let result = reply[WatchKeys.result] as? String
                Task { @MainActor in
                    if let snapshot { self?.store(snapshot) }
                    if let result, !result.isEmpty { self?.show(result) }
                }
            }, errorHandler: { [weak self] _ in
                // Lost the phone mid-send: queue it instead. The phone drops
                // a repeat shift by its draft id if both copies arrive.
                session.transferUserInfo(payload)
                Task { @MainActor in self?.show("Saved — syncs when your iPhone is near") }
            })
        } else {
            session.transferUserInfo(payload)
            show("Saved — syncs when your iPhone is near")
        }
    }

    private func show(_ text: String) {
        banner = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if banner == text { banner = nil }
        }
    }

    private func store(_ new: WatchSnapshot) {
        snapshot = new
        UserDefaults.standard.set(WatchCoding.encode(new), forKey: Self.snapshotKey)
    }

    /// Optimistic copy of what the phone will do, so the screen updates now.
    private func applyLocally(_ command: WatchCommand) {
        var s = snapshot
        switch command {
        case .requestSnapshot:
            return
        case .clockIn(let at):
            guard s.liveShift == nil else { return }
            s.liveShift = WatchLiveShift(startDate: at, breaks: [])
            WKInterfaceDevice.current().play(.start)
        case .startBreak(let at):
            guard var live = s.liveShift, !live.isOnBreak else { return }
            live.breaks.append(WatchBreak(start: at, end: nil))
            s.liveShift = live
            WKInterfaceDevice.current().play(.click)
        case .endBreak(let at):
            guard var live = s.liveShift, live.isOnBreak, let last = live.breaks.indices.last else { return }
            live.breaks[last].end = at
            s.liveShift = live
            WKInterfaceDevice.current().play(.click)
        case .clockOut(let at):
            guard let live = s.liveShift else { return }
            let hours = live.workedSeconds(at: at) / 3600
            s.todayHours += hours
            s.weekHours += hours
            s.liveShift = nil
            WKInterfaceDevice.current().play(.stop)
        case .addShift(let draft):
            if Calendar.current.isDateInToday(draft.day) { s.todayHours += draft.paidHours }
            s.weekHours += draft.paidHours
            WKInterfaceDevice.current().play(.success)
        }
        store(s)
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = WatchCoding.decode(WatchSnapshot.self, from: session.receivedApplicationContext[WatchKeys.snapshot])
        let reachable = session.isReachable
        Task { @MainActor in
            if let context, context.generatedAt > self.snapshot.generatedAt { self.store(context) }
            self.isReachable = reachable
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable { self.refresh() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = WatchCoding.decode(WatchSnapshot.self, from: applicationContext[WatchKeys.snapshot])
        Task { @MainActor in if let context { self.store(context) } }
    }
}
