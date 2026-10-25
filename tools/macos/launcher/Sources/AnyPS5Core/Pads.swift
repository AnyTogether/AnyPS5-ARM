import Foundation

// The controllers the launcher knows about, whatever reads them (the GameController framework, the
// DualShock 3's own USB reader): what each one is, how it is connected, its battery, which one is
// Player 1, and a log line for every connect and disconnect that bug reports carry. The
// Windows/Linux launcher (AnyPS5 Desktop, lib/core/controllers) keeps the same model and the same
// log lines.

/// The family a controller belongs to: its icon, its button glyphs and what it can do.
public enum PadKind: String, CaseIterable, Codable, Sendable {
    case dualSense, dualShock4, dualShock3, xbox, switchPro, generic

    /// The PlayStation pads: ✕ ○ □ △ glyphs, a PS button.
    public var isPlayStation: Bool { self == .dualSense || self == .dualShock4 || self == .dualShock3 }

    /// A light bar the launcher can colour.
    public var hasLightBar: Bool { self == .dualSense || self == .dualShock4 }

    /// The English name the log and the reports use.
    public var reportName: String {
        switch self {
        case .dualSense: return "DualSense"
        case .dualShock4: return "DualShock 4"
        case .dualShock3: return "DualShock 3"
        case .xbox: return "Xbox"
        case .switchPro: return "Switch Pro"
        case .generic: return "generic"
        }
    }

    public static let sony = 0x054C
    public static let microsoft = 0x045E
    public static let nintendo = 0x057E
    public static let valve = 0x28DE

    /// What a controller is from its USB vendor and product numbers, and failing those its name.
    public static func classify(vendor: Int?, product: Int?, name: String) -> PadKind {
        if let vendor, let product {
            switch (vendor, product) {
            case (sony, 0x0CE6), (sony, 0x0DF2), (sony, 0x0E5F): return .dualSense
            case (sony, 0x05C4), (sony, 0x09CC), (sony, 0x0BA0): return .dualShock4
            case (sony, 0x0268): return .dualShock3
            case (microsoft, _): return .xbox
            case (nintendo, 0x2009): return .switchPro
            // Steam's virtual pad is an Xbox 360 pad to the games.
            case (valve, 0x11FF): return .xbox
            default: break
            }
        }
        let lower = name.lowercased()
        if lower.contains("dualsense") { return .dualSense }
        if lower.contains("dualshock 4") || lower.contains("dualshock4") || (vendor == sony && lower.contains("wireless controller")) { return .dualShock4 }
        if lower.contains("playstation(r)3") || lower.contains("dualshock 3") || lower.contains("ps3") || lower.contains("sixaxis") { return .dualShock3 }
        if lower.contains("xbox") || lower.contains("x-box") || lower.contains("xinput") { return .xbox }
        if lower.contains("pro controller") { return .switchPro }
        return .generic
    }
}

/// How a controller reaches the computer.
public enum PadConnection: String, Codable, Sendable {
    case usb, bluetooth, unknown

    public var reportName: String {
        switch self {
        case .usb: return "USB"
        case .bluetooth: return "Bluetooth"
        case .unknown: return "connection unknown"
        }
    }

    /// From a HID transport name (IOKit's "USB", "Bluetooth", "Bluetooth Low Energy").
    public static func transport(_ name: String?) -> PadConnection {
        guard let name = name?.lowercased() else { return .unknown }
        if name.contains("bluetooth") { return .bluetooth }
        if name.contains("usb") { return .usb }
        return .unknown
    }
}

/// A controller's battery: a percentage (rounded where the reader only gives levels) and
/// whether it charges, where that is known.
public struct PadBattery: Equatable, Codable, Sendable {
    public var percent: Int
    /// The reader gives only a few levels: the percentage is that level's middle.
    public var approximate: Bool
    public var charging: Bool?

    public init(percent: Int, approximate: Bool = false, charging: Bool? = nil) {
        self.percent = min(100, max(0, percent))
        self.approximate = approximate
        self.charging = charging
    }

    /// Low enough to say so (the troubleshooter, the controller indicator).
    public var low: Bool { percent <= 15 && charging != true }

    public var reportText: String {
        (approximate ? "about " : "") + "\(percent)%" + (charging == true ? " charging" : "")
    }
}

