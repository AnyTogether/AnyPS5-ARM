@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import SwiftUI
import XCTest

/// The cover of a game starting, as on Windows and Linux: it stays while the game's window
/// settles, in a window on the home screen and in full screen as a panel over the game that then
/// fades. It never stays while the game plays: the game ending and a menu opening drop it. The
/// test's own process stands in for the game; no window opens.
@MainActor
final class StartCoverModelTests: XCTestCase {
    private var alive = true
    private var moving = true
    private var step: CGFloat = 0
    private var fronts = 0

    private final class Surface: StartCoverSurface {
        var alphas: [Double] = []
        var closed = false
        var alpha: Double {
            get { alphas.last ?? 1 }
            set { alphas.append(newValue) }
        }
        func close() { closed = true }
    }

    private func model() throws -> (AppModel, Game) {
        let model = try LauncherFixture.model()
        model.coverTiming = StartCoverTiming(fade: 0.15, reducedFade: 0.03, holdLimit: 2, settle: 0.05, windowWait: 3, displayDelay: 0.1, entrance: 0.05)
        model.gameAlive = { [unowned self] _ in alive }
        // A window that moves (going full screen, being sized) until the test says it stopped.
        model.gameWindowFrame = { [unowned self] _ in
            guard moving else { return CGRect(x: 0, y: 0, width: 1280, height: 720) }
            step += 1
            return CGRect(x: step, y: 0, width: 1280, height: 720)
        }
        model.bringGameFront = { [unowned self] _ in fronts += 1 }
        model.makeCoverSurface = { _, _, _ in XCTFail("no panel in a window"); return nil }
        let game = try XCTUnwrap(model.games.first)
        model.previewRunning(game, app: .current)
        return (model, game)
    }

    private final class Flag {
        var on = false
    }

    /// Starts the hand-off; the closure turns true when it has finished.
    private func handOff(_ model: AppModel, _ game: Game, overGame: Bool) -> () -> Bool {
        let finished = Flag()
        Task {
            await model.handOff(game, app: .current, overGame: overGame, began: Date())
            finished.on = true
        }
        return { finished.on }
    }

    private func wait(_ seconds: Double = 3, until done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testInAWindowTheCoverStaysOnTheHomeScreenUntilTheWindowSettles() async throws {
        let (model, game) = try model()
        let done = handOff(model, game, overGame: false)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(model.coverGame?.id, game.id, "the window still moves: the cover stays")
        XCTAssertFalse(model.coverHandedOver, "no panel over the game in a window")
        XCTAssertEqual(fronts, 1, "the game has the front, its window in front of the cover")
        XCTAssertFalse(done())
        moving = false
        await wait(until: done)
        XCTAssertTrue(done())
        XCTAssertNil(model.coverGame, "settled: the cover went on the home screen")
        XCTAssertNil(model.coverTurn)
    }

    func testTheGameEndingEarlyDropsTheCover() async throws {
        let (model, game) = try model()
        let done = handOff(model, game, overGame: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.coverGame?.id, game.id)
        let ended = Date()
        alive = false
        await wait(until: done)
        XCTAssertTrue(done())
        XCTAssertNil(model.coverGame, "the game closed: no cover left over the home screen")
        XCTAssertLessThan(Date().timeIntervalSince(ended), 1, "at once, not after the window wait")
    }

    func testTheGameEndingDropsThePanelOverItWithoutTheHold() async throws {
        let (model, game) = try model()
        let surface = Surface()
        model.makeCoverSurface = { _, _, _ in surface }
        let done = handOff(model, game, overGame: true)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(model.coverHandedOver)
        let ended = Date()
        model.endCover()
        await wait(until: done)
        XCTAssertTrue(done())
        XCTAssertTrue(surface.closed)
        XCTAssertLessThan(Date().timeIntervalSince(ended), 0.6, "into the fade at once, not held")
        XCTAssertNil(model.coverGame)
        XCTAssertFalse(model.coverHandedOver)
    }

    func testAMenuOpeningDropsTheCover() async throws {
        let (model, game) = try model()
        let done = handOff(model, game, overGame: false)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.coverGame?.id, game.id)
        model.overlay = .quickMenu
        XCTAssertNil(model.coverGame, "the menu is not hidden under the cover")
        await wait(until: done)
        XCTAssertTrue(done(), "the hand-off ends with it")
    }

