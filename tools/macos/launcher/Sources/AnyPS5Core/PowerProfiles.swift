import Foundation

// Battery and heat profiles (Settings → Battery & Heat): what a MacBook on battery, or a Mac
// running hot, does to the game playing. On battery the game can be held to 30, 40 or 45 fps,
// started at a lower resolution, its frame generation paused and the launcher's heavy effects
// dimmed; running hot (serious or critical) the same, with a toast that can be undone. Plugged in
// and cool nothing changes. The policy here is pure: PowerMonitor (the app) feeds it readings.

/// How warm macOS says the Mac is (ProcessInfo.thermalState), comparable.
public enum ThermalLevel: Int, Codable, Comparable, Sendable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One reading of the Mac's power: where it draws from, the battery, the heat, Low Power Mode.
public struct PowerReading: Equatable, Sendable {
    /// Whether the Mac has a battery at all (a desktop Mac has none).
    public var hasBattery: Bool
    public var onBattery: Bool
    public var batteryPercent: Int?
    /// macOS's own estimate of the minutes left, nil while it is still working one out.
    public var minutesToEmpty: Int?
    public var thermal: ThermalLevel
    public var lowPowerMode: Bool

    public init(hasBattery: Bool, onBattery: Bool, batteryPercent: Int?, minutesToEmpty: Int?, thermal: ThermalLevel, lowPowerMode: Bool) {
        self.hasBattery = hasBattery
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.minutesToEmpty = minutesToEmpty
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
    }

    /// A desktop Mac, cool, plugged in.
    public static let pluggedIn = PowerReading(hasBattery: false, onBattery: false, batteryPercent: nil, minutesToEmpty: nil, thermal: .nominal, lowPowerMode: false)

    /// Battery or Low Power Mode: the user wants power saved.
    public var savingPower: Bool { onBattery || lowPowerMode }
    public var hot: Bool { thermal >= .serious }
}

/// What one profile does while it holds.
public struct PowerProfile: Codable, Equatable, Sendable {
    /// The frame caps offered; 0 is none.
    public static let frameCaps = [0, 30, 40, 45]

    public var on: Bool
    /// The game's frame rate cap, 0 for none.
    public var frameCap: Int
    /// The game started at the next resolution down its patch offers (applies at the next launch).
    public var lowerResolution: Bool
    public var pauseFrameGeneration: Bool
    /// The launcher's Glass blur and animations turned down.
    public var dimEffects: Bool

    public init(on: Bool, frameCap: Int, lowerResolution: Bool, pauseFrameGeneration: Bool, dimEffects: Bool) {
        self.on = on
        self.frameCap = frameCap
        self.lowerResolution = lowerResolution
        self.pauseFrameGeneration = pauseFrameGeneration
        self.dimEffects = dimEffects
    }

    public static let battery = PowerProfile(on: true, frameCap: 40, lowerResolution: false, pauseFrameGeneration: true, dimEffects: true)
    public static let hot = PowerProfile(on: true, frameCap: 40, lowerResolution: false, pauseFrameGeneration: true, dimEffects: true)

    /// What this profile changes, none when it is off.
    public var adjustment: PowerAdjustment {
        on ? PowerAdjustment(frameCap: frameCap, lowerResolution: lowerResolution, pauseFrameGeneration: pauseFrameGeneration, dimEffects: dimEffects) : .none
    }

    // Saved settings miss what came later: each missing field takes `defaults`'s.
    fileprivate struct Partial: Decodable {
        var on: Bool?
        var frameCap: Int?
        var lowerResolution: Bool?
        var pauseFrameGeneration: Bool?
        var dimEffects: Bool?

        func over(_ defaults: PowerProfile) -> PowerProfile {
            PowerProfile(on: on ?? defaults.on, frameCap: frameCap ?? defaults.frameCap, lowerResolution: lowerResolution ?? defaults.lowerResolution,
                         pauseFrameGeneration: pauseFrameGeneration ?? defaults.pauseFrameGeneration, dimEffects: dimEffects ?? defaults.dimEffects)
        }
    }

