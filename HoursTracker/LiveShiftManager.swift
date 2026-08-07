import Foundation
import Combine
import ActivityKit

// MARK: - Live shift model

/// One break taken during a live shift. `end == nil` means the break is
/// still in progress.
struct BreakInterval: Codable, Equatable {
    var start: Date
    var end: Date?
}

/// A clock-in/out shift that is currently in progress. Pure client-side
/// state — it only becomes a `WorkEntry` (and therefore reaches storage/
/// sync) when the user clocks out and `LiveShiftManager` materializes it
/// through the same path the entry editor uses.
struct LiveShift: Codable, Equatable {
    var startDate: Date
    var breaks: [BreakInterval] = []

    /// True while a break has been started but not ended.
    var isOnBreak: Bool {
        breaks.last?.end == nil && !breaks.isEmpty
    }

    /// Total break time in seconds as of `now`. An in-flight break counts
    /// up to `now`.
    func breakSeconds(at now: Date) -> TimeInterval {
        breaks.reduce(0) { total, brk in
            let end = brk.end ?? now
            return total + max(0, end.timeIntervalSince(brk.start))
        }
    }

    /// Seconds actually worked as of `now` (wall time minus breaks,
    /// including any in-flight break). Never negative.
    func elapsedWorked(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(startDate) - breakSeconds(at: now))
    }

    /// Accumulated break time rounded to whole minutes, as of `now`.
    func totalBreakMinutes(at now: Date = Date()) -> Int {
        max(0, Int((breakSeconds(at: now) / 60).rounded()))
    }

    /// True when the shift has been running for over 16 hours — the UI
    /// uses this to warn about a probable forgotten clock-out. The shift
    /// is never auto-discarded; that stays the user's call.
    func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(startDate) > 16 * 3600
    }

    var isStale: Bool { isStale(at: Date()) }
}

// MARK: - Manager

/// Engine for the live clock-in/out flow. Owns the single active `LiveShift`,
/// persists it to UserDefaults across app kills, and materializes a completed
/// shift into a `WorkEntry` via `HoursStore.add` — the exact same entry shape
/// and save path the entry editor uses. No timers live here: elapsed time is
/// computed on demand (the UI drives updates with `TimelineView`).
final class LiveShiftManager: ObservableObject {
    static let shared = LiveShiftManager()

    @Published private(set) var activeShift: LiveShift?

    private let defaults: UserDefaults
    private let storageKey: String

    /// Longest shift the engine will materialize. Anything above this is
    /// almost certainly a forgotten clock-out; refusing keeps garbage
    /// entries out of stats/sync while leaving the shift active for the
    /// user to resolve.
    private static let maxShiftSeconds: TimeInterval = 24 * 3600

    init(defaults: UserDefaults = .standard, storageKey: String = "live_shift_v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        restore()
    }

    /// The project compiles with MainActor default isolation, which gives
    /// classes an *isolated* deinit. The isolated-deinit back-deploy shim
    /// (deployment target < iOS 18.4) aborts when short-lived instances
    /// deallocate (seen in unit tests). Nothing isolated is touched during
    /// teardown, so opt the deinit out of the executor hop.
    nonisolated deinit {}

    // MARK: Clock in / out

    /// Starts a shift. Ignored when one is already active.
    func clockIn(at date: Date = Date()) {
        guard activeShift == nil else { return }
        activeShift = LiveShift(startDate: date, breaks: [])
        persist()
        syncActivity()
    }

    /// Ends the shift and saves it as a `WorkEntry` through `store.add`
    /// (the editor's save path — gamification, notifications and sync all
    /// fire exactly as if the entry had been logged by hand).
    ///
    /// Returns the saved entry, or `nil` (leaving the shift active) when
    /// the worked time is not positive or exceeds 24 hours.
    @discardableResult
    func clockOut(at date: Date = Date(), into store: HoursStore) -> WorkEntry? {
        guard let entry = materializedEntry(at: date) else { return nil }
        store.add(entry)
        activeShift = nil
        persist()
        syncActivity()
        return entry
    }

    /// Abandons the active shift without saving anything.
    func discard() {
        guard activeShift != nil else { return }
        activeShift = nil
        persist()
        syncActivity()
    }

    // MARK: Breaks

