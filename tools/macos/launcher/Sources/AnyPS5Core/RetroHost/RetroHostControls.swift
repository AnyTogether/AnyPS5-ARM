import Foundation

/// The launcher's controllers as a game reads them: which are connected, in the launcher's order
/// (Player 1 first), and each one's whole state.
public struct RetroPadReader {
    /// The ids of the controllers connected now.
    public let pads: () -> [String]
    /// Everything a controller holds now; nil for one the reader does not know.
    public let state: (String) -> PadState?

    public init(pads: @escaping () -> [String], state: @escaping (String) -> PadState?) {
        self.pads = pads
        self.state = state
    }
}

/// The controllers' motors.
@MainActor
public protocol RetroPadMotors: AnyObject {
    /// Whether `pad` can vibrate here.
    func canRumble(_ pad: String) -> Bool
    /// Turns `pad`'s motors to `strong` and `weak` (0 to 1) for `hold`; zeros for `.zero` stop them.
    func rumble(_ pad: String, strong: Double, weak: Double, hold: Duration)
}

/// Plays a `RetroHostGame` with the launcher's controllers, as on Windows and Linux (AnyPS5
/// Desktop's lib/ui/retro_host/retro_host_controls.dart): their state becomes `input` for the port
/// each one sits at (`RetroSeats`), port 2 is connected while a second controller is there
/// (`connectedPorts`), and the core's vibration goes to the controller at its port.
///
/// The controllers are read every `every`. A port's state is sent when it changes, and again in
/// full whenever the game starts taking input (a game that loaded, focus that came back), because
/// the client zeroes both ports when it starts a game or loses focus. While `suspended` (an in-game
/// menu is open) both ports are sent as idle, and a button still held when it ends reaches the
/// game only once it is let go and pressed again.
@MainActor
public final class RetroHostControls {
    public let game: RetroHostGame
    public let pads: RetroPadReader
    /// The controllers' motors; nil where the reader cannot turn them.
    public let motors: RetroPadMotors?
    /// The keyboard's state now, joined to the controller at port 1 (`RetroKeyboard.merge`); nil
    /// when the keyboard does not play.
    public let keyboard: (() -> PadState)?
    public let every: Duration
    /// How long one rumble order lasts. The protocol's `rumble` holds until the next one, but the
    /// motors stop after the length they are given, so a level that is not zero is given again
    /// every half of this.
    public let rumbleHold: Duration

    /// Settings › Controllers › Stick Dead Zone, in percent.
    public var deadzonePercent = 0

    /// Whether the core's vibration reaches the controllers.
    public var vibration = true {
        didSet { if !vibration, oldValue { stopMotors() } }
    }

    public private(set) var seats = RetroSeats()

