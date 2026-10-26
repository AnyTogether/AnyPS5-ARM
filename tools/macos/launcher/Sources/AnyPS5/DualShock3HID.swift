import AnyPS5Core
import Foundation
import IOKit.hid

/// The DualShock 3 over USB, read through IOHIDManager (no permission needed for a game
/// controller, opened shared so macOS's own GameController copy keeps working): started with
/// the handshake (DualShock3Handshake: feature reports 0xF2 and 0xF5), its reports turned into
/// pad states (DualShock3Report) for the launcher's input and the controller test, and its motors
/// and player light set with output report 0x01 once it reports (DualShock3OutputGate). A pad is
/// shown only after it has stayed a moment (PadSettle): a multi-mode clone leaves after a second
/// and comes back as an Xbox 360 pad, which the GameController framework reads.
/// Also lists the HID game controllers macOS sees, with their transport, for Settings →
/// Controllers (the connection of GameController's pads) and the troubleshooter.
@MainActor
final class DualShock3HID {
    struct Device {
        let device: IOHIDDevice
        let id: String
        let name: String
        let transport: String?
        var state = PadState.idle
        var battery: PadBattery?
        var reports = 0
        var gate = DualShock3OutputGate()
        let buffer: UnsafeMutablePointer<UInt8>
    }

    /// A DualShock 3 was shown (its info), sent a report (its new and previous state) or went.
    var connected: ((PadInfo) -> Void)?
    var changed: ((String, PadState, PadState) -> Void)?
    var batteryChanged: ((String, PadBattery) -> Void)?
    var disconnected: ((String) -> Void)?
    /// A log line that is no connect or disconnect: the handshake, a clone that left at once.
    var note: ((String) -> Void)?
    /// The devices held changed (one came or went, shown or not): the framework's copies are matched again.
    var devicesChanged: (() -> Void)?

