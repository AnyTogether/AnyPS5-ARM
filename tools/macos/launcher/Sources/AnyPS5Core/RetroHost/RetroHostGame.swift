import Foundation

/// Where one game in an emulator host stands.
public enum RetroHostGamePhase: Equatable, Sendable {
    /// No game was started yet.
    case idle
    /// Waiting for the host to greet the launcher and accept `start`.
    case starting
    /// `start` was accepted; `status.ready` is still false.
    case loading
    /// `status.ready` is true: the game runs and its frames are shown.
    case playing
    /// The game ended: stopped, failed, or `start` was refused. `endStatus` or `failure` says why.
    case ended
    /// The host was shut down, or let go for the next game; nothing more can be done with it.
    case closed
}

/// One game in one emulator host, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_host_game.dart): starting it, forwarding input, pausing while the
/// launcher has no input focus, following its `status`, stopping it, and shutting the host down or
/// letting it go for the next game. It owns its `session` (until it is detached) and the `picture`
/// of its frames.
@MainActor
public final class RetroHostGame: ObservableObject {
    public let session: RetroHostSession
    /// How often `status` is asked while a game is loaded.
    public let statusEvery: Duration
    /// The picture of the newest frame of this game.
    public let picture = RetroFramePicture()

    public private(set) var phase: RetroHostGamePhase = .idle
    /// The display aspect ratio the core reports.
    public private(set) var aspect = 4.0 / 3.0
    private var pausedByPlayer = false
    private var pausedByFocus = false
    /// Whether the game is paused, by the player or by losing input focus.
    public var paused: Bool { pausedByPlayer || pausedByFocus }
    /// Whether the launcher's window has input focus.
    public private(set) var focused = true
    /// The last `status` of the game, which after it ended says why.
    public private(set) var status: RetroStatus?
    /// The status the game ended with, once `phase` is `.ended`.
    public var endStatus: RetroStatus? { phase == .ended ? status : nil }
    /// The host's output volume, 0 to 1, as the player set it.
    public private(set) var volume: Double
    /// Whether the host's output is muted.
    public private(set) var muted: Bool
    /// Why the game could not be started or followed, for logs, when no status says it.
    public private(set) var failure: String?
    /// The game was a PS2 one and its host does not list `ps2`, so it was never started.
    public private(set) var consoleRefused = false
    /// Whether the game was started with a states folder on a host that lists `saveStates`, so
    /// `saveState(_:)` and `loadState(_:)` can be asked for. A start with a folder on an older host
    /// leaves the folder out, and the game plays without save states.
    public private(set) var savesStates = false
    /// Whether the host limits a PS2 game's internal resolution (`ps2ResolutionLimits`), so the
    /// menu may offer it. False until the host has greeted the launcher.
    public var limitsPs2Resolution: Bool { session.limitsPs2Resolution }
    /// How many `saveState` and `loadState` calls have been answered.
    public private(set) var stateReplies = 0
    /// How the host's connection ended; nil while it is open. `.unsupported` means the host speaks
    /// no protocol version this launcher does: the emulator needs updating.
    public private(set) var hostEnd: RetroHostEnd?

    /// Whether a game is loaded: `phase` is `.loading` or `.playing`.
    public var loaded: Bool { phase == .loading || phase == .playing }
    /// Whether `input` reaches the host now: a game is loaded and the window has input focus.
    public var acceptsInput: Bool { loaded && focused }

