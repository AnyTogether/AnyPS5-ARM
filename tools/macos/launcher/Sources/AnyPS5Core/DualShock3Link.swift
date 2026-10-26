import Foundation

// The DualShock 3 over USB between the device and the roster, apart from IOKit so the tests can
// drive it: the handshake that starts its reports (DualShock3Handshake, through a transport the
// launcher backs with IOHID), what may be written to it (DualShock3OutputGate), when a
// controller that just came is shown (PadSettle), and which of the GameController framework's
// controllers are the same DualShock 3 again (PadMerge).

/// The calls the DualShock 3 reader makes on one device: IOHIDDevice in the launcher, a fake in
/// the tests. A code is an IOReturn: 0 is success.
public protocol DualShock3Transport: AnyObject {
    /// Reads feature report `id` (`length` bytes with the id): the bytes, or the failure's code.
    func getFeature(_ id: UInt8, length: Int) -> Result<[UInt8], DualShock3Failure>
    /// Writes a feature report (its id first).
    func setFeature(_ bytes: [UInt8]) -> Int32
}

public struct DualShock3Failure: Error, Equatable, Sendable {
    public var code: Int32
    public init(_ code: Int32) { self.code = code }
}

/// What starts a DualShock 3's input reports over USB. A real one sends nothing until it is
/// asked for feature report 0xF2 (its Bluetooth address); clones and some hosts want 0xF5 (the
/// paired host) as well, and a few only answer the set report 0xF4 (42 0C 00 00) instead.
/// SDL's PS3 driver and Linux's hid-sony read 0xF2 then 0xF5 (the order a PS3 uses); the
/// set report is the fallback for a controller that refuses both reads.
public enum DualShock3Handshake {
    public enum Step: Equatable, Sendable {
        case getFeature(UInt8, length: Int)
        case setFeature([UInt8])

        public var label: String {
            switch self {
            case .getFeature(let id, let length): return String(format: "get feature 0x%02X (%d bytes)", id, length)
            case .setFeature(let bytes): return "set feature " + bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            }
        }
    }

    public static let readAddress = Step.getFeature(0xF2, length: 17)
    public static let readHost = Step.getFeature(0xF5, length: 8)
    public static let enableCommand = Step.setFeature([0xF4, 0x42, 0x0C, 0x00, 0x00])

    public struct Outcome: Equatable, Sendable {
        /// Each step sent and its code (0 for success).
        public var steps: [(step: Step, code: Int32)]
        /// The controller's Bluetooth address from 0xF2, when it answered.
        public var address: String?

        /// Some step reached the controller.
        public var reached: Bool { steps.contains { $0.code == 0 } }

        /// "get feature 0xF2 (17 bytes) ok, get feature 0xF5 (8 bytes) 0xE0005000".
        public var logText: String {
            steps.map { $0.step.label + " " + ($0.code == 0 ? "ok" : String(format: "0x%08X", UInt32(bitPattern: $0.code))) }.joined(separator: ", ")
        }

        public static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            lhs.address == rhs.address && lhs.steps.map(\.step) == rhs.steps.map(\.step) && lhs.steps.map(\.code) == rhs.steps.map(\.code)
        }
    }

    /// Runs the handshake: 0xF2, then 0xF5, and the set report 0xF4 only when neither read
    /// reached the controller. Nothing else is written: no output report goes with it (a clone
    /// can take one as the wrong host and reset).
    public static func run(_ transport: DualShock3Transport) -> Outcome {
        var outcome = Outcome(steps: [])
        for step in [readAddress, readHost] {
            guard case .getFeature(let id, let length) = step else { continue }
            switch transport.getFeature(id, length: length) {
            case .success(let bytes):
                outcome.steps.append((step, 0))
                if id == 0xF2 { outcome.address = address(bytes) }
            case .failure(let failure):
                outcome.steps.append((step, failure.code == 0 ? -1 : failure.code))
            }
        }
        if !outcome.reached, case .setFeature(let bytes) = enableCommand {
            let code = transport.setFeature(bytes)
            outcome.steps.append((enableCommand, code))
        }
        return outcome
    }

    /// When the handshake goes again after the first, counted from the attach, while the
    /// controller has sent no report: the first try can come before the device is ready (macOS's
    /// own GameController copy opens it at the same moment).
    public static let retries: [TimeInterval] = [0.4, 1.0, 2.5]

    /// Whether the try after `attempt` (0 the first) goes: only while nothing has come.
    public static func retries(after attempt: Int, reports: Int) -> Bool {
        reports == 0 && attempt < retries.count
    }

    /// The Bluetooth address in report 0xF2: bytes 4 to 9 counting the id (where Linux's
    /// hid-sony reads it); nil when the report is too short or all zero.
    public static func address(_ report: [UInt8]) -> String? {
        // Without the id in front the address starts one byte earlier.
        let start = report.first == 0xF2 ? 4 : 3
        guard report.count >= start + 6 else { return nil }
        let bytes = Array(report[start..<(start + 6)])
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}

