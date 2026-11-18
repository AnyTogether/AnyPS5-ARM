import Foundation

/// What the launcher's UI uses of one emulator host connection, as on Windows and Linux (AnyPS5
/// Desktop's lib/core/retro_host/retro_host_session.dart). `RetroHostClientSession` is the real
/// one; tests give a fake, so the UI is tested without starting a host.
public protocol RetroHostSession: AnyObject, Sendable {
    /// Returns once the host greeted the launcher; throws `RetroHostGone` when it never did.
    func ready() async throws
    /// How the connection ended.
    func ended() async -> RetroHostEnd
    /// How the connection ended, once it has.
    var end: RetroHostEnd? { get }
    /// Whether the launcher's window has input focus; losing it zeroes input and motors.
    func setInputFocus(_ focused: Bool)
    /// `start`: loads a game and gives its epoch.
    func startGame(_ args: RetroJSON) async throws -> Int
    /// Any call but `stop`; `error` replies throw `RetroCallError`.
    func call(_ method: String, _ args: RetroJSON) async throws -> RetroJSON
    /// `status`: nil with no game loaded.
    func status() async throws -> RetroStatus?
    /// `stop`, then `status` until the game has ended, which it gives.
    func stopGame() async throws -> RetroStatus?
    /// The controller state of one port.
    func input(port: Int, buttons: Int, leftX: Int, leftY: Int, rightX: Int, rightY: Int)
    /// Whether the host lists `ps2`, so a PS2 game can be started on it.
    var canPlayPs2: Bool { get }
    /// Whether the host lists `saveStates`, so a game can be started with a states folder
    /// (`RetroHostStartRequest.states`) and saved and loaded with `saveState` and `loadState`.
    var canSaveStates: Bool { get }
    /// Asks the host to stop its game and exit.
    func shutdown()
    /// Kills the host if it still runs and frees the connection.
    func close() async
    /// Where each `frame` event and each `rumble` go: `frame` is called on the session's own queue,
    /// where the frame may be read and only there; `rumble` on any queue.
    func setHandlers(frame: ((RetroFrameEvent) -> Void)?, rumble: ((RetroRumble) -> Void)?)
}

/// One real emulator host, started through `RetroHostClient`.
public final class RetroHostClientSession: RetroHostSession, @unchecked Sendable {
    /// The handlers the client's own callbacks pass events on to.
    final class Relay: @unchecked Sendable {
        private let lock = NSLock()
        private var frame: ((RetroFrameEvent) -> Void)?
        private var rumble: ((RetroRumble) -> Void)?

        func set(frame: ((RetroFrameEvent) -> Void)?, rumble: ((RetroRumble) -> Void)?) {
            lock.withLock {
                self.frame = frame
                self.rumble = rumble
            }
        }

        func onFrame(_ event: RetroFrameEvent) { lock.withLock { frame }?(event) }
        func onRumble(_ event: RetroRumble) { lock.withLock { rumble }?(event) }
    }

    public let client: RetroHostClient
    private let relay: Relay

    private init(client: RetroHostClient, relay: Relay) {
        self.client = client
        self.relay = relay
    }

    /// Starts a host from `command`, through `checked` for a signed release's host
    /// (`RetroHostClient.start(command:checked:...)`), with the player's volume.
    public static func start(command: [String], checked: RetroHostChecked?, environment: [String: String] = [:],
                             volume: Double, muted: Bool) async throws -> RetroHostClientSession {
        let relay = Relay()
        let client = try await RetroHostClient.start(command: command, checked: checked, environment: environment, volume: volume,
                                                     muted: muted, onFrame: { relay.onFrame($0) }, onRumble: { relay.onRumble($0) })
        return RetroHostClientSession(client: client, relay: relay)
    }

    public func ready() async throws { try await client.ready() }
    public func ended() async -> RetroHostEnd { await client.ended() }
    public var end: RetroHostEnd? { client.end }
    public func setInputFocus(_ focused: Bool) { client.setInputFocus(focused) }
    public func startGame(_ args: RetroJSON) async throws -> Int { try await client.startGame(args) }
    public func call(_ method: String, _ args: RetroJSON) async throws -> RetroJSON { try await client.call(method, args) }
    public func status() async throws -> RetroStatus? { try await client.status() }
    public func stopGame() async throws -> RetroStatus? { try await client.stopGame() }

    public func input(port: Int, buttons: Int, leftX: Int, leftY: Int, rightX: Int, rightY: Int) {
        try? client.input(port: port, buttons: buttons, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY)
    }

    public var canPlayPs2: Bool { client.canPlayPs2 }
    public var canSaveStates: Bool { client.canSaveStates }
    public func shutdown() { client.shutdown() }
    public func close() async { await client.close() }

    public func setHandlers(frame: ((RetroFrameEvent) -> Void)?, rumble: ((RetroRumble) -> Void)?) {
        relay.set(frame: frame, rumble: rumble)
    }
}

/// The `start` call's argument (anyps5-retro-host docs/protocol.md "start").
public struct RetroHostStartRequest: Equatable, Sendable {
    /// The SwanStation library the launcher checked, or for a PS2 game the LRPS2 library.
    public var core: String
    /// A `.cue`, `.chd`, `.pbp` or `.m3u` file; for a PS2 game a `.iso`, `.chd`, `.cso`, `.zso`,
    /// `.cue` or `.elf` file.
    public var disc: String
    /// The core's system directory (BIOS files).
    public var system: String
    /// Where memory cards are kept.
    public var saves: String
    /// Core option values saved by the player, by key.
    public var options: [String: String]
    /// Only for an `.m3u`: the playlist entry to insert at boot, 0 to 127.
    public var initialDisc: Int?
    /// `RetroConsole.ps2` for a PS2 game, which only a host that lists `ps2` takes; nil for a PS1
    /// game, the host's default, so a PS1 start is the same on every host.
    public var console: String?
    /// The folder for this game's save states, which only a host that lists `saveStates` takes; nil
    /// for a game without save states.
    public var states: String?

    public init(core: String, disc: String, system: String, saves: String, options: [String: String] = [:],
                initialDisc: Int? = nil, console: String? = nil, states: String? = nil) {
        self.core = core
        self.disc = disc
        self.system = system
        self.saves = saves
        self.options = options
        self.initialDisc = initialDisc
        self.console = console
        self.states = states
    }

    /// The same start without `states`, for a host that does not list `saveStates`.
    public func withoutStates() -> RetroHostStartRequest {
        var request = self
        request.states = nil
        return request
    }

    /// The `start` arguments: `console`, `options`, `initialDisc` and `states` only when given.
    public var args: RetroJSON {
        var map: [String: RetroJSON] = [
            "core": .string(core), "disc": .string(disc), "system": .string(system), "saves": .string(saves),
        ]
        if let console { map["console"] = .string(console) }
        if !options.isEmpty { map["options"] = .object(options.mapValues { .string($0) }) }
        if let initialDisc { map["initialDisc"] = .int(initialDisc) }
        if let states { map["states"] = .string(states) }
        return .object(map)
    }
}