    func testInFullScreenThePanelFadesOverTheGameOnceItSettled() async throws {
        let (model, game) = try model()
        // A fade long enough to be seen between two frames, with reduced motion too: the runner
        // may reduce motion (its accessibility setting or a power profile), and the 30 ms reduced
        // fade then passes in one late frame, so the panel closes at full opacity.
        model.coverTiming = StartCoverTiming(fade: 0.8, reducedFade: 0.8, holdLimit: 2, settle: 0.05, windowWait: 3, displayDelay: 0.1, entrance: 0.05)
        let began = Date()
        let surface = Surface()
        model.makeCoverSurface = { _, _, _ in surface }
        let done = handOff(model, game, overGame: true)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(model.coverHandedOver, "the panel took the cover's place")
        XCTAssertNil(model.coverGame, "the launcher's own cover went under it")
        XCTAssertEqual(fronts, 1)
        XCTAssertFalse(surface.alphas.isEmpty)
        XCTAssertTrue(surface.alphas.allSatisfy { $0 == 1 }, "opaque while the window moves")
        XCTAssertFalse(surface.closed)
        moving = false
        await wait(until: done)
        XCTAssertTrue(done())
        XCTAssertTrue(surface.closed)
        XCTAssertLessThan(surface.alphas.last ?? 1, 1, "it faded before it went (reduced motion: \(model.coverReducedMotion), \(surface.alphas.count) frames, \(Date().timeIntervalSince(began)) s)")
        XCTAssertEqual(surface.alphas, surface.alphas.sorted(by: >), "it only ever fades")
        XCTAssertFalse(model.coverHandedOver)
    }

    func testAMenuOpeningLetsThePanelOverTheGameGo() async throws {
        let (model, game) = try model()
        let surface = Surface()
        model.makeCoverSurface = { _, _, _ in surface }
        let done = handOff(model, game, overGame: true)
        try await Task.sleep(for: .milliseconds(200))
        model.overlay = .quickMenu
        await wait(1, until: done)
        XCTAssertTrue(done(), "released although the window still moves")
        XCTAssertTrue(surface.closed)
    }

    func testAGamesOwnOffWinsOverTheDefaultOn() throws {
        let (model, game) = try model()
        let other = try XCTUnwrap(model.games.last)
        model.updateDisplayDefaults { $0.fullscreen = true }
        XCTAssertTrue(model.displayDefaults.startAnimation, "on by default, as on Windows and Linux")
        XCTAssertTrue(model.showsCover(game))
        XCTAssertTrue(model.launchSettings(for: game).fadesCover)
        let row = try XCTUnwrap(model.gameDisplayRows(game, model.settings(for: game)).first { $0.id == "startAnimation" })
        XCTAssertEqual(row.title, "Start animation")
        guard case .choice(let options, let selected, let set) = row.kind else { return XCTFail("a choice") }
        XCTAssertEqual(options, ["Default (On)", "On", "Off"])
        XCTAssertEqual(selected, 0)
        set(2)
        XCTAssertEqual(model.settings(for: game).ownStartAnimation, false)
        XCTAssertFalse(model.launchSettings(for: game).startAnimation, "the game's own Off")
        XCTAssertFalse(model.launchSettings(for: game).fadesCover)
        XCTAssertFalse(model.showsCover(game), "its start shows the start screen without the cover")
        XCTAssertTrue(model.showsCover(other), "another game follows the default")
        XCTAssertNotNil(model.gameDisplayRows(game, model.settings(for: game)).first { $0.id == "useDisplayDefaults" }, "a choice of its own to put back")
    }

    func testTheDefaultDisplayHasStartAnimation() throws {
        let (model, _) = try model()
        let row = try XCTUnwrap(model.displayDefaultRows().first { $0.id == "defaultStartAnimation" })
        XCTAssertEqual(row.detail, T.text(.startAnimationDetail))
        guard case .toggle(let on, let set) = row.kind else { return XCTFail("a toggle") }
        XCTAssertTrue(on)
        set(false)
        XCTAssertEqual(model.preferences.displayDefaults?.startAnimation, false)
        set(true)
        XCTAssertNil(model.preferences.displayDefaults, "back to the built-in values: nothing kept")
    }

    func testAStartShowsWhatWasChosenWhenPlayWasPressed() throws {
        let (model, game) = try model()
        model.previewRunning(game, app: .current)
        model.previewStarting(game)
        model.startCover = StartCoverChoice(animation: false, overGame: false)
        XCTAssertFalse(model.showsCover(game))
        model.startCover = StartCoverChoice(animation: true, overGame: true)
        XCTAssertTrue(model.showsCover(game))
    }

    func testReducedMotionHasTheShortFadeAndNoZoom() async throws {
        let (model, game) = try model()
        model.preferences.reducedMotion = true
        XCTAssertTrue(model.coverReducedMotion)
        XCTAssertEqual(StartCoverView.entranceScale(reducedMotion: true), 1, "it only fades in")
        XCTAssertEqual(StartCoverView.entranceScale(reducedMotion: false), 1.04)
        // Without reduced motion this fade would take a second and a half.
        model.coverTiming.fade = 1.5
        let surface = Surface()
        model.makeCoverSurface = { _, _, _ in surface }
        moving = false
        let started = Date()
        let done = handOff(model, game, overGame: true)
        await wait(until: done)
        XCTAssertTrue(done())
        XCTAssertTrue(surface.closed)
        // Settled after two still checks a tenth of a second apart, then the settle and 30 ms of fade.
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }
}