    private var listeners: [Int: @MainActor () -> Void] = [:]
    private var rumbleListeners: [Int: @MainActor (RetroRumble) -> Void] = [:]
    private var nextListener = 0
    private var pollTask: Task<Void, Never>?
    private var polling = false
    private var disposed = false
    private var hostEnded = false
    private var detached = false
    private var starting: Task<Void, Never>?
    private var detaching: Task<Bool, Never>?
    private var closing: Task<Void, Never>?
    /// `stop()` has begun: the client's `stopGame()` asks `status` until the game has ended, without
    /// waiting for a state call, so no `saveState` or `loadState` is sent from then on.
    private var stopping = false
    /// A `saveState` or `loadState` is under way, until its reply: protocol.md "saveState and
    /// loadState" says a launcher MUST NOT send another call after one until that reply has come, as
    /// a call queued behind it in the host could otherwise be answered more than 5 seconds after it
    /// was sent. Every other call of this game waits for it (`afterStateCall`); pings go on.
    private var stateCallRunning = false
    /// This game's other calls that went out through `afterStateCall` and have not been answered: a
    /// state call waits for them before it is sent, as the session's calls reach the client's queue
    /// only after a hop off the main actor, so one asked just before it could otherwise go out after.
    private var callsOut = 0
    private var turnWaiters: [CheckedContinuation<Void, Never>] = []
    /// The most state replies there were when a `status` that said the game had not ended was asked.
    private var playingAfterReplies = -1

