import Foundation

/// Keeps the emulator host of the last game running while the player may start another, so the
/// next game starts on it instead of on a new host, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_host_keeper.dart). protocol.md "Processes": "One host runs games one
/// after another until the launcher exits or the host fails."
///
/// It holds at most one host, with no game loaded (`RetroHostGame.detach()` made sure). That host
/// is shut down after `idleLimit` without a game, when `shutdown()` is asked (the player left the
/// emulator games), or when another host is kept. A host that ends while kept (it crashed, or it
/// exited after `release`, as protocol.md "release" allows) is forgotten, so the next game starts a
/// new one.
@MainActor
public final class RetroHostKeeper {
    /// How long a host with no game is kept.
    public var idleLimit: Duration

    private var session: RetroHostSession?
    private var program: String?
    private var idle: Task<Void, Never>?
    private var closing: [Int: Task<Void, Never>] = [:]
    private var nextClosing = 0

    public init(idleLimit: Duration = .seconds(300)) {
        self.idleLimit = idleLimit
    }

    /// Whether a host is kept now.
    public var holding: Bool { session != nil }

    /// Whether the host kept now was started from `program`, so `take(program:)` would give it.
    public func keeps(program: String) -> Bool { session != nil && self.program == program }

    /// Keeps `session`, the host started from `program`, for the next game; a host kept before is
    /// shut down.
    public func keep(_ session: RetroHostSession, program: String) {
        if session === self.session { return }
        shutdownKept()
        self.session = session
        self.program = program
        let limit = idleLimit
        idle = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled, let self, self.session === session else { return }
            self.shutdownKept()
        }
        Task { [weak self] in
            _ = await session.ended()
            guard let self, self.session === session else { return }
            self.forget()
            self.track(Task { await session.close() })
        }
    }

    /// The kept host, for a game starting now, when it was started from `program`; it is no longer
    /// kept. Nil when none is, or the kept one runs another program, which is then shut down.
    public func take(program: String) -> RetroHostSession? {
        guard let session else { return nil }
        guard self.program == program else {
            shutdownKept()
            return nil
        }
        forget()
        return session
    }

    /// Shuts the kept host down, if one is, and waits for every host this keeper shut down to end.
    public func shutdown() async {
        shutdownKept()
        for task in Array(closing.values) { await task.value }
    }

    private func shutdownKept() {
        guard let session else { return }
        forget()
        session.shutdown()
        track(Task {
            _ = await session.ended()
            await session.close()
        })
    }

    private func track(_ task: Task<Void, Never>) {
        nextClosing += 1
        let id = nextClosing
        closing[id] = task
        Task { [weak self] in
            await task.value
            self?.closing[id] = nil
        }
    }

    private func forget() {
        idle?.cancel()
        idle = nil
        session = nil
        program = nil
    }
}
