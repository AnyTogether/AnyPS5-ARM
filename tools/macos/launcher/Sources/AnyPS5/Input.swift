import AppKit
import Carbon.HIToolbox
import GameController

enum Command {
    case left, right, up, down, select, back, options
    /// L1 and R1: the game before or after the selected one, from the home screen or a game's panel.
    case previousGame, nextGame
    /// The controller's PS button: the launcher in front of the game, or back to the game.
    case home
    /// Create on a DualSense (Share on a DualShock 4), or ⌥F12: the last seconds as a clip.
    case capture
}

/// Keyboard and game controller input, as the commands the screens act on. Held directions repeat
/// the way a console menu does.
@MainActor
final class Input {
    static let shared = Input()
    var handler: ((Command) -> Bool)?
    /// Scroll wheel turns as left and right moves, where the screen wants them.
    var scrollHandler: ((Command) -> Bool)?
    /// Takes every key while a binding waits for one (the controls panel); returns whether it used it.
    var capture: ((NSEvent) -> Bool)?
    private var monitor: Any?
    private var wheelMonitor: Any?
    private var accumulated: CGFloat = 0
    private var repeatTimer: Timer?
    private var held: Command?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, !Input.belongsToPanel(event) else { return event }
            if let capture = self.capture { return capture(event) ? nil : event }
            guard event.type == .keyDown, let command = Input.command(for: event) else { return event }
            // Text fields keep their keys.
            if let responder = event.window?.firstResponder as? NSTextView, responder.isEditable { return event }
            return self.handler?(command) == true ? nil : event
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
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.direction(x: x, y: y) }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.direction(x: abs(x) > 0.55 ? x : 0, y: abs(y) > 0.55 ? y : 0) }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.select) } }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.back) } }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.options) } }
        }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.options) } }
        }
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.previousGame) } }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.nextGame) } }
        }
        pad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { MainActor.assumeIsolated { self?.controller(.home) } }
        }
        // Only a PlayStation controller's Create (Share) is the console's; another controller's
        // View button is its touchpad in the game.
        if pad is GCDualSenseGamepad || pad is GCDualShockGamepad {
            pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { MainActor.assumeIsolated { self?.controller(.capture) } }
            }
        }
    }

    /// ⌥F12, beside F12's screenshot, from any app: a hot key the system hands over without the
    /// accessibility permission a key monitor in the background would need.
    private func registerCaptureKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { Input.shared.controller(.capture) }
            return noErr
        }, 1, &type, nil, nil)
        var reference: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_F12), UInt32(optionKey), EventHotKeyID(signature: OSType(0x4150_5335), id: 1), GetApplicationEventTarget(), 0, &reference)
    }

    /// A controller command; while the launcher is behind a game only PS is acted on.
    private func controller(_ command: Command) {
        guard NSApp.isActive || command == .home || command == .capture else { return }
        _ = handler?(command)
    }

    private func direction(x: Float, y: Float) {
        let command: Command? = abs(x) > abs(y) ? (x > 0 ? .right : x < 0 ? .left : nil) : (y > 0 ? .up : y < 0 ? .down : nil)
        guard command != held else { return }
        held = command
        repeatTimer?.invalidate()
        guard let command, NSApp.isActive else { return }
        _ = handler?(command)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        guard let self, let held = self.held else { return }
                        _ = self.handler?(held)
                    }
                }
            }
        }
    }
}
