import XCTest
@testable import AnyPS5Core

/// Preparing new games in the background, like a console installing: one at a time, only while
/// nothing else needs the Mac, never on a low battery or a drive without the room.
final class PrepareQueueTests: XCTestCase {
    let noShortage: (String) -> SpaceShortage? = { _ in nil }

    /// Every action until the queue has nothing more to do.
    func drain(_ queue: inout PrepareQueue, _ conditions: PrepareConditions, shortage: ((String) -> SpaceShortage?)? = nil) -> [PrepareQueue.Action] {
        var actions: [PrepareQueue.Action] = []
        while true {
            let action = queue.step(conditions, shortage: shortage ?? noShortage)
            if action == .none { return actions }
            actions.append(action)
            if actions.count > 20 { XCTFail("the queue does not settle"); return actions }
        }
    }

    func testANewGameIsPreparedAtOnceWhenNothingElseHappens() {
        var queue = PrepareQueue()
        queue.add(["a"])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        XCTAssertEqual(queue.active, "a")
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testGamesArePreparedOneAtATimeInTheOrderTheyCame() {
        var queue = PrepareQueue()
        queue.add(["a", "b"])
        queue.add(["a", "c"])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        XCTAssertEqual(queue.pending, ["b", "c"])
        queue.finished("a")
        XCTAssertEqual(drain(&queue, .idle), [.start("b")])
        queue.finished("b")
        XCTAssertEqual(drain(&queue, .idle), [.start("c")])
        queue.finished("c")
        XCTAssertEqual(drain(&queue, .idle), [])
        XCTAssertNil(queue.active)
    }

    /// A game playing gets the whole Mac: nothing starts, and a preparation already going stops
    /// where it is until the game closes.
    func testAGameRunningHoldsTheQueueAndPausesThePreparation() {
        var queue = PrepareQueue()
        queue.add(["a"])
        var playing = PrepareConditions.idle
        playing.playing = true
        XCTAssertEqual(drain(&queue, playing), [])
        XCTAssertNil(queue.active)
        XCTAssertEqual(queue.pending, ["a"], "waits, not skipped")
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        XCTAssertEqual(drain(&queue, playing), [.pause])
        XCTAssertTrue(queue.paused)
        XCTAssertEqual(drain(&queue, playing), [], "paused once")
        XCTAssertEqual(drain(&queue, .idle), [.resume])
        XCTAssertFalse(queue.paused)
    }

    /// The user's own unlocks come first: the queue waits for them, and a preparation going on
    /// stops for them.
    func testTheUsersOwnUnlocksComeFirst() {
        var queue = PrepareQueue()
        queue.add(["a", "b"])
        var unlocking = PrepareConditions.idle
        unlocking.unlocking = true
        XCTAssertEqual(drain(&queue, unlocking), [])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        XCTAssertEqual(drain(&queue, unlocking), [.pause])
        XCTAssertEqual(drain(&queue, .idle), [.resume])
    }

    /// Play on a game being prepared makes it the user's own: it no longer stops for their other
    /// unlocks.
    func testAPromotedPreparationDoesNotStopForTheUsersUnlocks() {
        var queue = PrepareQueue()
        queue.add(["a"])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        var unlocking = PrepareConditions.idle
        unlocking.unlocking = true
        XCTAssertEqual(drain(&queue, unlocking), [.pause])
        queue.promote("a")
        XCTAssertTrue(queue.promoted)
        XCTAssertEqual(drain(&queue, unlocking), [.resume])
        queue.finished("a")
        XCTAssertFalse(queue.promoted)
    }

    func testOnALowBatteryNewGamesAreSkipped() {
        var queue = PrepareQueue()
        queue.add(["a", "b"])
        var battery = PrepareConditions.idle
        battery.power = PowerState(onBattery: true, level: 22)
        XCTAssertEqual(drain(&queue, battery), [.skip("a", .battery(22)), .skip("b", .battery(22))])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertNil(queue.active)
    }

    func testPluggedInOrAFullEnoughBatteryGoesAhead() {
        var queue = PrepareQueue()
        queue.add(["a"])
        var battery = PrepareConditions.idle
        battery.power = PowerState(onBattery: true, level: 30)
        XCTAssertEqual(drain(&queue, battery), [.start("a")], "30% is enough")
        queue.finished("a")
        queue.add(["b"])
        battery.power = PowerState(onBattery: false, level: 5)
        XCTAssertEqual(drain(&queue, battery), [.start("b")], "charging at 5% is fine")
    }

    func testABatteryThatDoesNotSayItsLevelCountsAsLow() {
        XCTAssertTrue(PowerState(onBattery: true, level: nil).low)
        XCTAssertFalse(PowerState.mains.low)
    }

    /// Unplugged below the line while preparing: it stops until the Mac is plugged in.
    func testALowBatteryPausesAPreparationGoingOn() {
        var queue = PrepareQueue()
        queue.add(["a"])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        var battery = PrepareConditions.idle
        battery.power = PowerState(onBattery: true, level: 10)
        XCTAssertEqual(drain(&queue, battery), [.pause])
        XCTAssertEqual(drain(&queue, .idle), [.resume])
    }

    func testAGameWithoutTheRoomIsSkippedWithTheShortage() {
        var queue = PrepareQueue()
        queue.add(["big", "small"])
        let shortage = SpaceShortage(needed: 10 << 30, free: 2 << 30, volume: "Games", copying: false)
        let actions = drain(&queue, .idle) { $0 == "big" ? shortage : nil }
        XCTAssertEqual(actions, [.skip("big", .space(shortage)), .start("small")])
        XCTAssertEqual(queue.active, "small")
    }

    func testCancelTakesAGameOutOfTheQueue() {
        var queue = PrepareQueue()
        queue.add(["a", "b", "c"])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        XCTAssertFalse(queue.cancel("b") , "b was only waiting")
        XCTAssertEqual(queue.pending, ["c"])
        XCTAssertTrue(queue.cancel("a"), "a is being prepared: its installer must be stopped")
        XCTAssertEqual(queue.active, "a", "until the installer says it stopped")
        queue.finished("a")
        XCTAssertEqual(drain(&queue, .idle), [.start("c")])
    }

    /// Turned off in Settings: nothing more starts; what is going on finishes.
    func testTurnedOffNothingMoreStarts() {
        var queue = PrepareQueue()
        queue.add(["a", "b"])
        XCTAssertEqual(drain(&queue, .idle), [.start("a")])
        var off = PrepareConditions.idle
        off.enabled = false
        XCTAssertEqual(drain(&queue, off), [])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertEqual(queue.active, "a")
    }

    func testAGameAlreadyBeingPreparedIsNotQueuedAgain() {
        var queue = PrepareQueue()
        queue.add(["a"])
        _ = drain(&queue, .idle)
        queue.add(["a"])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(queue.contains("a"))
    }
}
