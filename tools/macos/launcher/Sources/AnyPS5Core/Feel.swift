import CoreGraphics
import Foundation

// How the launcher feels under a thumb, a finger and a pointer: one repeat for the pad and the
// keys, a stick that does not flutter, a bump at the end of a row, a tick when the pointer arrives
// on something and soft pulses in the controller. The Windows/Linux launcher (AnyPS5 Desktop,
// lib/core/gamepad/feel.dart) uses the same numbers.

/// A held direction, keyboard or controller alike: it moves at once, again after 0.40 s, then
/// every 0.08 s and, after six repeats, every 0.06 s.
public enum KeyRepeat {
    public static let firstDelay: TimeInterval = 0.40
    public static let interval: TimeInterval = 0.08
    public static let fastInterval: TimeInterval = 0.06
    /// Repeats at `interval` before the pace picks up.
    public static let fastAfter = 6

    /// The wait before repeat number `repeatNumber` (1 is the first) since the move before it;
    /// `first` in place of `firstDelay` before the first (the stick's up and down, StickGate).
    public static func delay(beforeRepeat repeatNumber: Int, firstDelay first: TimeInterval = firstDelay) -> TimeInterval {
        repeatNumber <= 1 ? first : repeatNumber <= fastAfter ? interval : fastInterval
    }

    /// When a hold of `duration` seconds moves: 0 for the press, then each repeat.
    public static func times(within duration: TimeInterval, firstDelay first: TimeInterval = firstDelay) -> [TimeInterval] {
        var times: [TimeInterval] = [0]
        var time: TimeInterval = 0
        var repeatNumber = 1
        while true {
            time += delay(beforeRepeat: repeatNumber, firstDelay: first)
            guard time <= duration + 1e-9 else { return times }
            times.append(time)
            repeatNumber += 1
        }
    }
}

/// The left stick as a direction with hysteresis: left and right engage past 0.5 and let go only
/// below 0.3, so a stick resting near the line does not flutter; a flick through the middle turns
/// at once.
///
/// Up and down are harder to reach, as on Home one of them leaves the tiles for the top bar or the
/// buttons: they engage only past 0.65 and with the stick clearly upright (Y at least 1.2 times X;
/// a diagonal goes sideways), let go below 0.4, take over from a held left or right only when Y
/// leads by half again, and repeat first after `verticalFirstDelay`. A thumb sweeping in an arc on
/// its way to the side, a light push or a wobble moved up or down before. Letting go of one axis,
/// the other engages only from the next sample.
public struct StickGate: Sendable {
    public static let engage = 0.5
    public static let release = 0.3
    public static let verticalEngage = 0.65
    public static let verticalRelease = 0.4
    /// How much Y must lead X for up or down to engage.
    public static let verticalLead = 1.2
    /// How much the other axis must lead to take over a held direction: left or right from up or
    /// down, up or down from left or right.
    public static let switchRatio = 1.25
    public static let verticalSwitchRatio = 1.5
    /// Up and down held on the stick repeat first after this (the D-pad and the keys, and left and
    /// right, after KeyRepeat.firstDelay).
    public static let verticalFirstDelay: TimeInterval = 0.55

    public private(set) var held: Command?

    public init() {}

    public static func isVertical(_ direction: Command) -> Bool { direction == .up || direction == .down }

    /// `x` right positive, `y` up positive, both -1 to 1.
    public mutating func update(x: Double, y: Double) -> Command? {
        if let direction = held {
            let vertical = Self.isVertical(direction)
            let along = Self.along(direction, x: x, y: y)
            if along >= (vertical ? Self.verticalRelease : Self.release) {
                let other = vertical ? x : y
                let takesOver = vertical
                    ? abs(other) >= Self.engage && abs(other) > along * Self.switchRatio
                    : abs(other) >= Self.verticalEngage && abs(other) > along * Self.verticalSwitchRatio
                if takesOver {
                    held = vertical ? (other > 0 ? .right : .left) : (other > 0 ? .up : .down)
                }
                return held
            }
            held = nil
            // The other axis waits for the next sample; the same axis turns at once (a flick).
            if let next = Self.engaged(x: x, y: y), Self.isVertical(next) == vertical { held = next }
            return held
        }
        held = Self.engaged(x: x, y: y)
        return held
    }

    static func engaged(x: Double, y: Double) -> Command? {
        if abs(y) >= verticalEngage && abs(y) >= abs(x) * verticalLead { return y > 0 ? .up : .down }
        if abs(x) >= engage && abs(x) >= abs(y) { return x > 0 ? .right : .left }
        return nil
    }

    static func along(_ direction: Command, x: Double, y: Double) -> Double {
        switch direction {
        case .right: return x
        case .left: return -x
        case .up: return y
        case .down: return -y
        default: return 0
        }
    }
}

/// A direction with nowhere to go (the first or last tile, the end of a list) answers with a
/// bump: once per press, and once in a hold that reaches the end. Nothing wraps around that did
/// not wrap before.
public struct EdgeBump: Sendable {
    private var bumped = false

    public init() {}

    public static func isDirection(_ command: Command) -> Bool {
        command == .left || command == .right || command == .up || command == .down
    }

    /// After a command was handled: whether it bumps. `repeat` for the repeats of a held
    /// direction; `changed` when it moved the focus or did anything else.
    public mutating func handled(_ command: Command, repeat isRepeat: Bool, changed: Bool) -> Bool {
        if !isRepeat { bumped = false }
        guard Self.isDirection(command), !changed, !bumped else { return false }
        bumped = true
        return true
    }
}

