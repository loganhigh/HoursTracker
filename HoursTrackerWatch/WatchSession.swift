import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

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
    /// Shifts per month (keyed by the month's first day), kept so months
    /// already opened still show with the phone out of reach.
    @Published private(set) var monthShifts: [Date: [WatchRecentShift]]
    /// Months whose last fetch failed, so the screen stops spinning.
    @Published private(set) var failedMonths: Set<Date> = []

    private static let snapshotKey = "watch_snapshot_v2"
    private static let monthShiftsKey = "watch_month_shifts_v1"

    private override init() {
        let defaults = UserDefaults.standard
        snapshot = WatchCoding.decode(WatchSnapshot.self, from: defaults.data(forKey: Self.snapshotKey)) ?? .empty
        monthShifts = WatchCoding.decode([Date: [WatchRecentShift]].self, from: defaults.data(forKey: Self.monthShiftsKey)) ?? [:]
        super.init()
        // Builds before complications existed never saved the face's copy.
        if WatchComplicationStore.load() == nil { WatchComplicationStore.save(snapshot) }
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

    /// Fetches one month's shifts from the phone. Returns false when the
    /// phone can't be reached (the cached copy, if any, stays on screen).
    @discardableResult
    func loadMonth(_ monthStart: Date) -> Bool {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable,
              let data = WatchCoding.encode(WatchCommand.requestMonth(monthStart)) else { return false }
        failedMonths.remove(monthStart)
        session.sendMessage([WatchKeys.command: data], replyHandler: { [weak self] reply in
            let shifts = WatchCoding.decode([WatchRecentShift].self, from: reply[WatchKeys.monthShifts])
            Task { @MainActor in
                guard let self, let shifts else { return }
                self.monthShifts[monthStart] = shifts
                UserDefaults.standard.set(WatchCoding.encode(self.monthShifts), forKey: Self.monthShiftsKey)
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.failedMonths.insert(monthStart) }
        })
        return true
    }

    /// Asks the phone and waits for its answer: the result line and the
    /// decoded payload. Nil when the phone can't be reached.
    func request<T: Decodable>(_ command: WatchCommand, as type: T.Type) async -> (result: String, value: T?)? {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable,
              let data = WatchCoding.encode(command) else { return nil }
        return await withCheckedContinuation { continuation in
            session.sendMessage([WatchKeys.command: data], replyHandler: { reply in
                let result = reply[WatchKeys.result] as? String ?? ""
                continuation.resume(returning: (result, WatchCoding.decode(T.self, from: reply[WatchKeys.payload])))
            }, errorHandler: { _ in
                continuation.resume(returning: nil)
            })
        }
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
        let faceChanged = new.liveShift != snapshot.liveShift || new.chequeHours != snapshot.chequeHours
            || new.monthHours != snapshot.monthHours || new.signedIn != snapshot.signedIn
        snapshot = new
        UserDefaults.standard.set(WatchCoding.encode(new), forKey: Self.snapshotKey)
        WatchComplicationStore.save(new)
        // Complications have a refresh budget; only spend it when what they
        // show actually changed.
        if faceChanged { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Optimistic copy of what the phone will do, so the screen updates now.
    private func applyLocally(_ command: WatchCommand) {
        var s = snapshot
        switch command {
        case .requestSnapshot, .requestMonth, .requestBoard, .requestChat, .sendChat,
             .requestInbox, .requestThread, .sendDirect:
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
            s.add(hours, on: live.startDate)
            s.liveShift = nil
            WKInterfaceDevice.current().play(.stop)
        case .addShift(let draft):
            s.add(draft.paidHours, on: draft.day)
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

    /// Complication pushes from the phone (they can wake the app in the background).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let snapshot = WatchCoding.decode(WatchSnapshot.self, from: userInfo[WatchKeys.snapshot])
        Task { @MainActor in
            if let snapshot, snapshot.generatedAt >= self.snapshot.generatedAt { self.store(snapshot) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = WatchCoding.decode(WatchSnapshot.self, from: applicationContext[WatchKeys.snapshot])
        Task { @MainActor in if let context { self.store(context) } }
    }
}

private extension WatchSnapshot {
    /// Counts new hours toward this cheque and this month, like the phone will.
    mutating func add(_ hours: Double, on day: Date) {
        if day >= chequeStart, day < chequeEnd { chequeHours += hours }
        if Calendar.current.isDate(day, equalTo: Date(), toGranularity: .month) { monthHours += hours }
    }
}
