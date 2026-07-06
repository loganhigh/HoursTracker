import XCTest
@testable import HoursTracker

/// Unit tests for Saturday overtime rule: first 4h at regular, remaining at 1.5x.
final class OvertimeRulesTests: XCTestCase {

    let wage: Double = 10.0
    let satThreshold: Double = 4.0
    let satMult: Double = 1.5
    let sunMult: Double = 2.0
    let wdAfter: Double = 8.0
    let wdMult: Double = 1.5

    func testSaturday_3h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 3.0,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 3.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.pay, 3.0 * wage, accuracy: 1e-6)
    }

    func testSaturday_4h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 4.0,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 4.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        XCTAssertEqual(b.pay, 4.0 * wage, accuracy: 1e-6)
    }

    func testSaturday_6_5h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 6.5,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 4.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 2.5, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        let expectedPay = (4.0 * wage) + (2.5 * wage * 1.5)
        XCTAssertEqual(b.pay, expectedPay, accuracy: 1e-6)
    }

    func testSaturday_12h() {
        let b = OvertimeRules.breakdown(
            weekday: 7,
            rawHours: 12.0,
            wage: wage,
            saturdayThreshold: satThreshold,
            saturdayMultiplier: satMult,
            sundayMultiplier: sunMult,
            weekdayOTAfterHours: wdAfter,
            weekdayOTMultiplier: wdMult
        )
        XCTAssertEqual(b.regularHours, 4.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt1_5, 8.0, accuracy: 1e-6)
        XCTAssertEqual(b.overtimeHoursAt2_0, 0.0, accuracy: 1e-6)
        let expectedPay = (4.0 * wage) + (8.0 * wage * 1.5)
        XCTAssertEqual(b.pay, expectedPay, accuracy: 1e-6)
    }
}