/// What may be written to one DualShock 3: the player light and the motors (output report 0x01)
/// only once its reports come and it has stayed (a clone that is about to switch to its Xbox
/// mode is left alone), never the same light twice, and nothing more after a write fails.
public struct DualShock3OutputGate: Equatable, Sendable {
    public private(set) var reporting = false
    public private(set) var settled = false
    public private(set) var failed = false
    private var lastLight: Int?

    public init() {}

    public mutating func reportArrived() { reporting = true }
    public mutating func settle() { settled = true }

    /// Whether an output report with this player light and these motors goes out now.
    public mutating func allows(player: Int, rumble: Bool) -> Bool {
        guard reporting, settled, !failed else { return false }
        if !rumble, lastLight == player { return false }
        lastLight = rumble ? nil : player
        return true
    }

    /// The write's code: a failure stops the writes to this controller.
    public mutating func wrote(_ code: Int32) {
        if code != 0 { failed = true; lastLight = nil }
    }
}

/// A controller that just came is shown only once it has stayed a moment: a multi-mode
/// DualShock 3 clone comes as a DualShock 3, leaves about a second later and comes back as an
/// Xbox 360 pad, and that first second is no controller to list or announce.
public struct PadSettle: Sendable {
    public static let delay: TimeInterval = 1.6

    public enum Left: Equatable, Sendable {
        /// It had been shown: a disconnect like any.
        case shown
        /// It left before it was shown, after this long: nothing to announce.
        case unseen(TimeInterval)
        /// Not known.
        case unknown
    }

    private var waiting: [String: Date] = [:]
    private var shown: Set<String> = []

    public init() {}

    public mutating func came(_ id: String, at date: Date = Date()) {
        guard !shown.contains(id) else { return }
        waiting[id] = date
    }

    /// The ones that have stayed long enough by `date`, in the order they came; they count as shown.
    public mutating func due(at date: Date = Date()) -> [String] {
        let ready = waiting.filter { date.timeIntervalSince($0.value) >= Self.delay }.sorted { $0.value < $1.value }.map(\.key)
        for id in ready {
            waiting[id] = nil
            shown.insert(id)
        }
        return ready
    }

    public mutating func left(_ id: String, at date: Date = Date()) -> Left {
        if shown.remove(id) != nil { return .shown }
        if let since = waiting.removeValue(forKey: id) { return .unseen(date.timeIntervalSince(since)) }
        return .unknown
    }

    public func isShown(_ id: String) -> Bool { shown.contains(id) }
}

/// macOS 26's GameController framework lists a DualShock 3 on USB as a generic 'HID' controller
/// of its own, beside the launcher's reader of the same device: two entries for one pad. These
/// are the framework's controllers that stand for a DualShock 3 the reader holds, one for one,
/// by name first (the reader's product name is the framework's vendor name), then any left of
/// the DualShock 3 kind.
public enum PadMerge {
    public struct Entry: Equatable, Sendable {
        public var id: String
        public var name: String
        public var kind: PadKind

        public init(id: String, name: String, kind: PadKind) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    /// The framework controller → the reader's device it duplicates.
    public static func aliases(framework: [Entry], reader: [Entry]) -> [String: String] {
        var result: [String: String] = [:]
        var free = framework.filter { $0.kind == .dualShock3 }
        var unmatched: [Entry] = []
        func key(_ name: String) -> String { name.lowercased().filter { $0.isLetter || $0.isNumber } }
        for device in reader {
            if let index = free.firstIndex(where: { key($0.name) == key(device.name) }) {
                result[free.remove(at: index).id] = device.id
            } else {
                unmatched.append(device)
            }
        }
        for device in unmatched where !free.isEmpty {
            result[free.removeFirst().id] = device.id
        }
        return result
    }

    /// The pad the reader's input and the framework's both go to: the reader's, unless it has
    /// sent nothing while the framework's copy has.
    public static func preferFramework(readerReports: Int, frameworkChanges: Int) -> Bool {
        readerReports == 0 && frameworkChanges > 0
    }
}
