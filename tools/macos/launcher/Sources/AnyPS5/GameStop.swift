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

    /// The game is gone: nothing is left to stop.
    func gameStopped() {
        gameStopWatch?.cancel()
        gameStopWatch = nil
        stopping = false
    }
}
