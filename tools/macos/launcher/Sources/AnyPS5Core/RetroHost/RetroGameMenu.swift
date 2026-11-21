import Foundation

/// A disc of a multi-disc game (`status.discs`), to insert with `changeDisc`.
public struct RetroDiscRow: Equatable, Sendable {
    /// The index into `discs.labels`, which is the `changeDisc` argument.
    public let index: Int
    public let label: String
    /// This disc is in the console now.
    public let inserted: Bool
    /// It can be chosen: it is not in the console and no change is in progress.
    public let enabled: Bool

    public init(index: Int, label: String, inserted: Bool, enabled: Bool) {
        self.index = index
        self.label = label
        self.inserted = inserted
        self.enabled = enabled
    }
}

/// A core option the status lists (`status.options`), to change with `option`.
public struct RetroOptionRow: Equatable, Sendable {
    public let option: RetroOption

    public init(_ option: RetroOption) { self.option = option }

    public var key: String { option.key }
    /// The option's title, without SwanStation's own " (Restart)".
    public var title: String { RetroOptionSection.title(option.title) }
    /// Where it is shown; rows are made only for options that are shown.
    public var section: RetroOptionSection { RetroOptionSection.of(key) ?? .advanced }
    /// The label of the value chosen.
    public var choice: String { option.labels[option.selected] }
    /// The chosen value is not the one the core runs with yet: it waits for a graphics change or,
    /// with `restartNeeded`, for the game to be started again.
    public var pending: Bool { option.values[option.selected] != option.activeValue }
    /// A change only takes effect when the game is started again.
    public var restartNeeded: Bool { option.restart }
}

/// One row of the in-game menu.
public enum RetroMenuRow: Equatable, Sendable {
    case disc(RetroDiscRow)
    case option(RetroOptionRow)
    /// The host's output volume (`volume`).
    case volume(level: Double, muted: Bool)
}

/// The in-game menu of a `RetroHostGame`, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_game_menu.dart): its rows and what choosing them does. Opening it pauses
/// the game and keeps the controllers' presses from it (`RetroHostControls.suspended`); closing it
/// gives both back. It shows nothing itself: a menu view lists `rows` and calls the actions.
@MainActor
public final class RetroGameMenu {
    public let game: RetroHostGame
    public let controls: RetroHostControls?
    /// How far one step of the volume row moves it.
    public let volumeStep: Double

    public private(set) var isOpen = false

    public init(game: RetroHostGame, controls: RetroHostControls?, volumeStep: Double = 0.1) {
        self.game = game
        self.controls = controls
        self.volumeStep = volumeStep
    }

    /// Whether the last disc change failed (`discs.failed`).
    public var discChangeFailed: Bool { game.status?.discs?.failed ?? false }

    /// The rows for the game's last status: the discs of a multi-disc game, then the core options
    /// that are shown in the order the host lists them, then the volume.
    public var rows: [RetroMenuRow] { Self.rowsFor(game.status, volume: game.volume, muted: game.muted) }

    /// The disc rows of a multi-disc game.
    public var discs: [RetroDiscRow] {
        rows.compactMap { row -> RetroDiscRow? in if case .disc(let disc) = row { return disc } else { return nil } }
    }

    /// The core options of `section`, in the order the host lists them.
    public func optionsIn(_ section: RetroOptionSection) -> [RetroOptionRow] {
        rows.compactMap { row -> RetroOptionRow? in
            if case .option(let option) = row, option.section == section { return option }
            return nil
        }
    }

    /// The rows for `status` (nil before the first one) and the volume.
    public static func rowsFor(_ status: RetroStatus?, volume: Double, muted: Bool) -> [RetroMenuRow] {
        var rows: [RetroMenuRow] = []
        if let discs = status?.discs, discs.labels.count > 1 {
            for (index, label) in discs.labels.enumerated() {
                rows.append(.disc(RetroDiscRow(index: index, label: label, inserted: discs.inserted == index,
                                               enabled: !discs.busy && discs.inserted != index)))
            }
        }
        for option in status?.orderedOptions ?? [] where RetroOptionSection.shown(option.key) {
            rows.append(.option(RetroOptionRow(option)))
        }
        rows.append(.volume(level: volume, muted: muted))
        return rows
    }

    /// Opens the menu: the game is paused and the controllers' presses stay out of it.
    public func open() async {
        guard !isOpen, game.loaded else { return }
        isOpen = true
        controls?.suspended = true
        await game.pause(true)
    }

    /// Closes the menu and gives the game back its controllers; a button still held from the menu
    /// reaches the game only once it is let go and pressed again.
    public func close() async {
        guard isOpen else { return }
        isOpen = false
        controls?.suspended = false
        await game.pause(false)
    }

    /// Inserts a disc; false when the row cannot be chosen now or the host refused.
    @discardableResult
    public func chooseDisc(_ row: RetroDiscRow) async -> Bool {
        guard let current = discs.first(where: { $0.index == row.index }), current.enabled else { return false }
        return await game.changeDisc(row.index)
    }

    /// Moves an option `steps` values on (back when negative), stopping at the first and last;
    /// false when it is already there, the option is gone, or the host refused.
    @discardableResult
    public func stepOption(_ key: String, _ steps: Int) async -> Bool {
        guard let option = game.status?.options[key] else { return false }
        let next = min(option.values.count - 1, max(0, option.selected + steps))
        guard next != option.selected else { return false }
        return await game.setOption(key: key, value: option.values[next])
    }

    /// The game's internal resolution as the menu offers it, or nil when it offers none
    /// (`RetroResolutionChoice.of`).
    public var resolution: RetroResolutionChoice? { RetroResolutionChoice.of(game.status, limitsPs2: game.limitsPs2Resolution) }

    /// Chooses the internal resolution `value`; false when the menu does not offer it now, it is
    /// already chosen, or the host refused.
    @discardableResult
    public func chooseResolution(_ value: String) async -> Bool {
        guard let choice = resolution, choice.values.contains(where: { $0.value == value }),
              choice.values[choice.selected].value != value else { return false }
        return await game.setOption(key: choice.key, value: value)
    }

    /// Moves the volume `steps` of `volumeStep` up (down when negative), from 0 to 1. Turning it up
    /// unmutes. The level is counted in whole steps and divided last, so three tenths is 0.3.
    public func stepVolume(_ steps: Int) async {
        let perUnit = Int((1 / volumeStep).rounded())
        let next = min(perUnit, max(0, Int((game.volume * Double(perUnit)).rounded()) + steps))
        await game.setVolume(level: Double(next) / Double(perUnit), muted: steps > 0 ? false : nil)
    }

    public func toggleMute() async { await game.setVolume(muted: !game.muted) }

    /// A menu that goes away while open gives the game back its controllers and resumes it.
    public func dispose() {
        guard isOpen else { return }
        isOpen = false
        controls?.suspended = false
        let game = self.game
        Task { await game.pause(false) }
    }
}
