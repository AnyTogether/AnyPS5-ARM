import XCTest
@testable import AnyPS5Core

/// One game in one host, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_host_game_test.dart), against a fake session: no host is started.
@MainActor
final class RetroHostGameTests: XCTestCase {
    static let request = RetroHostStartRequest(core: "/cores/swanstation_libretro.dylib", disc: "/games/FF7.m3u", system: "/retro/system",
                                               saves: "/retro/saves/ps1", options: ["swanstation_GPU_ResolutionScale": "4"], initialDisc: 1)

    /// The `status` example of anyps5-retro-host docs/protocol.md "status".
    static let protocolStatus = #"{"ready":true,"ended":false,"error":"","errorCode":"","aspect":1.3333333333333333,"hardware":true,"#
        + #""resolutionError":"","graphicsPending":false,"progressLabel":null,"progressPercent":null,"#
        + #""options":{"swanstation_GPU_ResolutionScale":{"title":"Internal Resolution","values":["1","2","4"],"#
        + #""labels":["1x","2x","4x"],"selected":2,"activeValue":"4","restart":false}},"#
        + #""discs":{"labels":["Disc 1","Disc 2"],"inserted":0,"insertedDiscPath":"/Games/PS1/FF7/FF7 (Disc 1).cue","#
        + #""playedDiscPath":"/Games/PS1/FF7/FF7 (Disc 1).cue","busy":false,"failed":false}}"#

    static func parsed(_ text: String = protocolStatus) throws -> RetroStatus {
        try RetroStatus.parse(try RetroJSON.parse(Array(text.utf8)))
    }

    private var games: [RetroHostGame] = []

    override func tearDown() async throws {
        for game in games { game.dispose() }
        games = []
    }

    private func made(_ session: FakeRetroHostSession = FakeRetroHostSession()) -> (FakeRetroHostSession, RetroHostGame) {
        let game = RetroHostGame(session: session, statusEvery: .seconds(3600))
        games.append(game)
        return (session, game)
    }

    private func started(_ status: RetroStatus? = nil) async -> (FakeRetroHostSession, RetroHostGame) {
        let (session, game) = made()
        session.greet()
        session.nextStatus = status ?? fakeStatus(ready: false)
        await game.start(Self.request)
        return (session, game)
    }

    // MARK: Starting and following

    func testStartWaitsForTheGreetingThenSendsTheProtocolsStartArgument() async throws {
        let (session, game) = made()
        let starting = Task { await game.start(Self.request) }
        await yieldRetro()
        XCTAssertEqual(game.phase, .starting)
        XCTAssertNil(session.startArgs)
        session.nextStatus = fakeStatus(ready: false)
        session.greet()
        await starting.value
        XCTAssertEqual(session.startArgs, .object([
            "core": .string("/cores/swanstation_libretro.dylib"), "disc": .string("/games/FF7.m3u"), "system": .string("/retro/system"),
            "saves": .string("/retro/saves/ps1"), "options": .object(["swanstation_GPU_ResolutionScale": .string("4")]),
            "initialDisc": .int(1),
        ]))
        XCTAssertEqual(game.phase, .loading)
    }

    func testARequestWithoutOptionsOrAPlaylistEntryLeavesBothOut() {
        let plain = RetroHostStartRequest(core: "c", disc: "d.cue", system: "s", saves: "v")
        XCTAssertEqual(plain.args, .object(["core": .string("c"), "disc": .string("d.cue"), "system": .string("s"), "saves": .string("v")]))
        var ps2 = plain
        ps2.console = RetroConsole.ps2
        XCTAssertEqual(ps2.args.objectValue?["console"], .string("ps2"))
    }

