import Foundation

/// A pad input a keyboard key or mouse button can press, named as the engine's anyps5-input.ini names it.
public enum PadAction: String, CaseIterable, Codable, Sendable {
    case cross = "Cross", circle = "Circle", square = "Square", triangle = "Triangle"
    case l1 = "L1", r1 = "R1", l2 = "L2", r2 = "R2", l3 = "L3", r3 = "R3"
    case options = "Options", touchLeft = "TouchLeft", touchRight = "TouchRight"
    case up = "Up", down = "Down", left = "Left", right = "Right"
    case leftStickUp = "LeftStickUp", leftStickDown = "LeftStickDown", leftStickLeft = "LeftStickLeft", leftStickRight = "LeftStickRight"
    case rightStickUp = "RightStickUp", rightStickDown = "RightStickDown", rightStickLeft = "RightStickLeft", rightStickRight = "RightStickRight"
    /// Held, the keyboard sticks tilt only by the tuning's stick modifier scale, for walking.
    case stickModifier = "StickModifier"
}

/// The input file's settings for the controller sticks, the mouse as the right stick and the
/// keyboard sticks, in the steps the launcher shows them: whole percentages, tenths and
/// milliseconds. The defaults are the engine's, and only changed ones are written.
public struct InputTuning: Codable, Equatable, Sendable {
    public var leftDeadzone = 0
    public var rightDeadzone = 0
    public var mouseSensitivity = 10
    public var mouseVerticalScale = 10
    public var mouseCurve = 10
    public var mouseDeadzoneOffset = 20
    public var mouseMaxSpeed = 10
    public var mouseSmoothingMs = 10
    public var mouseDecayMs = 30
    public var stickModifierScale = 50
    public var keyboardRampMs = 0
    public var triggerRampMs = 0

    public init() {}

    /// Settings saved by an older launcher miss the newer fields, which keep their defaults.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InputTuning()
        func read(_ key: CodingKeys, _ fallback: Int) throws -> Int { try values.decodeIfPresent(Int.self, forKey: key) ?? fallback }
        leftDeadzone = try read(.leftDeadzone, defaults.leftDeadzone)
        rightDeadzone = try read(.rightDeadzone, defaults.rightDeadzone)
        mouseSensitivity = try read(.mouseSensitivity, defaults.mouseSensitivity)
        mouseVerticalScale = try read(.mouseVerticalScale, defaults.mouseVerticalScale)
        mouseCurve = try read(.mouseCurve, defaults.mouseCurve)
        mouseDeadzoneOffset = try read(.mouseDeadzoneOffset, defaults.mouseDeadzoneOffset)
        mouseMaxSpeed = try read(.mouseMaxSpeed, defaults.mouseMaxSpeed)
        mouseSmoothingMs = try read(.mouseSmoothingMs, defaults.mouseSmoothingMs)
        mouseDecayMs = try read(.mouseDecayMs, defaults.mouseDecayMs)
        stickModifierScale = try read(.stickModifierScale, defaults.stickModifierScale)
        keyboardRampMs = try read(.keyboardRampMs, defaults.keyboardRampMs)
        triggerRampMs = try read(.triggerRampMs, defaults.triggerRampMs)
    }

    /// `Setting = Value` lines for the settings that differ from the engine's defaults, clamped
    /// to the ranges the engine accepts.
    public var lines: [String] {
        let defaults = InputTuning()
        func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(range.upperBound, max(range.lowerBound, value)) }
        func tenths(_ value: Int) -> String { String(Double(value) / 10) }
        func hundredths(_ value: Int) -> String { String(Double(value) / 100) }
        let settings: [(String, Int, Int, (Int) -> String)] = [
            ("LeftStickDeadzone", clamp(leftDeadzone, 0...90), defaults.leftDeadzone, String.init),
            ("RightStickDeadzone", clamp(rightDeadzone, 0...90), defaults.rightDeadzone, String.init),
            ("MouseSensitivity", clamp(mouseSensitivity, 1...100), defaults.mouseSensitivity, tenths),
            ("MouseVerticalScale", clamp(mouseVerticalScale, 1...100), defaults.mouseVerticalScale, tenths),
            ("MouseCurve", clamp(mouseCurve, 2...50), defaults.mouseCurve, tenths),
            ("MouseDeadzoneOffset", clamp(mouseDeadzoneOffset, 0...90), defaults.mouseDeadzoneOffset, hundredths),
            ("MouseMaxSpeed", clamp(mouseMaxSpeed, 1...100), defaults.mouseMaxSpeed, tenths),
            ("MouseSmoothingMs", clamp(mouseSmoothingMs, 0...500), defaults.mouseSmoothingMs, String.init),
            ("MouseDecayMs", clamp(mouseDecayMs, 1...1000), defaults.mouseDecayMs, String.init),
            ("StickModifierScale", clamp(stickModifierScale, 5...100), defaults.stickModifierScale, hundredths),
            ("KeyboardRampMs", clamp(keyboardRampMs, 0...2000), defaults.keyboardRampMs, String.init),
            ("TriggerRampMs", clamp(triggerRampMs, 0...2000), defaults.triggerRampMs, String.init),
        ]
        return settings.filter { $0.1 != $0.2 }.map { "\($0.0) = \($0.3($0.1))" }
    }
}

