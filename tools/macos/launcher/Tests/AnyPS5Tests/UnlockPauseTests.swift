@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import XCTest

/// Pause and Resume for an unlock, its small Cancel button with the question before it, and the
/// question before quitting while games are unlocked, as on Windows and Linux. The unlocks are
/// stand-ins that only count what is asked of them; the test ends them by hand.
@MainActor
final class UnlockPauseTests: XCTestCase {
    final class FakeUnlock: UnlockWork {
        var paused = 0, resumed = 0, cancelled = 0
        let done: (Result<URL, Error>) -> Void
        init(done: @escaping (Result<URL, Error>) -> Void) { self.done = done }
        func pause() { paused += 1 }
        func resume() { resumed += 1 }
        func cancel() { cancelled += 1 }
        func finish() { done(.success(URL(fileURLWithPath: NSTemporaryDirectory()))) }
        func ended() { done(.failure(CancellationError())) }
    }

    private var works: [String: FakeUnlock] = [:]
    private var terminated = 0

    private func model() throws -> (AppModel, [Game]) {
        let model = try LauncherFixture.model(games: 3)
        model.unlockStarter = { [unowned self] game, done in
            let work = FakeUnlock(done: done)
            works[game.id] = work
            return work
        }
        model.terminateApp = { [unowned self] in terminated += 1 }
        model.selected = 0
        return (model, model.games)
    }

    func testPauseLetsTheNextUnlockStartAndResumeGoesOnFromWhereItStood() throws {
        let (model, games) = try model()
        model.previewQueueUnlock(games[0])
        model.previewQueueUnlock(games[1])
        XCTAssertEqual(model.unlockControl(games[0]), .running)
        XCTAssertEqual(model.state(of: games[1]), .queued)
        XCTAssertNil(works[games[1].id], "one unlock works at a time")
        XCTAssertTrue(model.showsCancelUnlock(games[0]))

        // The main button of an unlock under way is Pause.
        model.primaryAction(games[0])
        XCTAssertEqual(works[games[0].id]?.paused, 1)
        XCTAssertEqual(model.unlockControl(games[0]), .paused)
        XCTAssertNotNil(works[games[1].id], "a paused unlock does not hold the next one back")
        XCTAssertEqual(model.unlockControl(games[1]), .running)

        // Resume while the other runs: it waits its turn, and its button pauses it again rather
        // than dropping it.
        model.primaryAction(games[0])
        XCTAssertEqual(model.unlockControl(games[0]), .waiting)
        XCTAssertEqual(works[games[0].id]?.resumed, 0)
        model.primaryAction(games[0])
        XCTAssertEqual(model.unlockControl(games[0]), .paused)
        XCTAssertEqual(works[games[0].id]?.cancelled, 0, "one press never throws the work away")
        model.primaryAction(games[0])
        XCTAssertEqual(model.unlockControl(games[0]), .waiting)

        // The other one ends: the waiting one goes on before anything else.
        works[games[1].id]?.finish()
        XCTAssertEqual(works[games[0].id]?.resumed, 1)
        XCTAssertEqual(model.unlockControl(games[0]), .running)
        XCTAssertEqual(works[games[0].id]?.cancelled, 0)
    }

    func testResumeWithNothingElseRunningGoesOnAtOnce() throws {
        let (model, games) = try model()
        model.previewQueueUnlock(games[0])
        model.pauseUnlock(games[0])
        XCTAssertEqual(model.unlockControl(games[0]), .paused)
        model.resumeUnlock(games[0])
        XCTAssertEqual(works[games[0].id]?.resumed, 1)
        XCTAssertEqual(model.unlockControl(games[0]), .running)
    }

    func testTheSmallCancelAsksFirstAndKeepGoingKeepsTheWork() throws {
        let (model, games) = try model()
        model.previewQueueUnlock(games[0])
        // Pause, Cancel, the settings: the small Cancel button is the second one.
        XCTAssertEqual(model.actionCount, 3)
        model.focus = .actions(model.cancelAction)
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.overlay, .confirmCancelUnlock)
        XCTAssertEqual(model.cancelAsking?.id, games[0].id)
        XCTAssertEqual(model.menuIndex, 0, "Keep going is where the focus starts")
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertEqual(works[games[0].id]?.cancelled, 0)

