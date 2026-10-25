import XCTest
@testable import AnyPS5Core

final class AwakeTests: XCTestCase {
    func testHoldingTwiceKeepsOneActivityAndReleasingEndsIt() {
        let awake = Awake("test")
        XCTAssertFalse(awake.held)
        awake.hold()
        awake.hold()
        XCTAssertTrue(awake.held)
        awake.release()
        XCTAssertFalse(awake.held)
        awake.release()
        XCTAssertFalse(awake.held)
    }

    func testTheActivityKeepsTimersOnTimeWhileHeld() {
        let awake = Awake("test")
        awake.hold()
        XCTAssertEqual(awake.options, [.userInitiated, .latencyCritical])
        awake.release()
    }
}
