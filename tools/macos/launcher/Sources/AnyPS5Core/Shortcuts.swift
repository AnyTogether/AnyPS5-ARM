import Foundation

// Settings → Shortcuts: the launcher's own actions on keys and on controller buttons or chords,
// what clashes, and how a pad's presses and holds become those actions. A game's own buttons are
// set in its Controls page, not here. The Windows/Linux launcher (AnyPS5 Desktop) has the same
// actions and defaults.

public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    /// PS: the launcher in front of the game or back; held, the home menu or "Close game?".
    case home
    /// The in-game quick menu at once (Resume, Game Settings, Close Game).
    case quickMenu
    case screenshot
    /// The last seconds of the game as a clip.
    case clip
    case fullScreen
    /// L1 and R1: the game before or after, the settings category before or after.
    case previousSection, nextSection

    /// Acts while a game is in front, so its key is one the system hands over from any app.
    public var worksInGame: Bool {
        switch self {
        case .home, .quickMenu, .screenshot, .clip: return true
        case .fullScreen, .previousSection, .nextSection: return false
        }
    }

    /// Holding it means something else (the home menu, "Close game?"), so a press acts when it
    /// is let go.
    public var hasHold: Bool { self == .home }
}

/// A key with its modifiers. Two chords are the same key when the key code and the modifiers are.
public struct KeyChord: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// The key's name (Controls.keyName): "F11", "Escape", "Q".
    public var name: String

    public init(keyCode: UInt16, modifiers: Modifiers = [], name: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.name = name
    }

    public static func == (left: KeyChord, right: KeyChord) -> Bool {
        left.keyCode == right.keyCode && left.modifiers == right.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    /// ⌃ ⌥ ⇧ ⌘ as macOS writes them, then the key: "⌥Esc", "⇧⌥F12".
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch name {
        case "Escape": return text + "Esc"
        case "Backspace": return text + "⌫"
        case "Return": return text + "↩"
        case "Left": return text + "←"
        case "Right": return text + "→"
        case "Up": return text + "↑"
        case "Down": return text + "↓"
        default: return text + name
        }
    }

    public var isFunctionKey: Bool {
        guard name.hasPrefix("F"), let number = Int(name.dropFirst()) else { return false }
        return (1 ... 20).contains(number)
    }

    /// A modifier other than Shift, which a key typed anywhere else seldom has.
    public var hasModifier: Bool { !modifiers.subtracting(.shift).isEmpty }

    public static let escape: UInt16 = 53
    public static let backspace: UInt16 = 51
    /// The keys the screens move with (arrows, Return, Enter, Space, Esc, Backspace, O).
    static let navigation: Set<UInt16> = [123, 124, 125, 126, 36, 76, 49, 53, 51, 31]

    public var isNavigation: Bool { modifiers.isEmpty && Self.navigation.contains(keyCode) }

    /// Keys AnyPS5 already takes from any app (⌥V talks in a party, ⌥A and ⌥D answer and decline a
    /// call) and ⌘ with or without ⇧, the menus' keys.
    public var isReserved: Bool {
        if modifiers == .option && [9, 0, 2].contains(keyCode) { return true }
        return modifiers == .command || modifiers == [.command, .shift]
    }
}

/// Controller buttons pressed together, and whether the chord is held (0.5 s) rather than pressed.
public struct PadChord: Codable, Hashable, Sendable {
    public private(set) var buttons: [PadButton]
    public var hold: Bool

    public init(_ buttons: Set<PadButton>, hold: Bool = false) {
        self.buttons = buttons.sorted { $0.order < $1.order }
        self.hold = hold
    }

    public var set: Set<PadButton> { Set(buttons) }

    /// The buttons the screens move with on their own (✕ ○ △, Options, the D-pad): part of a
    /// chord they are fine.
    static let navigation: Set<PadButton> = [.south, .east, .north, .start, .dpadUp, .dpadDown, .dpadLeft, .dpadRight]

    public var isNavigation: Bool { buttons.count == 1 && Self.navigation.contains(buttons[0]) }
}

