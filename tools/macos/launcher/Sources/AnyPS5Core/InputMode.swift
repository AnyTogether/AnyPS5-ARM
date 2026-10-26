import Foundation

// The input the user holds now, keyboard and mouse or a controller, and what the screens show
// for it: a controller's glyphs while the pad is in use, the keys' while the keyboard or the
// mouse is, switching the moment the other one is touched. The Windows/Linux launcher (AnyPS5
// Desktop) keeps the same rules.

public enum InputMode: String, Codable, Sendable {
    case keyboard, pad
}

/// Which input was used last. A controller's press or stick, a key or a click switch at once; the
/// pointer has to travel `pointerTravel` points first, so a mouse nudged by the desk does not
/// take the screen from the pad.
public struct InputModeTracker: Sendable {
    public static let pointerTravel: Double = 24

    public private(set) var mode: InputMode
    private var travelled: Double = 0

    public init(mode: InputMode = .keyboard) {
        self.mode = mode
    }

    /// A controller button, D-pad or stick; true when the mode changed.
    @discardableResult
    public mutating func usedPad() -> Bool { set(.pad) }

    /// A key or a mouse click.
    @discardableResult
    public mutating func usedKeyboard() -> Bool { set(.keyboard) }

    /// The pointer moved `distance` points.
    @discardableResult
    public mutating func pointerMoved(_ distance: Double) -> Bool {
        guard mode == .pad else { return false }
        travelled += abs(distance)
        return travelled >= Self.pointerTravel ? set(.keyboard) : false
    }

    private mutating func set(_ next: InputMode) -> Bool {
        travelled = 0
        guard next != mode else { return false }
        mode = next
        return true
    }
}

extension HintKeys {
    /// What a hint glyph belongs to: a key, a controller button, or both (the arrows are the
    /// keyboard's and the D-pad's).
    public enum Side: Equatable, Sendable { case keyboard, pad, both }

    static let padGlyphs: Set<String> = ["✕", "○", "△", "□", "l1", "r1", "l2", "r2", "ps", "create", "options"]
    static let sharedGlyphs: Set<String> = ["←", "→", "↑", "↓"]

    public static func side(of glyph: String) -> Side {
        let lower = glyph.lowercased()
        if sharedGlyphs.contains(lower) { return .both }
        return padGlyphs.contains(lower) ? .pad : .keyboard
    }

    /// A hint's keys for the input in use: "↩ / ✕" is "↩" at the keyboard and "✕" on the pad,
    /// "PS / esc / ○" is "esc" or "PS / ○". A hint with nothing left for that input stays whole.
    public static func keys(_ keys: String, for mode: InputMode) -> String {
        let wanted: Side = mode == .pad ? .pad : .keyboard
        var groups: [[String]] = [[]]
        for word in keys.split(separator: " ").map(String.init) {
            if word == "/" {
                groups.append([])
            } else {
                let side = side(of: word)
                if side == .both || side == wanted { groups[groups.count - 1].append(word) }
            }
        }
        // Arrows left alone before a "/" belong with what follows: "← → ↩ / ✕" is "← → ✕" on the pad.
        var kept: [[String]] = []
        for group in groups where !group.isEmpty {
            if let last = kept.last, last.allSatisfy({ side(of: $0) == .both }) {
                kept[kept.count - 1] = last + group
            } else {
                kept.append(group)
            }
        }
        return kept.isEmpty ? keys : kept.map { $0.joined(separator: " ") }.joined(separator: " / ")
    }
}

/// A settings row that changes with left and right (a choice or a stepper): with a controller,
/// moving onto it changes nothing. ✕ starts editing it, left and right then change it, and ✕ or
/// ○ end editing (up or down end it too, moving on). At the keyboard and with the mouse it
/// changes at once, as always.
public enum RowValueKind: Sendable {
    case choice, toggle, other
}

/// What a command does to the focused row of a panel.
public enum RowIntent: Equatable, Sendable {
    case move(Int)
    case change(Int)
    case activate
    case startEditing
    case stopEditing
    /// Leaves the rows for the categories (or closes a panel without them).
    case leaveRows
    case close
    case none
}

public struct RowEditor: Equatable, Sendable {
    /// The row being edited, by its id.
    public private(set) var editing: String?

    public init() {}

    public func isEditing(_ row: String) -> Bool { editing == row }

    /// What `command` does on `row`; the editing state follows.
    public mutating func intent(for command: Command, row: String, kind: RowValueKind, mode: InputMode) -> RowIntent {
        if editing != nil && editing != row { editing = nil }
        if editing == row {
            switch command {
            case .left: return .change(-1)
            case .right: return .change(1)
            case .select, .back:
                editing = nil
                return .stopEditing
            case .up, .down:
                editing = nil
                return .move(command == .up ? -1 : 1)
            case .options:
                editing = nil
                return .close
            default:
                return .none
            }
        }
        switch command {
        case .up: return .move(-1)
        case .down: return .move(1)
        case .back: return .leaveRows
        case .options: return .close
        case .select:
            if mode == .pad && kind == .choice {
                editing = row
                return .startEditing
            }
            return .activate
        case .left:
            return mode == .keyboard && kind != .other ? .change(-1) : .leaveRows
        case .right:
            return mode == .keyboard && kind != .other ? .change(1) : .none
        default:
            return .none
        }
    }

    /// The focus left the row, the panel closed or the mouse took over.
    public mutating func stop() { editing = nil }
}
