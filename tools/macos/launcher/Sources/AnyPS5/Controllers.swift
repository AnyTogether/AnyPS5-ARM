import AnyPS5Core
import AppKit
import CoreHaptics
import GameController
import SwiftUI

/// Every controller the launcher reads: the GameController framework's (DualSense, DualShock 4,
/// Xbox, Switch Pro and the other profiles) and the DualShock 3 over USB (DualShock3HID). Keeps
/// the roster (what each is, its connection and battery, Player 1 the one used last), logs every
/// connect and disconnect (PadLog, the game's log while one runs, the crash report), sets the
/// light bars and player lights, and holds each pad's live state for the controller test.
@MainActor
final class Controllers: ObservableObject {
    static let shared = Controllers()

    @Published private(set) var roster = PadRoster()
    /// Each pad's live state, apart: it changes at the controller's rate, and only the test watches it.
    let live = PadLive()
    @Published private(set) var findings: [PadTroubleshooter.Finding] = []
    private(set) var log = PadLog()

    /// A log line for the game's log while a game runs (AppModel sets it).
    var gameLog: ((String) -> Void)?
    /// A controller came or went: the toast (AppModel sets it).
    var announce: ((String, String) -> Void)?
    /// The light bar's colour: the setting, and the theme's accent for Theme Colour.
    var light: PadLight = .theme { didSet { if light != oldValue { applyLights() } } }
    var accent: (Double, Double, Double) = (0.31, 0.58, 1.0) {
        didSet { if light == .theme, accent != oldValue { applyLights() } }
    }

    private var controllers: [String: GCController] = [:]
    let ds3 = DualShock3HID()
    private var batteryTimer: Timer?
    private var hid: [(name: String, vendor: Int, product: Int, transport: String?)] = []

    var pads: [PadInfo] { roster.pads }
    var playerOne: PadInfo? { roster.playerOne.flatMap(roster.pad) }

