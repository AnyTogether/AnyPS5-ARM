import XCTest
@testable import AnyPS5Core

final class InputModeTests: XCTestCase {
    func testThePadAndTheKeyboardSwitchAtOnce() {
        var tracker = InputModeTracker()
        XCTAssertEqual(tracker.mode, .keyboard)
        XCTAssertTrue(tracker.usedPad())
        XCTAssertEqual(tracker.mode, .pad)
        XCTAssertFalse(tracker.usedPad())
        XCTAssertTrue(tracker.usedKeyboard())
        XCTAssertEqual(tracker.mode, .keyboard)
    }

    /// A mouse nudged by the desk does not take the screen from the pad; moved on purpose it does.
    func testThePointerHasToTravelBeforeItSwitches() {
        var tracker = InputModeTracker(mode: .pad)
        XCTAssertFalse(tracker.pointerMoved(5))
        XCTAssertFalse(tracker.pointerMoved(-10))
        XCTAssertEqual(tracker.mode, .pad)
        XCTAssertTrue(tracker.pointerMoved(10))
        XCTAssertEqual(tracker.mode, .keyboard)
    }

    /// The travel starts again from each pad press.
    func testAPadPressStartsTheTravelAgain() {
        var tracker = InputModeTracker(mode: .pad)
        tracker.pointerMoved(20)
        tracker.usedPad()
        XCTAssertFalse(tracker.pointerMoved(20))
        XCTAssertEqual(tracker.mode, .pad)
    }

    func testThePointerMovingAtTheKeyboardChangesNothing() {
        var tracker = InputModeTracker()
        XCTAssertFalse(tracker.pointerMoved(500))
        XCTAssertEqual(tracker.mode, .keyboard)
    }

    func testHintsShowTheKeysOfTheInputInUse() {
        XCTAssertEqual(HintKeys.keys("↩ / ✕", for: .keyboard), "↩")
        XCTAssertEqual(HintKeys.keys("↩ / ✕", for: .pad), "✕")
        XCTAssertEqual(HintKeys.keys("esc / ○", for: .pad), "○")
        XCTAssertEqual(HintKeys.keys("O / △", for: .keyboard), "O")
        XCTAssertEqual(HintKeys.keys("Q E / L1 R1", for: .keyboard), "Q E")
        XCTAssertEqual(HintKeys.keys("Q E / L1 R1", for: .pad), "L1 R1")
        XCTAssertEqual(HintKeys.keys("PS / esc / ○", for: .keyboard), "esc")
        XCTAssertEqual(HintKeys.keys("PS / esc / ○", for: .pad), "PS / ○")
    }

    /// The arrows are the keyboard's and the D-pad's alike.
    func testArrowsStayForBoth() {
        XCTAssertEqual(HintKeys.keys("← → ↑ ↓", for: .pad), "← → ↑ ↓")
        XCTAssertEqual(HintKeys.keys("← → ↑ ↓", for: .keyboard), "← → ↑ ↓")
        XCTAssertEqual(HintKeys.keys("← → ↩ / ✕", for: .keyboard), "← → ↩")
        XCTAssertEqual(HintKeys.keys("← → ↩ / ✕", for: .pad), "← → ✕")
    }

    /// A hint that has nothing for the input in use is shown whole rather than empty.
    func testAHintWithNothingLeftStaysWhole() {
        XCTAssertEqual(HintKeys.keys("PS", for: .keyboard), "PS")
        XCTAssertEqual(HintKeys.keys("F12", for: .pad), "F12")
    }

    func testEveryHintKeepsItsCommandsForEitherInput() {
        for keys in ["← → ↑ ↓", "Q E / L1 R1", "↩ / ✕", "esc / ○", "O / △", "↑ ↓", "← →", "← → ↩ / ✕", "PS / esc / ○", "PS"] {
            for mode in [InputMode.keyboard, .pad] {
                let tokens = HintKeys.tokens(HintKeys.keys(keys, for: mode))
                XCTAssertFalse(tokens.isEmpty, keys)
                XCTAssertFalse(tokens.contains { $0.text != "/" && $0.command == nil }, "\(keys) for \(mode)")
            }
        }
    }
}

final class RowEditorTests: XCTestCase {
    /// With the pad, moving onto a choice and pressing left or right changes nothing.
    func testHighlightingAChoiceWithThePadDoesNotChangeIt() {
        var editor = RowEditor()
        XCTAssertEqual(editor.intent(for: .right, row: "theme", kind: .choice, mode: .pad), .none)
        XCTAssertEqual(editor.intent(for: .left, row: "theme", kind: .choice, mode: .pad), .leaveRows)
        XCTAssertNil(editor.editing)
    }