    /// Starts a break. Ignored when no shift is active, a break is already
    /// running, or the time is before clock-in.
    func startBreak(at date: Date = Date()) {
        guard var shift = activeShift, !shift.isOnBreak, date >= shift.startDate else { return }
        shift.breaks.append(BreakInterval(start: date, end: nil))
        activeShift = shift
        persist()
        syncActivity()
    }

    /// Ends the current break. Ignored when no break is running.
    func endBreak(at date: Date = Date()) {
        guard var shift = activeShift, shift.isOnBreak, let last = shift.breaks.indices.last else { return }
        shift.breaks[last].end = max(date, shift.breaks[last].start)
        activeShift = shift
        persist()
        syncActivity()
    }

    // MARK: Materialization

    /// Builds the `WorkEntry` this shift would save at `date`, mirroring
    /// `EntryEditorView.save()` field-for-field:
    /// - `date` is the clock-in day (`startOfDay`), so an overnight shift
    ///   stays one entry on the day it started.
    /// - `start`/`end` carry the clock-in day's date component with
    ///   seconds zeroed (the editor's `merge(day:with:)` convention);
    ///   overnight shifts get `end < start`, which `WorkEntry.paidHours`
    ///   resolves with its +24h wrap — same as editor-logged entries.
    /// - `breakMinutes` is the accumulated break time rounded to whole
    ///   minutes; an in-flight break is auto-ended at clock-out.
    ///
    /// Returns `nil` when worked time is ≤ 0 or > 24h, or when minute
    /// rounding collapses the shift to zero paid hours.
    func materializedEntry(at date: Date = Date()) -> WorkEntry? {
        guard let shift = activeShift else { return nil }

        let worked = shift.elapsedWorked(at: date)
        guard worked > 0, worked <= Self.maxShiftSeconds else { return nil }

        let cal = Calendar.current
        let day = cal.startOfDay(for: shift.startDate)
        let start = merge(day: day, with: shift.startDate, calendar: cal)
        let end = merge(day: day, with: date, calendar: cal)

        let entry = WorkEntry(
            date: day,
            start: start,
            end: end,
            breakMinutes: shift.totalBreakMinutes(at: date),
            notes: "",
            isOffDay: false,
            offDayReason: "",
            isHoliday: false
        )

        // Mirror the editor's validation: a shift that rounds down to zero
        // paid hours is not worth saving.
        guard entry.paidHours > 0 else { return nil }
        return entry
    }

    /// Same day/time merge the entry editor uses: the day's date component
    /// with the time's hour/minute, seconds zeroed.
    private func merge(day: Date, with time: Date, calendar cal: Calendar) -> Date {
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        let timeComps = cal.dateComponents([.hour, .minute], from: time)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = 0
        return cal.date(from: comps) ?? day
    }

    // MARK: Persistence

    private func persist() {
        guard let shift = activeShift else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(shift) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let shift = try? dec.decode(LiveShift.self, from: data) else {
            // Unreadable payload — drop it rather than crash-looping on it.
            defaults.removeObject(forKey: storageKey)
            return
        }
        // Deliberately kept even when start is >24h ago: the user forgot to
        // clock out and the UI surfaces it (isStale) instead of silently
        // destroying their shift.
        activeShift = shift
        syncActivity()
    }

    // MARK: - Live Activity (Dynamic Island / Lock Screen)

    /// Starts, updates, or ends this shift's Live Activity to match
    /// `activeShift`. Best-effort: Live Activities can be disabled in
    /// system Settings, and a live shift never depends on the Activity
    /// existing, so failures here are silent.
    private func syncActivity() {
        guard let shift = activeShift else {
            endActivity()
            return
        }
        let completedBreakSeconds = shift.breaks
            .compactMap { brk -> Int? in
                guard let end = brk.end else { return nil }
                return Int(max(0, end.timeIntervalSince(brk.start)))
            }
            .reduce(0, +)
        let state = LiveShiftActivityAttributes.ContentState(
            startDate: shift.startDate,
            completedBreakSeconds: completedBreakSeconds,
            isOnBreak: shift.isOnBreak,
            breakStartDate: shift.isOnBreak ? shift.breaks.last?.start : nil
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = Activity<LiveShiftActivityAttributes>.activities.first {
            Task { await activity.update(content) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: LiveShiftActivityAttributes(), content: content)
        }
    }

    private func endActivity() {
        for activity in Activity<LiveShiftActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
