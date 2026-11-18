import Foundation

/// The RetroPad buttons by their bit in the `input` message's `buttons` (anyps5-retro-host
/// docs/protocol.md "input"): the libretro `RETRO_DEVICE_ID_JOYPAD_*` numbers as SwanStation maps
/// them. As on Windows and Linux (AnyPS5 Desktop's lib/core/retro_host/retro_pad.dart).
public enum RetroPadButton: Int, CaseIterable, Sendable {
    case cross = 0, square, select, start, up, down, left, right, circle, triangle, l1, r1, l2, r2, l3, r3

    public var bit: Int { rawValue }
    public var mask: Int { 1 << rawValue }

    /// The RetroPad button a launcher pad button presses, by its place on the pad: south is Cross
    /// on every controller, as on a PS1 pad. PS/Guide, the touchpad and the extra button have none:
    /// PS stays the launcher's.
    public static func of(_ button: PadButton) -> RetroPadButton? {
        switch button {
        case .south: return .cross
        case .east: return .circle
        case .west: return .square
        case .north: return .triangle
        case .l1: return .l1
        case .r1: return .r1
        case .l2: return .l2
        case .r2: return .r2
        case .l3: return .l3
        case .r3: return .r3
        case .select: return .select
        case .start: return .start
        case .dpadUp: return .up
        case .dpadDown: return .down
        case .dpadLeft: return .left
        case .dpadRight: return .right
        case .guide, .touchpad, .misc: return nil
        }
    }
}

/// One controller port's state as an `input` message carries it: the sixteen button bits and both
/// sticks from -32768 (fully left or up) to 32767.
public struct RetroPadInput: Equatable, Sendable {
    public var buttons: Int
    public var leftX: Int
    public var leftY: Int
    public var rightX: Int
    public var rightY: Int

    public init(buttons: Int = 0, leftX: Int = 0, leftY: Int = 0, rightX: Int = 0, rightY: Int = 0) {
        self.buttons = buttons
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
    }

    /// Nothing held, both sticks centred: what a port with no controller sends.
    public static let idle = RetroPadInput()

    /// Where a trigger counts as pressed, as the launchers' SDL reader counts it on Windows and
    /// Linux.
    public static let triggerPressed = 0.35

    /// A launcher pad's state. A trigger counts as pressed from `triggerPressed`, also for readers
    /// that give only its button. The sticks go through Settings › Controllers › Stick Dead Zone
    /// (`StickDeadzone`), each stick on its own.
    public static func fromPad(_ state: PadState, deadzonePercent: Int = 0) -> RetroPadInput {
        var buttons = 0
        for button in state.pressed {
            if let retro = RetroPadButton.of(button) { buttons |= retro.mask }
        }
        if state.l2 >= triggerPressed { buttons |= RetroPadButton.l2.mask }
        if state.r2 >= triggerPressed { buttons |= RetroPadButton.r2.mask }
        let left = StickDeadzone.apply(x: state.leftX, y: state.leftY, percent: deadzonePercent)
        let right = StickDeadzone.apply(x: state.rightX, y: state.rightY, percent: deadzonePercent)
        return RetroPadInput(buttons: buttons, leftX: axis(left.x), leftY: axis(left.y), rightX: axis(right.x), rightY: axis(right.y))
    }

    /// A stick axis from -1 (left, up) to 1 (right, down) as the protocol's -32768 to 32767, so
    /// both ends reach the end of the range.
    public static func axis(_ value: Double) -> Int {
        if value.isNaN { return 0 }
        let unit = min(1, max(-1, value))
        return unit < 0 ? Int((unit * 32768).rounded()) : Int((unit * 32767).rounded())
    }

    /// The same sticks with `buttons` held.
    public func withButtons(_ buttons: Int) -> RetroPadInput {
        RetroPadInput(buttons: buttons, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY)
    }
}

/// The keyboard as a PS1 controller, by the keys a game's Controls give each `PadAction`
/// (`Controls.sources`: the launcher's layout with the keys the player moved), as on Windows and
/// Linux (AnyPS5 Desktop's lib/core/retro_host/retro_keyboard.dart). Its state joins the controller
/// at port 1, as a libretro frontend binds the keyboard to player 1.
///
/// Only keys count: mouse buttons and the wheel are not read. The touchpad's two halves are the
/// PS1's Select, as on the PS4 and PS5's own PS1 releases. The stick modifier tilts the keyboard's
/// sticks only by `modifierScale`.
public struct RetroKeyboard: Sendable {
    /// How far the keyboard's sticks tilt while the stick modifier is held, 0 to 1.
    public let modifierScale: Double
    private let actions: [String: [PadAction]]

    public init(changes: [String: [String]], modifierScale: Double = 0.5) {
        self.modifierScale = modifierScale
        var actions: [String: [PadAction]] = [:]
        for action in PadAction.allCases {
            for source in Controls.sources(action, changes) where source.hasPrefix("KEY:") {
                actions[String(source.dropFirst(4)), default: []].append(action)
            }
        }
        self.actions = actions
    }

    /// The keyboard's whole state while `held` are down, by their names (`Controls.keyName`).
    public func state(held: Set<String>) -> PadState {
        var down = Set<PadAction>()
        for name in held { down.formUnion(actions[name] ?? []) }
        let pressed = Set(down.compactMap(Self.button))
        let tilt = down.contains(.stickModifier) ? modifierScale : 1
        func axis(_ negative: PadAction, _ positive: PadAction) -> Double {
            Double((down.contains(positive) ? 1 : 0) - (down.contains(negative) ? 1 : 0)) * tilt
        }
        return PadState(pressed: pressed, leftX: axis(.leftStickLeft, .leftStickRight), leftY: axis(.leftStickUp, .leftStickDown),
                        rightX: axis(.rightStickLeft, .rightStickRight), rightY: axis(.rightStickUp, .rightStickDown),
                        l2: down.contains(.l2) ? 1 : 0, r2: down.contains(.r2) ? 1 : 0)
    }

    static func button(_ action: PadAction) -> PadButton? {
        switch action {
        case .cross: return .south
        case .circle: return .east
        case .square: return .west
        case .triangle: return .north
        case .l1: return .l1
        case .r1: return .r1
        case .l2: return .l2
        case .r2: return .r2
        case .l3: return .l3
        case .r3: return .r3
        case .options: return .start
        case .touchLeft, .touchRight: return .select
        case .up: return .dpadUp
        case .down: return .dpadDown
        case .left: return .dpadLeft
        case .right: return .dpadRight
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight, .rightStickUp, .rightStickDown, .rightStickLeft,
             .rightStickRight, .stickModifier:
            return nil
        }
    }

    /// `pad` and `keys` held together: every button of either, and each stick from the keys while
    /// they tilt it, from the controller otherwise.
    public static func merge(_ pad: PadState?, _ keys: PadState) -> PadState {
        guard let pad else { return keys }
        let keysLeft = keys.leftX != 0 || keys.leftY != 0
        let keysRight = keys.rightX != 0 || keys.rightY != 0
        return PadState(pressed: pad.pressed.union(keys.pressed), leftX: keysLeft ? keys.leftX : pad.leftX,
                        leftY: keysLeft ? keys.leftY : pad.leftY, rightX: keysRight ? keys.rightX : pad.rightX,
                        rightY: keysRight ? keys.rightY : pad.rightY, l2: max(pad.l2, keys.l2), r2: max(pad.r2, keys.r2))
    }
}
