import XCTest
@testable import HoursTracker

/// The split feeds real pay calculations (weekend premiums land on the split
/// day), so the portion math has to be exact: durations must sum to the
/// original shift, dates must be consecutive, and WorkEntry.paidHours must
/// agree with both portions.
final class OvernightSplitTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Saturday 2026-06-06 with wizard-convention times (all on the same day;
    /// an end at/before start means "ends tomorrow").
    private func dates(startHour: Int, startMinute: Int = 0, endHour: Int, endMinute: Int = 0)
        -> (date: Date, start: Date, end: Date) {
        var d = DateComponents(year: 2026, month: 6, day: 6); d.timeZone = cal.timeZone
        let day = cal.date(from: d)!
        let start = cal.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day)!
        let end = cal.date(bySettingHour: endHour, minute: endMinute, second: 0, of: day)!
        return (day, start, end)
    }

    // MARK: - The Sat 2 PM → Sun 6 AM case this feature exists for

    func testSaturdayNightIntoSundaySplitsCorrectly() {
        let (day, start, end) = dates(startHour: 14, endHour: 6)
        let split = OvernightSplit.split(date: day, start: start, end: end, breakMinutes: 0, calendar: cal)
        XCTAssertNotNil(split)
        guard let split else { return }

        // First portion: Saturday, 2 PM → midnight, 10h.
        XCTAssertEqual(split.first.date, day)
        let firstEntry = WorkEntry(date: split.first.date, start: split.first.start,
                                   end: split.first.end, breakMinutes: 0, notes: "")
        XCTAssertEqual(firstEntry.paidHours, 10, accuracy: 0.001)
        XCTAssertEqual(cal.component(.weekday, from: split.first.date), 7, "Saturday")

        // Second portion: Sunday, midnight → 6 AM, 6h.
        XCTAssertEqual(split.second.date, cal.date(byAdding: .day, value: 1, to: day))
        let secondEntry = WorkEntry(date: split.second.date, start: split.second.start,
                                    end: split.second.end, breakMinutes: 0, notes: "")
        XCTAssertEqual(secondEntry.paidHours, 6, accuracy: 0.001)
        XCTAssertEqual(cal.component(.weekday, from: split.second.date), 1, "Sunday")
    }

    func testPortionsAlwaysSumToTheOriginalShift() {
        // A spread of overnight shapes, including minute-precision times.
        let cases: [(sh: Int, sm: Int, eh: Int, em: Int, total: Double)] = [
            (14, 0, 6, 0, 16),      // 2 PM → 6 AM
            (22, 30, 7, 15, 8.75),  // 10:30 PM → 7:15 AM
            (23, 0, 0, 30, 1.5),    // 11 PM → 12:30 AM
            (18, 0, 17, 0, 23),     // 6 PM → 5 PM next day (worst case)
        ]
        for c0 in cases {
            let (day, start, end) = dates(startHour: c0.sh, startMinute: c0.sm, endHour: c0.eh, endMinute: c0.em)
            guard let split = OvernightSplit.split(date: day, start: start, end: end, breakMinutes: 0, calendar: cal) else {
                XCTFail("Expected a split for \(c0)"); continue
            }
            let first = WorkEntry(date: split.first.date, start: split.first.start,
                                  end: split.first.end, breakMinutes: 0, notes: "")
            let second = WorkEntry(date: split.second.date, start: split.second.start,
                                   end: split.second.end, breakMinutes: 0, notes: "")
            XCTAssertEqual(first.paidHours + second.paidHours, c0.total, accuracy: 0.001,
                           "Portions must sum to the original for \(c0)")
        }
    }

    // MARK: - Nothing-to-split cases

    func testDayShiftDoesNotSplit() {
        let (day, start, end) = dates(startHour: 9, endHour: 17)
        XCTAssertNil(OvernightSplit.split(date: day, start: start, end: end, breakMinutes: 30, calendar: cal))
    }

    func testShiftEndingExactlyAtMidnightDoesNotSplit() {
        // 2 PM → 12:00 AM: zero hours belong to the next day.
        let (day, start, end) = dates(startHour: 14, endHour: 0)
        XCTAssertNil(OvernightSplit.split(date: day, start: start, end: end, breakMinutes: 0, calendar: cal))
    }

    // MARK: - Break attribution

    func testBreakGoesToTheLongerPortion() {
        // 2 PM → 6 AM: first portion (10h) is longer, so it carries the break.
        let (day, start, end) = dates(startHour: 14, endHour: 6)
        let split = OvernightSplit.split(date: day, start: start, end: end, breakMinutes: 30, calendar: cal)
        XCTAssertEqual(split?.first.breakMinutes, 30)
        XCTAssertEqual(split?.second.breakMinutes, 0)

        // 11 PM → 8 AM: second portion (8h) is longer.
        let late = dates(startHour: 23, endHour: 8)
        let lateSplit = OvernightSplit.split(date: late.date, start: late.start, end: late.end, breakMinutes: 45, calendar: cal)
        XCTAssertEqual(lateSplit?.first.breakMinutes, 0)
        XCTAssertEqual(lateSplit?.second.breakMinutes, 45)
    }

    func testOversizedBreakIsCappedBelowItsPortion() {
        // 11:30 PM → 1 AM: portions are 30m and 60m. A 90m break must not
        // zero out (or exceed) the 60m portion that carries it.
        let (day, start, end) = dates(startHour: 23, startMinute: 30, endHour: 1)
        guard let split = OvernightSplit.split(date: day, start: start, end: end, breakMinutes: 90, calendar: cal) else {
            XCTFail("Expected a split"); return
        }
        let carrier = WorkEntry(date: split.second.date, start: split.second.start,
                                end: split.second.end, breakMinutes: split.second.breakMinutes, notes: "")
        XCTAssertGreaterThan(carrier.paidHours, 0, "The break may never consume its whole portion")
    }
}