        model.focus = .actions(model.cancelAction)
        XCTAssertTrue(model.handle(.select))
        XCTAssertTrue(model.handle(.right))
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertEqual(works[games[0].id]?.cancelled, 1)
        XCTAssertEqual(model.unlockControl(games[0]), .cancelling)
        XCTAssertFalse(model.showsCancelUnlock(games[0]))
        XCTAssertEqual(model.focus, .actions(0), "the focus goes back to the main button")
        // While it is being cancelled the button does nothing more.
        model.primaryAction(games[0])
        XCTAssertEqual(works[games[0].id]?.cancelled, 1)
        XCTAssertEqual(works[games[0].id]?.paused, 0)
        works[games[0].id]?.ended()
        XCTAssertEqual(model.state(of: games[0]), .locked)
        XCTAssertNil(model.unlockControl(games[0]))
    }

    func testAPausedUnlockCanBeCancelledAndAQueuedOneIsDroppedAtOnce() throws {
        let (model, games) = try model()
        model.previewQueueUnlock(games[0])
        model.previewQueueUnlock(games[1])
        model.previewQueueUnlock(games[2])
        model.pauseUnlock(games[0])
        // games[1] runs now, games[2] only waits in the queue: no work of its own to lose.
        XCTAssertEqual(model.state(of: games[2]), .queued)
        XCTAssertFalse(model.showsCancelUnlock(games[2]))
        model.primaryAction(games[2])
        XCTAssertEqual(model.state(of: games[2]), .locked)
        XCTAssertNil(model.overlay)

        model.askCancelUnlock(games[0])
        XCTAssertEqual(model.overlay, .confirmCancelUnlock)
        model.cancelUnlockAnswered()
        XCTAssertEqual(works[games[0].id]?.cancelled, 1)
        XCTAssertEqual(model.unlockControl(games[0]), .cancelling)
        works[games[0].id]?.ended()
        XCTAssertEqual(model.state(of: games[0]), .locked)
        XCTAssertEqual(model.unlockControl(games[1]), .running, "the one running is not touched")
    }

    func testQuittingWithAnUnlockAsksAndCancelAndQuitStopsEveryUnlockFirst() async throws {
        let (model, games) = try model()
        model.previewQueueUnlock(games[0])
        model.previewQueueUnlock(games[1])
        model.pauseUnlock(games[0])
        // Escape's question, then Quit: the unlocks' question comes before anything closes.
        XCTAssertTrue(model.escape())
        XCTAssertEqual(model.overlay, .confirmQuit)
        XCTAssertTrue(model.handle(.right))
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.overlay, .confirmQuitUnlocks)
        XCTAssertEqual(terminated, 0)
        // Go back.
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertEqual(works[games[0].id]?.cancelled, 0)

        // Cmd-Q or the window's close reach the same question.
        XCTAssertTrue(model.terminateAsks())
        XCTAssertEqual(model.overlay, .confirmQuitUnlocks)
        XCTAssertTrue(model.handle(.right))
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(works[games[0].id]?.cancelled, 1, "the paused one is cancelled too")
        XCTAssertEqual(works[games[1].id]?.cancelled, 1)
        XCTAssertEqual(terminated, 0, "it waits for the work to end")
        works[games[0].id]?.ended()
        works[games[1].id]?.ended()
        for _ in 0..<30 where terminated == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(terminated, 1)
        XCTAssertFalse(model.terminateAsks(), "the terminate that follows goes through")
    }

    func testQuittingWithNothingUnlockedAsksNothing() throws {
        let (model, _) = try model()
        XCTAssertFalse(model.quitAsks)
        XCTAssertFalse(model.terminateAsks())
        model.quitApp()
        XCTAssertEqual(terminated, 1)
    }

    func testThePhoneSeesAPausedUnlockAsLockedAndFollowsTheOneThatRuns() throws {
        let (model, games) = try model()
        model.previewQueueUnlock(games[0])
        model.previewQueueUnlock(games[1])
        XCTAssertEqual(model.remoteGame(games[0]).state, .installing)
        model.pauseUnlock(games[0])
        XCTAssertEqual(model.remoteGame(games[0]).state, .locked)
        XCTAssertEqual(model.remoteGame(games[1]).state, .installing)
        XCTAssertEqual(model.activityForPhone()?.id, games[1].id)
        model.askCancelUnlock(games[1])
        model.cancelUnlockAnswered()
        XCTAssertEqual(model.remoteGame(games[1]).state, .installing, "cancelling is still busy")
    }

    func testTheTextsInEnglishAndTurkish() {
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        XCTAssertEqual(TUnlock.text(.unlockPause), "Pause")
        XCTAssertEqual(TUnlock.text(.unlockResume), "Resume")
        XCTAssertEqual(TUnlock.format(.cancelUnlockAskTitle, "Orbit Runner"), "Cancel the unlock of Orbit Runner?")
        T.language = .turkish
        XCTAssertEqual(TUnlock.text(.unlockPause), "Duraklat")
        XCTAssertEqual(TUnlock.format(.cancelUnlockAskTitle, "Orbit Runner"), "Orbit Runner için kilit açma iptal edilsin mi?")
    }
}