extension PadButton {
    /// The order buttons are named in a chord: shoulders first, then the face, then the rest.
    var order: Int {
        let order: [PadButton] = [.l1, .r1, .l2, .r2, .guide, .select, .start, .touchpad, .south, .east, .west, .north, .l3, .r3,
                                  .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .misc]
        return order.firstIndex(of: self) ?? order.count
    }

    /// The PlayStation name of the button.
    public var glyph: String {
        switch self {
        case .south: return "✕"
        case .east: return "○"
        case .west: return "□"
        case .north: return "△"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .l3: return "L3"
        case .r3: return "R3"
        case .select: return "Create"
        case .start: return "Options"
        case .guide: return "PS"
        case .touchpad: return "Touchpad"
        case .dpadUp: return "↑"
        case .dpadDown: return "↓"
        case .dpadLeft: return "←"
        case .dpadRight: return "→"
        case .misc: return "Share"
        }
    }
}

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var key: KeyChord?
    public var pad: PadChord?

    public init(key: KeyChord? = nil, pad: PadChord? = nil) {
        self.key = key
        self.pad = pad
    }
}

/// Two actions on one key or one chord, or a binding the launcher cannot honour.
public enum ShortcutConflict: Equatable, Sendable {
    case sameKey(ShortcutAction, ShortcutAction)
    case samePad(ShortcutAction, ShortcutAction)
    /// A key the screens move with, without a modifier.
    case navigationKey(ShortcutAction)
    /// A button the screens move with, on its own.
    case navigationButton(ShortcutAction)
    /// A key AnyPS5 or the menus already use (KeyChord.isReserved).
    case reservedKey(ShortcutAction)
    /// An action that works in a game needs ⌃, ⌥ or ⌘, or a function key: otherwise every app
    /// would lose that key while the launcher runs.
    case needsModifier(ShortcutAction)

    public var actions: [ShortcutAction] {
        switch self {
        case .sameKey(let a, let b), .samePad(let a, let b): return [a, b]
        case .navigationKey(let a), .navigationButton(let a), .reservedKey(let a), .needsModifier(let a): return [a]
        }
    }
}

/// The user's shortcuts over the defaults; only what differs is kept.
public struct ShortcutMap: Codable, Equatable, Sendable {
    public private(set) var changed: [ShortcutAction: ShortcutBinding] = [:]

    public init() {}

    public static let defaults: [ShortcutAction: ShortcutBinding] = [
        .home: ShortcutBinding(key: KeyChord(keyCode: 53, modifiers: .option, name: "Escape"), pad: PadChord([.guide])),
        .quickMenu: ShortcutBinding(key: KeyChord(keyCode: 53, modifiers: [.option, .shift], name: "Escape")),
        .screenshot: ShortcutBinding(key: KeyChord(keyCode: 111, modifiers: [.option, .shift], name: "F12"), pad: PadChord([.select], hold: true)),
        .clip: ShortcutBinding(key: KeyChord(keyCode: 111, modifiers: .option, name: "F12"), pad: PadChord([.select])),
        .fullScreen: ShortcutBinding(key: KeyChord(keyCode: 103, name: "F11")),
        .previousSection: ShortcutBinding(key: KeyChord(keyCode: 12, name: "Q"), pad: PadChord([.l1])),
        .nextSection: ShortcutBinding(key: KeyChord(keyCode: 14, name: "E"), pad: PadChord([.r1])),
    ]

    public func binding(_ action: ShortcutAction) -> ShortcutBinding {
        changed[action] ?? Self.defaults[action] ?? ShortcutBinding()
    }

    public mutating func setKey(_ key: KeyChord?, for action: ShortcutAction) {
        var binding = self.binding(action)
        binding.key = key
        store(binding, for: action)
    }

    public mutating func setPad(_ pad: PadChord?, for action: ShortcutAction) {
        var binding = self.binding(action)
        binding.pad = pad
        store(binding, for: action)
    }

    public mutating func reset() { changed = [:] }

    public var isDefault: Bool { changed.isEmpty }

    private mutating func store(_ binding: ShortcutBinding, for action: ShortcutAction) {
        changed[action] = binding == Self.defaults[action] ? nil : binding
    }

