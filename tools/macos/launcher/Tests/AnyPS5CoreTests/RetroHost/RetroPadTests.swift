import XCTest
@testable import AnyPS5Core

/// A launcher controller, the seats and the keyboard as the PS1 pad, as on Windows and Linux (AnyPS5
/// Desktop's test/core/retro_host/retro_pad_test.dart, retro_seats_test.dart and
/// retro_keyboard_test.dart).
final class RetroPadTests: XCTestCase {
    // MARK: Buttons and sticks

    func testEachPadButtonPressesTheBitOfTheProtocolsInput() {
        let table: [PadButton: Int] = [
            .south: 0, .west: 1, .select: 2, .start: 3, .dpadUp: 4, .dpadDown: 5, .dpadLeft: 6, .dpadRight: 7, .east: 8, .north: 9,
            .l1: 10, .r1: 11, .l2: 12, .r2: 13, .l3: 14, .r3: 15,
        ]
        for (button, bit) in table {
            XCTAssertEqual(RetroPadInput.fromPad(PadState(pressed: [button])).buttons, 1 << bit, "\(button)")
        }
        XCTAssertEqual(RetroPadInput.fromPad(PadState(pressed: Set(table.keys))).buttons, 0xFFFF)
    }

    func testPSTheTouchpadAndTheExtraButtonStayTheLaunchers() {
        XCTAssertEqual(RetroPadInput.fromPad(PadState(pressed: [.guide, .touchpad, .misc])), .idle)
    }

    func testATriggerPulledPastThePressPointPressesL2OrR2() {
        XCTAssertEqual(RetroPadInput.fromPad(PadState(l2: 0.34)).buttons, 0)
        XCTAssertEqual(RetroPadInput.fromPad(PadState(l2: 0.35)).buttons, RetroPadButton.l2.mask)
        XCTAssertEqual(RetroPadInput.fromPad(PadState(r2: 1)).buttons, RetroPadButton.r2.mask)
    }

    func testTheSticksReachBothEndsOfTheRangeUpAndLeftNegative() {
        XCTAssertEqual(RetroPadInput.fromPad(PadState(leftX: -1, leftY: 1, rightX: 1, rightY: -1)),
                       RetroPadInput(leftX: -32768, leftY: 32767, rightX: 32767, rightY: -32768))
        XCTAssertEqual(RetroPadInput.axis(0), 0)
        XCTAssertEqual(RetroPadInput.axis(0.5), 16384)
        XCTAssertEqual(RetroPadInput.axis(-0.5), -16384)
        XCTAssertEqual(RetroPadInput.axis(2), 32767)
        XCTAssertEqual(RetroPadInput.axis(.nan), 0)
    }

    func testTheStickDeadZoneCentresEachStickOnItsOwn() {
        let input = RetroPadInput.fromPad(PadState(leftX: 0.1, rightY: 1), deadzonePercent: 20)
        XCTAssertEqual(input.leftX, 0)
        XCTAssertEqual(input.rightY, 32767)
    }

    // MARK: Seats

    func testPlayer1SitsAtPort1AndTheNextControllerAtPort2() {
        var seats = RetroSeats()
        XCTAssertEqual(seats.connectedPorts, 1)
        XCTAssertEqual(seats.sync(["a", "b", "c"]), [RetroSeatChange(0, "a", joined: true), RetroSeatChange(1, "b", joined: true)])
        XCTAssertEqual(seats.at(0), "a")
        XCTAssertEqual(seats.at(1), "b")
        XCTAssertNil(seats.portOf("c"))
        XCTAssertEqual(seats.connectedPorts, 2)
    }

    func testANewOrderDoesNotSwapThePlayers() {
        var seats = RetroSeats()
        _ = seats.sync(["a", "b"])
        XCTAssertEqual(seats.sync(["b", "a"]), [])
        XCTAssertEqual(seats.portOf("a"), 0)
        XCTAssertEqual(seats.portOf("b"), 1)
    }

    func testAControllerThatLeavesFreesItsPortForTheNextOneWaiting() {
        var seats = RetroSeats()
        _ = seats.sync(["a", "b", "c"])
        XCTAssertEqual(seats.sync(["a", "c"]), [RetroSeatChange(1, "b", joined: false), RetroSeatChange(1, "c", joined: true)])
        XCTAssertEqual(seats.connectedPorts, 2)
    }

