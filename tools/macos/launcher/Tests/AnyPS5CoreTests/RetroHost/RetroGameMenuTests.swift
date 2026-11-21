import XCTest
@testable import AnyPS5Core

/// The in-game menu's model, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_game_menu_test.dart).
@MainActor
final class RetroGameMenuTests: XCTestCase {
    /// The `status` example of anyps5-retro-host docs/protocol.md "status", with the disc and
    /// option fields the test changes.
    nonisolated static func status(inserted: Int? = 0, busy: Bool = false, failed: Bool = false, selected: Int = 2, active: String = "4") -> RetroStatus {
        let text = #"{"ready":true,"ended":false,"error":"","errorCode":"","aspect":1.3333333333333333,"hardware":true,"#
            + #""resolutionError":"","graphicsPending":false,"progressLabel":null,"progressPercent":null,"#
            + #""options":{"swanstation_GPU_ResolutionScale":{"title":"Internal Resolution","values":["1","2","4"],"#
            + #""labels":["1x","2x","4x"],"selected":\#(selected),"activeValue":"\#(active)","restart":false}},"#
            + #""discs":{"labels":["Disc 1","Disc 2"],"inserted":\#(inserted.map(String.init) ?? "null"),"#
            + #""insertedDiscPath":"/Games/FF7 (Disc 1).cue","playedDiscPath":"/Games/FF7 (Disc 1).cue","busy":\#(busy),"failed":\#(failed)}}"#
        return try! RetroStatus.parse(try! RetroJSON.parse(Array(text.utf8)))
    }

    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        for cleanup in cleanups.reversed() { cleanup() }
        cleanups = []
    }

    private func made() -> (FakeRetroHostSession, RetroHostGame, RetroGameMenu) {
        let session = FakeRetroHostSession()
        let game = RetroHostGame(session: session, statusEvery: .seconds(3600), volume: 0.5)
        let menu = RetroGameMenu(game: game, controls: nil)
        cleanups.append { game.dispose() }
        cleanups.append { menu.dispose() }
        return (session, game, menu)
    }

    private func controls(_ game: RetroHostGame) -> RetroHostControls {
        let controls = RetroHostControls(game: game, pads: RetroPadReader(pads: { [] }, state: { _ in nil }), polls: false)
        cleanups.append { controls.dispose() }
        return controls
    }

    private func started(_ session: FakeRetroHostSession, _ game: RetroHostGame, _ status: RetroStatus = RetroGameMenuTests.status()) async {
        session.greet()
        session.nextStatus = status
        await game.start(RetroHostStartRequest(core: "c", disc: "d.m3u", system: "s", saves: "v"))
    }

    func testTheRowsAreTheDiscsTheOptionsAndTheVolumeFromTheProtocolsStatus() async {
        let (session, game, menu) = made()
        XCTAssertEqual(menu.rows, [.volume(level: 0.5, muted: false)])
        await started(session, game)
        XCTAssertEqual(menu.discs, [
            RetroDiscRow(index: 0, label: "Disc 1", inserted: true, enabled: false),
            RetroDiscRow(index: 1, label: "Disc 2", inserted: false, enabled: true),
        ])
        let options = menu.rows.compactMap { row -> RetroOptionRow? in if case .option(let option) = row { return option } else { return nil } }
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options.first?.key, "swanstation_GPU_ResolutionScale")
        XCTAssertEqual(options.first?.title, "Internal Resolution")
        XCTAssertEqual(options.first?.choice, "4x")
        XCTAssertEqual(options.first?.pending, false)
        XCTAssertEqual(options.first?.restartNeeded, false)
        XCTAssertEqual(options.first?.section, .graphics)
        XCTAssertTrue(menu.optionsIn(.console).isEmpty)
        XCTAssertEqual(menu.rows.last, .volume(level: 0.5, muted: false))
    }

    func testASingleDiscGameHasNoDiscRowsAndAnOpenTrayOrAChangeInProgressBlocksThem() {
        XCTAssertEqual(RetroGameMenu.rowsFor(fakeStatus(), volume: 1, muted: false), [.volume(level: 1, muted: false)])
        func discs(_ status: RetroStatus) -> [Bool] {
            RetroGameMenu.rowsFor(status, volume: 1, muted: false).compactMap { row -> Bool? in if case .disc(let disc) = row { return disc.enabled } else { return nil } }
        }
        XCTAssertEqual(discs(Self.status(inserted: nil)), [true, true])
        XCTAssertEqual(discs(Self.status(busy: true)), [false, false])
    }

    func testChoosingADiscSendsChangeDiscAndAsksStatusAtOnce() async throws {
        let (session, game, menu) = made()
        await started(session, game)
        session.callResults["changeDisc"] = .bool(true)
        session.nextStatus = Self.status(busy: true)
        let disc = try XCTUnwrap(menu.discs.last)
        let changed = await menu.chooseDisc(disc)
        XCTAssertTrue(changed)
        XCTAssertEqual(session.methods, ["changeDisc"])
        XCTAssertEqual(session.calls.first?.1, .int(1))
        XCTAssertTrue(menu.discs.allSatisfy { !$0.enabled })
        let again = await menu.chooseDisc(disc)
        XCTAssertFalse(again)
        XCTAssertEqual(session.calls.count, 1)
    }

    func testARefusedDiscChangeAndAFailedOneAreToldApart() async throws {
        let (session, game, menu) = made()
        await started(session, game)
        session.callResults["changeDisc"] = .bool(false)
        let refused = await menu.chooseDisc(try XCTUnwrap(menu.discs.last))
        XCTAssertFalse(refused)
        XCTAssertFalse(menu.discChangeFailed)
        session.nextStatus = Self.status(failed: true)
        await game.refresh()
        XCTAssertTrue(menu.discChangeFailed)
    }

    func testAnOptionStepsThroughItsValuesAndStopsAtTheEnds() async {
        let (session, game, menu) = made()
        await started(session, game)
        session.callResults["option"] = .bool(true)
        let pastEnd = await menu.stepOption("swanstation_GPU_ResolutionScale", 1)
        XCTAssertFalse(pastEnd)
        session.nextStatus = Self.status(selected: 1)
        let back = await menu.stepOption("swanstation_GPU_ResolutionScale", -1)
        XCTAssertTrue(back)
        XCTAssertEqual(session.methods, ["option"])
        XCTAssertEqual(session.calls.first?.1, .object(["key": .string("swanstation_GPU_ResolutionScale"), "value": .string("2")]))
        let option = menu.optionsIn(.graphics).first
        XCTAssertEqual(option?.choice, "2x")
        XCTAssertEqual(option?.pending, true)
        let unknown = await menu.stepOption("unknown", 1)
        XCTAssertFalse(unknown)
    }

    func testVolumeStepsByTenthsTurningItUpUnmutesAndMuteToggles() async {
        let (session, game, menu) = made()
        await started(session, game)
        await menu.toggleMute()
        await menu.stepVolume(-6)
        XCTAssertEqual(game.volume, 0)
        XCTAssertTrue(game.muted)
        await menu.stepVolume(3)
        XCTAssertEqual(game.volume, 0.3, "whole tenths, not 3 × 0.1")
        XCTAssertFalse(game.muted)
        await menu.stepVolume(20)
        XCTAssertEqual(game.volume, 1)
        func volume(_ level: Double, _ muted: Bool) -> RetroJSON { .object(["level": .number(level), "muted": .bool(muted)]) }
        XCTAssertEqual(session.calls.map(\.1), [volume(0.5, true), volume(0, true), volume(0.3, false), volume(1, false)])
    }

    func testVolumeSetBeforeTheHostGreetsTheLauncherIsSentOnceItDoes() async {
        let (session, game, _) = made()
        let pending = Task { await game.setVolume(level: 0.2) }
        await yieldRetro()
        XCTAssertTrue(session.calls.isEmpty)
        session.greet()
        await pending.value
        XCTAssertEqual(session.methods, ["volume"])
        XCTAssertEqual(session.calls.first?.1, .object(["level": .number(0.2), "muted": .bool(false)]))
    }

    func testOpeningTheMenuPausesTheGameAndKeepsTheControllersOutAndClosingGivesBothBack() async {
        let (session, game, _) = made()
        let controls = controls(game)
        let menu = RetroGameMenu(game: game, controls: controls)
        cleanups.append { menu.dispose() }
        await menu.open()
        XCTAssertFalse(menu.isOpen, "a game that is not loaded has no menu")
        await started(session, game)
        await menu.open()
        XCTAssertTrue(menu.isOpen)
        XCTAssertTrue(game.paused)
        XCTAssertTrue(controls.suspended)
        await menu.close()
        XCTAssertFalse(game.paused)
        XCTAssertFalse(controls.suspended)
        XCTAssertEqual(session.calls.map(\.1), [.bool(true), .bool(false)])
    }

    func testOpeningTheMenuAgainWhileClosingWaitsOnTheHostKeepsTheControllersOut() async {
        let (session, game, _) = made()
        let controls = controls(game)
        let menu = RetroGameMenu(game: game, controls: controls)
        cleanups.append { menu.dispose() }
        await started(session, game)
        await menu.open()
        let gate = RetroGate()
        session.callGate = gate
        let closing = Task { await menu.close() }
        await yieldRetro()
        let opening = Task { await menu.open() }
        await yieldRetro()
        gate.open()
        await closing.value
        await opening.value
        XCTAssertTrue(menu.isOpen)
        XCTAssertTrue(game.paused)
        XCTAssertTrue(controls.suspended)
    }

    func testDisposingAnOpenMenuGivesTheGameBackItsControllers() async {
        let (session, game, _) = made()
        let controls = controls(game)
        let menu = RetroGameMenu(game: game, controls: controls)
        await started(session, game)
        await menu.open()
        menu.dispose()
        await settleRetro({ !game.paused })
        XCTAssertFalse(controls.suspended)
    }
}