    /// Every clash, in the order of the actions.
    public func conflicts() -> [ShortcutConflict] {
        var found: [ShortcutConflict] = []
        let actions = ShortcutAction.allCases
        for (index, action) in actions.enumerated() {
            let mine = binding(action)
            if let key = mine.key {
                if key.isNavigation { found.append(.navigationKey(action)) }
                if key.isReserved { found.append(.reservedKey(action)) }
                if action.worksInGame && !key.hasModifier && !key.isFunctionKey { found.append(.needsModifier(action)) }
                for other in actions[(index + 1)...] where binding(other).key == key { found.append(.sameKey(action, other)) }
            }
            if let pad = mine.pad {
                if pad.isNavigation { found.append(.navigationButton(action)) }
                for other in actions[(index + 1)...] where binding(other).pad == pad { found.append(.samePad(action, other)) }
            }
        }
        return found
    }

    public func conflicts(of action: ShortcutAction) -> [ShortcutConflict] {
        conflicts().filter { $0.actions.contains(action) }
    }

    /// The action a key pressed in the launcher gives; one in conflict gives none.
    public func action(forKey key: KeyChord) -> ShortcutAction? {
        let clashing = Set(conflicts().flatMap(\.actions))
        return ShortcutAction.allCases.first { binding($0).key == key && !clashing.contains($0) }
    }

    /// The chords the pad reader listens for; chords in conflict act for neither action.
    public var padChords: [(ShortcutAction, PadChord)] {
        let clashing = Set(conflicts().flatMap { conflict -> [ShortcutAction] in
            switch conflict {
            case .samePad, .navigationButton: return conflict.actions
            default: return []
            }
        })
        return ShortcutAction.allCases.compactMap { action in
            guard let pad = binding(action).pad, !clashing.contains(action) else { return nil }
            return (action, pad)
        }
    }

    /// The keys that work from any app.
    public var inGameKeys: [(ShortcutAction, KeyChord)] {
        let clashing = Set(conflicts().flatMap(\.actions))
        return ShortcutAction.allCases.compactMap { action in
            guard action.worksInGame, let key = binding(action).key, !clashing.contains(action) else { return nil }
            return (action, key)
        }
    }
}

extension ShortcutMap {
    private struct Entry: Codable {
        var action: ShortcutAction
        var binding: ShortcutBinding
    }

    public init(from decoder: Decoder) throws {
        let entries = try decoder.singleValueContainer().decode([Entry].self)
        for entry in entries { changed[entry.action] = entry.binding }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ShortcutAction.allCases.compactMap { action in changed[action].map { Entry(action: action, binding: $0) } })
    }
}

/// A press held long enough to mean something else: `release` before `threshold` is a press,
/// reaching it while held is a hold (told once, by `tick`).
public struct LongPress: Sendable {
    public enum Outcome: Equatable, Sendable { case press, hold }

    public static let threshold: Double = 0.5

    public let threshold: Double
    private var downAt: Double?
    private var held = false

    public init(threshold: Double = LongPress.threshold) {
        self.threshold = threshold
    }

    public var isDown: Bool { downAt != nil }

    public mutating func press(at time: Double) {
        guard downAt == nil else { return }
        downAt = time
        held = false
    }

    public mutating func release(at time: Double) -> Outcome? {
        guard let downAt else { return nil }
        self.downAt = nil
        if held { return nil }
        return time - downAt >= threshold ? .hold : .press
    }

    public mutating func tick(at time: Double) -> Outcome? {
        guard let downAt, !held, time - downAt >= threshold else { return nil }
        held = true
        return .hold
    }

    /// When `tick` next has something to say, nil when nothing waits.
    public var due: Double? { held ? nil : downAt.map { $0 + threshold } }
}

/// One controller's buttons as shortcut presses and holds. A chord acts when its last button goes
/// down (the longest chord that just completed wins: L1+R1 over R1); a chord that also means
/// something held (PS, or Create with Screenshot on Create held) waits: let go before 0.5 s it
/// is a press, held that long it is the hold.
public struct PadShortcutReader: Sendable {
    public enum Event: Equatable, Sendable {
        case press(ShortcutAction)
        /// PS held (the home menu, "Close game?"), or an action bound to a held chord.
        case hold(ShortcutAction)
    }