    private var manager: IOHIDManager?
    private var devices: [String: Device] = [:]
    private var settle = PadSettle()
    /// When a DualShock 3 last left before it was shown: an Xbox pad right after is that clone.
    private(set) var lastUnseenExit: Date?
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
        // Shared, never seized: macOS's GameController copy and the games' SDL read it too.
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    /// One id per physical controller: its USB location (one per port), else its registry entry.
    static func id(of device: IOHIDDevice) -> String {
        if let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int, location != 0 {
            return "ds3-\(String(location, radix: 16))"
        }
        var entry: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entry)
        return "ds3-r\(String(entry, radix: 16))"
    }

    /// The controllers held now (shown or not), for matching the framework's copies.
    var held: [PadMerge.Entry] { devices.values.sorted { $0.id < $1.id }.map { PadMerge.Entry(id: $0.id, name: $0.name, kind: .dualShock3) } }
    func reports(_ id: String) -> Int { devices[id]?.reports ?? 0 }
    func isShown(_ id: String) -> Bool { settle.isShown(id) }

    private func attach(_ device: IOHIDDevice) {
        let id = Self.id(of: device)
        // The same controller through a second interface or usage: one entry.
        guard devices[id] == nil else { return }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.reportSize)
        buffer.initialize(repeating: 0, count: Self.reportSize)
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "PLAYSTATION(R)3 Controller"
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        devices[id] = Device(device: device, id: id, name: name, transport: transport, buffer: buffer)
        // Listening first: the reports start the moment the handshake reaches the controller.
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
        handshake(id, attempt: 0)
        settle.came(id)
        devicesChanged?()
        DispatchQueue.main.asyncAfter(deadline: .now() + PadSettle.delay + 0.05) { [weak self] in self?.showSettled() }
    }

    /// The handshake, again a little later while the controller sends nothing.
    private func handshake(_ id: String, attempt: Int) {
        guard let known = devices[id] else { return }
        let outcome = DualShock3Handshake.run(HIDTransport(known.device))
        note?("DualShock 3 '\(known.name)' (\(id)) handshake \(attempt + 1): \(outcome.logText)")
        guard attempt < DualShock3Handshake.retries.count else { return }
        let wait = DualShock3Handshake.retries[attempt] - (attempt > 0 ? DualShock3Handshake.retries[attempt - 1] : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self, device = known.device] in
            guard let self, let now = self.devices[id], now.device === device,
                  DualShock3Handshake.retries(after: attempt, reports: now.reports) else { return }
            self.handshake(id, attempt: attempt + 1)
        }
    }

    /// The controllers that stayed: shown, their player light set once they report.
    private func showSettled() {
        for id in settle.due() {
            guard var known = devices[id] else { continue }
            known.gate.settle()
            devices[id] = known
            if known.reports == 0 { note?("DualShock 3 '\(known.name)' (\(id)) has sent no report yet") }
            connected?(PadInfo(id: id, name: known.name, kind: .dualShock3,
                               connection: PadConnection.transport(known.transport) == .unknown ? .usb : PadConnection.transport(known.transport),
                               battery: known.battery, driver: "IOHID (DualShock 3)", vendor: DualShock3Report.vendor, product: DualShock3Report.product,
                               hasRumble: true))
            if known.state != .idle { changed?(id, known.state, .idle) }
        }
    }

    private func detach(_ device: IOHIDDevice) {
        let id = Self.id(of: device)
        guard let gone = devices.removeValue(forKey: id) else { return }
        gone.buffer.deallocate()
        switch settle.left(id) {
        case .shown:
            disconnected?(id)
        case .unseen(let after):
            lastUnseenExit = Date()
            note?(String(format: "DualShock 3 '%@' (%@) left after %.1f s, before it was shown (%d reports): a clone switching to its Xbox mode, or a loose cable",
                         gone.name, id, after, gone.reports))
        case .unknown:
            break
        }
        devicesChanged?()
    }

    private func report(_ bytes: [UInt8], from device: IOHIDDevice) {
        let id = Self.id(of: device)
        guard var known = devices[id] else { return }
        known.reports += 1
        let first = !known.gate.reporting
        known.gate.reportArrived()
        guard let state = DualShock3Report.parse(bytes) else {
            devices[id] = known
            return
        }
        let previous = known.state
        known.state = state
        let battery = DualShock3Report.battery(bytes)
        let batteryNew = battery != nil && battery != known.battery
        if let battery { known.battery = battery }
        devices[id] = known
        if first { note?("DualShock 3 '\(known.name)' (\(id)) reports") }
        // Before it is shown only kept: the test and the input start with the pad.
        guard settle.isShown(id) else { return }
        if batteryNew, let battery { batteryChanged?(id, battery) }
        if state != previous { changed?(id, state, previous) }
    }

    func state(_ id: String) -> PadState? { devices[id]?.state }

    /// The motors (0 to 1) and the player light of one DualShock 3.
    func setOutput(_ id: String, strong: Double, weak: Double, player: Int) {
        guard var known = devices[id] else { return }
        let rumble = strong > 0.05 || weak > 0.05
        guard known.gate.allows(player: player, rumble: rumble) else {
            devices[id] = known
            return
        }
        let report = DualShock3Report.output(strong: strong, weak: weak, player: player)
        // A numbered report goes with its id as the first byte (as hidapi sends it).
        let code = IOHIDDeviceSetReport(known.device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        known.gate.wrote(code)
        devices[id] = known
        if code != kIOReturnSuccess {
            note?(String(format: "DualShock 3 '%@' (%@) refused output report 0x01 (0x%08X): no light or vibration on it", known.name, id, UInt32(bitPattern: code)))
        }
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

/// The handshake's calls on one IOHIDDevice.
private final class HIDTransport: DualShock3Transport {
    let device: IOHIDDevice
    init(_ device: IOHIDDevice) { self.device = device }

    func getFeature(_ id: UInt8, length: Int) -> Result<[UInt8], DualShock3Failure> {
        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = id
        var size = CFIndex(length)
        let code = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &size)
        guard code == kIOReturnSuccess else { return .failure(DualShock3Failure(code)) }
        return .success(Array(buffer.prefix(max(0, min(size, length)))))
    }

    func setFeature(_ bytes: [UInt8]) -> Int32 {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(bytes[0]), bytes, bytes.count)
    }
}