/// The soft tick when the pointer arrives on a control, tile, row or card: one per arrival on a
/// new element, only after the pointer itself moved (not when a list scrolls under it), at most
/// one every 60 ms (a dropped one is not told late), none within 90 ms of another sound or with
/// a mouse button held, and none when sounds are off, a game is in front or the launcher is behind.
public struct HoverGate: Sendable {
    public static let minimumGap: TimeInterval = 0.06
    public static let afterCue: TimeInterval = 0.09
    /// Points the pointer must have moved since the last arrival.
    public static let movement: CGFloat = 2

    private var current: String?
    private var pointer: CGPoint?
    private var lastTick: TimeInterval = -.infinity

    public init() {}

    public mutating func arrive(_ id: String, pointer location: CGPoint, now: TimeInterval, lastCue: TimeInterval?, buttonsDown: Bool, allowed: Bool) -> Bool {
        let moved = pointer.map { hypot(location.x - $0.x, location.y - $0.y) >= Self.movement } ?? true
        pointer = location
        guard id != current else { return false }
        current = id
        guard allowed, !buttonsDown, moved, now - lastTick >= Self.minimumGap else { return false }
        if let lastCue, now - lastCue < Self.afterCue { return false }
        lastTick = now
        return true
    }

    /// The pointer left `id`: arriving on it again is an arrival.
    public mutating func leave(_ id: String) {
        if current == id { current = nil }
    }
}

/// What the controller's motors say.
public enum HapticCue: String, CaseIterable, Sendable {
    case select, back, error, trophy, ring, edge

    /// The pulse an interface sound comes with: select, back and the bump; moving and hovering
    /// have none, and trophies, calls and errors are told on their own.
    public init?(sound: String) {
        switch sound {
        case "select": self = .select
        case "back": self = .back
        case "bump": self = .edge
        default: return nil
        }
    }
}

/// One pulse: when it starts and how long it lasts (seconds), and how hard each motor turns, 0 to
/// 1: `strong` the heavy low motor (or a deep, round haptic), `weak` the light high one (a crisp
/// tap).
public struct HapticPulse: Equatable, Sendable {
    public var start: TimeInterval
    public var length: TimeInterval
    public var strong: Double
    public var weak: Double

    public init(start: TimeInterval, length: TimeInterval, strong: Double, weak: Double) {
        self.start = start
        self.length = length
        self.strong = strong
        self.weak = weak
    }

    /// One number for an actuator with a single strength (Core Haptics' intensity).
    public var intensity: Double { max(strong, weak) }
    /// How crisp it is, 0 (round) to 1 (sharp): a tap on the light motor is sharp.
    public var sharpness: Double { strong + weak == 0 ? 0.5 : weak / (strong + weak) }
}

/// The pulses: select one very light tap, back a lighter one, an error two short taps, a trophy
/// three that swell, a call a heavy beat then a light one, the edge bump barely there.
public enum HapticPatterns {
    public static func pulses(for cue: HapticCue) -> [HapticPulse] {
        switch cue {
        case .select: return [HapticPulse(start: 0, length: 0.018, strong: 0, weak: 0.42)]
        case .back: return [HapticPulse(start: 0, length: 0.014, strong: 0, weak: 0.30)]
        case .edge: return [HapticPulse(start: 0, length: 0.012, strong: 0, weak: 0.20)]
        case .error:
            return [HapticPulse(start: 0, length: 0.035, strong: 0.45, weak: 0.35),
                    HapticPulse(start: 0.09, length: 0.035, strong: 0.45, weak: 0.35)]
        case .trophy:
            return [HapticPulse(start: 0, length: 0.04, strong: 0.25, weak: 0.30),
                    HapticPulse(start: 0.11, length: 0.045, strong: 0.40, weak: 0.40),
                    HapticPulse(start: 0.23, length: 0.07, strong: 0.60, weak: 0.50)]
        case .ring:
            return [HapticPulse(start: 0, length: 0.08, strong: 0.70, weak: 0.30),
                    HapticPulse(start: 0.16, length: 0.05, strong: 0.25, weak: 0.35)]
        }
    }
}

/// Where pulses go: a controller's haptics, or a fake in tests. `stop` sets every motor to zero.
public protocol HapticOutput: AnyObject {
    func play(_ pulses: [HapticPulse])
    func stop()
}

/// Decides whether a pulse plays: the setting on, the launcher in front (never while a game is:
/// the game owns the pad) and the controller the device in use (no buzz on the desk while the
/// keyboard and mouse are used). The same cue twice within 30 ms plays once.
public final class HapticFeedback {
    public static let sameCueGap: TimeInterval = 0.03

    public var enabled: Bool {
        didSet { if !enabled && oldValue { output.stop() } }
    }
    /// The controller sent the last input (not the keyboard or the mouse).
    public var padInUse = false
    /// The launcher's window is in front; false while a game or another app is.
    public var launcherInFront = true {
        didSet { if !launcherInFront && oldValue { output.stop() } }
    }

    private let output: HapticOutput
    private var last: (cue: HapticCue, time: TimeInterval)?

    public init(output: HapticOutput, enabled: Bool = true) {
        self.output = output
        self.enabled = enabled
    }

    @discardableResult
    public func play(_ cue: HapticCue, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard enabled, launcherInFront, padInUse else { return false }
        if let last, last.cue == cue, now - last.time < Self.sameCueGap { return false }
        last = (cue, now)
        output.play(HapticPatterns.pulses(for: cue))
        return true
    }

    public func stop() { output.stop() }
}
