import Foundation
import IOKit.ps

/// The Mac's power: on its battery, and how full that is.
public struct PowerState: Equatable, Sendable {
    public var onBattery: Bool
    /// Percent, nil when the battery does not say.
    public var level: Int?

    public init(onBattery: Bool, level: Int?) {
        self.onBattery = onBattery
        self.level = level
    }

    /// On mains power (or a Mac without a battery).
    public static let mains = PowerState(onBattery: false, level: nil)

    /// Below this, on battery, nothing is prepared in the background.
    public static let lowLevel = 30

    /// Running on a battery below `lowLevel` (or one that does not say how full it is).
    public var low: Bool { onBattery && (level ?? 0) < PowerState.lowLevel }

    /// The Mac's power now, from IOKit's power sources.
    public static func current() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .mains }
        let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        guard source == kIOPSBatteryPowerValue else { return .mains }
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            if let current, let maximum, maximum > 0 { return PowerState(onBattery: true, level: current * 100 / maximum) }
            return PowerState(onBattery: true, level: current)
        }
        return PowerState(onBattery: true, level: nil)
    }
}

/// What the background preparation looks at before each step.
public struct PrepareConditions: Equatable, Sendable {
    /// Settings → Game Library → Prepare New Games Automatically.
    public var enabled = true
    /// A game is starting or running.
    public var playing = false
    /// The user's own unlocks are running or waiting.
    public var unlocking = false
    public var power = PowerState.mains

    public init(enabled: Bool = true, playing: Bool = false, unlocking: Bool = false, power: PowerState = .mains) {
        self.enabled = enabled
        self.playing = playing
        self.unlocking = unlocking
        self.power = power
    }

    /// Nothing in the way.
    public static let idle = PrepareConditions()
}

/// Why a new game was not prepared.
public enum PrepareSkip: Equatable, Sendable {
    case battery(Int?)
    case space(SpaceShortage)
}

/// New games unlocked in the background like a console installing them: one at a time, only
/// while no game plays and the user's own unlocks are done, never on a low battery, never on a
/// drive without the room. A game started meanwhile stops the preparation where it is until the
/// game closes; the user's own unlock does too, unless they asked to play the game being
/// prepared (`promote`).
///
/// The launcher calls `step` whenever something changed (a scan, a game starting or ending, an
/// unlock done, the power) until it answers `.none`, and does what each answer says.
public struct PrepareQueue: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Nothing to do now.
        case none
        /// Unlock this game in the background.
        case start(String)
        /// Stop the background unlock where it is.
        case pause
        /// Let it go on.
        case resume
        /// This game will not be prepared, and why.
        case skip(String, PrepareSkip)
    }

    /// Waiting, in the order they came.
    public private(set) var pending: [String] = []
    /// Being prepared.
    public private(set) var active: String?
    public private(set) var paused = false
    /// The user asked to play the game being prepared.
    public private(set) var promoted = false

    public init() {}

    public func contains(_ id: String) -> Bool { active == id || pending.contains(id) }

    /// New games from a scan, after those already waiting.
    public mutating func add(_ ids: [String]) {
        for id in ids where !contains(id) { pending.append(id) }
    }

    /// The next thing to do, given `conditions`; `shortage` tells a game's want of room.
    public mutating func step(_ conditions: PrepareConditions, shortage: (String) -> SpaceShortage?) -> Action {
        if active != nil {
            if !conditions.enabled { pending.removeAll() }
            let hold = conditions.playing || conditions.power.low || (conditions.unlocking && !promoted)
            if hold && !paused {
                paused = true
                return .pause
            }
            if !hold && paused {
                paused = false
                return .resume
            }
            return .none
        }
        guard conditions.enabled else {
            pending.removeAll()
            return .none
        }
        guard let next = pending.first, !conditions.playing, !conditions.unlocking else { return .none }
        if conditions.power.low {
            pending.removeFirst()
            return .skip(next, .battery(conditions.power.level))
        }
        if let short = shortage(next) {
            pending.removeFirst()
            return .skip(next, .space(short))
        }
        pending.removeFirst()
        active = next
        paused = false
        promoted = false
        return .start(next)
    }

    /// The user wants to play the game being prepared: it stops waiting for their other unlocks.
    public mutating func promote(_ id: String) {
        if active == id { promoted = true }
    }

    /// Takes a game out of the queue; true when it is being prepared, and its unlock must be
    /// stopped (then `finished` follows).
    @discardableResult
    public mutating func cancel(_ id: String) -> Bool {
        pending.removeAll { $0 == id }
        return active == id
    }

    /// The background unlock of `id` ended, however it ended.
    public mutating func finished(_ id: String) {
        guard active == id else { return }
        active = nil
        paused = false
        promoted = false
    }
}
