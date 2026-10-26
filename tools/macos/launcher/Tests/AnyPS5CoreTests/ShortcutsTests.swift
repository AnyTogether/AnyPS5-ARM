import XCTest
@testable import AnyPS5Core

final class LongPressTests: XCTestCase {
    func testALetGoBeforeTheThresholdIsAPress() {
        var press = LongPress()
        press.press(at: 10)
        XCTAssertNil(press.tick(at: 10.3))
        XCTAssertEqual(press.release(at: 10.4), .press)
        XCTAssertFalse(press.isDown)
    }

    func testHeldToTheThresholdIsAHoldToldOnce() {
        var press = LongPress()
        press.press(at: 0)
        XCTAssertEqual(press.due, LongPress.threshold)
        XCTAssertEqual(press.tick(at: 0.6), .hold)
        XCTAssertNil(press.tick(at: 0.9))
        XCTAssertNil(press.due)
        // Its release says nothing more.
        XCTAssertNil(press.release(at: 1.2))
    }

    /// A tick that came late still makes a long press a hold when it is let go.
    func testAReleaseAfterTheThresholdWithoutATickIsAHold() {
        var press = LongPress()
        press.press(at: 0)
        XCTAssertEqual(press.release(at: 0.8), .hold)
    }

    func testAReleaseWithoutAPressIsNothing() {
        var press = LongPress()
        XCTAssertNil(press.release(at: 1))
        XCTAssertNil(press.tick(at: 1))
    }

    /// A second press while down is the same press (a key's repeats).
    func testRepeatedPressesKeepTheFirstTime() {
        var press = LongPress()
        press.press(at: 0)
        press.press(at: 0.5)
        XCTAssertEqual(press.tick(at: 0.6), .hold)
    }
}

final class ShortcutMapTests: XCTestCase {
    func testTheDefaultsHaveNoConflicts() {
        XCTAssertEqual(ShortcutMap().conflicts(), [])
        XCTAssertTrue(ShortcutMap().isDefault)
    }

    func testTheDefaults() {
        let map = ShortcutMap()
        XCTAssertEqual(map.binding(.home).pad, PadChord([.guide]))
        XCTAssertEqual(map.binding(.clip).pad, PadChord([.select]))
        XCTAssertEqual(map.binding(.screenshot).pad, PadChord([.select], hold: true))
        XCTAssertEqual(map.binding(.clip).key?.display, "⌥F12")
        XCTAssertEqual(map.binding(.fullScreen).key?.display, "F11")
        XCTAssertEqual(map.binding(.previousSection).pad, PadChord([.l1]))
        XCTAssertEqual(map.binding(.nextSection).key?.name, "E")
    }

    func testTheSameKeyOnTwoActionsIsAConflict() {
        var map = ShortcutMap()
        map.setKey(KeyChord(keyCode: 111, modifiers: .option, name: "F12"), for: .screenshot)
        XCTAssertEqual(map.conflicts(), [.sameKey(.screenshot, .clip)])
        XCTAssertEqual(map.conflicts(of: .clip), [.sameKey(.screenshot, .clip)])
        XCTAssertEqual(map.conflicts(of: .home), [])
        // A key in conflict acts for neither.
        XCTAssertNil(map.action(forKey: KeyChord(keyCode: 111, modifiers: .option, name: "F12")))
    }

    /// The same key with other modifiers is another key.
    func testModifiersMakeAnotherKey() {
        var map = ShortcutMap()
        map.setKey(KeyChord(keyCode: 111, modifiers: [.option, .control], name: "F12"), for: .screenshot)
        XCTAssertEqual(map.conflicts(), [])
    }

    func testTheSameChordOnTwoActionsIsAConflict() {
        var map = ShortcutMap()
        map.setPad(PadChord([.l1, .r1]), for: .screenshot)
        map.setPad(PadChord([.r1, .l1]), for: .quickMenu)
        XCTAssertEqual(map.conflicts(), [.samePad(.quickMenu, .screenshot)])
        // Neither acts until one of them changes.
        XCTAssertEqual(map.padChords.map(\.0), [.home, .clip, .previousSection, .nextSection])
    }