    func testAReadyStatusStartsPlayAndItsAspectRatioIsKept() async throws {
        let (session, game) = await started()
        session.nextStatus = try Self.parsed()
        await game.refresh()
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.aspect, 4.0 / 3.0, accuracy: 1e-12)
        session.nextStatus = fakeStatus(aspect: 1.5)
        await game.refresh()
        XCTAssertEqual(game.aspect, 1.5)
    }

    func testTheSameStatusAskedAgainTellsNoOneAndOneThatSaysSomethingNewDoes() async throws {
        let (session, game) = await started()
        session.nextStatus = try Self.parsed()
        await game.refresh()
        var heard = 0
        game.addListener { heard += 1 }
        for _ in 0..<3 {
            session.nextStatus = try Self.parsed()
            await game.refresh()
        }
        XCTAssertEqual(heard, 0, "a game that plays on with the same status changes nothing")
        session.nextStatus = try Self.parsed(Self.protocolStatus.replacingOccurrences(of: #""busy":false"#, with: #""busy":true"#))
        await game.refresh()
        XCTAssertEqual(heard, 1)
        session.nextStatus = fakeStatus(aspect: 1.5)
        await game.refresh()
        XCTAssertEqual(heard, 2)
        await game.refresh()
        XCTAssertEqual(heard, 2)
    }

    func testALoadingGameWithTheSameStatusTellsNoOneUntilItIsReady() async {
        let (session, game) = await started(fakeStatus(ready: false))
        var heard = 0
        game.addListener { heard += 1 }
        await game.refresh()
        await game.refresh()
        XCTAssertEqual(heard, 0)
        session.nextStatus = fakeStatus()
        await game.refresh()
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(heard, 1)
    }

    // MARK: Input and focus

    func testInputReachesTheHostOnlyWhileAGameIsLoadedAndTheWindowHasFocus() async {
        let (session, game) = made()
        game.input(port: 0, buttons: 1)
        session.greet()
        session.nextStatus = fakeStatus()
        await game.start(Self.request)
        game.input(port: 0, buttons: 8)
        await game.setFocused(false)
        game.input(port: 1, buttons: 4)
        await game.setFocused(true)
        game.input(port: 1, buttons: 2)
        XCTAssertEqual(session.inputs.map { [$0.0, $0.1.buttons] }, [[0, 8], [1, 2]])
    }

    func testLosingFocusPausesTheGameAndGettingItBackResumes() async {
        let (session, game) = await started(fakeStatus())
        await game.setFocused(false)
        XCTAssertEqual(session.focusChanges, [false])
        XCTAssertTrue(game.paused)
        await game.setFocused(true)
        XCTAssertEqual(session.focusChanges, [false, true])
        XCTAssertFalse(game.paused)
        XCTAssertEqual(session.calls.map(\.0), ["pause", "pause"])
        XCTAssertEqual(session.calls.map(\.1), [.bool(true), .bool(false)])
    }

    func testAGameThePlayerPausedStaysPausedWhenFocusComesBack() async {
        let (session, game) = await started(fakeStatus())
        await game.pause(true)
        await game.setFocused(false)
        await game.setFocused(true)
        XCTAssertTrue(game.paused)
        XCTAssertEqual(session.calls.map(\.1), [.bool(true)])
        await game.pause(false)
        XCTAssertEqual(session.calls.map(\.1), [.bool(true), .bool(false)])
    }

    func testAGameStartedWithoutFocusIsPausedAsSoonAsItLoads() async {
        let (session, game) = made()
        await game.setFocused(false)
        session.greet()
        session.nextStatus = fakeStatus(ready: false)
        await game.start(Self.request)
        XCTAssertEqual(session.methods, ["pause"])
        XCTAssertTrue(game.paused)
    }

    // MARK: Ends

    func testAnEndedStatusEndsTheGameAndKeepsWhy() async {
        let (session, game) = await started(fakeStatus())
        session.nextStatus = fakeStatus(ended: true, errorCode: RetroErrorCode.bios)
        await game.refresh()
        XCTAssertEqual(game.phase, .ended)
        XCTAssertEqual(game.endStatus?.errorCode, RetroErrorCode.bios)
        XCTAssertNil(game.picture.image)
    }

    func testARefusedStartEndsTheGameWithTheReason() async {
        let (session, game) = made()
        session.startError = RetroCallError(code: RetroCallError.busy, message: "A game is loaded.")
        session.greet()
        await game.start(Self.request)
        XCTAssertEqual(game.phase, .ended)
        XCTAssertTrue(game.failure?.contains("busy") == true, game.failure ?? "")
    }

    func testAHostThatNeverGreetsEndsTheGame() async {
        let (session, game) = made()
        session.greet(false)
        session.end(.hostFailure)
        await game.start(Self.request)
        XCTAssertEqual(game.phase, .ended)
        XCTAssertNil(session.startArgs)
    }

    func testAPs2GameIsNeverSentToAHostWithoutPs2() async {
        let (session, game) = made()
        session.canPlayPs2 = false
        session.greet()
        var request = Self.request
        request.console = RetroConsole.ps2
        request.initialDisc = nil
        await game.start(request)
        XCTAssertEqual(game.phase, .ended)
        XCTAssertTrue(game.consoleRefused)
        XCTAssertNil(session.startArgs)
    }

    func testAHostFailureWhilePlayingShowsTheClientsFailureReport() async {
        let (session, game) = await started(fakeStatus())
        session.nextStatus = .failed(error: "The emulator closed unexpectedly.", errorCode: RetroErrorCode.hostExited)
        session.end(.hostFailure)
        await settleRetro({ game.phase == .ended })
        XCTAssertEqual(game.endStatus?.errorCode, RetroErrorCode.hostExited)
        XCTAssertEqual(game.hostEnd, .hostFailure)
    }

    func testStopWhileWaitingForTheGreetingCancelsTheGameBeforeStartIsSent() async {
        let (session, game) = made()
        let starting = Task { await game.start(Self.request) }
        await yieldRetro()
        let stopping = Task { await game.stop() }
        await yieldRetro()
        session.greet()
        await starting.value
        _ = await stopping.value
        XCTAssertNil(session.startArgs)
        XCTAssertTrue(session.calls.isEmpty)
        XCTAssertEqual(game.phase, .ended)
    }

    func testStopWhileStartWaitsForItsReplyStopsTheGameTheHostThenStarts() async {
        let (session, game) = made()
        let gate = RetroGate()
        session.startGate = gate
        session.greet()
        let starting = Task { await game.start(Self.request) }
        await settleRetro({ session.startArgs != nil })
        let stopping = Task { await game.stop() }
        await yieldRetro()
        gate.open()
        await starting.value
        _ = await stopping.value
        XCTAssertEqual(session.methods, ["stop", "release"])
        XCTAssertEqual(game.phase, .ended)
    }

    func testFramesThatComeAfterTheGameEndedOrDuringShutdownAreNotShown() async {
        let slot = FakeSlot(1, 1)
        slot.fill([1, 2, 3, 255])
        let (session, game) = await started(fakeStatus())
        session.send(slot.pin())
        await settleRetro({ game.picture.image != nil }, "a frame of the game is shown")
        session.nextStatus = fakeStatus(ended: true)
        await game.refresh()
        XCTAssertNil(game.picture.image)
        session.send(slot.pin())
        await yieldRetro()
        XCTAssertNil(game.picture.image)
        await game.shutdown()
        session.send(slot.pin())
        await yieldRetro()
        XCTAssertNil(game.picture.image)
    }

    func testFocusChangesAfterShutdownOrAHostFailureDoNotReachTheClosedSession() async {
        let (session, game) = await started(fakeStatus())
        await game.shutdown()
        await game.setFocused(false)
        XCTAssertFalse(game.focused)
        XCTAssertTrue(session.focusChanges.isEmpty)

        let (failed, other) = made()
        failed.greet()
        failed.nextStatus = fakeStatus()
        await other.start(Self.request)
        failed.nextStatus = .failed(error: "gone", errorCode: RetroErrorCode.hostExited)
        failed.end(.hostFailure)
        await settleRetro({ other.phase == .ended })
        await other.setFocused(false)
        XCTAssertTrue(failed.focusChanges.isEmpty)
    }

    func testStopStopsTheGameReleasesItAndGivesTheStatusItEndedWith() async {
        let (session, game) = await started(fakeStatus())
        let ended = await game.stop()
        XCTAssertEqual(ended?.ended, true)
        XCTAssertEqual(session.methods, ["stop", "release"])
        XCTAssertEqual(game.phase, .ended)
    }

    func testShutdownAsksTheHostToExitAndFreesTheConnectionOnceItHas() async {
        let (session, game) = await started(fakeStatus())
        async let first: Void = game.shutdown()
        async let second: Void = game.shutdown()
        _ = await (first, second)
        XCTAssertTrue(session.shutdownAsked)
        XCTAssertTrue(session.closed)
        XCTAssertEqual(game.phase, .closed)
        game.input(port: 0, buttons: 1)
        XCTAssertTrue(session.inputs.isEmpty)
    }

    func testDisposeShutsTheHostDown() async {
        let (session, game) = await started(fakeStatus())
        game.dispose()
        await settleRetro({ session.closed })
        XCTAssertTrue(session.shutdownAsked)
    }

    // MARK: Detach

    func testDetachLeavesTheHostRunningForTheNextGame() async {
        let (session, game) = await started(fakeStatus())
        await game.setFocused(false)
        session.clearFocusChanges()
        async let first = game.detach()
        async let second = game.detach()
        let answers = await (first, second)
        XCTAssertTrue(answers.0)
        XCTAssertTrue(answers.1)
        XCTAssertEqual(Array(session.methods.filter { $0 == "stop" || $0 == "release" }.prefix(2)), ["stop", "release"])
        XCTAssertFalse(session.shutdownAsked)
        XCTAssertFalse(session.closed)
        XCTAssertEqual(game.phase, .closed)
        XCTAssertEqual(session.focusChanges, [true], "the next game starts with focus, as a new host does")
        game.input(port: 0, buttons: 1)
        XCTAssertTrue(session.inputs.isEmpty, "a detached game sends nothing")
        game.dispose()
        await yieldRetro()
        XCTAssertFalse(session.shutdownAsked, "the host is no longer the game's")

        let (_, next) = made(session)
        session.nextStatus = fakeStatus()
        await next.start(Self.request)
        XCTAssertEqual(next.phase, .playing)
        next.dispose()
        await settleRetro({ session.shutdownAsked })
    }

    func testDetachReleasesAGameThatEndedOnItsOwn() async {
        let (session, game) = await started(fakeStatus())
        session.nextStatus = fakeStatus(ended: true, errorCode: RetroErrorCode.stalled)
        await game.refresh()
        XCTAssertEqual(game.phase, .ended)
        session.clearCalls()
        let free = await game.detach()
        XCTAssertTrue(free)
        XCTAssertEqual(session.methods, ["release"])
    }

    func testDetachShutsTheHostDownWhenItStillHoldsAGameAfterRelease() async {
        let (session, game) = await started(fakeStatus())
        session.stopStatus = fakeStatus()
        let free = await game.detach()
        XCTAssertFalse(free)
        XCTAssertTrue(session.shutdownAsked)
        XCTAssertTrue(session.closed)
    }

    func testDetachShutsTheHostDownWhenStatusFails() async {
        let (session, game) = await started(fakeStatus())
        session.statusError = RetroCallError(code: RetroCallError.argument, message: "refused")
        let free = await game.detach()
        XCTAssertFalse(free)
        XCTAssertTrue(session.shutdownAsked)
    }

    func testDetachAfterTheHostEndedOrAfterShutdownKeepsNothing() async {
        let (session, game) = await started(fakeStatus())
        session.nextStatus = .failed(error: "The emulator closed unexpectedly.", errorCode: RetroErrorCode.hostExited)
        session.end(.hostFailure)
        await settleRetro({ game.hostEnd != nil })
        let afterEnd = await game.detach()
        XCTAssertFalse(afterEnd)
        XCTAssertTrue(session.closed)

        let (_, other) = await started(fakeStatus())
        await other.shutdown()
        let afterShutdown = await other.detach()
        XCTAssertFalse(afterShutdown)
    }

    // MARK: The host's order

    func testAParsedStatusKeepsTheHostsOrderOfOptions() throws {
        let option = #"{"title":"T","values":["a"],"labels":["A"],"selected":0,"activeValue":"a","restart":false}"#
        let text = Self.protocolStatus.replacingOccurrences(
            of: #""options":{"swanstation_GPU_ResolutionScale":{"title":"Internal Resolution","values":["1","2","4"],"labels":["1x","2x","4x"],"selected":2,"activeValue":"4","restart":false}}"#,
            with: #""options":{"zeta":\#(option),"alpha":\#(option),"mid":\#(option)}"#)
        let status = try Self.parsed(text)
        XCTAssertEqual(status.optionOrder, ["zeta", "alpha", "mid"])
        XCTAssertEqual(status.orderedOptions.map(\.key), ["zeta", "alpha", "mid"])
        XCTAssertEqual(status.json.objectValue?["options"]?.objectKeys, ["zeta", "alpha", "mid"])
        let reordered = try Self.parsed(text.replacingOccurrences(of: #""zeta":\#(option),"alpha""#, with: #""alpha":\#(option),"zeta""#))
        XCTAssertFalse(status.sameAs(reordered), "the order is the menu's, so another order says something new")
        XCTAssertTrue(status.sameAs(try Self.parsed(text)))
        XCTAssertEqual(try RetroJSON.parse(Array(#"{"b":1,"a":2}"#.utf8)), .object(["a": .int(2), "b": .int(1)]),
                       "equal whatever the order of their keys")
    }
}
