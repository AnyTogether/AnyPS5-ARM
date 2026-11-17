import Foundation

/// What the app finishes before it quits, as on Windows and Linux: the game playing closes (asked
/// first, so it can save) and a call is left. Each has its own limit, and the quit as a whole
/// goes on after `unanswered` at the latest, once. A server that does not answer, a media
/// server's close that hangs or a game that never goes cannot keep the launcher from quitting.
public enum QuitWait {
    /// How long leaving a call waits at most.
    public static let limit: Duration = .seconds(3)

    /// How long a quit waits at most for everything it finishes first: longer than the game's
    /// grace and what follows its end, as AnyPS5-Desktop's LauncherShutdown.defaultUnansweredAfter.
    public static let unanswered: Duration = .seconds(20)

    /// How long the quit waits for a game it ended to be gone, so the programs ended after it
    /// (ChildProcesses) go after it.
    public static let afterEnd: Duration = .seconds(1)

    /// Calls `reply` once, when `task` has ended or `limit` has passed.
    @MainActor
    public static func reply(after task: Task<Void, Never>, within limit: Duration = QuitWait.limit, _ reply: @escaping @MainActor () -> Void) {
        self.reply(afterAll: [task], within: limit, reply)
    }

    /// Calls `reply` once, when every task in `tasks` has ended or `limit` has passed.
    @MainActor
    public static func reply(afterAll tasks: [Task<Void, Never>], within limit: Duration = QuitWait.unanswered, _ reply: @escaping @MainActor () -> Void) {
        let once = Once(reply)
        Task { @MainActor in
            for task in tasks { await task.value }
            once.run()
        }
        Task { @MainActor in
            try? await Task.sleep(for: limit)
            once.run()
        }
    }

    /// A task that ends when `task` has ended or `limit` has passed, whichever comes first.
    @MainActor
    public static func bounded(_ task: Task<Void, Never>, within limit: Duration = QuitWait.limit) -> Task<Void, Never> {
        Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                reply(after: task, within: limit) { continuation.resume() }
            }
        }
    }

    /// The game playing as the launcher quits, as Close Game: `ask` asks it to close so it can
    /// save, and once `grace` has passed with it still there (`gone` false), `end` ends it. Returns
    /// when it is gone, or `afterEnd` after it was ended.
    @MainActor
    public static func closeGame(grace: Duration, afterEnd: Duration = QuitWait.afterEnd, poll: Duration = .milliseconds(50),
                                 ask: () -> Void, gone: () -> Bool, end: () -> Void) async {
        ask()
        await endAfterGrace(grace, afterEnd: afterEnd, poll: poll, gone: gone, end: end)
    }

    /// The second half of `closeGame`, for a game already asked: `end` once `grace` has passed
    /// with it still there, then `afterEnd` at most for it to go.
    @MainActor
    public static func endAfterGrace(_ grace: Duration, afterEnd: Duration = QuitWait.afterEnd, poll: Duration = .milliseconds(50),
                                     gone: () -> Bool, end: () -> Void) async {
        let clock = ContinuousClock()
        let deadline = clock.now + grace
        while !gone(), clock.now < deadline { try? await Task.sleep(for: poll) }
        guard !gone() else { return }
        end()
        let ended = clock.now + afterEnd
        while !gone(), clock.now < ended { try? await Task.sleep(for: poll) }
    }

    @MainActor
    private final class Once {
        private var action: (@MainActor () -> Void)?

        init(_ action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        func run() {
            let action = self.action
            self.action = nil
            action?()
        }
    }
}