    public init(from decoder: Decoder) throws {
        self = try Partial(from: decoder).over(.battery)
    }
}

/// The two profiles the user sets.
public struct PowerProfiles: Codable, Equatable, Sendable {
    public var battery = PowerProfile.battery
    public var hot = PowerProfile.hot

    public init() {}

    private enum CodingKeys: String, CodingKey { case battery, hot }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        battery = try container.decodeIfPresent(PowerProfile.Partial.self, forKey: .battery)?.over(.battery) ?? .battery
        hot = try container.decodeIfPresent(PowerProfile.Partial.self, forKey: .hot)?.over(.hot) ?? .hot
    }
}

/// What is changed for the game and the launcher now; `.none` changes nothing.
public struct PowerAdjustment: Equatable, Sendable {
    public var frameCap: Int
    public var lowerResolution: Bool
    public var pauseFrameGeneration: Bool
    public var dimEffects: Bool

    public init(frameCap: Int, lowerResolution: Bool, pauseFrameGeneration: Bool, dimEffects: Bool) {
        self.frameCap = frameCap
        self.lowerResolution = lowerResolution
        self.pauseFrameGeneration = pauseFrameGeneration
        self.dimEffects = dimEffects
    }

    public static let none = PowerAdjustment(frameCap: 0, lowerResolution: false, pauseFrameGeneration: false, dimEffects: false)

    public var isNone: Bool { self == .none }

    /// The stricter of the two in each part: the lower cap, any of the switches.
    public func merged(_ other: PowerAdjustment) -> PowerAdjustment {
        let caps = [frameCap, other.frameCap].filter { $0 > 0 }
        return PowerAdjustment(frameCap: caps.min() ?? 0, lowerResolution: lowerResolution || other.lowerResolution,
                               pauseFrameGeneration: pauseFrameGeneration || other.pauseFrameGeneration, dimEffects: dimEffects || other.dimEffects)
    }
}

/// Which profile is in force.
public enum PowerMode: String, Sendable {
    case pluggedIn, battery, hot
}

/// From readings to the adjustment in force, with hysteresis so it does not flap: a change of
/// power source counts once it has held `sourceSettle` seconds (a cable that slips changes
/// nothing), heat counts at once and ends only after `coolDown` seconds below serious. Undo lifts
/// the heat's part (then the battery's) until that episode ends; heat that rises past the level
/// that was undone applies again.
public struct PowerPolicy: Sendable {
    public static let sourceSettle: TimeInterval = 10
    public static let coolDown: TimeInterval = 90

    public var profiles: PowerProfiles
    public private(set) var savingPower = false
    public private(set) var hot = false
    /// The latest reading entered a hot episode.
    public private(set) var becameHot = false
    /// The heat level an undo was made at, nil when the heat's part is not undone.
    public private(set) var hotUndoneAt: ThermalLevel?
    public private(set) var batteryUndone = false

    private var started = false
    private var sourceChangeSince: Date?
    private var coolSince: Date?
    private var lastThermal = ThermalLevel.nominal

    public init(profiles: PowerProfiles = PowerProfiles()) {
        self.profiles = profiles
    }

    /// Feeds a reading taken at `now`; the adjustment in force after it.
    @discardableResult
    public mutating func update(_ state: PowerReading, at now: Date) -> PowerAdjustment {
        becameHot = false
        if !started {
            started = true
            savingPower = state.savingPower
        } else if state.savingPower != savingPower {
            let since = sourceChangeSince ?? now
            sourceChangeSince = since
            if now.timeIntervalSince(since) >= Self.sourceSettle {
                savingPower = state.savingPower
                sourceChangeSince = nil
                batteryUndone = false
            }
        } else {
            sourceChangeSince = nil
        }

        if state.hot {
            coolSince = nil
            if !hot {
                hot = true
                becameHot = true
            }
            if let undone = hotUndoneAt, state.thermal > undone { hotUndoneAt = nil }
        } else if hot {
            let since = coolSince ?? now
            coolSince = since
            if now.timeIntervalSince(since) >= Self.coolDown {
                hot = false
                coolSince = nil
                hotUndoneAt = nil
            }
        }
        lastThermal = state.thermal
        return adjustment
    }

