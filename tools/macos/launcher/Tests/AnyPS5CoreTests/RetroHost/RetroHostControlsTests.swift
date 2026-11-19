import XCTest
@testable import AnyPS5Core

/// The launcher's controllers playing a game in the host, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_host_controls_test.dart).
@MainActor
final class RetroHostControlsTests: XCTestCase {
    private struct Rig {
        let session: FakeRetroHostSession
        let game: RetroHostGame
        let pads: FakePads
        let motors: FakeMotors
        var controls: RetroHostControls
    }

    private var rigs: [(RetroHostGame, () -> RetroHostControls)] = []

    override func tearDown() async throws {
        for (game, controls) in rigs {
            controls().dispose()
            game.dispose()
        }
        rigs = []
    }

    private let hold = Duration.seconds(7200)

    private func makeRig(keyboard: (() -> PadState)? = nil) -> Rig {
        let session = FakeRetroHostSession()
        let game = RetroHostGame(session: session, statusEvery: .seconds(3600))
        let pads = FakePads(), motors = FakeMotors()
        let controls = RetroHostControls(game: game, pads: pads.reader, motors: motors, keyboard: keyboard, rumbleHold: hold, polls: false)
        rigs.append((game, { controls }))
        return Rig(session: session, game: game, pads: pads, motors: motors, controls: controls)
    }

    private func started(_ rig: Rig) async {
        rig.session.greet()
        rig.session.nextStatus = fakeStatus()
        rig.session.callResults["connectedPorts"] = .bool(true)
        await rig.game.start(RetroHostStartRequest(core: "c", disc: "d.cue", system: "s", saves: "v"))
    }

    private func sent(_ rig: Rig, port: Int? = nil) -> [RetroPadInput] {
        rig.session.inputs.filter { port == nil || $0.0 == port }.map(\.1)
    }

    private func ports(_ rig: Rig) -> [RetroJSON] {
        rig.session.calls.filter { $0.0 == "connectedPorts" }.map(\.1)
    }

    private let cross = RetroPadButton.cross.mask

    func testNothingIsSentBeforeAGameIsLoaded() {
        let rig = makeRig()
        rig.pads.connect("a", PadState(pressed: [.south]))
        rig.controls.poll()
        XCTAssertTrue(rig.session.inputs.isEmpty)
        XCTAssertTrue(rig.session.calls.isEmpty)
    }