    public init(session: RetroHostSession, statusEvery: Duration = .milliseconds(500), volume: Double = 1, muted: Bool = false) {
        self.session = session
        self.statusEvery = statusEvery
        self.volume = volume
        self.muted = muted
        picture.accepting = false
        let picture = self.picture
        // Both run on the session's queues, never on the main thread.
        session.setHandlers(frame: { @Sendable event in picture.take(event) }, rumble: { @Sendable [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.deliver(event) } }
        })
        Task { [weak self] in
            let end = await session.ended()
            self?.hostDidEnd(end)
        }
    }

    // MARK: Listening

    /// `body` is called after the game's state changed (`objectWillChange` is sent too); the id
    /// removes it.
    @discardableResult
    public func addListener(_ body: @escaping @MainActor () -> Void) -> Int {
        nextListener += 1
        listeners[nextListener] = body
        return nextListener
    }

    public func removeListener(_ id: Int) { listeners[id] = nil }

    /// The core's vibration for each controller port (protocol.md "rumble"), on the main thread.
    /// The client gives nothing while the game is paused or the window has no focus, and gives
    /// zeros for both ports when the game starts, pauses, ends or loses focus.
    @discardableResult
    public func addRumbleListener(_ body: @escaping @MainActor (RetroRumble) -> Void) -> Int {
        nextListener += 1
        rumbleListeners[nextListener] = body
        return nextListener
    }

    public func removeRumbleListener(_ id: Int) { rumbleListeners[id] = nil }

    private func deliver(_ event: RetroRumble) {
        guard !disposed, !detached else { return }
        for id in rumbleListeners.keys.sorted() { rumbleListeners[id]?(event) }
    }

    private func notify() {
        guard !disposed else { return }
        objectWillChange.send()
        for id in listeners.keys.sorted() { listeners[id]?() }
    }

    private func setPhase(_ next: RetroHostGamePhase) {
        phase = next
        notify()
    }

    // MARK: Starting and following

    /// Waits for the host's greeting, then starts the game. Only one game is started per
    /// `RetroHostGame`: a second start does nothing.
    public func start(_ request: RetroHostStartRequest) async {
        guard phase == .idle else { return }
        setPhase(.starting)
        let task = Task { await self.startNow(request) }
        starting = task
        await task.value
    }

    private func startNow(_ request: RetroHostStartRequest) async {
        do {
            try await session.ready()
            guard phase == .starting else { return }
            if request.console == RetroConsole.ps2, !session.canPlayPs2 {
                consoleRefused = true
                finish(failure: "The host does not list the \(RetroProtocol.ps2Capability) capability.")
                return
            }
            let states = request.states != nil && session.canSaveStates
            // A PS2 game's internal resolution goes only to a host that limits it; an older host
            // starts the game at LRPS2's own default.
            let resolution = request.console == RetroConsole.ps2 && !session.limitsPs2Resolution
                ? request.withoutOption(RetroResolution.ps2Key) : request
            _ = try await session.startGame((states ? resolution : resolution.withoutStates()).args)
            savesStates = states
        } catch {
            if phase == .starting { finish(failure: "\(error)") }
            return
        }
        if phase == .ended {
            _ = await stopAndRelease()
            return
        }
        guard phase == .starting else { return }
        picture.clear()
        picture.accepting = true
        setPhase(.loading)
        if !focused { await pauseForFocus() }
        guard loaded else { return }
        startPolling()
        await refresh()
    }

    private func startPolling() {
        pollTask?.cancel()
        let every = statusEvery
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every)
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    /// Asks `status` once and follows it: the aspect ratio, the first frame, and the game's end.
    /// Listeners hear of it only when the status says something new: a game that plays on with the
    /// same status, asked twice a second, changes nothing.
    public func refresh() async {
        guard loaded, !polling else { return }
        polling = true
        defer { polling = false }
        do {
            var asked = 0
            let current = try await afterStateCall { () async throws -> RetroStatus? in
                asked = stateReplies
                return try await session.status()
            }
            guard loaded else { return }
            guard let current else {
                finish(failure: "The host has no game loaded.")
                return
            }
            let changed = !(status?.sameAs(current) ?? false)
            status = current
            aspect = current.aspect
            if current.ended {
                finish()
                return
            }
            if asked > playingAfterReplies { playingAfterReplies = asked }
            if current.ready, phase == .loading {
                setPhase(.playing)
            } else if changed {
                notify()
            }
        } catch {
            if loaded { finish(failure: "\(error)") }
        }
    }

    // MARK: Input and calls

    /// The controller state of one port, forwarded while a game is loaded and the launcher has input
    /// focus; the host keeps it until the next state.
    public func input(port: Int, buttons: Int, leftX: Int = 0, leftY: Int = 0, rightX: Int = 0, rightY: Int = 0) {
        guard loaded, focused else { return }
        session.input(port: port, buttons: buttons, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY)
    }

    /// `connectedPorts`: how many controller ports, from port 1, have a controller in (1 or 2).
    /// False when no game is loaded, the host did not take it, or the call failed; a host failure
    /// is then seen by the next status.
    public func connectedPorts(_ count: Int) async -> Bool {
        guard (1...2).contains(count) else { return false }
        return await gameCall("connectedPorts", .int(count))
    }

    /// `changeDisc`: inserts the disc at `index` of `status.discs.labels`. True when the change
    /// started; the status is asked at once, so the menu shows its progress.
    public func changeDisc(_ index: Int) async -> Bool {
        guard (0...127).contains(index) else { return false }
        let started = await gameCall("changeDisc", .int(index))
        if started { await refresh() }
        return started
    }

    /// `option`: sets a core option the status lists to one of its values. True when the host
    /// took it; the status is asked at once, so the option shows its new choice.
    public func setOption(key: String, value: String) async -> Bool {
        let taken = await gameCall("option", .object(["key": .string(key), "value": .string(value)]))
        if taken { await refresh() }
        return taken
    }

    /// `volume`: the host's output volume for this and every later game. Sent once the host has
    /// greeted the launcher; only kept when the host has ended or never greeted it.
    public func setVolume(level: Double? = nil, muted: Bool? = nil) async {
        if let level, level.isNaN || level < 0 || level > 1 { return }
        volume = level ?? volume
        self.muted = muted ?? self.muted
        notify()
        do {
            try await session.ready()
            if hostEnded || phase == .closed { return }
            let args: RetroJSON = .object(["level": .number(volume), "muted": .bool(self.muted)])
            _ = try await afterStateCall { try await session.call("volume", args) }
        } catch {
            return
        }
    }

    private func gameCall(_ method: String, _ args: RetroJSON) async -> Bool {
        guard loaded else { return false }
        return (try? await afterStateCall { try await session.call(method, args) }) == .bool(true)
    }

    // MARK: Save states

    /// `saveState`: saves the game's state into `slot`, 0 to 7, of the states folder it was started
    /// with (`savesStates`). The host writes it between two frames, also while paused.
    public func saveState(_ slot: Int) async -> RetroStateOutcome { await stateCall("saveState", slot) }

    /// `loadState`: loads the state in `slot`, 0 to 7, back into the game; a paused game shows it
    /// with its next frame once resumed. A state of another game or core build is refused
    /// (`.otherGame`, `.otherCore`) and the game runs on.
    public func loadState(_ slot: Int) async -> RetroStateOutcome { await stateCall("loadState", slot) }

    /// Whether a status asked once `replies` state calls had been answered said the game had not
    /// ended. A load that the core began but did not finish ends the game before the host replies
    /// `false` (the host's `Game::AwaitStateWork`), so after a `loadState` answered `false` this says
    /// the load left the game untouched and it plays on.
    public func playingAfter(_ replies: Int) -> Bool { playingAfterReplies >= replies }

    private func stateCall(_ method: String, _ slot: Int) async -> RetroStateOutcome {
        guard (0..<RetroStateFolder.slots).contains(slot) else { return .failed }
        guard loaded, savesStates, !stopping else { return .notNow }
        while stateCallRunning { await waitTurn() }
        guard loaded, !stopping else { return .notNow }
        stateCallRunning = true
        defer {
            stateCallRunning = false
            wakeTurns()
        }
        while callsOut > 0 { await waitTurn() }
        guard loaded, !stopping else { return .notNow }
        let outcome: RetroStateOutcome
        do {
            let result = try await session.call(method, .object(["slot": .int(slot)]))
            outcome = result.objectValue != nil ? .done : .notNow
        } catch let error as RetroCallError {
            outcome = RetroStateOutcome(errorCode: error.code)
        } catch {
            outcome = .failed
        }
        stateReplies += 1
        return outcome
    }

    /// Sends `send` once no `saveState` or `loadState` is under way, and counts it as out until its
    /// reply, so a state call asked meanwhile waits for it.
    private func afterStateCall<T>(_ send: () async throws -> T) async rethrows -> T {
        while stateCallRunning { await waitTurn() }
        callsOut += 1
        defer {
            callsOut -= 1
            if callsOut == 0 { wakeTurns() }
        }
        return try await send()
    }

    private func waitTurn() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in turnWaiters.append(continuation) }
    }

    private func wakeTurns() {
        let waiting = turnWaiters
        turnWaiters = []
        for waiter in waiting { waiter.resume() }
    }

    // MARK: Pausing

    /// Pauses or resumes the game for the player. A game paused by losing focus stays paused until
    /// focus comes back.
    public func pause(_ pause: Bool) async {
        guard loaded, pausedByPlayer != pause else { return }
        let wasPaused = paused
        pausedByPlayer = pause
        await sendPause(wasPaused)
    }

    /// Tells the game whether the launcher's window has input focus. Losing it zeroes the
    /// controllers' input and motors, and pauses the game until focus comes back.
    public func setFocused(_ focused: Bool) async {
        guard self.focused != focused else { return }
        self.focused = focused
        if !hostEnded, phase != .closed { session.setInputFocus(focused) }
        guard loaded else { return notify() }
        if focused {
            let wasPaused = paused
            pausedByFocus = false
            await sendPause(wasPaused)
        } else {
            await pauseForFocus()
        }
    }

    private func pauseForFocus() async {
        let wasPaused = paused
        pausedByFocus = true
        await sendPause(wasPaused)
    }

    private func sendPause(_ wasPaused: Bool) async {
        let now = paused
        notify()
        guard now != wasPaused else { return }
        do {
            _ = try await afterStateCall { try await session.call("pause", .bool(now)) }
        } catch {
            if loaded { finish(failure: "\(error)") }
        }
    }

    // MARK: The end

    /// Stops the game and forgets it in the host, giving the status it ended with. A game still
    /// starting is cancelled: if the host already accepted `start`, that game is stopped as soon as
    /// the reply comes, and this waits for it.
    @discardableResult
    public func stop() async -> RetroStatus? {
        if phase == .starting {
            finish(failure: "Stopped before the game started.")
            await starting?.value
            return nil
        }
        guard loaded else { return endStatus }
        pollTask?.cancel()
        picture.accepting = false
        stopping = true
        let ended = await stopAndRelease()
        if phase == .closed { return ended }
        if let ended { status = ended }
        finish()
        return ended
    }

    private func stopAndRelease() async -> RetroStatus? {
        do {
            let ended = try await afterStateCall { try await session.stopGame() }
            _ = try await afterStateCall { try await session.call("release", .null) }
            return ended
        } catch {
            failure = "\(error)"
            return nil
        }
    }

    /// Lets go of the host without shutting it down, so a next game can start on it: protocol.md
    /// "Processes" says "One host runs games one after another until the launcher exits or the host
    /// fails." The game is stopped if it still runs, and an ended game is forgotten with `release`,
    /// since `start` is `busy` "if a game is loaded, running or ended". True when the host still
    /// runs and `status` then says no game is loaded; the caller may then start the next game on
    /// `session` and must shut it down itself. False when the host ended, was shut down, or still
    /// holds a game: the host is shut down as usual. The window's focus is given back to the host,
    /// as a new host starts with it. Every caller waits for the same answer.
    public func detach() async -> Bool {
        if let detaching { return await detaching.value }
        let task = Task { await self.detachNow() }
        detaching = task
        return await task.value
    }

    private func detachNow() async -> Bool {
        if closing != nil { return false }
        _ = await stop()
        pollTask?.cancel()
        picture.accepting = false
        picture.clear()
        var free = false
        if !hostEnded, closing == nil {
            do {
                _ = try await afterStateCall { try await session.call("release", .null) }
                let left = try await afterStateCall { try await session.status() }
                free = left == nil && !hostEnded && closing == nil
            } catch {
                if failure == nil { failure = "\(error)" }
            }
        }
        if !free {
            await shutdown()
            return false
        }
        detached = true
        session.setHandlers(frame: nil, rumble: nil)
        if !focused { session.setInputFocus(true) }
        setPhase(.closed)
        return true
    }

    /// Asks the host to exit and frees the connection once it has; the client kills a host that has
    /// not exited within its time limit. Every caller waits for the same shutdown. A host this game
    /// was detached from is no longer its own: nothing is done.
    public func shutdown() async {
        if closing == nil {
            if detached {
                closing = Task {}
            } else {
                pollTask?.cancel()
                setPhase(.closed)
                picture.accepting = false
                picture.clear()
                session.shutdown()
                let session = self.session
                closing = Task {
                    _ = await session.ended()
                    await session.close()
                }
            }
        }
        await closing?.value
    }

    private func hostDidEnd(_ end: RetroHostEnd) {
        hostEnded = true
        hostEnd = end
        if phase != .closed, !disposed {
            if loaded {
                Task { await self.refresh() }
            } else if phase == .starting {
                finish(failure: "The host ended before the game started.")
            }
        }
        notify()
    }

    private func finish(failure: String? = nil) {
        pollTask?.cancel()
        if let failure { self.failure = failure }
        pausedByFocus = false
        pausedByPlayer = false
        picture.accepting = false
        picture.clear()
        setPhase(.ended)
    }

    /// Shuts the host down if nothing did yet, unless it was detached for the next game, and
    /// tells no one anything more.
    public func dispose() {
        guard !disposed else { return }
        disposed = true
        pollTask?.cancel()
        if detaching == nil { Task { await self.shutdown() } }
    }
}