/// The keyboard and mouse layout a game starts with: the launcher's own layout, with the keys the user
/// moved. Every action is written to the input file, so none of the engine's scattered built-in keys
/// (C for Circle, I for Triangle) stay behind.
public enum Controls {
    /// Stands for "no key": the engine refuses an empty source, and no Mac keyboard has an F24.
    public static let unbound = "KEY:F24"

    /// Left hand on WASD for the left stick, right hand on JKLI for the face buttons, as console
    /// emulators lay them out; the mouse keeps its clicks.
    public static let layout: [PadAction: [String]] = [
        .cross: ["KEY:K", "KEY:Space", "KEY:Return"],
        .circle: ["KEY:L"],
        .square: ["KEY:J", "MOUSE:Left"],
        .triangle: ["KEY:I"],
        .l1: ["KEY:Q"],
        .r1: ["KEY:E"],
        .l2: ["KEY:U", "MOUSE:X1"],
        .r2: ["KEY:O", "MOUSE:Right"],
        .l3: ["KEY:Left Shift"],
        .r3: ["KEY:Left Ctrl"],
        .options: ["KEY:Escape"],
        .touchLeft: ["KEY:Backspace"],
        .touchRight: ["KEY:Tab"],
        .up: ["KEY:Up", "WHEEL:Up"],
        .down: ["KEY:Down", "WHEEL:Down"],
        .left: ["KEY:Left"],
        .right: ["KEY:Right"],
        .leftStickUp: ["KEY:W"],
        .leftStickDown: ["KEY:S"],
        .leftStickLeft: ["KEY:A"],
        .leftStickRight: ["KEY:D"],
        .rightStickUp: ["KEY:T"],
        .rightStickDown: ["KEY:G"],
        .rightStickLeft: ["KEY:F"],
        .rightStickRight: ["KEY:H"],
    ]

    /// The sources an action has, the user's changes over the layout.
    public static func sources(_ action: PadAction, _ changes: [String: [String]]) -> [String] {
        changes[action.rawValue] ?? layout[action] ?? []
    }

    /// The changes after giving `key` (a KEY: source) to `action`: it replaces the action's keys, keeps
    /// its mouse buttons, and leaves every other action that had it.
    public static func assign(_ key: String, to action: PadAction, _ changes: [String: [String]]) -> [String: [String]] {
        var result = changes
        for other in PadAction.allCases where other != action {
            let current = sources(other, changes)
            if current.contains(key) { result[other.rawValue] = current.filter { $0 != key } }
        }
        result[action.rawValue] = [key] + sources(action, changes).filter { !$0.hasPrefix("KEY:") }
        return result.filter { change in PadAction(rawValue: change.key).flatMap { layout[$0] } != change.value }
    }

    /// anyps5-input.ini text for the changes and the tuning.
    public static func file(_ changes: [String: [String]], tuning: InputTuning = InputTuning()) -> String {
        var lines = ["# Written by AnyPS5.app at each start; change the keys in the game's settings there."]
        for action in PadAction.allCases {
            let current = sources(action, changes)
            for source in current.isEmpty ? [unbound] : current { lines.append("\(action.rawValue) = \(source)") }
        }
        lines += tuning.lines
        return lines.joined(separator: "\n") + "\n"
    }

    /// The SDL scancode name of a Mac virtual key code (the key's position on a US layout, as SDL
    /// reads scancodes), nil for keys a binding cannot use.
    public static func keyName(forKeyCode code: UInt16) -> String? {
        keyNames[code]
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab",
        49: "Space", 50: "`", 51: "Backspace", 53: "Escape", 54: "Right GUI", 55: "Left GUI", 56: "Left Shift",
        57: "CapsLock", 58: "Left Alt", 59: "Left Ctrl", 60: "Right Shift", 61: "Right Alt", 62: "Right Ctrl",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 75: "Keypad /", 76: "Keypad Enter", 78: "Keypad -",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        118: "F4", 120: "F2", 122: "F1", 115: "Home", 116: "PageUp", 117: "Delete", 119: "End", 121: "PageDown",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
    ]
}
