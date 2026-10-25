import Foundation

/// What a key, a controller button, a click on a hint or the phone's pad asks a screen to do.
public enum Command: String, CaseIterable, Sendable {
    case left, right, up, down, select, back, options
    /// L1 and R1: the game before or after the selected one, from the home screen or a game's panel.
    case previousGame, nextGame
    /// The controller's PS button: the launcher in front of the game, or back to the game.
    case home
    /// Create on a DualSense (Share on a DualShock 4), or ⌥F12: the last seconds as a clip.
    case capture
}

/// The hint pills at the bottom of the screens ("↩ / ✕ Select"), read as the commands a click
/// on them gives: the same ones their keys give, through the same handler.
public enum HintKeys {
    /// One glyph of a pill's keys and the command it stands for; "/" between the keyboard's and
    /// the controller's glyphs stands for none.
    public struct Token: Equatable, Sendable {
        public var text: String
        public var command: Command?

        public init(_ text: String, _ command: Command?) {
            self.text = text
            self.command = command
        }
    }

    /// The glyphs the hints use, keyboard and controller alike.
    static let glyphs: [String: Command] = [
        "←": .left, "→": .right, "↑": .up, "↓": .down,
        "↩": .select, "✕": .select, "enter": .select,
        "esc": .back, "○": .back,
        "o": .options, "△": .options,
        "q": .previousGame, "l1": .previousGame,
        "e": .nextGame, "r1": .nextGame,
        "ps": .home,
    ]

    public static func command(for glyph: String) -> Command? {
        glyphs[glyph.lowercased()]
    }

    /// "Q E / L1 R1" → Q, E, /, L1, R1, each with its command.
    public static func tokens(_ keys: String) -> [Token] {
        keys.split(separator: " ").map(String.init).map { Token($0, $0 == "/" ? nil : command(for: $0)) }
    }

    /// The one command every glyph of the pill gives ("↩ / ✕", "esc / ○"), so that the whole
    /// pill is one button; nil when its glyphs give several (the arrows, Q and E), each then a
    /// button of its own, or none.
    public static func single(_ keys: String) -> Command? {
        let commands = Set(tokens(keys).filter { $0.text != "/" }.map(\.command))
        guard commands.count == 1, let only = commands.first else { return nil }
        return only
    }
}
