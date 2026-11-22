import XCTest
@testable import AnyPS5Core

/// What the Auto Optimizer under test kept, logged and read the time from.
final class RetroAutoRecord {
    var memories: [String: RetroAutoMemory] = [:]
    var saves = 0
    var log: [String] = []
    var now: Duration = .zero
}

/// The Auto Optimizer of a PS1 game, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_auto_controller_test.dart), on a fake host whose statuses are the real
/// host's recorded Spyro the Dragon status with `gamePerformance`
/// (Fixtures/retro-host-performance-status.json, anyps5-retro-host
/// fixtures/v1/messages/call-status-performance.json), at the scale and speed each step needs, with
/// a clock moved by hand.
@MainActor
final class RetroAutoControllerTests: XCTestCase {
    private static let request = RetroHostStartRequest(core: "c", disc: "d.cue", system: "s", saves: "v")
    private static let titleID = "PS1-SCUS94228"

    private var session = FakeRetroHostSession()
    private var game: RetroHostGame!
    private var menu: RetroGameMenu!
    private var record = RetroAutoRecord()

    override func setUp() async throws {
        session = FakeRetroHostSession()
        session.reportsPerformance = true
        game = RetroHostGame(session: session, statusEvery: .seconds(3600), volume: 0.5)
        menu = RetroGameMenu(game: game, controls: nil)
        record = RetroAutoRecord()
    }

    override func tearDown() async throws {
        menu.dispose()
        game.dispose()
    }

    private func status(scale: Int = 2, speed: Double? = 1, work: Double = 0.08, gpu: String? = "RTX", pending: Bool = false,
                        ready: Bool = true) throws -> RetroStatus {
        var map = try RetroAutoResolutionTests.recorded("retro-host-performance-status.json")
        map["ready"] = .bool(ready)
        map["graphicsPending"] = .bool(pending)
        map["performance"] = speed.map { RetroAutoResolutionTests.performance($0, work) } ?? .null
        map["gpu"] = gpu.map { .object(["renderer": .string($0), "vendor": .string("v"), "maxTexture": .int(16384)]) } ?? .null
        let status = try RetroStatus.parse(.object(map), performance: true)
        return RetroGraphicsTests.edited(status, RetroResolution.ps1Key, selected: scale - 1, active: "\(scale)")
    }

    private func controller(need: Int = 5, every: Duration = RetroAutoRules.window) -> RetroAutoController {
        let record = self.record
        return RetroAutoController(
            menu: menu, titleID: Self.titleID, kept: { record.memories[Self.titleID] },
            saved: { memory in
                record.memories[Self.titleID] = memory
                record.saves += 1
            },
            need: { need }, log: { record.log.append($0) }, every: every, clock: { record.now })
    }

    private func started(_ first: RetroStatus) async {
        session.greet()
        session.nextStatus = first
        await game.start(Self.request)
    }

    /// Moves the clock to `milliseconds`, the host's next status to `next`, and judges it.
    private func at(_ auto: RetroAutoController, milliseconds: Int, _ next: RetroStatus) async {
        record.now = .milliseconds(milliseconds)
        session.nextStatus = next
        await game.refresh()
        await auto.tick()
    }

    /// `at(_:milliseconds:_:)` at a whole number of `seconds`.
    private func at(_ auto: RetroAutoController, _ seconds: Int, _ next: RetroStatus) async {
        await at(auto, milliseconds: seconds * 1000, next)
    }

    private var options: [RetroJSON] { session.calls.filter { $0.0 == "option" }.map(\.1) }

    private func option(_ value: String) -> RetroJSON {
        .object(["key": .string(RetroResolution.ps1Key), "value": .string(value)])
    }

    private var memory: RetroAutoMemory? { record.memories[Self.titleID] }

    func testASlowGameIsLoweredOneScaleAndTheSlowScaleIsRememberedForTheGame() async throws {
        try await started(status(scale: 4, speed: nil))
        session.callResults["option"] = .bool(true)
        let auto = controller()
        try await at(auto, 0, status(scale: 4, speed: nil))
        XCTAssertTrue(record.memories.isEmpty, "nothing measured yet")
        try await at(auto, 5, status(scale: 4))
        XCTAssertEqual(memory, RetroAutoMemory(gpu: "RTX", host: "1.2.0", config: "", scale: 4))
        try await at(auto, 20, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options, [], "one slow reading is not enough, and the first 20 seconds are not judged")
        try await at(auto, 25, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options, [option("3")])
        XCTAssertEqual(memory?.slow, [4])
        XCTAssertEqual(memory?.scale, 3)
        XCTAssertGreaterThanOrEqual(record.saves, 2)
        XCTAssertEqual(record.log, ["auto resolution: 4x to 3x for PS1-SCUS94228 (speed 0.6, work 1.5)"])

        try await at(auto, 30, status(scale: 3, pending: true))
        try await at(auto, 50, status(scale: 3, speed: 1))
        XCTAssertEqual(options.count, 1, "settling at 3x")
    }

    func testAMinuteOfHeadroomRaisesItOneScaleUpToWhatTheDisplayNeeds() async throws {
        try await started(status(scale: 2))
        session.callResults["option"] = .bool(true)
        let auto = controller(need: 3)
        for seconds in stride(from: 0, through: 75, by: 5) { try await at(auto, seconds, status(scale: 2)) }
        XCTAssertEqual(options, [option("3")])
        for seconds in stride(from: 80, through: 300, by: 5) { try await at(auto, seconds, status(scale: 3)) }
        XCTAssertEqual(options.count, 1, "4x is past a 720-line display")
    }

