import Foundation

/// Settings → Controllers → Troubleshoot on the Mac: what can keep a controller from the
/// launcher, from what the launcher sees (the controllers, the HID game controllers macOS lists,
/// the apps running). Each finding names its cause; the texts are the launcher's (ControllerStrings).
public enum PadTroubleshooter {
    public enum Finding: Equatable, Sendable {
        /// No controller at all: the cable and pairing tips follow.
        case noControllers
        /// A cable that charges but carries no data looks like no controller.
        case usbCable
        /// How to pair a PlayStation, Xbox or Switch controller over Bluetooth.
        case bluetoothPairing
        /// A DualShock 3 works over USB only: macOS cannot pair it over Bluetooth.
        case dualShock3
        /// A controller macOS lists as a HID game controller but has no profile for (it shows
        /// only to games through SDL); its name.
        case unmapped(String)
        /// A controller's battery is nearly empty; its name and percentage.
        case lowBattery(String, Int)
        /// Steam is running: with its PlayStation, Xbox or Switch support on, it can turn the pad
        /// into a mouse outside its own games.
        case steamRunning

        public var isProblem: Bool {
            switch self {
            case .noControllers, .unmapped, .lowBattery: return true
            default: return false
            }
        }

        /// A stable name for the log and the tests.
        public var id: String {
            switch self {
            case .noControllers: return "noControllers"
            case .usbCable: return "usbCable"
            case .bluetoothPairing: return "bluetoothPairing"
            case .dualShock3: return "dualShock3"
            case .unmapped: return "unmapped"
            case .lowBattery: return "lowBattery"
            case .steamRunning: return "steamRunning"
            }
        }
    }

    /// What the launcher sees now.
    public struct Facts: Sendable {
        public var pads: [PadInfo]
        /// HID game controllers macOS lists (name, vendor, product), whether or not a profile reads them.
        public var hidControllers: [(name: String, vendor: Int, product: Int)]
        /// The running apps' bundle identifiers or executable names.
        public var running: [String]

        public init(pads: [PadInfo], hidControllers: [(name: String, vendor: Int, product: Int)] = [], running: [String] = []) {
            self.pads = pads
            self.hidControllers = hidControllers
            self.running = running
        }
    }

    /// Controllers the GameController framework reads, by USB numbers; the DualShock 3 is read by
    /// the launcher's own reader.
    static func readable(vendor: Int, product: Int) -> Bool {
        let kind = PadKind.classify(vendor: vendor, product: product, name: "")
        return kind != .generic
    }

    public static func diagnose(_ facts: Facts) -> [Finding] {
        var findings: [Finding] = []
        let known = Set(facts.pads.compactMap(\.usbID))
        let unmapped = facts.hidControllers.filter { hid in
            !readable(vendor: hid.vendor, product: hid.product) && !known.contains(String(format: "%04x:%04x", hid.vendor, hid.product))
        }
        if facts.pads.isEmpty && unmapped.isEmpty { findings.append(.noControllers) }
        findings += unmapped.map { .unmapped($0.name.isEmpty ? String(format: "%04x:%04x", $0.vendor, $0.product) : $0.name) }
        for pad in facts.pads {
            if let battery = pad.battery, battery.low { findings.append(.lowBattery(pad.name, battery.percent)) }
        }
        if facts.running.contains(where: { $0 == "com.valvesoftware.steam" || $0.lowercased() == "steam_osx" || $0.lowercased() == "steam" }) {
            findings.append(.steamRunning)
        }
        if facts.pads.isEmpty {
            findings += [.usbCable, .bluetoothPairing, .dualShock3]
        } else if !facts.pads.contains(where: { $0.kind == .dualShock3 }) {
            findings.append(.dualShock3)
        }
        return findings
    }

    /// One line for the controller indicator in the top bar: nil when there is nothing to say.
    public static func statusLine(_ pads: [PadInfo]) -> String? {
        guard !pads.isEmpty else { return nil }
        if let low = pads.first(where: { $0.battery?.low == true }) { return "\(low.name) · \(low.battery!.percent)%" }
        return nil
    }
}
