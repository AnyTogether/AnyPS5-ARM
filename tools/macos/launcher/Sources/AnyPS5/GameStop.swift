import AnyPS5Core
import AppKit
import SwiftUI

/// Stopping the game playing, as on Windows and Linux: it is asked to close as closing its window
/// would, so it can save (macOS's quit request, which the game's window layer treats as its
/// window closing; a game that cannot be asked is sent SIGTERM), and it is ended after
/// `gameStopGrace` when it is still there. A game that does not answer is stopped all the same.
extension AppModel {
    /// Stop: Close Game in the quick menu and Stop Game in the game's settings. Its tile reads
    /// Closing the game meanwhile and goes back to Ready once it is gone.
    func stopRunningGame() {
        if let run = emulator?.run { return stopEmulator(run) }
        guard let app = running?.app, !stopping else { return }
        withAnimation(Motion.overlay) { stopping = true }
        gameStopWatch?.cancel()
        let grace = gameStopGrace
        gameStopWatch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard let self, !Task.isCancelled, self.running?.app == app else { return }
            self.endGame(app)
        }
        if !askGameToClose(app) { kill(app.processIdentifier, SIGTERM) }
    }

    /// Stop on a disc playing in its emulator: the emulator is asked to end (SIGTERM), so it can
    /// save, and ended after the same grace when it is still there.
    func stopEmulator(_ run: EmulatorRun) {
        guard !stopping else { return }
        emulatorStopped = true
        withAnimation(Motion.overlay) { stopping = true }
        gameStopWatch?.cancel()
        let grace = gameStopGrace
        gameStopWatch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: grace)
            guard let self, !Task.isCancelled, self.emulator?.run === run else { return }
            run.kill()
        }
        if !run.stop() { run.kill() }
    }

    /// What the app delegate finishes before the launcher quits (Cmd-Q, the window's close, Quit
    /// AnyPS5, an update's Restart Now), as on Windows and Linux: the game playing closes
    /// (closeGameOnQuit) and a call is left, three seconds at most. ChildProcesses ends the rest
    /// once they are done, as the app terminates.
    func quitSteps() -> [Task<Void, Never>] {
        [closeGameOnQuit(), leaveTogetherOnQuit().map { QuitWait.bounded($0) }].compactMap { $0 }
    }

    /// The launcher is quitting: the game or emulator playing is asked to close exactly as Close
    /// Game does, has `gameStopGrace` to save, and is ended only then. nil when nothing plays.
    func closeGameOnQuit() -> Task<Void, Never>? {
        guard running != nil || emulator != nil else { return nil }
        let app = running?.app
        let run = emulator?.run
        let grace = gameStopGrace
        stopRunningGame()
        // The quit ends it after the grace itself, and waits for that.
        gameStopWatch?.cancel()
        gameStopWatch = nil
        return Task { @MainActor [weak self] in
            await QuitWait.endAfterGrace(grace, gone: {
                guard let self else { return true }
                return (app == nil || self.running?.app != app) && (run == nil || self.emulator?.run !== run)
            }, end: {
                guard let self else { return }
                if let app { self.endGame(app) }
                run?.kill()
            })
        }
    }

    /// The game is gone: nothing is left to stop.
    func gameStopped() {
        gameStopWatch?.cancel()
        gameStopWatch = nil
        stopping = false
    }
}
