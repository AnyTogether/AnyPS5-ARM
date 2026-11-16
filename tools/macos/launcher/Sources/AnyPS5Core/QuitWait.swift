import Foundation

/// What the app finishes before it quits (leaving a call), never for longer than a limit: the quit
/// goes on at whichever comes first, once. A server that does not answer, or a media server's
/// close that hangs, cannot keep the launcher from quitting.
public enum QuitWait {
    /// How long a quit waits at most.
    public static let limit: Duration = .seconds(3)

    /// Calls `reply` once, when `task` has ended or `limit` has passed.
    @MainActor
    public static func reply(after task: Task<Void, Never>, within limit: Duration = QuitWait.limit, _ reply: @escaping @MainActor () -> Void) {
        let once = Once(reply)
        Task { @MainActor in
            await task.value
            once.run()
        }
        Task { @MainActor in
            try? await Task.sleep(for: limit)
            once.run()
        }
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