    /// Pressing and holding the same buttons are two bindings: Create and Create held.
    func testAPressAndAHoldOfTheSameButtonsDoNotClash() {
        var map = ShortcutMap()
        map.setPad(PadChord([.guide], hold: true), for: .quickMenu)
        XCTAssertEqual(map.conflicts(), [])
    }

    func testNavigationKeysAndButtonsAreRefusedAlone() {
        var map = ShortcutMap()
        map.setKey(KeyChord(keyCode: 36, name: "Return"), for: .fullScreen)
        map.setPad(PadChord([.south]), for: .clip)
        XCTAssertEqual(map.conflicts(), [.navigationButton(.clip), .navigationKey(.fullScreen)])
        // In a chord they are fine.
        map.setPad(PadChord([.l1, .south]), for: .clip)
        map.setKey(KeyChord(keyCode: 36, modifiers: [.command, .control], name: "Return"), for: .fullScreen)
        XCTAssertEqual(map.conflicts(), [])
    }

    /// A key that works from a game needs a modifier or a function key, or every app loses it.
    func testInGameKeysNeedAModifier() {
        var map = ShortcutMap()
        map.setKey(KeyChord(keyCode: 40, name: "K"), for: .clip)
        XCTAssertEqual(map.conflicts(), [.needsModifier(.clip)])
        map.setKey(KeyChord(keyCode: 40, modifiers: .shift, name: "K"), for: .clip)
        XCTAssertEqual(map.conflicts(), [.needsModifier(.clip)])
        map.setKey(KeyChord(keyCode: 101, name: "F9"), for: .clip)
        XCTAssertEqual(map.conflicts(), [])
        // The launcher's own keys may be plain.
        map.setKey(KeyChord(keyCode: 40, name: "K"), for: .fullScreen)
        XCTAssertEqual(map.conflicts(), [])
    }

    /// ⌥V, ⌥A and ⌥D are the party's and the calls' keys; ⌘ alone is the menus'.
    func testKeysAnyPS5OrTheMenusUseAreRefused() {
        var map = ShortcutMap()
        map.setKey(KeyChord(keyCode: 9, modifiers: .option, name: "V"), for: .screenshot)
        map.setKey(KeyChord(keyCode: 12, modifiers: .command, name: "Q"), for: .fullScreen)
        XCTAssertEqual(map.conflicts(), [.reservedKey(.screenshot), .reservedKey(.fullScreen)])
        map.setKey(KeyChord(keyCode: 3, modifiers: [.command, .control], name: "F"), for: .fullScreen)
        map.setKey(KeyChord(keyCode: 9, modifiers: [.option, .shift], name: "V"), for: .screenshot)
        XCTAssertEqual(map.conflicts(), [])
    }

    func testResetGoesBackToTheDefaults() {
        var map = ShortcutMap()
        map.setKey(nil, for: .home)
        map.setPad(PadChord([.l3, .r3]), for: .screenshot)
        XCTAssertNil(map.binding(.home).key)
        XCTAssertFalse(map.isDefault)
        map.reset()
        XCTAssertEqual(map, ShortcutMap())
        XCTAssertEqual(map.binding(.home).key?.display, "⌥Esc")
    }

    /// Setting a binding back to its default forgets the change.
    func testSettingTheDefaultAgainForgetsTheChange() {
        var map = ShortcutMap()
        map.setPad(PadChord([.l3]), for: .clip)
        map.setPad(PadChord([.select]), for: .clip)
        XCTAssertTrue(map.isDefault)
    }