    func start() {
        guard batteryTimer == nil else { return }
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(controller) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.detach(controller) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // A game may have changed the light bars: the launcher's colour again.
            MainActor.assumeIsolated { self?.applyLights() }
        }
        ds3.connected = { [weak self] info in self?.connect(info) }
        ds3.disconnected = { [weak self] id in self?.disconnect(id) }
        ds3.changed = { [weak self] id, state, previous in
            guard let self else { return }
            self.live.states[id] = state
            if !state.pressed.subtracting(previous.pressed).isEmpty { self.used(id) }
            Input.shared.external(id, state: state, previous: previous)
        }
        ds3.batteryChanged = { [weak self] id, battery in
            guard let self, var info = self.roster.pad(id) else { return }
            info.battery = battery
            self.roster.update(info)
            self.refreshFindings()
        }
        ds3.start()
        refreshHID()
        GCController.controllers().forEach(attach)
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBatteries() }
        }
        refreshFindings()
    }

    static func id(_ controller: GCController) -> String { "gc-\(UInt(bitPattern: ObjectIdentifier(controller).hashValue) & 0xFFFFFF)" }

    private func attach(_ controller: GCController) {
        let id = Self.id(controller)
        guard controllers[id] == nil, controller.extendedGamepad != nil else { return }
        // Seen again when HID lists it: its transport is known only through IOKit.
        refreshHID()
        controllers[id] = controller
        controller.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let state = Self.state(of: pad)
                let before = self.live.states[id] ?? .idle
                self.live.states[id] = state
                if !state.pressed.subtracting(before.pressed).isEmpty { self.used(id) }
            }
        }
        connect(info(for: controller, id: id))
    }

    private func detach(_ controller: GCController) {
        let id = Self.id(controller)
        guard controllers.removeValue(forKey: id) != nil else { return }
        disconnect(id)
    }

    private func connect(_ info: PadInfo) {
        guard let line = roster.connect(info) else { return }
        record(line)
        announce?(TP.format(.connected, info.name), symbol(info.kind))
        applyLights()
        applyPlayerLights()
        refreshFindings()
    }

    private func disconnect(_ id: String) {
        let name = roster.pad(id)?.name
        live.states[id] = nil
        guard let line = roster.disconnect(id) else { return }
        record(line)
        if let name { announce?(TP.format(.disconnected, name), "gamecontroller") }
        applyPlayerLights()
        refreshFindings()
    }

    private func record(_ line: String) {
        log.add(line)
        NSLog("[anyps5-launcher] %@", line)
        gameLog?(line)
    }

    /// A press from `id`: it is Player 1 now (the vibration and the test follow it).
    func used(_ id: String) {
        // Asked first: a mutation of the published roster redraws the screens even when nothing changed.
        guard roster.playerOne != id, roster.pad(id) != nil else { return }
        if roster.used(id) {
            applyPlayerLights()
            if let controller = controllers[id] { Feel.shared.pad.use(controller) } else { Feel.shared.pad.use(external: id) }
        }
    }

    /// The report's lines: the controllers now and the recent connects and disconnects.
    var reportLines: [String] { PadLog.report(roster: roster, log: log) }

    // MARK: What each controller is

    private func info(for controller: GCController, id: String) -> PadInfo {
        let pad = controller.extendedGamepad
        let name = controller.vendorName ?? controller.productCategory
        let kind: PadKind
        if pad is GCDualSenseGamepad { kind = .dualSense }
        else if pad is GCDualShockGamepad { kind = .dualShock4 }
        else if pad is GCXboxGamepad { kind = .xbox }
        else if controller.productCategory.localizedCaseInsensitiveContains("Pro Controller") { kind = .switchPro }
        else { kind = PadKind.classify(vendor: nil, product: nil, name: name + " " + controller.productCategory) }
        // The HID device of the same family tells the numbers and the transport, when only one is there.
        let family = hid.filter { PadKind.classify(vendor: $0.vendor, product: $0.product, name: $0.name) == kind }
        let match = family.count == 1 ? family.first : nil
        let transports = Set(family.map { PadConnection.transport($0.transport) })
        return PadInfo(id: id, name: name, kind: kind, connection: transports.count == 1 ? transports.first! : .unknown,
                       battery: Self.battery(controller), driver: "GameController", vendor: match?.vendor, product: match?.product,
                       hasRumble: controller.haptics != nil, hasLight: controller.light != nil)
    }

    static func battery(_ controller: GCController) -> PadBattery? {
        guard let battery = controller.battery else { return nil }
        // A wired Xbox pad reports no level: nothing to show.
        if battery.batteryState == .unknown && battery.batteryLevel <= 0 { return nil }
        let charging: Bool? = battery.batteryState == .charging ? true : battery.batteryState == .unknown ? nil : false
        return PadBattery(percent: Int((battery.batteryLevel * 100).rounded()), charging: charging)
    }

    private func refreshHID() { hid = DualShock3HID.hidControllers() }

    func refreshBatteries() {
        for (id, controller) in controllers {
            guard var info = roster.pad(id) else { continue }
            let battery = Self.battery(controller)
            guard battery != info.battery else { continue }
            info.battery = battery
            roster.update(info)
        }
        refreshFindings()
    }

    /// Asks again: HID devices, batteries, running apps (Settings → Controllers opens).
    func refresh() {
        refreshHID()
        for (id, controller) in controllers {
            if var info = roster.pad(id) {
                let fresh = self.info(for: controller, id: id)
                info.connection = fresh.connection
                info.vendor = fresh.vendor ?? info.vendor
                info.product = fresh.product ?? info.product
                roster.update(info)
            }
        }
        refreshBatteries()
    }

    func refreshFindings() {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier ?? $0.executableURL?.lastPathComponent }
        findings = PadTroubleshooter.diagnose(.init(pads: roster.pads, hidControllers: hid.map { ($0.name, $0.vendor, $0.product) }, running: running))
    }

    // MARK: Lights, vibration

    private func applyLights() {
        guard NSApp?.isActive ?? true else { return }
        let rgb = light.rgb ?? accent
        for controller in controllers.values {
            controller.light?.color = GCColor(red: Float(rgb.0), green: Float(rgb.1), blue: Float(rgb.2))
        }
    }

    /// Player 1's light on the controller used last, 2, 3, 4 on the others in the order they came.
    private func applyPlayerLights() {
        let ordered = roster.pads.filter { $0.id == roster.playerOne } + roster.pads.filter { $0.id != roster.playerOne }
        let indices: [GCControllerPlayerIndex] = [.index1, .index2, .index3, .index4]
        for (number, pad) in ordered.enumerated() {
            if let controller = controllers[pad.id] {
                controller.playerIndex = number < indices.count ? indices[number] : .indexUnset
            } else if pad.kind == .dualShock3 {
                ds3.setOutput(pad.id, strong: 0, weak: 0, player: number + 1)
            }
        }
    }

    /// Settings → Controllers → Test Vibration: three strong pulses on Player 1, whatever the
    /// vibration setting (it is a test). False when that controller cannot vibrate here.
    @discardableResult
    func testVibration() -> Bool {
        guard let pad = playerOne else { return false }
        let pulses = [HapticPulse(start: 0, length: 0.18, strong: 1, weak: 0.2), HapticPulse(start: 0.3, length: 0.18, strong: 0.2, weak: 1),
                      HapticPulse(start: 0.6, length: 0.3, strong: 0.8, weak: 0.8)]
        if let controller = controllers[pad.id] {
            guard controller.haptics != nil else { return false }
            let haptics = PadHaptics()
            haptics.use(controller)
            haptics.play(pulses)
            // Kept until the pattern ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { _ = haptics }
            return true
        }
        if pad.kind == .dualShock3 {
            for pulse in pulses {
                DispatchQueue.main.asyncAfter(deadline: .now() + pulse.start) { self.ds3.setOutput(pad.id, strong: pulse.strong, weak: pulse.weak, player: 1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + pulse.start + pulse.length) { self.ds3.setOutput(pad.id, strong: 0, weak: 0, player: 1) }
            }
            return true
        }
        return false
    }

    /// The launcher's pulses on a DualShock 3 (PadHaptics with an external pad).
    func externalRumble(_ id: String, strong: Double, weak: Double) {
        let player = (roster.pads.firstIndex { $0.id == id }).map { roster.playerOne == id ? 1 : $0 + 1 } ?? 1
        ds3.setOutput(id, strong: strong, weak: weak, player: player)
    }

    func symbol(_ kind: PadKind) -> String {
        switch kind {
        case .dualSense, .dualShock4, .dualShock3: return "logo.playstation"
        case .xbox: return "logo.xbox"
        case .switchPro, .generic: return "gamecontroller.fill"
        }
    }

    // MARK: Pad states

    static func state(of pad: GCExtendedGamepad) -> PadState {
        var pressed = Set<PadButton>()
        func add(_ input: GCControllerButtonInput?, _ button: PadButton) { if input?.isPressed == true { pressed.insert(button) } }
        add(pad.buttonA, .south)
        add(pad.buttonB, .east)
        add(pad.buttonX, .west)
        add(pad.buttonY, .north)
        add(pad.leftShoulder, .l1)
        add(pad.rightShoulder, .r1)
        add(pad.leftTrigger, .l2)
        add(pad.rightTrigger, .r2)
        add(pad.buttonOptions, .select)
        add(pad.buttonMenu, .start)
        add(pad.buttonHome, .guide)
        add(pad.leftThumbstickButton, .l3)
        add(pad.rightThumbstickButton, .r3)
        add(pad.dpad.up, .dpadUp)
        add(pad.dpad.down, .dpadDown)
        add(pad.dpad.left, .dpadLeft)
        add(pad.dpad.right, .dpadRight)
        if let sense = pad as? GCDualSenseGamepad { add(sense.touchpadButton, .touchpad) }
        if let shock = pad as? GCDualShockGamepad { add(shock.touchpadButton, .touchpad) }
        if let xbox = pad as? GCXboxGamepad { add(xbox.buttonShare, .misc) }
        return PadState(pressed: pressed, leftX: Double(pad.leftThumbstick.xAxis.value), leftY: -Double(pad.leftThumbstick.yAxis.value),
                        rightX: Double(pad.rightThumbstick.xAxis.value), rightY: -Double(pad.rightThumbstick.yAxis.value),
                        l2: Double(pad.leftTrigger.value), r2: Double(pad.rightTrigger.value))
    }

    // MARK: Previews

    /// Offscreen previews: these controllers and states in place of the real ones.
    func preview(_ pads: [PadInfo], states: [String: PadState] = [:], playerOne: String? = nil, findings: [PadTroubleshooter.Finding]? = nil) {
        var roster = PadRoster()
        for pad in pads { roster.connect(pad) }
        if let playerOne { roster.used(playerOne) }
        self.roster = roster
        live.states = states
        self.findings = findings ?? PadTroubleshooter.diagnose(.init(pads: pads))
    }
}

/// The pads' live states for the controller test.
@MainActor
final class PadLive: ObservableObject {
    @Published var states: [String: PadState] = [:]
}