    func testWhenPlayer1LeavesPlayer2KeepsPort2() {
        var seats = RetroSeats()
        _ = seats.sync(["a", "b"])
        XCTAssertEqual(seats.sync(["b"]), [RetroSeatChange(0, "a", joined: false)])
        XCTAssertNil(seats.at(0))
        XCTAssertEqual(seats.at(1), "b")
        XCTAssertEqual(seats.connectedPorts, 2)
        XCTAssertEqual(seats.sync(["b", "d"]), [RetroSeatChange(0, "d", joined: true)])
    }

    func testPort2IsDisconnectedOnceItsControllerLeaves() {
        var seats = RetroSeats()
        _ = seats.sync(["a", "b"])
        _ = seats.sync(["a"])
        XCTAssertEqual(seats.connectedPorts, 1)
        XCTAssertEqual(seats.sync([]), [RetroSeatChange(0, "a", joined: false)])
        XCTAssertEqual(seats.connectedPorts, 1)
    }

    // MARK: The keyboard

    func testTheLaunchersLayoutPlaysThePS1Pad() {
        let keyboard = RetroKeyboard(changes: [:])
        XCTAssertEqual(keyboard.state(held: []), .idle)
        XCTAssertEqual(keyboard.state(held: ["K", "L", "J", "I"]).pressed, [.south, .east, .west, .north])
        XCTAssertEqual(keyboard.state(held: ["Escape"]).pressed, [.start])
        XCTAssertEqual(keyboard.state(held: ["Backspace"]).pressed, [.select])
        XCTAssertEqual(keyboard.state(held: ["Tab"]).pressed, [.select])
        XCTAssertEqual(keyboard.state(held: ["Up"]).pressed, [.dpadUp])
        XCTAssertEqual(keyboard.state(held: ["Left Shift"]).pressed, [.l3])
        let walking = keyboard.state(held: ["W", "D"])
        XCTAssertEqual(walking.leftX, 1)
        XCTAssertEqual(walking.leftY, -1)
        let both = keyboard.state(held: ["A", "D", "S"])
        XCTAssertEqual(both.leftX, 0, "left and right together cancel")
        XCTAssertEqual(both.leftY, 1)
        let l2 = keyboard.state(held: ["U"])
        XCTAssertEqual(l2.l2, 1)
        XCTAssertEqual(l2.pressed, [.l2])
        XCTAssertEqual(RetroPadInput.fromPad(keyboard.state(held: ["K", "Escape"])).buttons, RetroPadButton.cross.mask | RetroPadButton.start.mask)
    }

    func testTheKeysAGamesControlsMovedAndOnlyKeyboardKeys() {
        let keyboard = RetroKeyboard(changes: Controls.assign("KEY:F1", to: .cross, [:]))
        XCTAssertEqual(keyboard.state(held: ["F1"]).pressed, [.south])
        XCTAssertEqual(keyboard.state(held: ["K"]).pressed, [], "K no longer presses Cross")
        XCTAssertEqual(keyboard.state(held: ["Left"]).pressed, [.dpadLeft], "the mouse's sources are not keys")
        XCTAssertEqual(keyboard.state(held: ["Right"]).pressed, [.dpadRight])
    }

    func testTheStickModifierTiltsTheKeyboardSticksOnlyPartWay() {
        let keyboard = RetroKeyboard(changes: Controls.assign("KEY:Left Alt", to: .stickModifier, [:]), modifierScale: 0.25)
        XCTAssertEqual(keyboard.state(held: ["W", "Left Alt"]).leftY, -0.25)
    }

    func testKeysJoinAController() {
        let pad = PadState(pressed: [.east], leftX: 0.5, rightY: 0.25, l2: 0.6)
        let keys = RetroKeyboard(changes: [:]).state(held: ["K", "W"])
        let both = RetroKeyboard.merge(pad, keys)
        XCTAssertEqual(both.pressed, [.east, .south])
        XCTAssertEqual(both.leftX, 0)
        XCTAssertEqual(both.leftY, -1)
        XCTAssertEqual(both.rightX, 0)
        XCTAssertEqual(both.rightY, 0.25)
        XCTAssertEqual(both.l2, 0.6)
        XCTAssertEqual(RetroKeyboard.merge(nil, keys), keys)
    }
}