    func testOnlyChangesAreSavedAndTheyComeBack() throws {
        var map = ShortcutMap()
        map.setPad(PadChord([.l3, .r3]), for: .screenshot)
        map.setKey(nil, for: .quickMenu)
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(ShortcutMap.self, from: data)
        XCTAssertEqual(decoded, map)
        XCTAssertEqual(decoded.binding(.screenshot).pad, PadChord([.l3, .r3]))
        XCTAssertNil(decoded.binding(.quickMenu).key)
        XCTAssertEqual(decoded.binding(.clip), ShortcutMap.defaults[.clip])
    }

    func testKeysFromAnyAppAreTheInGameOnes() {
        XCTAssertEqual(ShortcutMap().inGameKeys.map(\.0), [.home, .quickMenu, .screenshot, .clip])
    }

    func testTheKeyGivesItsAction() {
        let map = ShortcutMap()
        XCTAssertEqual(map.action(forKey: KeyChord(keyCode: 103, name: "F11")), .fullScreen)
        XCTAssertEqual(map.action(forKey: KeyChord(keyCode: 12, name: "Q")), .previousSection)
        XCTAssertNil(map.action(forKey: KeyChord(keyCode: 12, modifiers: .option, name: "Q")))
    }

    func testChordsAreNamedInPlayStationOrder() {
        XCTAssertEqual(PadChord([.south, .r1, .guide]).buttons.map(\.glyph), ["R1", "PS", "✕"])
    }
}

final class PadShortcutReaderTests: XCTestCase {
    private func reader(_ change: (inout ShortcutMap) -> Void = { _ in }) -> PadShortcutReader {
        var map = ShortcutMap()
        change(&map)
        return PadShortcutReader(map: map)
    }

    /// L1 acts the moment it goes down: it means nothing held.
    func testAPlainButtonActsAtOnce() {
        var pad = reader()
        XCTAssertEqual(pad.update([.l1], at: 0), [.press(.previousSection)])
        XCTAssertFalse(pad.waiting)
        XCTAssertEqual(pad.update([], at: 0.1), [])
    }

    /// PS waits: let go soon it is a press, held it is the hold.
    func testPSIsAPressWhenLetGoSoon() {
        var pad = reader()
        XCTAssertEqual(pad.update([.guide], at: 0), [])
        XCTAssertTrue(pad.waiting)
        XCTAssertEqual(pad.tick(at: 0.3), [])
        XCTAssertEqual(pad.update([], at: 0.35), [.press(.home)])
        XCTAssertFalse(pad.waiting)
    }

    func testPSHeldIsTheHold() {
        var pad = reader()
        _ = pad.update([.guide], at: 0)
        XCTAssertEqual(pad.due, LongPress.threshold)
        XCTAssertEqual(pad.tick(at: 0.6), [.hold(.home)])
        XCTAssertEqual(pad.tick(at: 1.0), [])
        XCTAssertEqual(pad.update([], at: 1.5), [])
    }

    /// Create: a press saves the clip, held it takes a screenshot.
    func testCreatePressedAndHeld() {
        var pad = reader()
        _ = pad.update([.select], at: 0)
        XCTAssertEqual(pad.update([], at: 0.2), [.press(.clip)])
        _ = pad.update([.select], at: 5)
        XCTAssertEqual(pad.tick(at: 5.7), [.hold(.screenshot)])
        XCTAssertEqual(pad.update([], at: 6), [])
    }

    /// The longest chord that completes wins, and takes over from a shorter one waiting in it.
    func testTheLongestChordWins() {
        var pad = reader { $0.setPad(PadChord([.guide, .west]), for: .quickMenu) }
        XCTAssertEqual(pad.update([.guide], at: 0), [])
        XCTAssertEqual(pad.update([.guide, .west], at: 0.1), [.press(.quickMenu)])
        // PS let go after is no press of its own.
        XCTAssertEqual(pad.update([.west], at: 0.2), [])
        XCTAssertEqual(pad.update([], at: 0.3), [])
        XCTAssertFalse(pad.waiting)
    }

