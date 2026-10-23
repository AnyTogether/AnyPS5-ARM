import XCTest
@testable import AnyPS5Core

final class PowerNoticeTests: XCTestCase {
    func testLowPowerModeOnAFastDisplayIsTold() {
        XCTAssertEqual(PowerNotice.kind(lowPower: true, displayMaximumFPS: 120, frameGeneration: true), .frameGeneration)
        XCTAssertEqual(PowerNotice.kind(lowPower: true, displayMaximumFPS: 120, frameGeneration: false), .refresh)
    }

    func testNothingIsToldWhereItChangesNothing() {
        XCTAssertNil(PowerNotice.kind(lowPower: false, displayMaximumFPS: 120, frameGeneration: true), "Low Power Mode is off")
        XCTAssertNil(PowerNotice.kind(lowPower: true, displayMaximumFPS: 60, frameGeneration: true), "a 60 Hz display stays at 60 Hz anyway")
    }
}