    private struct Group: Sendable {
        var buttons: Set<PadButton>
        var press: ShortcutAction?
        var hold: ShortcutAction?
        /// Its hold is PS's own.
        var builtInHold = false

        var waits: Bool { hold != nil || builtInHold }
    }

    private struct Armed: Sendable {
        var group: Int
        var timer: LongPress
    }

    private var groups: [Group] = []
    private var pressed: Set<PadButton> = []
    private var armed: [Armed] = []

    public init(map: ShortcutMap) {
        for (action, chord) in map.padChords {
            let index = groups.firstIndex { $0.buttons == chord.set } ?? {
                groups.append(Group(buttons: chord.set))
                return groups.count - 1
            }()
            if chord.hold {
                groups[index].hold = action
            } else {
                groups[index].press = action
                if action.hasHold { groups[index].builtInHold = true }
            }
        }
    }

    /// Something waits for `tick`.
    public var waiting: Bool { armed.contains { $0.timer.due != nil } }
    public var due: Double? { armed.compactMap(\.timer.due).min() }

    /// The buttons held now, at `time` seconds.
    public mutating func update(_ now: Set<PadButton>, at time: Double) -> [Event] {
        var events: [Event] = []
        let released = pressed.subtracting(now)
        let added = now.subtracting(pressed)
        pressed = now
        if !released.isEmpty {
            armed.removeAll { armed in
                let group = groups[armed.group]
                guard !group.buttons.isSubset(of: now) else { return false }
                var timer = armed.timer
                switch timer.release(at: time) {
                case .press: if let action = group.press { events.append(.press(action)) }
                case .hold: if let action = group.hold ?? (group.builtInHold ? group.press : nil) { events.append(.hold(action)) }
                case nil: break
                }
                return true
            }
        }
        guard !added.isEmpty else { return events }
        let completed = groups.indices.filter { groups[$0].buttons.isSubset(of: now) && !groups[$0].buttons.isDisjoint(with: added) }
        let longest = completed.filter { index in !completed.contains { groups[$0].buttons.isStrictSuperset(of: groups[index].buttons) } }
        for index in longest {
            // A longer chord takes over from the shorter one waiting inside it.
            armed.removeAll { groups[$0.group].buttons.isStrictSubset(of: groups[index].buttons) }
            let group = groups[index]
            if group.waits {
                var timer = LongPress()
                timer.press(at: time)
                armed.append(Armed(group: index, timer: timer))
            } else if let action = group.press {
                events.append(.press(action))
            }
        }
        return events
    }

    /// Holds that reached their time by `time`.
    public mutating func tick(at time: Double) -> [Event] {
        var events: [Event] = []
        for index in armed.indices {
            guard armed[index].timer.tick(at: time) == .hold else { continue }
            let group = groups[armed[index].group]
            if let hold = group.hold {
                events.append(.hold(hold))
            } else if group.builtInHold, let press = group.press {
                events.append(.hold(press))
            }
        }
        return events
    }

    /// Lets go of everything (the controller went, a capture took the buttons).
    public mutating func reset() {
        pressed = []
        armed = []
    }
}

/// A chord being set in Settings → Shortcuts: every button pressed until all are let go, held
/// (all of them together for `LongPress.threshold`) or pressed.
public struct ChordRecorder: Sendable {
    public private(set) var buttons: Set<PadButton> = []
    private var completedAt: Double?
    private var letGoAt: Double?

    public init() {}

    /// The buttons held now; the chord once the last one is let go.
    public mutating func update(_ pressed: Set<PadButton>, at time: Double) -> PadChord? {
        if !pressed.subtracting(buttons).isEmpty {
            buttons.formUnion(pressed)
            completedAt = time
            letGoAt = nil
        } else if pressed.count < buttons.count, letGoAt == nil {
            letGoAt = time
        }
        guard pressed.isEmpty, !buttons.isEmpty, let completedAt else { return nil }
        let held = (letGoAt ?? time) - completedAt >= LongPress.threshold
        let chord = PadChord(buttons, hold: held)
        self = ChordRecorder()
        return chord
    }
}
