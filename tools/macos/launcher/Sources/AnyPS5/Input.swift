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
    /// A right click on Home opens the Options menu; true when it took the click.
    var rightClickHandler: (() -> Bool)?
    /// Esc (the key, not Circle): true when the screen took it as more than Back ("Quit AnyPS5?").
    var escapeHandler: (() -> Bool)?
    /// The mouse's side buttons, once a capture or a text field has had its say.
    var sideButtonHandler: ((SideButton) -> Void)?
    /// Options/Start on Home opens the same menu (△ stays the game's settings); true when it
    /// took the press, else it is Options as ever.
    var menuHandler: (() -> Bool)?
    /// Takes every key while a binding waits for one (the controls panel); returns whether it used it.
    var capture: ((NSEvent) -> Bool)? {
        didSet { if capture != nil { hold(nil) } }
    }
    /// Settings → Shortcuts: an action from its key or pad chord, pressed or held.
    var shortcutHandler: ((ShortcutAction, Bool) -> Void)?
    /// Takes the controllers' buttons while a shortcut waits for a chord: what is held now, when.
    var padCapture: ((Set<PadButton>, TimeInterval) -> Void)? {
        didSet {
            hold(nil)
            for id in readers.keys { readers[id]?.reset() }
        }
    }
    private(set) var shortcuts = ShortcutMap()
    /// Each controller's chords, by controller.
    private var readers: [AnyHashable: PadShortcutReader] = [:]
    /// A shortcut key held that means something else held (Home): its action and its press.
    private var keyHold: (action: ShortcutAction, keyCode: UInt16?, press: LongPress)?
    private var holdTimer: Timer?
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
    private var dpads: [AnyHashable: Command] = [:]
    private var sticks: [AnyHashable: StickGate] = [:]
    /// Settings → Controllers → Confirm Button: Circle confirms and Cross goes back.
    var circleConfirms = false
    /// Settings → Controllers → Stick Dead Zone, in percent.
    var deadzone = 0
    /// The controller test is open: the pads' buttons are being tried, not used (only PS acts).
    var testing = false {
        didSet { if testing { hold(nil) } }
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, !Input.belongsToPanel(event) else { return event }
            if let capture = self.capture { return event.type == .keyUp ? event : (capture(event) ? nil : event) }
            if event.type == .keyUp, event.keyCode == self.heldKey { self.hold(nil) }
            if event.type == .keyUp {
                return self.keyReleased(event.keyCode) ? nil : event
            }
            guard event.type == .keyDown else { return event }
            // Text fields keep their keys.
            if let responder = event.window?.firstResponder as? NSTextView, responder.isEditable { return event }
            if self.keyShortcut(event) { return nil }
            if event.keyCode == UInt16(kVK_Escape), Input.modifiers(event.modifierFlags).isEmpty, self.escapeHandler?() == true {
                Feel.shared.usedKeyboard()
                InputModeState.shared.usedKeyboard()
                return nil
            }
            guard let command = Input.command(for: event) else { return event }
            Feel.shared.usedKeyboard()
            InputModeState.shared.usedKeyboard()
            if EdgeBump.isDirection(command) {
                // The system's repeats of the held arrow: the launcher's own repeat paces it.
                if event.isARepeat { return event.keyCode == self.heldKey ? nil : event }
                guard self.dispatch(command, repeat: false) else { return event }
                self.hold(command, key: event.keyCode)
                return nil
            }
            return self.dispatch(command, repeat: false) ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved]) { [weak self] event in
            if event.type == .otherMouseDown, let button = Input.sideButton(event.buttonNumber), !Input.belongsToPanel(event) {
                Feel.shared.usedKeyboard()
                InputModeState.shared.usedKeyboard()
                self?.side(button, in: event.window)
                return nil
            }
            if event.type == .rightMouseDown, !Input.belongsToPanel(event), self?.rightClickHandler?() == true {
                Feel.shared.usedKeyboard()
                InputModeState.shared.usedKeyboard()
                return nil
            }
            if event.type == .mouseMoved {
                InputModeState.shared.pointerMoved(hypot(event.deltaX, event.deltaY))
            } else {
                Feel.shared.usedKeyboard()
                InputModeState.shared.usedKeyboard()
            }
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
        apply(shortcuts)
        GCController.controllers().forEach(attach)
        GCController.startWirelessControllerDiscovery {}
    }

    /// The mouse's side buttons: Back is Circle wherever the user is, Forward opens again the
    /// screen Back just closed, as in a browser.
    enum SideButton: Equatable {
        case back, forward
    }

    /// macOS numbers the side buttons 3 (Back) and 4 (Forward); 2 is the middle button.
    static func sideButton(_ number: Int) -> SideButton? {
        switch number {
        case 3: return .back
        case 4: return .forward
        default: return nil
        }
    }

    /// Esc as a key event, for a capture waiting for a key: Back gives it up as Esc does.
    static let escapeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                              characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: UInt16(kVK_Escape))

    /// A side button pressed: a key or chord being waited for is given up and a text field being
    /// typed in lets go first, as Esc does; else the screens take it.
    private func side(_ button: SideButton, in window: NSWindow?) {
        if capture != nil || padCapture != nil {
            if button == .back, let escape = Input.escapeEvent { _ = capture?(escape) }
            return
        }
        if button == .back, let window, let text = window.firstResponder as? NSTextView, text.isEditable {
            window.makeFirstResponder(nil)
            return
        }
        sideButtonHandler?(button)
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
            default: return nil
            }
        }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let id = AnyHashable(ObjectIdentifier(controller))
        // A DualShock 3's framework copy while the launcher's reader delivers the same pad: ignored.
        func ignored(_ controller: GCController?) -> Bool { controller.map { Controllers.shared.ignores($0) } ?? false }
        pad.dpad.valueChangedHandler = { [weak self, weak controller, weak pad] _, x, y in
            MainActor.assumeIsolated {
                guard let self, !ignored(controller) else { return }
                self.dpads[id] = abs(x) > abs(y) ? (x > 0 ? .right : x < 0 ? .left : nil) : (y > 0 ? .up : y < 0 ? .down : nil)
                if let pad { self.padButtons(id, Input.shortcutButtons(of: pad), controller) }
                self.padMoved(id, controller)
            }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self, weak controller] _, x, y in
            MainActor.assumeIsolated {
                guard let self, !ignored(controller) else { return }
                var stick = self.sticks[id] ?? StickGate()
                let before = stick.held
                let zoned = StickDeadzone.apply(x: Double(x), y: Double(y), percent: self.deadzone)
                _ = stick.update(x: zoned.x, y: zoned.y)
                self.sticks[id] = stick
                if stick.held != before { self.padMoved(id, controller) }
            }
        }
        // ✕ ○ △ and Options move around the screens; every button can be in a shortcut's chord
        // (Settings → Shortcuts: PS, Create, L1 and R1 by default).
        func button(_ input: GCControllerButtonInput?, _ command: Command?) {
            input?.pressedChangedHandler = { [weak self, weak controller, weak pad] _, _, pressed in
                MainActor.assumeIsolated {
                    guard let self, !ignored(controller) else { return }
                    if let pad { self.padButtons(id, Input.shortcutButtons(of: pad), controller) }
                    if pressed, let command { self.controller(command, from: controller) }
                }
            }
        }
        button(pad.buttonA, .select)
        button(pad.buttonB, .back)
        button(pad.buttonY, .options)
        // Options/Start: on Home the Options menu (Switch Profile, online or offline), else Options.
        pad.buttonMenu.pressedChangedHandler = { [weak self, weak controller, weak pad] _, _, pressed in
            MainActor.assumeIsolated {
                guard let self, !ignored(controller) else { return }
                if let pad { self.padButtons(id, Input.shortcutButtons(of: pad), controller) }
                guard pressed else { return }
                if NSApp.isActive, let controller { self.usedPad(controller) }
                if self.takesMenu() { return }
                self.controller(.options, from: controller)
            }
        }
        for input in [pad.buttonX, pad.leftShoulder, pad.rightShoulder, pad.leftTrigger, pad.rightTrigger, pad.buttonHome, pad.buttonOptions,
                      pad.leftThumbstickButton, pad.rightThumbstickButton] {
            button(input, nil)
        }
        if let sense = pad as? GCDualSenseGamepad { button(sense.touchpadButton, nil) }
        if let shock = pad as? GCDualShockGamepad { button(shock.touchpadButton, nil) }
        if let xbox = pad as? GCXboxGamepad { button(xbox.buttonShare, nil) }
    }

    /// The buttons a controller holds as the shortcuts name them. Create is a PlayStation pad's
    /// Create (Share on a DualShock 4) or an Xbox pad's Share; another pad's View button is its
    /// touchpad in the game, never the console's.
    static func shortcutButtons(of pad: GCExtendedGamepad) -> Set<PadButton> {
        var pressed = Controllers.state(of: pad).pressed
        let playStation = pad is GCDualSenseGamepad || pad is GCDualShockGamepad
        if !playStation { pressed.remove(.select) }
        if pressed.remove(.misc) != nil { pressed.insert(.select) }
        return pressed
    }

    // MARK: Shortcuts

    /// Settings → Shortcuts changed (or the launcher started): the keys that work from any app are
    /// registered again, and the pads read the new chords.
    func apply(_ map: ShortcutMap) {
        shortcuts = map
        readers = [:]
        keyHold = nil
        for id in Input.shortcutKeys { unregisterHotKey(id: id) }
        for (index, (action, key)) in map.inGameKeys.enumerated() {
            registerHotKey(id: Input.shortcutKeys.lowerBound + UInt32(index), keyCode: Int(key.keyCode), modifiers: Input.carbon(key.modifiers)) { [weak self] pressed in
                self?.hotKey(action, pressed: pressed)
            }
        }
    }

    /// The hot keys' ids for the shortcuts that work in games.
    static let shortcutKeys: Range<UInt32> = 100 ..< 120

    static func carbon(_ modifiers: KeyChord.Modifiers) -> Int {
        var carbon = 0
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.command) { carbon |= cmdKey }
        return carbon
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyChord.Modifiers {
        var modifiers: KeyChord.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    static func chord(of event: NSEvent) -> KeyChord? {
        guard let name = Controls.keyName(forKeyCode: event.keyCode) else { return nil }
        return KeyChord(keyCode: event.keyCode, modifiers: modifiers(event.modifierFlags), name: name)
    }

    /// A key pressed in the launcher that is a shortcut (or ⌃⌘F, macOS's own full screen key).
    private func keyShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_ANSI_F) && Input.modifiers(event.modifierFlags) == [.control, .command] {
            if !event.isARepeat { fire(.fullScreen, hold: false, keyboard: true) }
            return true
        }
        guard let chord = Input.chord(of: event), let action = shortcuts.action(forKey: chord) else { return false }
        if event.isARepeat { return true }
        keyPressed(action, keyCode: event.keyCode)
        return true
    }

    private func keyPressed(_ action: ShortcutAction, keyCode: UInt16?) {
        guard action.hasHold else { return fire(action, hold: false, keyboard: true) }
        var press = LongPress()
        press.press(at: ProcessInfo.processInfo.systemUptime)
        keyHold = (action, keyCode, press)
        scheduleHoldTick()
    }

    /// A key let go: the press or hold of the shortcut it held.
    private func keyReleased(_ keyCode: UInt16?) -> Bool {
        guard var held = keyHold, held.keyCode == keyCode else { return false }
        keyHold = nil
        if let outcome = held.press.release(at: ProcessInfo.processInfo.systemUptime) { fire(held.action, hold: outcome == .hold, keyboard: true) }
        return true
    }

    /// A shortcut's hot key, from any app.
    private func hotKey(_ action: ShortcutAction, pressed: Bool) {
        if pressed {
            guard keyHold == nil else { return }
            keyPressed(action, keyCode: nil)
        } else if keyHold?.action == action {
            _ = keyReleased(nil)
        }
    }

    /// A controller's buttons changed: its chords, or the shortcut waiting for one.
    private func padButtons(_ id: AnyHashable, _ pressed: Set<PadButton>, _ controller: GCController?) {
        let now = ProcessInfo.processInfo.systemUptime
        if let padCapture {
            if NSApp.isActive, !pressed.isEmpty { usedPad(controller) }
            return padCapture(pressed, now)
        }
        var reader = readers[id] ?? PadShortcutReader(map: shortcuts)
        let events = reader.update(pressed, at: now)
        readers[id] = reader
        if !events.isEmpty, NSApp.isActive { usedPad(controller) }
        for event in events { padEvent(event) }
        scheduleHoldTick()
    }

    private func padEvent(_ event: PadShortcutReader.Event) {
        switch event {
        case .press(let action): fire(action, hold: false, keyboard: false)
        case .hold(let action): fire(action, hold: true, keyboard: false)
        }
    }

    /// While the launcher is behind a game only the shortcuts that work in games act; the
    /// controller test lets only Home through.
    private func fire(_ action: ShortcutAction, hold: Bool, keyboard: Bool) {
        guard NSApp.isActive || action.worksInGame else { return }
        guard !testing || action == .home else { return }
        if keyboard, NSApp.isActive {
            Feel.shared.usedKeyboard()
            InputModeState.shared.usedKeyboard()
        }
        shortcutHandler?(action, hold)
    }

    /// One timer for whatever hold comes due first, a key's or a controller's.
    private func scheduleHoldTick() {
        holdTimer?.invalidate()
        holdTimer = nil
        let due = (readers.values.compactMap(\.due) + [keyHold?.press.due].compactMap { $0 }).min()
        guard let due else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, due - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.holdTick() }
        }
    }

    private func holdTick() {
        let now = ProcessInfo.processInfo.systemUptime
        if var held = keyHold, held.press.tick(at: now) == .hold {
            keyHold = held
            fire(held.action, hold: true, keyboard: true)
        }
        for id in Array(readers.keys) {
            guard var reader = readers[id] else { continue }
            let events = reader.tick(at: now)
            readers[id] = reader
            events.forEach(padEvent)
        }
        scheduleHoldTick()
    }

    private func usedPad(_ controller: GCController?) {
        Feel.shared.usedPad(controller)
        InputModeState.shared.usedPad()
    }
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

    /// A controller command; while the launcher is behind a game only PS is acted on. Cross and
    /// Circle change places when Circle confirms.
    /// Options/Start pressed: the Options menu when Home takes it.
    private func takesMenu() -> Bool {
        NSApp.isActive && padCapture == nil && !testing && menuHandler?() == true
    }

    private func controller(_ command: Command, from controller: GCController?) {
        if NSApp.isActive, let controller { usedPad(controller) }
        guard padCapture == nil else { return }
        guard NSApp.isActive || command == .home || command == .capture else { return }
        guard !testing || command == .home else { return }
        _ = dispatch(controller == nil ? command : ConfirmButton.command(command, circleConfirms: circleConfirms), repeat: false)
    }

    /// A controller the launcher reads itself (the DualShock 3): its new state against the one
    /// before, as the same commands a GameController pad gives.
    func external(_ id: String, state: PadState, previous: PadState) {
        let key = AnyHashable(id)
        let buttons: [(PadButton, Command)] = [(.south, .select), (.east, .back), (.north, .options), (.start, .options)]
        if state.pressed != previous.pressed {
            if NSApp.isActive, !state.pressed.subtracting(previous.pressed).isEmpty {
                Feel.shared.haptics.padInUse = true
                Feel.shared.pad.use(external: id)
                InputModeState.shared.usedPad()
            }
            // PS, Select (the DualShock 3's Create), L1 and R1 are shortcuts like any pad's.
            padButtons(key, state.pressed, nil)
        }
        for (button, command) in buttons where state.pressed.contains(button) && !previous.pressed.contains(button) {
            guard padCapture == nil else { continue }
            if button == .start, takesMenu() { continue }
            guard NSApp.isActive || command == .home || command == .capture else { continue }
            guard !testing || command == .home else { continue }
            _ = dispatch(ConfirmButton.command(command, circleConfirms: circleConfirms), repeat: false)
        }
        let p = state.pressed
        dpads[key] = p.contains(.dpadLeft) ? .left : p.contains(.dpadRight) ? .right : p.contains(.dpadUp) ? .up : p.contains(.dpadDown) ? .down : nil
        var stick = sticks[key] ?? StickGate()
        let zoned = StickDeadzone.apply(x: state.leftX, y: -state.leftY, percent: deadzone)
        _ = stick.update(x: zoned.x, y: zoned.y)
        sticks[key] = stick
        padMoved(key, nil)
    }

    /// A controller's D-pad or stick changed: the direction it holds now, the D-pad first.
    private func padMoved(_ id: AnyHashable, _ controller: GCController?) {
        let command = dpads[id] ?? sticks[id]?.held
        if command != nil, NSApp.isActive { usedPad(controller) }
        guard !testing, padCapture == nil else { return }
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

/// The input in use for the screens to follow: a controller's glyphs and no pointer-only arrows
/// while the pad is used, the keys' hints while the keyboard or the mouse is (InputModeTracker).
@MainActor
final class InputModeState: ObservableObject {
    static let shared = InputModeState()

    @Published private(set) var mode: InputMode = .keyboard
    private var tracker = InputModeTracker()
    /// The mode changed (a choice being edited ends when the mouse takes over).
    var changed: ((InputMode) -> Void)?

    func usedPad() {
        // The pointer hides until the mouse moves again, as a console has none.
        if NSApp?.isActive == true { NSCursor.setHiddenUntilMouseMoves(true) }
        if tracker.usedPad() { publish() }
    }

    func usedKeyboard() {
        if tracker.usedKeyboard() { publish() }
    }

    func pointerMoved(_ distance: Double) {
        if tracker.pointerMoved(distance) { publish() }
    }

    /// Offscreen previews: the screens as the pad or the keyboard sees them.
    func preview(_ mode: InputMode) {
        tracker = InputModeTracker(mode: mode)
        self.mode = mode
    }

    private func publish() {
        mode = tracker.mode
        changed?(mode)
    }
}
