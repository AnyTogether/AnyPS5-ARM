import AnyPS5Core
import Foundation
import IOKit.hid

/// The DualShock 3 over USB, which the GameController framework does not know: read through
/// IOHIDManager (no permission needed for a game controller), switched into sending reports with
/// feature report 0xF2, its reports turned into pad states (DualShock3Report) for the launcher's
/// input and the controller test, and its motors and player light set with output report 0x01.
/// Also lists the HID game controllers macOS sees, with their transport, for Settings →
/// Controllers (the connection of GameController's pads) and the troubleshooter.
@MainActor
final class DualShock3HID {
    struct Device {
        let device: IOHIDDevice
        let id: String
        var state = PadState.idle
        var battery: PadBattery?
        let buffer: UnsafeMutablePointer<UInt8>
    }

    /// A DualShock 3 came (its info), sent a report (its new and previous state) or went.
    var connected: ((PadInfo) -> Void)?
    var changed: ((String, PadState, PadState) -> Void)?
    var batteryChanged: ((String, PadBattery) -> Void)?
    var disconnected: ((String) -> Void)?

    private var manager: IOHIDManager?
    private var devices: [String: Device] = [:]
    private static let reportSize = 64

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey: DualShock3Report.vendor, kIOHIDProductIDKey: DualShock3Report.product]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<DualShock3HID>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { reader.attach(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let reader = Unmanaged<DualShock3HID>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { reader.detach(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    static func id(of device: IOHIDDevice) -> String {
        let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? Int(bitPattern: UInt(bitPattern: ObjectIdentifier(device).hashValue))
        return "ds3-\(String(location, radix: 16))"
    }

    private func attach(_ device: IOHIDDevice) {
        let id = Self.id(of: device)
        guard devices[id] == nil else { return }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportSize)
        buffer.initialize(repeating: 0, count: Self.reportSize)
        devices[id] = Device(device: device, id: id, buffer: buffer)
        // Reading feature report 0xF2 starts the reports over USB; some controllers want 0xF4.
        var feature = [UInt8](repeating: 0, count: 18)
        var length = CFIndex(feature.count)
        _ = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(DualShock3Report.enableFeature), &feature, &length)
        let command = DualShock3Report.enableCommand
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(command[0]), command, command.count)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.reportSize, { context, _, sender, _, reportID, report, length in
            guard let context, let sender else { return }
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let reader = Unmanaged<DualShock3HID>.fromOpaque(context).takeUnretainedValue()
            // macOS hands the report without its id when the device numbers its reports.
            let full = bytes.first == UInt8(truncatingIfNeeded: reportID) ? bytes : [UInt8(truncatingIfNeeded: reportID)] + bytes
            MainActor.assumeIsolated { reader.report(full, from: device) }
        }, context)
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "PLAYSTATION(R)3 Controller"
        connected?(PadInfo(id: id, name: name, kind: .dualShock3, connection: PadConnection.transport(transport) == .unknown ? .usb : PadConnection.transport(transport),
                           driver: "IOHID (DualShock 3)", vendor: DualShock3Report.vendor, product: DualShock3Report.product, hasRumble: true))
        setOutput(id, strong: 0, weak: 0, player: 1)
    }

    private func detach(_ device: IOHIDDevice) {
        let id = Self.id(of: device)
        guard let gone = devices.removeValue(forKey: id) else { return }
        gone.buffer.deallocate()
        disconnected?(id)
    }

    private func report(_ bytes: [UInt8], from device: IOHIDDevice) {
        let id = Self.id(of: device)
        guard var known = devices[id], let state = DualShock3Report.parse(bytes) else { return }
        let previous = known.state
        known.state = state
        if let battery = DualShock3Report.battery(bytes), battery != known.battery {
            known.battery = battery
            batteryChanged?(id, battery)
        }
        devices[id] = known
        if state != previous { changed?(id, state, previous) }
    }

    func state(_ id: String) -> PadState? { devices[id]?.state }

    /// The motors (0 to 1) and the player light of one DualShock 3.
    func setOutput(_ id: String, strong: Double, weak: Double, player: Int) {
        guard let device = devices[id]?.device else { return }
        let report = DualShock3Report.output(strong: strong, weak: weak, player: player)
        // A numbered report goes with its id as the first byte (as hidapi sends it).
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }

    /// The HID game controllers macOS lists now (joysticks, gamepads, multi-axis), with their
    /// numbers and transport: a fresh look each time, no callbacks.
    static func hidControllers() -> [(name: String, vendor: Int, product: Int, transport: String?)] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let usages = [kHIDUsage_GD_Joystick, kHIDUsage_GD_GamePad, kHIDUsage_GD_MultiAxisController].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, usages as CFArray)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.map { device in
            (name: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "",
             vendor: IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0,
             product: IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0,
             transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String)
        }.sorted { $0.name < $1.name }
    }
}