    private var sent: [RetroPadInput?] = Array(repeating: nil, count: RetroSeats.portCount)
    private var swallowed: [Int] = Array(repeating: 0, count: RetroSeats.portCount)
    private var levels: [(strong: Int, weak: Int)] = Array(repeating: (0, 0), count: RetroSeats.portCount)
    /// The `connectedPorts` the host has: 1 for a game that has not loaded yet ("A game starts with
    /// 1"), unknown (nil) for one that was loaded before these controls, so it is sent.
    private var portsSent: Int?
    /// The `connectedPorts` asked last and not answered yet. A count is the host's only once it
    /// says it took it, so a call that failed is asked again by the next read.
    private var portsAsked: Int?
    private var disposed = false
    private var listener = 0
    private var rumbleListener = 0
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    /// `polls` false reads the controllers only when `poll()` is called (the tests).
    public init(game: RetroHostGame, pads: RetroPadReader, motors: RetroPadMotors? = nil, keyboard: (() -> PadState)? = nil,
                every: Duration = .milliseconds(16), rumbleHold: Duration = .seconds(2), polls: Bool = true) {
        self.game = game
        self.pads = pads
        self.motors = motors
        self.keyboard = keyboard
        self.every = every
        self.rumbleHold = rumbleHold
        portsSent = game.loaded ? nil : 1
        rumbleListener = game.addRumbleListener { [weak self] event in self?.onRumble(event) }
        listener = game.addListener { [weak self] in self?.onGameChanged() }
        if polls {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: every)
                    if Task.isCancelled { return }
                    self?.poll()
                }
            }
        }
        let half = rumbleHold / 2
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: half)
                if Task.isCancelled { return }
                self?.refreshRumble()
            }
        }
    }

    /// Whether the controllers' presses are kept from the game (an in-game menu is open): both
    /// ports are sent as idle until it is false again. The buttons held when it becomes false (the
    /// press that closed the menu) stay out of the game until they are let go.
    public var suspended = false {
        didSet {
            guard suspended != oldValue else { return }
            if !suspended, !disposed {
                syncSeats()
                for port in 0..<RetroSeats.portCount { swallowed[port] = read(port)?.buttons ?? 0 }
            }
            poll()
        }
    }

    /// The game stopped taking input: the client zeroed both ports (a game that started, focus that
    /// was lost), so what was sent is forgotten and sent again once it takes input. Told at each
    /// change, so focus lost and back between two reads is not missed. Once no game is loaded (it
    /// ended, or the host was shut down, which sends no `rumble`), the motors stop too.
    private func onGameChanged() {
        if game.acceptsInput { return }
        sent = Array(repeating: nil, count: RetroSeats.portCount)
        if game.loaded { return }
        portsSent = 1
        stopMotors()
        levels = Array(repeating: (0, 0), count: RetroSeats.portCount)
    }

    /// What the controller at `port` holds now, with the keyboard at port 1, or nil for a port
    /// without either.
    private func read(_ port: Int) -> RetroPadInput? {
        let padState = seats.at(port).flatMap { pads.state($0) }
        let keys = port == 0 ? keyboard?() : nil
        let state = keys.map { RetroKeyboard.merge(padState, $0) } ?? padState
        return state.map { RetroPadInput.fromPad($0, deadzonePercent: deadzonePercent) }
    }

    /// Reads the controllers and sends what changed (tests drive this; the timer calls it).
    public func poll() {
        guard !disposed else { return }
        syncSeats()
        let held = (0..<RetroSeats.portCount).map { suspended ? nil : read($0) }
        for port in 0..<RetroSeats.portCount { swallowed[port] &= held[port]?.buttons ?? 0 }
        guard game.acceptsInput else { return onGameChanged() }
        let count = seats.connectedPorts
        if count != (portsAsked ?? portsSent) {
            portsAsked = count
            Task { await self.sendPorts(count) }
        }
        for port in 0..<RetroSeats.portCount {
            let input = held[port].map { $0.withButtons($0.buttons & ~swallowed[port]) } ?? .idle
            if input == sent[port] { continue }
            sent[port] = input
            game.input(port: port, buttons: input.buttons, leftX: input.leftX, leftY: input.leftY, rightX: input.rightX, rightY: input.rightY)
        }
    }

    private func sendPorts(_ count: Int) async {
        let taken = await game.connectedPorts(count)
        if portsAsked == count { portsAsked = nil }
        if taken, !disposed, game.loaded { portsSent = count }
    }

    /// Seats the controllers connected now, and lets go of what a leaving one had.
    private func syncSeats() {
        for change in seats.sync(pads.pads()) where !change.joined { left(change) }
    }

    /// A controller left its port: its motors stop (protocol.md "rumble": "when a controller
    /// leaves its port"), and the port is sent as idle by the next state that is sent.
    private func left(_ change: RetroSeatChange) {
        swallowed[change.port] = 0
        if levels[change.port] != (0, 0) {
            levels[change.port] = (0, 0)
            setMotors(change.pad, 0, 0)
        }
    }

    /// The core's vibration for a port, kept and given to the controller there. Nothing once no
    /// game is loaded: a `rumble` still coming while the host shuts down must not start the motors
    /// that stopped with the game.
    private func onRumble(_ event: RetroRumble) {
        guard !disposed, game.loaded else { return }
        syncSeats()
        levels[event.port] = (event.strong, event.weak)
        if let pad = seats.at(event.port) { setMotors(pad, event.strong, event.weak) }
    }

    private func refreshRumble() {
        for port in 0..<RetroSeats.portCount {
            let level = levels[port]
            if let pad = seats.at(port), level.strong != 0 || level.weak != 0 { setMotors(pad, level.strong, level.weak) }
        }
    }

    private func setMotors(_ pad: String, _ strong: Int, _ weak: Int) {
        let on = strong != 0 || weak != 0
        guard let motors, !(on && !vibration), motors.canRumble(pad) else { return }
        motors.rumble(pad, strong: Double(strong) / 0xFFFF, weak: Double(weak) / 0xFFFF, hold: on ? rumbleHold : .zero)
    }

    private func stopMotors() {
        guard let motors else { return }
        for port in 0..<RetroSeats.portCount {
            if let pad = seats.at(port), levels[port] != (0, 0), motors.canRumble(pad) {
                motors.rumble(pad, strong: 0, weak: 0, hold: .zero)
            }
        }
    }

    /// Stops reading the controllers, lets go of what they held in a game that goes on, and stops
    /// any motor the game left running.
    public func dispose() {
        guard !disposed else { return }
        for port in 0..<RetroSeats.portCount {
            if let input = sent[port], input != .idle { game.input(port: port, buttons: 0) }
        }
        pollTask?.cancel()
        refreshTask?.cancel()
        game.removeListener(listener)
        game.removeRumbleListener(rumbleListener)
        stopMotors()
        disposed = true
    }
}
