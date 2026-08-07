import XCTest
@testable import HoursTracker

/// Unit tests for the live clock-in/out engine. All dates are injected so
/// the tests are fully deterministic.
final class LiveShiftManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LiveShiftManagerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager() -> LiveShiftManager {
        LiveShiftManager(defaults: defaults, storageKey: "live_shift_v1")
    }

    /// `HoursStore` (like every class in this MainActor-default project) has
    /// an isolated deinit, and the isolated-deinit back-deploy shim aborts
    /// when instances deallocate mid-test-run. Keep test stores alive for
    /// the process lifetime instead.
    private static var retainedStores: [HoursStore] = []

    private func makeStore() -> HoursStore {
        let store = HoursStore()
        Self.retainedStores.append(store)
        return store
    }

    /// A fixed reference day (2026-03-10) at the given time.
    private func date(hour: Int, minute: Int = 0, second: Int = 0, dayOffset: Int = 0) -> Date {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 10 + dayOffset
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return cal.date(from: comps)!
    }

    // MARK: - Clock in / out round trip

    func testClockInOutRoundTripProducesWorkEntry() {
        let manager = makeManager()
        let store = makeStore()
        let countBefore = store.entries.count

        manager.clockIn(at: date(hour: 8))
        manager.startBreak(at: date(hour: 12))
        manager.endBreak(at: date(hour: 12, minute: 30))

        let entry = manager.clockOut(at: date(hour: 16, minute: 30), into: store)

        XCTAssertNotNil(entry)
        guard let entry else { return }

        let cal = Calendar.current
        XCTAssertEqual(entry.date, cal.startOfDay(for: date(hour: 8)))
        XCTAssertEqual(entry.start, date(hour: 8))
        XCTAssertEqual(entry.end, date(hour: 16, minute: 30))
        XCTAssertEqual(entry.breakMinutes, 30)
        XCTAssertEqual(entry.paidHours, 8.0, accuracy: 1e-6)
        XCTAssertFalse(entry.isOffDay)
        XCTAssertFalse(entry.isHoliday)
        XCTAssertEqual(entry.notes, "")

        // Saved through the store's normal add path, and the shift cleared.
        XCTAssertEqual(store.entries.count, countBefore + 1)
        XCTAssertTrue(store.entries.contains(where: { $0.id == entry.id }))
        XCTAssertNil(manager.activeShift)
        XCTAssertNil(defaults.data(forKey: "live_shift_v1"))
    }

    // MARK: - Break accounting

    func testInFlightBreakIsAutoEndedAtClockOut() {
        let manager = makeManager()
        manager.clockIn(at: date(hour: 8))
        manager.startBreak(at: date(hour: 12))
        // Break never explicitly ended — clock out while on break.
        let entry = manager.materializedEntry(at: date(hour: 13))

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.breakMinutes, 60)
        XCTAssertEqual(entry?.paidHours ?? 0, 4.0, accuracy: 1e-6)
    }

    func testElapsedWorkedAndBreakMinutesWithInFlightBreak() throws {
        let manager = makeManager()
        manager.clockIn(at: date(hour: 9))
        manager.startBreak(at: date(hour: 10))

        let shift = try XCTUnwrap(manager.activeShift)
        XCTAssertTrue(shift.isOnBreak)
        // At 10:30 the in-flight break has consumed 30 min: worked = 1h.
        XCTAssertEqual(shift.elapsedWorked(at: date(hour: 10, minute: 30)), 3600, accuracy: 0.5)
        XCTAssertEqual(shift.totalBreakMinutes(at: date(hour: 10, minute: 30)), 30)
    }

    func testBreakGuards() {
        let manager = makeManager()

        // No shift: break calls are no-ops.
        manager.startBreak(at: date(hour: 9))
        XCTAssertNil(manager.activeShift)

        manager.clockIn(at: date(hour: 8))

        // End without start: no-op.
        manager.endBreak(at: date(hour: 9))
        XCTAssertEqual(manager.activeShift?.breaks.count, 0)

        // Double start: second one ignored.
        manager.startBreak(at: date(hour: 10))
        manager.startBreak(at: date(hour: 10, minute: 5))
        XCTAssertEqual(manager.activeShift?.breaks.count, 1)

        manager.endBreak(at: date(hour: 10, minute: 15))
        XCTAssertEqual(manager.activeShift?.isOnBreak, false)
        XCTAssertEqual(manager.activeShift?.totalBreakMinutes(at: date(hour: 11)), 15)
    }

    // MARK: - Guards

    func testDoubleClockInIsIgnored() {
        let manager = makeManager()
        manager.clockIn(at: date(hour: 8))
        manager.clockIn(at: date(hour: 9))

        XCTAssertEqual(manager.activeShift?.startDate, date(hour: 8))
    }

    func testClockOutOver24HoursIsRefused() {
        let manager = makeManager()
        let store = makeStore()
        let countBefore = store.entries.count

        manager.clockIn(at: date(hour: 8))
        let entry = manager.clockOut(at: date(hour: 9, dayOffset: 1), into: store) // 25h later

        XCTAssertNil(entry)
        XCTAssertEqual(store.entries.count, countBefore)
        // Refusal leaves the shift active for the user to resolve.
        XCTAssertNotNil(manager.activeShift)
    }

    func testClockOutWithNoWorkedTimeIsRefused() {
        let manager = makeManager()
        manager.clockIn(at: date(hour: 8))

        XCTAssertNil(manager.materializedEntry(at: date(hour: 8)))
        XCTAssertNotNil(manager.activeShift)
    }

    // MARK: - Rounding

    func testStartAndEndAreRoundedToTheMinute() {
        let manager = makeManager()
        manager.clockIn(at: date(hour: 8, minute: 0, second: 42))
        let entry = manager.materializedEntry(at: date(hour: 16, minute: 30, second: 17))

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.start, date(hour: 8))
        XCTAssertEqual(entry?.end, date(hour: 16, minute: 30))
    }

    // MARK: - Overnight

    func testOvernightShiftMaterializesOnClockInDay() {
        let manager = makeManager()
        manager.clockIn(at: date(hour: 22))
        manager.startBreak(at: date(hour: 2, dayOffset: 1))
        manager.endBreak(at: date(hour: 2, minute: 30, dayOffset: 1))

        let entry = manager.materializedEntry(at: date(hour: 6, dayOffset: 1))

        XCTAssertNotNil(entry)
        guard let entry else { return }

        let cal = Calendar.current
        // Entry belongs to the clock-in day...
        XCTAssertEqual(entry.date, cal.startOfDay(for: date(hour: 22)))
        // ...and uses the editor's overnight convention: end merged onto the
        // clock-in day, so end < start and paidHours wraps +24.
        XCTAssertEqual(entry.start, date(hour: 22))
        XCTAssertEqual(entry.end, date(hour: 6))
        XCTAssertLessThan(entry.end, entry.start)
        XCTAssertEqual(entry.breakMinutes, 30)
        XCTAssertEqual(entry.paidHours, 7.5, accuracy: 1e-6)
    }

    // MARK: - Persistence

    func testPersistenceRoundTripSurvivesRelaunch() throws {
        let first = makeManager()
        first.clockIn(at: date(hour: 8))
        first.startBreak(at: date(hour: 12))

        // Simulate app kill + relaunch: a fresh manager on the same defaults.
        let second = makeManager()
        let restored = try XCTUnwrap(second.activeShift)

        XCTAssertEqual(restored.startDate.timeIntervalSince1970,
                       date(hour: 8).timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(restored.breaks.count, 1)
        XCTAssertTrue(restored.isOnBreak)

        // Discard clears storage too.
        second.discard()
        XCTAssertNil(second.activeShift)
        XCTAssertNil(defaults.data(forKey: "live_shift_v1"))
        XCTAssertNil(makeManager().activeShift)
    }

    func testRestoredOldShiftIsKeptAndFlaggedStale() throws {
        let first = makeManager()
        first.clockIn(at: date(hour: 8, dayOffset: -2)) // >24h ago

        let second = makeManager()
        let restored = try XCTUnwrap(second.activeShift)
        XCTAssertTrue(restored.isStale(at: date(hour: 8)))
    }

    func testIsStaleThreshold() {
        let shift = LiveShift(startDate: date(hour: 0))
        XCTAssertFalse(shift.isStale(at: date(hour: 15)))
        XCTAssertFalse(shift.isStale(at: date(hour: 16)))
        XCTAssertTrue(shift.isStale(at: date(hour: 16, minute: 1)))
    }
}