    func testASeatedControllersStateIsSentForItsPortOnceThenOnEachChange() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a", PadState(pressed: [.south], leftY: -1))
        rig.controls.poll()
        rig.controls.poll()
        rig.pads.states["a"] = PadState(pressed: [.start])
        rig.controls.poll()
        XCTAssertEqual(rig.session.inputs.map(\.0), [0, 1, 0])
        XCTAssertEqual(sent(rig), [RetroPadInput(buttons: cross, leftY: -32768), .idle, RetroPadInput(buttons: RetroPadButton.start.mask)])
    }

    func testTheKeyboardPlaysAtPort1AndIsKeptOutByTheMenu() async {
        var keys = PadState.idle
        let rig = makeRig(keyboard: { keys })
        await started(rig)
        keys = PadState(pressed: [.south], leftX: 1)
        rig.controls.poll()
        rig.pads.connect("a", PadState(pressed: [.east], leftY: 1))
        rig.pads.connect("b", PadState(pressed: [.west]))
        rig.controls.poll()
        rig.controls.suspended = true
        rig.controls.suspended = false
        keys = .idle
        rig.controls.poll()
        XCTAssertEqual(rig.session.inputs.map(\.0), [0, 1, 0, 1, 0, 1, 0, 0])
        XCTAssertEqual(sent(rig), [
            RetroPadInput(buttons: cross, leftX: 32767), .idle,
            RetroPadInput(buttons: cross | RetroPadButton.circle.mask, leftX: 32767), RetroPadInput(buttons: RetroPadButton.square.mask),
            .idle, .idle,
            RetroPadInput(leftX: 32767), RetroPadInput(leftY: 32767),
        ], "keys held when the menu closes stay out until let go; the sticks come back at once")
    }

    func testASecondControllerConnectsPort2AndPort2IsLetGoWhenItLeaves() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.controls.poll()
        rig.pads.connect("b", PadState(pressed: [.east]))
        rig.controls.poll()
        await yieldRetro()
        XCTAssertEqual(ports(rig), [.int(2)])
        XCTAssertEqual(sent(rig, port: 1).last, RetroPadInput(buttons: RetroPadButton.circle.mask))
        rig.pads.disconnect("b")
        rig.controls.poll()
        await yieldRetro()
        XCTAssertEqual(ports(rig), [.int(2), .int(1)])
        XCTAssertEqual(sent(rig, port: 1).last, .idle)
    }

    func testAConnectedPortsTheHostDidNotTakeIsAskedAgain() async {
        let rig = makeRig()
        await started(rig)
        rig.session.callResults["connectedPorts"] = .bool(false)
        rig.pads.connect("a")
        rig.pads.connect("b")
        rig.controls.poll()
        rig.controls.poll()
        await yieldRetro()
        XCTAssertEqual(ports(rig), [.int(2)], "not asked again while the call waits")
        rig.session.callResults["connectedPorts"] = .bool(true)
        rig.controls.poll()
        await yieldRetro()
        XCTAssertEqual(ports(rig), [.int(2), .int(2)])
        rig.controls.poll()
        await yieldRetro()
        XCTAssertEqual(ports(rig).count, 2, "taken: not asked again")
    }

    func testAGameStartedWithTwoControllersConnectsPort2AsSoonAsItLoads() async {
        let rig = makeRig()
        rig.pads.connect("a")
        rig.pads.connect("b")
        rig.controls.poll()
        XCTAssertTrue(rig.session.calls.isEmpty)
        await started(rig)
        rig.controls.poll()
        await yieldRetro()
        XCTAssertEqual(ports(rig), [.int(2)])
    }

    func testAfterFocusComesBackEveryPortIsSentAgain() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a", PadState(pressed: [.north]))
        rig.controls.poll()
        await rig.game.setFocused(false)
        rig.controls.poll()
        XCTAssertEqual(rig.session.inputs.count, 2)
        await rig.game.setFocused(true)
        rig.controls.poll()
        XCTAssertEqual(Array(sent(rig).dropFirst(2)), [RetroPadInput(buttons: RetroPadButton.triangle.mask), .idle])
    }

    func testFocusLostAndBackBetweenTwoReadsStillSendsTheHeldStateAgain() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a", PadState(pressed: [.south]))
        rig.controls.poll()
        await rig.game.setFocused(false)
        await rig.game.setFocused(true)
        rig.controls.poll()
        XCTAssertEqual(Array(sent(rig).dropFirst(2)), [RetroPadInput(buttons: cross), .idle])
    }

    func testAButtonHeldWhenTheSuspensionEndsReachesTheGameOnlyOncePressedAgain() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.controls.poll()
        rig.controls.suspended = true
        rig.pads.states["a"] = PadState(pressed: [.south], leftX: 1)
        rig.controls.suspended = false
        XCTAssertEqual(sent(rig, port: 0).last, RetroPadInput(leftX: 32767))
        rig.pads.states["a"] = PadState(pressed: [.south, .east])
        rig.controls.poll()
        XCTAssertEqual(sent(rig, port: 0).last, RetroPadInput(buttons: RetroPadButton.circle.mask))
        rig.pads.states["a"] = .idle
        rig.controls.poll()
        rig.pads.states["a"] = PadState(pressed: [.south])
        rig.controls.poll()
        XCTAssertEqual(sent(rig, port: 0).last, RetroPadInput(buttons: cross))
    }

    func testWhileSuspendedBothPortsAreIdleAndAfterItTheSticksComeBackAtOnce() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a", PadState(pressed: [.l1], leftY: -1))
        rig.controls.poll()
        rig.controls.suspended = true
        XCTAssertEqual(sent(rig, port: 0).last, .idle)
        rig.controls.suspended = false
        XCTAssertEqual(sent(rig, port: 0).last, RetroPadInput(leftY: -32768))
    }

    func testRumbleGoesToTheControllerAtItsPortWhenItCanVibrate() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.pads.connect("b")
        rig.motors.vibrating.insert("b")
        rig.controls.poll()
        rig.session.sendRumble(0, 0xFFFF, 0)
        rig.session.sendRumble(1, 0xFFFF, 0x8000)
        rig.session.sendRumble(1, 0, 0)
        await settleRetro({ rig.motors.orders.count == 2 })
        XCTAssertEqual(rig.motors.orders.map(\.pad), ["b", "b"])
        XCTAssertEqual(rig.motors.orders.map(\.strong), [1, 0])
        XCTAssertEqual(rig.motors.orders.map(\.weak), [Double(0x8000) / 0xFFFF, 0])
        XCTAssertEqual(rig.motors.orders.map(\.hold), [hold, .zero])
    }

    func testAControllerThatLeavesItsPortHasItsMotorsStopped() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.pads.connect("b")
        rig.motors.vibrating.formUnion(["a", "b"])
        rig.controls.poll()
        rig.session.sendRumble(1, 0, 0xFFFF)
        await settleRetro({ rig.motors.orders.count == 1 })
        rig.motors.orders = []
        rig.pads.disconnect("b")
        rig.pads.connect("c")
        rig.motors.vibrating.insert("c")
        rig.controls.poll()
        XCTAssertEqual(rig.motors.orders.map(\.pad), ["b"])
        XCTAssertEqual(rig.motors.orders.first?.hold, .zero)
        XCTAssertEqual(rig.controls.seats.at(1), "c")
    }

    func testTurningVibrationOffStopsTheMotorsAndKeepsLaterRumbleAway() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.motors.vibrating.insert("a")
        rig.controls.poll()
        rig.session.sendRumble(0, 0xFFFF, 0)
        await settleRetro({ rig.motors.orders.count == 1 })
        rig.controls.vibration = false
        rig.session.sendRumble(0, 0x4000, 0)
        await yieldRetro()
        XCTAssertEqual(rig.motors.orders.map(\.strong), [1, 0])
        XCTAssertEqual(rig.motors.orders.map(\.hold), [hold, .zero])
    }

    func testAControllerThatSatDownHoldingAButtonJustBeforeTheSuspensionEndsIsKeptOutToo() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.controls.poll()
        rig.controls.suspended = true
        rig.pads.disconnect("a")
        rig.pads.connect("b", PadState(pressed: [.south]))
        rig.controls.suspended = false
        XCTAssertEqual(rig.controls.seats.at(0), "b")
        XCTAssertEqual(sent(rig, port: 0).last, .idle)
    }

    func testAHeldButtonLetGoAndPressedAgainWhileTheWindowHasNoFocusReachesTheGame() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.controls.poll()
        rig.controls.suspended = true
        rig.pads.states["a"] = PadState(pressed: [.south])
        rig.controls.suspended = false
        await rig.game.setFocused(false)
        rig.pads.states["a"] = .idle
        rig.controls.poll()
        rig.pads.states["a"] = PadState(pressed: [.south])
        rig.controls.poll()
        await rig.game.setFocused(true)
        rig.controls.poll()
        XCTAssertEqual(sent(rig, port: 0).last, RetroPadInput(buttons: cross))
    }

    func testShuttingTheHostDownStopsAMotorTheGameLeftRunning() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.motors.vibrating.insert("a")
        rig.controls.poll()
        rig.session.sendRumble(0, 0xFFFF, 0)
        await settleRetro({ rig.motors.orders.count == 1 })
        await rig.game.shutdown()
        XCTAssertEqual(rig.motors.orders.last?.strong, 0)
        XCTAssertEqual(rig.motors.orders.last?.hold, .zero)
        let count = rig.motors.orders.count
        rig.session.sendRumble(0, 0xFFFF, 0)
        await yieldRetro()
        XCTAssertEqual(rig.motors.orders.count, count, "a late rumble starts nothing")
    }

    func testDisposeLetsGoOfWhatTheControllersHeldInAGameThatGoesOn() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a", PadState(pressed: [.south], leftX: 1))
        rig.controls.poll()
        rig.controls.dispose()
        XCTAssertEqual(sent(rig, port: 0).last, .idle)
    }

    func testRumbleThatComesAsOneControllerTakesThePortOfAnotherGoesToTheNewOne() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.pads.connect("b")
        rig.pads.connect("c")
        rig.motors.vibrating.formUnion(["a", "b", "c"])
        rig.controls.poll()
        rig.pads.disconnect("a")
        rig.session.sendRumble(0, 0xFFFF, 0)
        await settleRetro({ !rig.motors.orders.isEmpty })
        XCTAssertEqual(rig.controls.seats.at(0), "c")
        XCTAssertEqual(rig.motors.orders.map(\.pad), ["c"])
        XCTAssertEqual(rig.motors.orders.map(\.strong), [1])
    }

    func testControlsMadeForAGameAlreadyLoadedTellTheHostHowManyPortsAreConnected() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.pads.connect("b")
        rig.controls.poll()
        await yieldRetro()
        rig.controls.dispose()
        rig.pads.disconnect("b")
        let again = RetroHostControls(game: rig.game, pads: rig.pads.reader, polls: false)
        again.poll()
        await yieldRetro()
        again.dispose()
        XCTAssertEqual(ports(rig), [.int(2), .int(1)])
    }

    func testDisposeStopsAMotorTheGameLeftRunning() async {
        let rig = makeRig()
        await started(rig)
        rig.pads.connect("a")
        rig.motors.vibrating.insert("a")
        rig.controls.poll()
        rig.session.sendRumble(0, 0xFFFF, 0)
        await settleRetro({ rig.motors.orders.count == 1 })
        rig.controls.dispose()
        XCTAssertEqual(rig.motors.orders.last?.strong, 0)
        rig.session.sendRumble(0, 0xFFFF, 0)
        await yieldRetro()
        XCTAssertEqual(rig.motors.orders.count, 2)
    }
}