    func testARefusedChangeIsNotCountedAsMadeAndNothingIsJudgedWhileTheMenuIsOpen() async throws {
        try await started(status(scale: 4))
        session.callResults["option"] = .bool(false)
        let auto = controller()
        try await at(auto, 20, status(scale: 4, speed: 0.6, work: 1.5))
        try await at(auto, 25, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(memory?.scale, 4, "the host kept 4x")
        await menu.open()
        session.callResults["option"] = .bool(true)
        try await at(auto, 30, status(scale: 4, speed: 0.6, work: 1.5))
        try await at(auto, 35, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options.count, 1, "the menu is open: the game is paused")
    }

    func testAnotherGpuOrGraphicsSettingStartsTheMemoryAgainTheSameKeepsItsSlowScales() async throws {
        record.memories[Self.titleID] = RetroAutoMemory(gpu: "RTX", host: "1.2.0", config: "", scale: 4, slow: [6])
        try await started(status(scale: 4))
        let auto = controller(need: 8)
        try await at(auto, 0, status(scale: 4))
        XCTAssertEqual(memory?.slow, [6], "measured on this GPU and host")
        try await at(auto, 5, status(scale: 4, gpu: "Radeon"))
        XCTAssertEqual(memory?.slow, [], "another GPU: what was learned does not hold")
        XCTAssertEqual(memory?.gpu, "Radeon")
    }

    func testAGpuNotYetKnownNeverTakesTheMemoryTheOldCardsSlowScalesStayWithIt() async throws {
        record.memories[Self.titleID] = RetroAutoMemory(gpu: "RTX", host: "1.2.0", config: "", scale: 4, slow: [6])
        try await started(status(scale: 4, speed: nil, gpu: nil, ready: false))
        let auto = controller(need: 8)
        try await at(auto, 0, status(scale: 4, speed: nil, gpu: nil, ready: false))
        XCTAssertEqual(memory?.gpu, "RTX", "loading: the GPU is not known yet")
        try await at(auto, 3, status(scale: 4, gpu: nil))
        XCTAssertEqual(memory?.gpu, "RTX", "measured, but the GPU is not named yet")
        try await at(auto, 5, status(scale: 4, speed: nil, gpu: "Radeon"))
        XCTAssertEqual(memory?.gpu, "RTX", "not measured yet")
        try await at(auto, 10, status(scale: 4, gpu: "Radeon"))
        XCTAssertEqual(memory?.gpu, "Radeon")
        XCTAssertEqual(memory?.slow, [], "6x ran slow on the RTX, which says nothing of the Radeon")
    }

    func testATimersUnevenTicksKeepEveryReading5Point01Then4Point99SecondsApart() async throws {
        try await started(status(scale: 2))
        session.callResults["option"] = .bool(true)
        let auto = controller(need: 3)
        var now = 20000
        for reading in 0..<11 {
            try await at(auto, milliseconds: now, status(scale: 2))
            now += reading.isMultiple(of: 2) ? 5010 : 4990
        }
        XCTAssertEqual(options, [], "eleven readings of a minute of headroom")
        try await at(auto, milliseconds: now, status(scale: 2))
        XCTAssertEqual(options, [option("3")], "the twelfth, 55 seconds after the first: none was dropped")
    }

    func testTheMenuOpeningBreaksTheRunOfReadings() async throws {
        try await started(status(scale: 4))
        session.callResults["option"] = .bool(true)
        let auto = controller()
        try await at(auto, 20, status(scale: 4, speed: 0.6, work: 1.5))
        await menu.open()
        try await at(auto, 25, status(scale: 4, speed: nil))
        await menu.close()
        try await at(auto, 300, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options, [], "one slow reading before the pause and one after")
        try await at(auto, 305, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options.count, 1)
    }

    func testTheMenuOpeningBetweenTwoJudgementsBreaksTheRunOfReadingsToo() async throws {
        try await started(status(scale: 4))
        session.callResults["option"] = .bool(true)
        let auto = controller(every: .seconds(3600))
        auto.start()
        try await at(auto, 20, status(scale: 4, speed: 0.6, work: 1.5))
        await menu.open()
        await menu.close()
        try await at(auto, 300, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options, [], "no judgement saw the menu open, yet it broke the run")
        try await at(auto, 305, status(scale: 4, speed: 0.6, work: 1.5))
        XCTAssertEqual(options.count, 1)
        auto.dispose()
    }

    func testStoppingWaitsForAChangeAlreadyAskedAndDoesNotCountIt() async throws {
        try await started(status(scale: 4))
        session.callResults["option"] = .bool(true)
        let auto = controller()
        try await at(auto, 20, status(scale: 4, speed: 0.6, work: 1.5))
        record.now = .seconds(25)
        session.nextStatus = try status(scale: 4, speed: 0.6, work: 1.5)
        await game.refresh()
        let gate = RetroGate()
        session.callGate = gate
        let ticking = Task { await auto.tick() }
        await settleRetro({ session.methods.contains("option") })
        let stopped = RetroFlag()
        let stopping = Task {
            await auto.stop()
            stopped.set()
        }
        await yieldRetro()
        XCTAssertFalse(stopped.value, "the change asked is not answered yet")
        session.callGate = nil
        gate.open()
        await stopping.value
        await ticking.value
        XCTAssertEqual(memory?.scale, 4, "stopped: the change is not counted")
        XCTAssertEqual(record.log, [])
    }

    func testAHostWithoutGamePerformanceIsNotJudged() async throws {
        session.reportsPerformance = false
        try await started(status(scale: 4))
        let auto = controller()
        try await at(auto, 20, status(scale: 4, speed: 0.5, work: 1.5))
        try await at(auto, 25, status(scale: 4, speed: 0.5, work: 1.5))
        XCTAssertEqual(options, [])
        XCTAssertTrue(record.memories.isEmpty)
    }
}
