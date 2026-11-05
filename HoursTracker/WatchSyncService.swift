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
    private var lastFace: FaceState?
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
        // Same pay period and job(s) as Home's cheque card.
        let cycle = store.currentPayCycle()
        let chequeIDs = Set(PayCycleEngine.entries(store.scopedEntries, in: cycle).map(\.id))
        let thisMonth = cal.dateInterval(of: .month, for: now)
        var cheque = 0.0, month = 0.0
        var byMonth: [Date: (hours: Double, shifts: Int)] = [:]
        for entry in store.entries where !entry.isOffDay {
            if chequeIDs.contains(entry.id) { cheque += entry.paidHours }
            if let thisMonth, thisMonth.contains(entry.date) { month += entry.paidHours }
            if let key = cal.dateInterval(of: .month, for: entry.date)?.start {
                byMonth[key, default: (0, 0)].hours += entry.paidHours
                byMonth[key, default: (0, 0)].shifts += 1
            }
        }
        let months = byMonth
            .map { WatchMonth(id: $0.key, hours: $0.value.hours, shiftCount: $0.value.shifts) }
            .sorted { $0.id > $1.id }

        let recent = store.entries
            .filter { !$0.isOffDay }
            .sorted { $0.start > $1.start }
            .prefix(6)
            .map(watchShift)

        let templates = store.shiftTemplatesByRecency.map {
            WatchTemplate(id: $0.id, name: $0.name, startMinutes: $0.startMinutes,
                          endMinutes: $0.endMinutes, breakMinutes: $0.breakMinutes,
                          locationName: $0.locationName)
        }
        let places = store.recentShiftPlaces(limit: 8).map(\.trimmedName).filter { !$0.isEmpty }

        return WatchSnapshot(
            signedIn: signedIn, liveShift: live, chequeHours: cheque, monthHours: month,
            chequeStart: cycle.start, chequeEnd: cycle.end,
            templates: templates, places: places, recentShifts: Array(recent),
            months: months, generatedAt: now
        )
    }

    /// Every worked shift in the month that starts on `monthStart`, newest first.
    func shifts(inMonthStarting monthStart: Date) -> [WatchRecentShift] {
        guard let store, let month = Calendar.current.dateInterval(of: .month, for: monthStart) else { return [] }
        return store.entries
            .filter { !$0.isOffDay && month.contains($0.date) }
            .sorted { $0.start > $1.start }
            .map(watchShift)
    }

    private func watchShift(_ entry: WorkEntry) -> WatchRecentShift {
        WatchRecentShift(
            id: entry.id.uuidString, day: entry.date, start: entry.start, end: entry.end,
            breakMinutes: entry.breakMinutes, hours: entry.paidHours,
            locationName: entry.locationName
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
              session.isPaired, session.isWatchAppInstalled else { return }
        let snapshot = makeSnapshot()
        guard let data = WatchCoding.encode(snapshot) else { return }
        try? session.updateApplicationContext([WatchKeys.snapshot: data])

        // With Hour Tracker on the watch face, this wakes the watch app in the
        // background so the complication updates without opening it. Apple
        // budgets these (about 50 a day), so only send when the face changes.
        let face = FaceState(snapshot)
        if session.isComplicationEnabled, face != lastFace, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchKeys.snapshot: data])
            lastFace = face
        }
    }

    /// What the watch face shows; a new value is worth a complication push.
    private struct FaceState: Equatable {
        let live: WatchLiveShift?
        let cheque: Double
        let month: Double
        init(_ s: WatchSnapshot) {
            live = s.liveShift
            cheque = (s.chequeHours * 10).rounded() / 10
            month = (s.monthHours * 10).rounded() / 10
        }
    }

    // MARK: Commands

    /// Applies one command and returns a short line the watch can show.
    func handle(_ command: WatchCommand) -> String {
        guard AuthService.shared.user != nil else { return "Sign in on your iPhone first." }
        let live = LiveShiftManager.shared
        switch command {
        case .requestSnapshot, .requestMonth, .requestBoard, .requestChat, .sendChat,
             .requestInbox, .requestThread, .sendDirect:
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

        var base = WorkEntry(date: day, start: start, end: end, breakMinutes: max(0, draft.breakMinutes),
                             notes: "", isOffDay: false, offDayReason: "", isHoliday: false)
        // The job Home's cheque is showing, like a clock-in.
        base.jobID = store.defaultJobID
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
                entry.jobID = store.defaultJobID
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
        var reply: [String: Any] = [:]
        if let command = WatchCoding.decode(WatchCommand.self, from: data) {
            result = handle(command)
            if case .requestMonth(let monthStart) = command,
               let shifts = WatchCoding.encode(shifts(inMonthStarting: monthStart)) {
                reply[WatchKeys.monthShifts] = shifts
            }
        }
        reply[WatchKeys.result] = result
        if let snapshot = WatchCoding.encode(makeSnapshot()) { reply[WatchKeys.snapshot] = snapshot }
        return reply
    }
}

