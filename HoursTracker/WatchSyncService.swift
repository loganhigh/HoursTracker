import Foundation
import Combine
import WatchConnectivity

// MARK: - Apple Watch bridge (phone side)
//
// The watch never touches Firestore. It sends a `WatchCommand`; this service
// applies it through the same paths the phone UI uses (`LiveShiftManager`
// for clock in/out and breaks, `HoursStore.add` for a logged shift — so XP,
// notifications and sync fire exactly as if it was entered on the phone),
// then answers with a fresh `WatchSnapshot`. The snapshot is also pushed as
// the application context whenever entries or the live shift change, so the
// watch is current the moment it wakes.

final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private var cancellables = Set<AnyCancellable>()
    private var pushWork: DispatchWorkItem?
    /// Draft ids already saved, so a command delivered twice (live message
    /// that timed out, then its queued copy) logs one shift, not two.
    private static let handledDraftsKey = "watch_handled_draft_ids_v1"

    private var store: HoursStore? { HoursStore.current }

    /// Called from app launch — including a background launch the watch
    /// triggers — so commands can be received before any UI exists.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        LiveShiftManager.shared.$activeShift
            .removeDuplicates()
            .sink { [weak self] _ in self?.schedulePush() }
            .store(in: &cancellables)
        store?.$entries
            .sink { [weak self] _ in self?.schedulePush() }
            .store(in: &cancellables)
        AuthService.shared.$user
            .map { $0?.uid }
            .removeDuplicates()
            .sink { [weak self] _ in self?.schedulePush() }
            .store(in: &cancellables)
    }

    // MARK: Snapshot

    func makeSnapshot(now: Date = Date()) -> WatchSnapshot {
        guard let store else { return .empty }
        let signedIn = AuthService.shared.user != nil
        let live = LiveShiftManager.shared.activeShift.map { shift in
            WatchLiveShift(
                startDate: shift.startDate,
                breaks: shift.breaks.map { WatchBreak(start: $0.start, end: $0.end) }
            )
        }

        let cal = Calendar.current
        var weekCal = cal
        // Same week as Home, the widget and Siri ("Week starts on", Monday when unset).
        weekCal.firstWeekday = store.paySettings.weekStartWeekday ?? 2
        let week = weekCal.dateInterval(of: .weekOfYear, for: now)
        var today = 0.0, weekTotal = 0.0
        for entry in store.entries {
            if cal.isDate(entry.date, inSameDayAs: now) { today += entry.paidHours }
            if let week, entry.date >= week.start, entry.date < week.end { weekTotal += entry.paidHours }
        }

        let recent = store.entries
            .filter { !$0.isOffDay }
            .sorted { $0.start > $1.start }
            .prefix(6)
            .map { entry in
                WatchRecentShift(
                    id: entry.id.uuidString, day: entry.date, start: entry.start, end: entry.end,
                    breakMinutes: entry.breakMinutes, hours: entry.paidHours,
                    locationName: entry.locationName
                )
            }

        let templates = store.shiftTemplatesByRecency.map {
            WatchTemplate(id: $0.id, name: $0.name, startMinutes: $0.startMinutes,
                          endMinutes: $0.endMinutes, breakMinutes: $0.breakMinutes,
                          locationName: $0.locationName)
        }
        let places = store.recentShiftPlaces(limit: 8).map(\.trimmedName).filter { !$0.isEmpty }

        return WatchSnapshot(
            signedIn: signedIn, liveShift: live, todayHours: today, weekHours: weekTotal,
            templates: templates, places: places, recentShifts: Array(recent), generatedAt: now
        )
    }

    /// Coalesces bursts (a sync batch rewrites many entries at once).
    private func schedulePush() {
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pushContext() }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func pushContext() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = WatchCoding.encode(makeSnapshot()) else { return }
        try? session.updateApplicationContext([WatchKeys.snapshot: data])
    }

    // MARK: Commands

    /// Applies one command and returns a short line the watch can show.
    func handle(_ command: WatchCommand) -> String {
        guard AuthService.shared.user != nil else { return "Sign in on your iPhone first." }
        let live = LiveShiftManager.shared
        switch command {
        case .requestSnapshot:
            return ""
        case .clockIn(let at):
            guard live.activeShift == nil else { return "Already clocked in." }
            live.clockIn(at: min(at, Date()))
            return "Clocked in"
        case .startBreak(let at):
            live.startBreak(at: min(at, Date()))
            return "Break started"
        case .endBreak(let at):
            live.endBreak(at: min(at, Date()))
            return "Back to work"
        case .clockOut(let at):
            guard let store else { return "Open Hour Tracker on your iPhone once." }
            guard live.activeShift != nil else { return "You're not clocked in." }
            guard let entry = live.clockOut(at: min(at, Date()), into: store) else {
                return "That shift is too short or over 24 hours — finish it on your iPhone."
            }
            return "Logged \(AppTheme.Format.hours(entry.paidHours))"
        case .addShift(let draft):
            return addShift(draft)
        }
    }

    private func addShift(_ draft: WatchShiftDraft) -> String {
        guard let store else { return "Open Hour Tracker on your iPhone once." }
        var handled = UserDefaults.standard.stringArray(forKey: Self.handledDraftsKey) ?? []
        guard !handled.contains(draft.id) else { return "Shift saved" }

        let cal = Calendar.current
        let day = cal.startOfDay(for: draft.day)
        guard day <= cal.startOfDay(for: Date()) else { return "Shifts can only be logged for today or earlier." }
        let start = time(draft.startMinutes, on: day)
        let end = time(draft.endMinutes, on: day)

        let base = WorkEntry(date: day, start: start, end: end, breakMinutes: max(0, draft.breakMinutes),
                             notes: "", isOffDay: false, offDayReason: "", isHoliday: false)
        guard base.paidHours > 0, base.paidHours <= 48 else { return "Those times don't add up to a shift." }

        // Reuse a past pin for the same place name, like the phone's picker.
        let name = draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = name.isEmpty ? ShiftPlace() : (store.recentShiftPlaces(limit: 12).first {
            $0.trimmedName.caseInsensitiveCompare(name) == .orderedSame
        } ?? ShiftPlace(name: name))

        // Honour the phone's "Split at midnight" choice for overnight shifts.
        let splits = UserDefaults.standard.bool(forKey: "split_overnight_at_midnight") && end <= start
        if splits, let portions = OvernightSplit.split(date: day, start: start, end: end, breakMinutes: base.breakMinutes) {
            for portion in [portions.first, portions.second] {
                var entry = WorkEntry(date: portion.date, start: portion.start, end: portion.end,
                                      breakMinutes: portion.breakMinutes, notes: "",
                                      isOffDay: false, offDayReason: "", isHoliday: false)
                place.apply(to: &entry)
                store.add(entry)
            }
        } else {
            var entry = base
            place.apply(to: &entry)
            store.add(entry)
        }
        if let templateID = draft.templateID { store.markShiftTemplateUsed(id: templateID) }

        handled.append(draft.id)
        UserDefaults.standard.set(Array(handled.suffix(50)), forKey: Self.handledDraftsKey)
        return "Logged \(AppTheme.Format.hours(base.paidHours))"
    }

    /// `minutes` after midnight on `day`, seconds zeroed — the wizard's convention.
    private func time(_ minutes: Int, on day: Date) -> Date {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        return Calendar.current.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day) ?? day
    }

    private func reply(for data: Any?) -> [String: Any] {
        var result = "Couldn't read that — update Hour Tracker on both devices."
        if let command = WatchCoding.decode(WatchCommand.self, from: data) {
            result = handle(command)
        }
        var reply: [String: Any] = [WatchKeys.result: result]
        if let snapshot = WatchCoding.encode(makeSnapshot()) { reply[WatchKeys.snapshot] = snapshot }
        return reply
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.schedulePush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: reactivate so the new one connects.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.schedulePush() }
    }

    /// Live path: the watch is waiting on the answer.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let data = message[WatchKeys.command] as? Data
        Task { @MainActor in replyHandler(self.reply(for: data)) }
    }

    /// Queued path: sent while the phone was out of reach, delivered later.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let data = userInfo[WatchKeys.command] as? Data
        Task { @MainActor in
            _ = self.reply(for: data)
            self.schedulePush()
        }
    }
}