    func testAChordPressedAtOnceIsOnlyTheChord() {
        var pad = reader { $0.setPad(PadChord([.l1, .r1]), for: .screenshot) }
        XCTAssertEqual(pad.update([.l1, .r1], at: 0), [.press(.screenshot)])
    }

    /// A chord whose first button acts on its own: that one acts first, the chord when it completes.
    func testAChordBuiltUpActsWhenItCompletes() {
        var pad = reader { $0.setPad(PadChord([.l1, .r1]), for: .screenshot) }
        XCTAssertEqual(pad.update([.l1], at: 0), [.press(.previousSection)])
        XCTAssertEqual(pad.update([.l1, .r1], at: 0.05), [.press(.screenshot)])
    }

    /// A chord held for an action of its own and no press: let go soon, nothing.
    func testAHoldOnlyChordLetGoSoonIsNothing() {
        var pad = reader { $0.setPad(PadChord([.l3, .r3], hold: true), for: .fullScreen) }
        XCTAssertEqual(pad.update([.l3, .r3], at: 0), [])
        XCTAssertEqual(pad.update([.l3], at: 0.2), [])
        _ = pad.update([.l3, .r3], at: 1)
        XCTAssertEqual(pad.tick(at: 1.6), [.hold(.fullScreen)])
    }

    /// Buttons that mean nothing say nothing; a binding in conflict is not read.
    func testOtherButtonsAndConflictsSayNothing() {
        var pad = reader { $0.setPad(PadChord([.select]), for: .screenshot) }
        XCTAssertEqual(pad.update([.south], at: 0), [])
        XCTAssertEqual(pad.update([.south, .select], at: 0.1), [])
        XCTAssertEqual(pad.update([.south], at: 0.2), [])
    }

    func testResetForgetsAWaitingPress() {
        var pad = reader()
        _ = pad.update([.guide], at: 0)
        pad.reset()
        XCTAssertFalse(pad.waiting)
        XCTAssertEqual(pad.update([], at: 0.2), [])
    }

    /// A late tick: the release still tells the hold.
    func testAReleaseAfterTheTimeIsTheHold() {
        var pad = reader()
        _ = pad.update([.guide], at: 0)
        XCTAssertEqual(pad.update([], at: 0.9), [.hold(.home)])
    }
}

final class ChordRecorderTests: XCTestCase {
    func testAQuickPressIsAPressedChord() {
        var recorder = ChordRecorder()
        XCTAssertNil(recorder.update([.l1], at: 0))
        XCTAssertNil(recorder.update([.l1, .r1], at: 0.05))
        XCTAssertNil(recorder.update([.r1], at: 0.2))
        XCTAssertEqual(recorder.update([], at: 0.25), PadChord([.l1, .r1]))
    }

    /// Held together long enough, the chord is a hold; the time counts from the last button down
    /// to the first let go.
    func testHeldTogetherIsAHold() {
        var recorder = ChordRecorder()
        _ = recorder.update([.l1], at: 0)
        _ = recorder.update([.l1, .west], at: 1)
        _ = recorder.update([.west], at: 1.6)
        XCTAssertEqual(recorder.update([], at: 3), PadChord([.l1, .west], hold: true))
    }

    /// One button held long before the other came, then let go soon: a press.
    func testLettingGoSoonAfterTheLastButtonIsAPress() {
        var recorder = ChordRecorder()
        _ = recorder.update([.l1], at: 0)
        _ = recorder.update([.l1, .west], at: 1)
        _ = recorder.update([.west], at: 1.3)
        XCTAssertEqual(recorder.update([], at: 3), PadChord([.l1, .west]))
    }

    func testOneButtonHeldIsAHold() {
        var recorder = ChordRecorder()
        _ = recorder.update([.select], at: 0)
        XCTAssertEqual(recorder.update([], at: 0.7), PadChord([.select], hold: true))
        // It starts over for the next chord.
        _ = recorder.update([.guide], at: 1)
        XCTAssertEqual(recorder.update([], at: 1.1), PadChord([.guide]))
    }
}