// MARK: - Leaderboard, Board Chat and messages

extension WatchSyncService {
    /// Answers the board / chat / messages commands, or nil for any other
    /// command. Sends go through ChatService, so the server's filter, rate
    /// limit and blocks apply exactly as on the phone.
    func socialReply(for command: WatchCommand) async -> [String: Any]? {
        guard AuthService.shared.user != nil else {
            switch command {
            case .requestBoard, .requestChat, .sendChat, .requestInbox, .requestThread, .sendDirect:
                return [WatchKeys.result: "Sign in on your iPhone first."]
            default:
                return nil
            }
        }
        let chat = ChatService.shared
        var result = ""
        let payload: Data?
        switch command {
        case .requestBoard:
            payload = WatchCoding.encode(await makeBoard())
        case .requestChat:
            await chat.refreshBlocked()
            payload = WatchCoding.encode(await makeChat())
        case .sendChat(let text):
            do {
                try await chat.sendGlobal(text)
                result = "Sent"
            } catch {
                result = error.localizedDescription
            }
            payload = WatchCoding.encode(await makeChat())
        case .requestInbox:
            await chat.refreshBlocked()
            payload = WatchCoding.encode(await makeInbox())
        case .requestThread(let otherUid):
            payload = WatchCoding.encode(await makeThread(with: otherUid))
        case .sendDirect(let otherUid, let otherUsername, let text):
            do {
                try await chat.sendDirect(text, toUid: otherUid, toUsername: otherUsername)
                result = "Sent"
            } catch {
                result = error.localizedDescription
            }
            payload = WatchCoding.encode(await makeThread(with: otherUid))
        default:
            return nil
        }
        var reply: [String: Any] = [WatchKeys.result: result]
        if let payload { reply[WatchKeys.payload] = payload }
        return reply
    }

    private func makeBoard() async -> WatchBoard {
        let board = TopTrackersService.shared
        board.startListening()
        // A cold launch (the watch woke the phone) needs a moment for the
        // board doc to arrive.
        for _ in 0..<20 where !board.hasLoaded {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        let myUid = AuthService.shared.user?.uid
        let rows = board.allTrackers.map { tracker in
            WatchBoardRow(uid: tracker.uid, rank: tracker.rank, username: Username.normalize(tracker.name),
                          hours: tracker.hours, hoursHidden: tracker.hoursHidden,
                          prestige: tracker.prestige, isMe: tracker.uid == myUid)
        }
        let top = Array(rows.prefix(10))
        var around: [WatchBoardRow] = []
        if let index = rows.firstIndex(where: \.isMe), index >= 10 {
            around = Array(rows[max(10, index - 2)...min(rows.count - 1, index + 2)])
        }
        let me = rows.first(where: \.isMe)
        return WatchBoard(myRank: me?.rank, myHours: me?.hours ?? 0, totalRanked: rows.count,
                          top: top, aroundMe: around)
    }

    private func makeChat() async -> WatchChat {
        let chat = ChatService.shared
        let myUid = AuthService.shared.user?.uid
        let lines = await chat.fetchRecentGlobal(limit: 25).map { message in
            WatchChatLine(id: message.id, uid: message.uid, username: message.username, text: message.text,
                          createdAt: message.createdAt, isMine: message.uid == myUid,
                          mentionsMe: myUid.map { message.mentions.contains($0) } ?? false)
        }
        let unread = await chat.fetchThreads().reduce(0) { $0 + $1.unread }
        return WatchChat(lines: lines, myUsername: FriendsService.shared.myUsername, unreadMessages: unread)
    }

    private func makeInbox() async -> [WatchThreadSummary] {
        await ChatService.shared.fetchThreads().prefix(20).map {
            WatchThreadSummary(id: $0.id, otherUid: $0.otherUid, otherUsername: $0.otherUsername,
                               lastText: $0.lastText, lastAt: $0.lastAt, unread: $0.unread)
        }
    }

    private func makeThread(with otherUid: String) async -> WatchThreadMessages? {
        let chat = ChatService.shared
        guard let threadId = chat.threadId(with: otherUid) else { return nil }
        let myUid = AuthService.shared.user?.uid
        let lines = await chat.fetchThreadMessages(threadId, limit: 30).map {
            WatchChatLine(id: $0.id, uid: $0.uid, username: "", text: $0.text, createdAt: $0.createdAt,
                          isMine: $0.uid == myUid, mentionsMe: false)
        }
        await chat.markReadNow(threadId)
        return WatchThreadMessages(threadId: threadId, lines: lines)
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
        Task { @MainActor in
            if let command = WatchCoding.decode(WatchCommand.self, from: data),
               let social = await self.socialReply(for: command) {
                replyHandler(social)
            } else {
                replyHandler(self.reply(for: data))
            }
        }
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
