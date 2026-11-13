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

    /// The game is gone: nothing is left to stop.
    func gameStopped() {
        gameStopWatch?.cancel()
        gameStopWatch = nil
        stopping = false
    }
}
