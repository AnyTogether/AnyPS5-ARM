import AnyPS5Core
import AppKit
import Carbon.HIToolbox
import GameController

/// Keyboard and game controller input, as the commands the screens act on. A held direction
/// repeats the way a console menu does, at the same pace under a finger and under a thumb
/// (KeyRepeat: the system's own key repeats are dropped); a direction with nowhere to go bumps.
@MainActor
final class Input {
    static let shared = Input()
    var handler: ((Command) -> Bool)?
    /// Scroll wheel turns as left and right moves, where the screen wants them.
    var scrollHandler: ((Command) -> Bool)?
    /// Takes every key while a binding waits for one (the controls panel); returns whether it used it.
    var capture: ((NSEvent) -> Bool)? {
        didSet { if capture != nil { hold(nil) } }
    }
    /// A number that changes whenever a command did something (the model changed or a sound
    /// played): a direction that left it as it was hit the end of its row.
    var activity: (() -> Int)?
    private var monitor: Any?
    private var wheelMonitor: Any?
    private var mouseMonitor: Any?
    private var accumulated: CGFloat = 0
    private var repeatTimer: Timer?
    /// The direction being held and what holds it: the controller, or an arrow key (its code).
    private var held: Command?
    private var heldKey: UInt16?
    private var repeats = 0
    private var edge = EdgeBump()
    /// Each controller's D-pad and stick, the D-pad winning while it is pressed.
    private var dpads: [ObjectIdentifier: Command] = [:]
    private var sticks: [ObjectIdentifier: StickGate] = [:]

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, !Input.belongsToPanel(event) else { return event }
            if let capture = self.capture { return event.type == .keyUp ? event : (capture(event) ? nil : event) }
            if event.type == .keyUp {
                if event.keyCode == self.heldKey { self.hold(nil) }
                return event
            }
            guard event.type == .keyDown, let command = Input.command(for: event) else { return event }
            // Text fields keep their keys.
            if let responder = event.window?.firstResponder as? NSTextView, responder.isEditable { return event }
            Feel.shared.usedKeyboard()
            if EdgeBump.isDirection(command) {
                // The system's repeats of the held arrow: the launcher's own repeat paces it.
                if event.isARepeat { return event.keyCode == self.heldKey ? nil : event }
                guard self.dispatch(command, repeat: false) else { return event }
                self.hold(command, key: event.keyCode)
                return nil
            }
            return self.dispatch(command, repeat: false) ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            Feel.shared.usedKeyboard()
            return event
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // A key let go in another app never says so here.
            MainActor.assumeIsolated { self?.hold(nil) }
        }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !Input.belongsToPanel(event) else { return event }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY
            self.accumulated += event.hasPreciseScrollingDeltas ? delta : delta * 12
            if event.phase == .began { self.accumulated = delta }
            guard abs(self.accumulated) >= 40 else { return event }
            let command: Command = self.accumulated > 0 ? .left : .right
            self.accumulated = 0
            return self.scrollHandler?(command) == true ? nil : event
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(controller) }
        }
        // The PS and Create buttons reach the launcher while a game is in front; nothing else does then.
        GCController.shouldMonitorBackgroundEvents = true
        registerCaptureKey()
        GCController.controllers().forEach(attach)
        GCController.startWirelessControllerDiscovery {}
    }

    /// Whether a flagsChanged event is a modifier key going down rather than up.
    static func pressesModifier(_ event: NSEvent) -> Bool {
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 56, 60: flag = .shift
        case 58, 61: flag = .option
        case 59, 62: flag = .control
        case 54, 55: flag = .command
        case 57: flag = .capsLock
        default: return false
        }
        return event.modifierFlags.contains(flag)
    }

    /// Open and save panels and alerts keep their own keys.
    static func belongsToPanel(_ event: NSEvent) -> Bool {
        NSApp.modalWindow != nil || event.window is NSPanel
    }

    static func command(for event: NSEvent) -> Command? {
        if event.modifierFlags.contains(.command) { return nil }
        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 36, 76, 49: return .select
        case 53, 51: return .back
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "o": return .options
            case "q": return .previousGame
            case "e": return .nextGame
            default: return nil
            }
        }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let id = ObjectIdentifier(controller)
        pad.dpad.valueChangedHandler = { [weak self, weak controller] _, x, y in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dpads[id] = abs(x) > abs(y) ? (x > 0 ? .right : x < 0 ? .left : nil) : (y > 0 ? .up : y < 0 ? .down : nil)
                self.padMoved(id, controller)
            }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self, weak controller] _, x, y in
            MainActor.assumeIsolated {
                guard let self else { return }
                var stick = self.sticks[id] ?? StickGate()
                let before = stick.held
                _ = stick.update(x: Double(x), y: Double(y))
                self.sticks[id] = stick
                if stick.held != before { self.padMoved(id, controller) }
            }
        }
        func button(_ input: GCControllerButtonInput?, _ command: Command) {
            input?.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
                if pressed { MainActor.assumeIsolated { self?.controller(command, from: controller) } }
            }
        }
        button(pad.buttonA, .select)
        button(pad.buttonB, .back)
        button(pad.buttonY, .options)
        button(pad.buttonMenu, .options)
        button(pad.leftShoulder, .previousGame)
        button(pad.rightShoulder, .nextGame)
        button(pad.buttonHome, .home)
        // Only a PlayStation controller's Create (Share) is the console's; another controller's
        // View button is its touchpad in the game.
        if pad is GCDualSenseGamepad || pad is GCDualShockGamepad {
            button(pad.buttonOptions, .capture)
        }
    }

    /// ⌥F12, beside F12's screenshot, from any app: a hot key the system hands over without the
    /// accessibility permission a key monitor in the background would need.
    private func registerCaptureKey() {
        registerHotKey(id: Input.captureKey, keyCode: kVK_F12, modifiers: optionKey) { [weak self] pressed in
            if pressed { self?.controller(.capture, from: nil) }
        }
    }

    static let captureKey: UInt32 = 1
    static let talkKey: UInt32 = 2
    /// ⌥A and ⌥D while a friend's call rings.
    static let answerKey: UInt32 = 3
    static let declineKey: UInt32 = 4
    private var hotKeys: [UInt32: (handler: (Bool) -> Void, reference: EventHotKeyRef?)] = [:]
    private var hotKeyHandler = false

    /// A key with modifiers that reaches the launcher from any app, pressed and released (a
    /// party's push-to-talk while a game is in front).
    func registerHotKey(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping (Bool) -> Void) {
        if !hotKeyHandler {
            hotKeyHandler = true
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var key = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                MainActor.assumeIsolated { Input.shared.hotKeys[key.id]?.handler(pressed) }
                return noErr
            }, 2, &types, nil, nil)
        }
        unregisterHotKey(id: id)
        var reference: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4150_5335), id: id), GetApplicationEventTarget(), 0, &reference)
        hotKeys[id] = (handler, reference)
    }

    func unregisterHotKey(id: UInt32) {
        if let reference = hotKeys[id]?.reference { UnregisterEventHotKey(reference) }
        hotKeys[id] = nil
    }

    /// A click on a hint pill: the command its key gives, through the same handler.
    func press(_ command: Command) {
        guard capture == nil else { return }
        _ = handler?(command)
    }

    /// A controller command; while the launcher is behind a game only PS is acted on.
    private func controller(_ command: Command, from controller: GCController?) {
        if NSApp.isActive, let controller { Feel.shared.usedPad(controller) }
        guard NSApp.isActive || command == .home || command == .capture else { return }
        _ = dispatch(command, repeat: false)
    }

    /// A controller's D-pad or stick changed: the direction it holds now, the D-pad first.
    private func padMoved(_ id: ObjectIdentifier, _ controller: GCController?) {
        let command = dpads[id] ?? sticks[id]?.held
        if command != nil, NSApp.isActive { Feel.shared.usedPad(controller) }
        // Another input's hold is let go only by that input.
        guard heldKey == nil || command != nil else { return }
        guard command != held || heldKey != nil else { return }
        guard let command, NSApp.isActive, capture == nil else { return hold(nil) }
        _ = dispatch(command, repeat: false)
        hold(command)
    }

    /// Hands a command to the screens; a direction that did nothing bumps (once per hold).
    @discardableResult
    private func dispatch(_ command: Command, repeat isRepeat: Bool) -> Bool {
        let before = activity?()
        let used = handler?(command) == true
        if used, let before, edge.handled(command, repeat: isRepeat, changed: activity?() != before) {
            Sounds.shared.play(.bump)
        }
        return used
    }

    /// Starts repeating `command` (nil stops): the first repeat after 0.40 s, then faster.
    private func hold(_ command: Command?, key: UInt16? = nil) {
        repeatTimer?.invalidate()
        repeatTimer = nil
        held = command
        heldKey = command == nil ? nil : key
        repeats = 0
        if command != nil { scheduleRepeat() }
    }

    private func scheduleRepeat() {
        repeatTimer = Timer.scheduledTimer(withTimeInterval: KeyRepeat.delay(beforeRepeat: repeats + 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let held = self.held else { return }
                // The hold ends when a dialog or a binding takes the keys, or the launcher goes behind.
                guard NSApp.isActive, self.capture == nil, NSApp.modalWindow == nil else { return self.hold(nil) }
                self.repeats += 1
                self.dispatch(held, repeat: true)
                self.scheduleRepeat()
            }
        }
    }
}