/// One controller as the launcher shows it.
public struct PadInfo: Equatable, Identifiable, Sendable {
    /// The reader's own id, kept while it stays connected.
    public var id: String
    public var name: String
    public var kind: PadKind
    public var connection: PadConnection
    public var battery: PadBattery?
    /// What reads it: "GameController", "IOHID (DualShock 3)".
    public var driver: String
    public var vendor: Int?
    public var product: Int?
    public var hasRumble: Bool
    public var hasLight: Bool

    public init(id: String, name: String, kind: PadKind, connection: PadConnection = .unknown, battery: PadBattery? = nil, driver: String,
                vendor: Int? = nil, product: Int? = nil, hasRumble: Bool = false, hasLight: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.connection = connection
        self.battery = battery
        self.driver = driver
        self.vendor = vendor
        self.product = product
        self.hasRumble = hasRumble
        self.hasLight = hasLight
    }

    /// "054c:0ce6", or nil.
    public var usbID: String? {
        guard let vendor, let product else { return nil }
        return String(format: "%04x:%04x", vendor, product)
    }

    /// "DualSense Wireless Controller (DualSense, Bluetooth, battery 80%, GameController, 054c:0ce6)".
    public var reportLine: String {
        var parts = [kind.reportName, connection.reportName]
        if let battery { parts.append("battery " + battery.reportText) }
        parts.append(driver)
        if let usbID { parts.append(usbID) }
        return "\(name) (\(parts.joined(separator: ", ")))"
    }
}

/// The controllers connected now, in the order they came, and Player 1: the one used last (the
/// one the launcher's vibration and light go to). Every connect and disconnect gives a log line.
public struct PadRoster: Sendable {
    public private(set) var pads: [PadInfo] = []
    public private(set) var playerOne: String?
    private var connectedAt: [String: Date] = [:]

    public init() {}

    public func pad(_ id: String) -> PadInfo? { pads.first { $0.id == id } }

    /// A controller came (or a reader saw it again with new facts): the log line when it is new.
    @discardableResult
    public mutating func connect(_ info: PadInfo, now: Date = Date()) -> String? {
        if let index = pads.firstIndex(where: { $0.id == info.id }) {
            pads[index] = info
            return nil
        }
        pads.append(info)
        connectedAt[info.id] = now
        if playerOne == nil { playerOne = info.id }
        return "controller connected: " + info.reportLine
    }

    /// A controller left: its log line (nil when it was not known). Player 1 passes to the
    /// controller that came first among those left.
    @discardableResult
    public mutating func disconnect(_ id: String, now: Date = Date()) -> String? {
        guard let index = pads.firstIndex(where: { $0.id == id }) else { return nil }
        let info = pads.remove(at: index)
        let since = connectedAt.removeValue(forKey: id)
        if playerOne == id { playerOne = pads.first?.id }
        var line = "controller disconnected: \(info.name) (\(info.kind.reportName), \(info.connection.reportName), \(info.driver))"
        if let since { line += " after " + Self.duration(now.timeIntervalSince(since)) }
        return line
    }

    /// A battery or connection reading changed; nothing is logged.
    public mutating func update(_ info: PadInfo) {
        guard let index = pads.firstIndex(where: { $0.id == info.id }) else { return }
        pads[index] = info
    }

    /// A press from `id`: it becomes Player 1. Returns whether Player 1 changed.
    @discardableResult
    public mutating func used(_ id: String) -> Bool {
        guard playerOne != id, pads.contains(where: { $0.id == id }) else { return false }
        playerOne = id
        return true
    }

    /// For readers that poll: the controllers present now against those known. Returns the log
    /// lines of those that came and went.
    public mutating func sync(_ present: [PadInfo], now: Date = Date()) -> [String] {
        var lines: [String] = []
        let ids = Set(present.map(\.id))
        for gone in pads.map(\.id) where !ids.contains(gone) {
            if let line = disconnect(gone, now: now) { lines.append(line) }
        }
        for info in present {
            if let line = connect(info, now: now) { lines.append(line) }
        }
        return lines
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        if whole < 60 { return "\(whole) s" }
        if whole < 3600 { return "\(whole / 60) min" }
        return "\(whole / 3600) h \(whole % 3600 / 60) min"
    }
}

/// The last controller log lines with their times, for the crash report and the issue.
public struct PadLog: Sendable {
    public static let capacity = 40
    public private(set) var lines: [String] = []

    public init() {}

    public mutating func add(_ line: String, at date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        lines.append("\(formatter.string(from: date)) \(line)")
        if lines.count > Self.capacity { lines.removeFirst(lines.count - Self.capacity) }
    }