    func testCrossStartsEditingAndLeftRightThenChange() {
        var editor = RowEditor()
        XCTAssertEqual(editor.intent(for: .select, row: "theme", kind: .choice, mode: .pad), .startEditing)
        XCTAssertTrue(editor.isEditing("theme"))
        XCTAssertEqual(editor.intent(for: .right, row: "theme", kind: .choice, mode: .pad), .change(1))
        XCTAssertEqual(editor.intent(for: .left, row: "theme", kind: .choice, mode: .pad), .change(-1))
        XCTAssertTrue(editor.isEditing("theme"))
    }

    func testCrossOrCircleEndEditing() {
        for command in [Command.select, .back] {
            var editor = RowEditor()
            _ = editor.intent(for: .select, row: "theme", kind: .choice, mode: .pad)
            XCTAssertEqual(editor.intent(for: command, row: "theme", kind: .choice, mode: .pad), .stopEditing)
            XCTAssertNil(editor.editing)
            // Out of editing, left and right are plain moves again.
            XCTAssertEqual(editor.intent(for: .right, row: "theme", kind: .choice, mode: .pad), .none)
        }
    }

    /// Up or down while editing ends it and moves on, changing nothing.
    func testMovingAwayEndsEditing() {
        var editor = RowEditor()
        _ = editor.intent(for: .select, row: "theme", kind: .choice, mode: .pad)
        XCTAssertEqual(editor.intent(for: .down, row: "theme", kind: .choice, mode: .pad), .move(1))
        XCTAssertNil(editor.editing)
    }

    /// Editing belongs to one row: the focus on another one is not editing.
    func testEditingIsForgottenOnAnotherRow() {
        var editor = RowEditor()
        _ = editor.intent(for: .select, row: "theme", kind: .choice, mode: .pad)
        XCTAssertEqual(editor.intent(for: .right, row: "accent", kind: .choice, mode: .pad), .none)
        XCTAssertNil(editor.editing)
    }

    /// A switch has no values to step through: ✕ flips it.
    func testCrossFlipsASwitch() {
        var editor = RowEditor()
        XCTAssertEqual(editor.intent(for: .select, row: "sounds", kind: .toggle, mode: .pad), .activate)
        XCTAssertNil(editor.editing)
        XCTAssertEqual(editor.intent(for: .right, row: "sounds", kind: .toggle, mode: .pad), .none)
    }

    /// At the keyboard left and right change at once, as before; Return still steps a choice.
    func testTheKeyboardChangesAtOnce() {
        var editor = RowEditor()
        XCTAssertEqual(editor.intent(for: .right, row: "theme", kind: .choice, mode: .keyboard), .change(1))
        XCTAssertEqual(editor.intent(for: .left, row: "sounds", kind: .toggle, mode: .keyboard), .change(-1))
        XCTAssertEqual(editor.intent(for: .select, row: "theme", kind: .choice, mode: .keyboard), .activate)
        XCTAssertNil(editor.editing)
    }

    /// Rows without values behave the same for both: left leaves the rows, select acts.
    func testOtherRowsBehaveTheSameForBoth() {
        for mode in [InputMode.keyboard, .pad] {
            var editor = RowEditor()
            XCTAssertEqual(editor.intent(for: .left, row: "rescan", kind: .other, mode: mode), .leaveRows)
            XCTAssertEqual(editor.intent(for: .right, row: "rescan", kind: .other, mode: mode), .none)
            XCTAssertEqual(editor.intent(for: .select, row: "rescan", kind: .other, mode: mode), .activate)
            XCTAssertEqual(editor.intent(for: .back, row: "rescan", kind: .other, mode: mode), .leaveRows)
            XCTAssertEqual(editor.intent(for: .options, row: "rescan", kind: .other, mode: mode), .close)
            XCTAssertEqual(editor.intent(for: .up, row: "rescan", kind: .other, mode: mode), .move(-1))
        }
    }

    /// The keyboard taking over in the middle of editing keeps the row in edit until it ends.
    func testSwitchingInputWhileEditingStillEndsWithSelect() {
        var editor = RowEditor()
        _ = editor.intent(for: .select, row: "theme", kind: .choice, mode: .pad)
        XCTAssertEqual(editor.intent(for: .right, row: "theme", kind: .choice, mode: .keyboard), .change(1))
        XCTAssertEqual(editor.intent(for: .select, row: "theme", kind: .choice, mode: .keyboard), .stopEditing)
    }
}