/// Map-pin shift locations: what gets written onto an entry and synced.
final class ShiftPlaceTests: XCTestCase {

    func testApplyWritesPinAndName() {
        var entry = WorkEntry(date: Date(), start: Date(), end: Date(), breakMinutes: 0, notes: "",
                              isOffDay: false, offDayReason: "", isHoliday: false)
        ShiftPlace(name: "  Main Yard ", latitude: 53.5, longitude: -113.5).apply(to: &entry)
        XCTAssertEqual(entry.locationName, "Main Yard")
        XCTAssertEqual(entry.latitude, 53.5)
        XCTAssertEqual(entry.longitude, -113.5)
        XCTAssertEqual(ShiftPlace(entry: entry).displayText, "Main Yard")
    }

    func testClearedPinEncodesAsNullSoCloudMergeClearsIt() throws {
        var entry = WorkEntry(date: Date(), start: Date(), end: Date(), breakMinutes: 0, notes: "",
                              isOffDay: false, offDayReason: "", isHoliday: false)
        ShiftPlace(name: "Site", latitude: 1, longitude: 2).apply(to: &entry)
        ShiftPlace().apply(to: &entry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        XCTAssertTrue(json["latitude"] is NSNull)
        XCTAssertTrue(json["longitude"] is NSNull)
        XCTAssertEqual(json["locationName"] as? String, "")
        // And it still decodes.
        let back = try JSONDecoder().decode(WorkEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertNil(back.latitude)
    }

    func testNameOnlyPlaceFromOlderEntries() {
        let place = ShiftPlace(name: "Old free-text site")
        XCTAssertNil(place.coordinate)
        XCTAssertFalse(place.isEmpty)
        XCTAssertEqual(place.displayText, "Old free-text site")
    }
}

/// Known bugs from the 2026-10-31 audit. Each test asserts the CORRECT
/// behaviour inside XCTExpectFailure, so the suite stays green today and the
/// test fails ("expected failure not seen") once the bug is fixed — remove
/// the XCTExpectFailure wrapper then.
final class AuditKnownBugTests: XCTestCase {

    private var toronto: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Toronto")!
        return c
    }

    /// Wizard convention: start and end on the shift's day, end <= start means "ends tomorrow".
    private func night(_ y: Int, _ m: Int, _ d: Int) -> (date: Date, start: Date, end: Date) {
        let day = toronto.date(from: DateComponents(year: y, month: m, day: d))!
        return (day,
                toronto.date(bySettingHour: 22, minute: 0, second: 0, of: day)!,
                toronto.date(bySettingHour: 6, minute: 0, second: 0, of: day)!)
    }

    func testOvernightShiftAcrossFallBackPaysRealElapsedHours() {
        // 10 PM Oct 31 → 6 AM Nov 1 2026 in Toronto is 9 real hours.
        let n = night(2026, 10, 31)
        let entry = WorkEntry(date: n.date, start: n.start, end: n.end, breakMinutes: 0, notes: "")
        XCTExpectFailure("paidHours wraps overnight shifts with a fixed +24h (WorkEntry.swift:55)") {
            XCTAssertEqual(entry.paidHours, 9, accuracy: 0.001)
        }
    }

    func testSplitFirstPortionOnFallBackDayIsTwoHours() {
        // 10 PM Nov 1 → 6 AM Nov 2: the Nov 1 portion is 10 PM → midnight = 2h.
        let n = night(2026, 11, 1)
        guard let split = OvernightSplit.split(date: n.date, start: n.start, end: n.end,
                                               breakMinutes: 0, calendar: toronto) else {
            return XCTFail("expected a split")
        }
        let first = WorkEntry(date: split.first.date, start: split.first.start,
                              end: split.first.end, breakMinutes: 0, notes: "")
        XCTExpectFailure("first portion ends at the same day's midnight and relies on the +24h wrap (OvernightSplit.swift:68-73)") {
            XCTAssertEqual(first.paidHours, 2, accuracy: 0.001)
        }
    }

    func testClearedStatHolidayIsWrittenAsNullSoCloudMergeClearsIt() throws {
        // Cloud saves use setData(merge: true); an absent key leaves the old
        // holiday rule and stat hours in Firestore, and the listener restores them.
        let entry = WorkEntry(date: Date(), start: Date(), end: Date(), breakMinutes: 0, notes: "")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        XCTAssertTrue(json["holidayPayRule"] is NSNull)
        XCTAssertEqual(json["statPayHours"] as? Double, 0)
    }

    // MARK: Sync merge (audit #4)

    private func stamped(_ entry: WorkEntry, _ seconds: TimeInterval) -> WorkEntry {
        var copy = entry
        copy.modifiedAt = Date(timeIntervalSince1970: seconds)
        return copy
    }

    func testNewerLocalEditBeatsOlderCloudCopy() {
        let base = WorkEntry(date: Date(), start: Date(), end: Date(), breakMinutes: 0, notes: "")
        var edited = stamped(base, 2_000)
        edited.notes = "edited offline"
        XCTAssertTrue(HoursStore.localCopyWins(edited, over: stamped(base, 1_000), pending: []))
        XCTAssertFalse(HoursStore.localCopyWins(stamped(base, 1_000), over: edited, pending: []))
    }

    func testQueuedUploadBeatsCloudCopyAndUnstampedFallsBackToCloud() {
        let base = WorkEntry(date: Date(), start: Date(), end: Date(), breakMinutes: 0, notes: "")
        XCTAssertTrue(HoursStore.localCopyWins(base, over: stamped(base, 9_000), pending: [base.id]))
        XCTAssertFalse(HoursStore.localCopyWins(base, over: stamped(base, 9_000), pending: []))
    }
}