    /// The report's lines: the controllers connected now (Player 1 first), then the log.
    public static func report(roster: PadRoster, log: PadLog) -> [String] {
        let ordered = roster.pads.filter { $0.id == roster.playerOne } + roster.pads.filter { $0.id != roster.playerOne }
        var lines = ordered.isEmpty ? ["none connected"] : ordered.enumerated().map { index, pad in (index == 0 ? "Player 1: " : "Also: ") + pad.reportLine }
        if !log.lines.isEmpty { lines += ["Recent:"] + log.lines.map { "  " + $0 } }
        return lines
    }
}

/// A controller's buttons by place on the pad (Cross is south and Triangle north; on an Xbox pad
/// A is south). The test screen lights them; the readers turn their own numbers into these.
public enum PadButton: String, CaseIterable, Codable, Sendable {
    case south, east, west, north, l1, r1, l2, r2, select, start, guide, l3, r3
    case dpadUp, dpadDown, dpadLeft, dpadRight, touchpad, misc
}

/// Everything a controller holds at one moment, for the test screen: the buttons, both sticks
/// (-1 to 1, up negative as the screen draws it) and both triggers (0 to 1).
public struct PadState: Equatable, Sendable {
    public var pressed: Set<PadButton>
    public var leftX: Double
    public var leftY: Double
    public var rightX: Double
    public var rightY: Double
    public var l2: Double
    public var r2: Double

    public init(pressed: Set<PadButton> = [], leftX: Double = 0, leftY: Double = 0, rightX: Double = 0, rightY: Double = 0, l2: Double = 0, r2: Double = 0) {
        self.pressed = pressed
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
        self.l2 = l2
        self.r2 = r2
    }

    public static let idle = PadState()
}

/// Settings → Controllers → Stick Dead Zone: a stick that rests a little off its middle (drift)
/// reads as centred. Radial, rescaled so the edge is still the edge.
public enum StickDeadzone {
    public static let range = 0...30
    public static let step = 2

    /// `percent` of the stick's travel is ignored; what is left is stretched back to 0…1.
    public static func apply(x: Double, y: Double, percent: Int) -> (x: Double, y: Double) {
        let zone = Double(min(range.upperBound, max(0, percent))) / 100
        let length = (x * x + y * y).squareRoot()
        guard zone > 0 else { return (x, y) }
        guard length > zone else { return (0, 0) }
        let scaled = min(1, (length - zone) / (1 - zone))
        return (x / length * scaled, y / length * scaled)
    }

    /// The tuning a game starts with: its own dead zones where it set them, the controllers'
    /// dead zone where it did not.
    public static func tuning(_ own: InputTuning?, percent: Int) -> InputTuning {
        var tuning = own ?? InputTuning()
        if tuning.leftDeadzone == 0 { tuning.leftDeadzone = percent }
        if tuning.rightDeadzone == 0 { tuning.rightDeadzone = percent }
        return tuning
    }
}

/// The colour of a DualSense's or DualShock 4's light bar while the launcher is in front.
public enum PadLight: String, CaseIterable, Codable, Sendable {
    case theme, blue, red, green, purple, pink, orange, white, off

    /// Red, green and blue, 0 to 1; nil for the theme's accent, which the launcher supplies.
    public var rgb: (Double, Double, Double)? {
        switch self {
        case .theme: return nil
        case .blue: return (0.0, 0.25, 1.0)
        case .red: return (1.0, 0.05, 0.05)
        case .green: return (0.05, 0.9, 0.2)
        case .purple: return (0.55, 0.1, 1.0)
        case .pink: return (1.0, 0.2, 0.6)
        case .orange: return (1.0, 0.45, 0.0)
        case .white: return (1.0, 1.0, 1.0)
        case .off: return (0, 0, 0)
        }
    }
}

/// The confirm button: Cross (the West's layout) or Circle (Japan's), and the hints' glyphs to match.
public enum ConfirmButton {
    /// The command a south or east press gives when Circle confirms.
    public static func command(_ command: Command, circleConfirms: Bool) -> Command {
        guard circleConfirms else { return command }
        switch command {
        case .select: return .back
        case .back: return .select
        default: return command
        }
    }

    /// A hint's glyphs as shown: ✕ and ○ change places when Circle confirms.
    public static func glyphs(_ text: String, circleConfirms: Bool) -> String {
        guard circleConfirms else { return text }
        return String(text.map { $0 == "✕" ? "○" : $0 == "○" ? "✕" : $0 })
    }
}