    private var heatPart: PowerAdjustment { hot && hotUndoneAt == nil ? profiles.hot.adjustment : .none }
    private var batteryPart: PowerAdjustment { savingPower && !batteryUndone ? profiles.battery.adjustment : .none }

    /// What is changed now.
    public var adjustment: PowerAdjustment { heatPart.merged(batteryPart) }

    public var mode: PowerMode {
        if hot && hotUndoneAt == nil { return .hot }
        return savingPower ? .battery : .pluggedIn
    }

    /// Whether anything is changed that Undo would lift.
    public var canUndo: Bool { !heatPart.isNone || !batteryPart.isNone }

    /// Lifts the heat's part, or with none the battery's; the adjustment after it.
    @discardableResult
    public mutating func undo() -> PowerAdjustment {
        if !heatPart.isNone {
            hotUndoneAt = max(lastThermal, .serious)
        } else if !batteryPart.isNone {
            batteryUndone = true
        }
        return adjustment
    }
}

/// The resolution a lower-resolution profile starts a game at.
public enum PowerResolution {
    /// The largest of `choices` with fewer pixels than `current`, nil when there is none.
    public static func lower(than current: String, choices: [String]) -> String? {
        guard let pixels = Self.pixels(current) else { return nil }
        return choices.compactMap { choice in Self.pixels(choice).map { (choice, $0) } }
            .filter { $0.1 < pixels }
            .max { $0.1 < $1.1 }?.0
    }

    private static func pixels(_ text: String) -> Int? {
        guard let (width, height) = GamePatches.parse(resolution: text) else { return nil }
        return Int(width) * Int(height)
    }
}

/// How the launcher tells the engine about the frame cap and frame generation: at launch through
/// the environment (ANYPS5_FPS_CAP, and ANYPS5_POWER_CONTROL naming a small file), then live by
/// rewriting that file, which the engine reads again within a second of a change.
public enum EngineControl {
    public static func text(_ adjustment: PowerAdjustment) -> String {
        "fps_cap=\(max(0, adjustment.frameCap))\nframe_gen=\(adjustment.pauseFrameGeneration ? 0 : 1)\n"
    }

    public static func environment(file: URL, adjustment: PowerAdjustment) -> [String: String] {
        ["ANYPS5_POWER_CONTROL": file.path, "ANYPS5_FPS_CAP": String(max(0, adjustment.frameCap))]
    }

    /// Writes the file whole (atomically), so the engine never reads half of it.
    public static func write(_ adjustment: PowerAdjustment, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text(adjustment).utf8).write(to: file, options: .atomic)
    }
}

/// Minutes of battery left: macOS's estimate where it has one, else the drain measured since the
/// Mac went on battery (at least 2 % over at least 3 minutes).
public struct BatteryEstimate: Sendable {
    private var first: (percent: Int, at: Date)?
    private var last: (percent: Int, at: Date)?

    public init() {}

    public mutating func add(percent: Int, onBattery: Bool, at now: Date) {
        guard onBattery else {
            first = nil
            last = nil
            return
        }
        if let first, percent > first.percent { self.first = nil }
        if first == nil { first = (percent, now) }
        last = (percent, now)
    }

    public func minutesLeft(system: Int?) -> Int? {
        if let system, system > 0 { return system }
        guard let first, let last else { return nil }
        let dropped = first.percent - last.percent
        let minutes = last.at.timeIntervalSince(first.at) / 60
        guard dropped >= 2, minutes >= 3 else { return nil }
        return Int((Double(last.percent) / (Double(dropped) / minutes)).rounded())
    }
}
