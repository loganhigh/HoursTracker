import XCTest
@testable import HoursTracker

/// Multiple jobs: each shift is paid by its own job's rules, jobs survive the
/// settings round trip, and stale paydays roll forward per job.
final class JobsTests: XCTestCase {

    /// Same reason as LiveShiftManagerTests: keep stores alive for the run.
    private static var retainedStores: [HoursStore] = []

    private func makeStore() -> HoursStore {
        let store = HoursStore()
        Self.retainedStores.append(store)
        return store
    }

    private func shift(day: Int, hours: Double, jobID: String?) -> WorkEntry {
        let cal = Calendar.current
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: day))!
        let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: date)!
        var entry = WorkEntry(date: date, start: start, end: start.addingTimeInterval(hours * 3600),
                              breakMinutes: 0, notes: "")
        entry.jobID = jobID
        return entry
    }

    private func settings(wage: Double) -> PaySettings {
        var s = PaySettings()
        s.hourlyRate = wage
        s.hourlyRateSet = true
        s.overtimeType = .daily
        s.weekdayOvertimeAfterHours = 8
        s.weekendPremiumsEnabled = false
        return s
    }

    func testEachShiftIsPaidByItsOwnJobsWage() {
        let store = makeStore()
        var main = settings(wage: 30)
        main.additionalJobs = [JobProfile(id: "bar", name: "Bar", settings: settings(wage: 20))]
        store.paySettings = main

        // Tuesday 2026-03-10, 4 hours each, well under any overtime.
        XCTAssertEqual(store.payBreakdown(for: shift(day: 10, hours: 4, jobID: nil)).pay, 120, accuracy: 0.001)
        XCTAssertEqual(store.payBreakdown(for: shift(day: 10, hours: 4, jobID: "bar")).pay, 80, accuracy: 0.001)
        // A deleted job's shift falls back to the main job.
        XCTAssertEqual(store.payBreakdown(for: shift(day: 10, hours: 4, jobID: "gone")).pay, 120, accuracy: 0.001)
    }

    func testJobsListAndScopeFallBackSafely() {
        let store = makeStore()
        var main = settings(wage: 30)
        main.primaryJobName = "Paving"
        main.additionalJobs = [JobProfile(id: "bar", name: "Bar", settings: settings(wage: 20))]
        store.paySettings = main

        XCTAssertEqual(store.jobs.map(\.name), ["Paving", "Bar"])
        XCTAssertTrue(store.hasMultipleJobs)
        XCTAssertEqual(store.job(id: nil).id, JobProfile.primaryID)
        XCTAssertEqual(store.jobID(of: shift(day: 10, hours: 4, jobID: "bar")), "bar")
        XCTAssertTrue(store.jobs[0].settings.additionalJobs.isEmpty, "a job's own rules never nest jobs")
    }

    func testJobsSurviveTheSettingsRoundTripAndOldPayloadsStillDecode() throws {
        var main = settings(wage: 30)
        main.primaryJobName = "Paving"
        main.additionalJobs = [JobProfile(id: "bar", name: "Bar", settings: settings(wage: 20))]
        let decoded = try JSONDecoder().decode(PaySettings.self, from: JSONEncoder().encode(main))
        XCTAssertEqual(decoded, main)

        // Settings saved before jobs existed decode with no extra jobs.
        let legacy = try JSONDecoder().decode(PaySettings.self, from: Data(#"{"hourlyRate": 31}"#.utf8))
        XCTAssertTrue(legacy.additionalJobs.isEmpty)
        XCTAssertEqual(legacy.primaryJobName, "")
    }

    func testShiftJobRoundTripsAndLegacyShiftsHaveNone() throws {
        let tagged = shift(day: 10, hours: 4, jobID: "bar")
        let decoded = try JSONDecoder().decode(WorkEntry.self, from: JSONEncoder().encode(tagged))
        XCTAssertEqual(decoded.jobID, "bar")

        let untagged = try JSONEncoder().encode(shift(day: 10, hours: 4, jobID: nil))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: untagged) as? [String: Any])
        XCTAssertNil(json["jobID"], "untouched shifts upload exactly as before")
    }

    func testStalePaydayRollsForwardBySchedule() {
        var s = PaySettings()
        s.payPeriodType = .biWeekly
        let cal = Calendar.current
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        s.nextPayday = cal.date(from: DateComponents(year: 2026, month: 3, day: 6))
        XCTAssertTrue(s.rollPayDatesForward(today: today))
        XCTAssertEqual(s.nextPayday, cal.date(from: DateComponents(year: 2026, month: 4, day: 3)))
        XCTAssertFalse(s.rollPayDatesForward(today: today))
    }
}
