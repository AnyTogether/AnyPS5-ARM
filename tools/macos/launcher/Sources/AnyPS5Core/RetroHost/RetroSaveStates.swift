import CoreGraphics
import Foundation

/// A game's save states in the emulator host, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_save_states.dart): its slots as its states folder holds them, and saving
/// into one and loading one back. A save keeps a picture of its moment beside the state: the frame
/// shown, which is the paused game's while its menu is open. One save or load runs at a time;
/// another asked meanwhile is `.notNow`.
@MainActor
public final class RetroSaveStates {
    /// Makes the picture kept beside a saved state from the game's image at its display aspect.
    public typealias PictureMaker = @Sendable (CGImage, Double) async -> Data?

    public let game: RetroHostGame
    public let folder: RetroStateFolder
    /// Called after the slots or what runs changed.
    public var onChange: (() -> Void)?
    /// Where a picture that could not be kept is told.
    public var log: ((String) -> Void)?
    private let picture: PictureMaker

    /// Every slot, as the folder held it when it was last read (`refresh()`); all empty before.
    public private(set) var slots: [RetroStateSlot] = (0..<RetroStateFolder.slots).map { RetroStateSlot($0) }
    /// The slot a save or a load is under way in, and whether it is a save; nil when none is.
    public private(set) var running: (slot: Int, saving: Bool)?
    private var disposed = false
    private var falseLoadAfter: Int?

    public init(game: RetroHostGame, folder: RetroStateFolder, picture: PictureMaker? = nil) {
        self.game = game
        self.folder = folder
        self.picture = picture ?? { image, aspect in
            await Task.detached(priority: .utility) { RetroStatePicture.png(image, aspect: aspect) }.value
        }
    }

    /// Whether the game's host saves and loads its states (`RetroHostGame.savesStates`).
    public var available: Bool { game.savesStates }
    /// Whether any slot holds a state.
    public var anySaved: Bool { slots.contains { !$0.empty } }
    /// Whether a save or a load is under way.
    public var busy: Bool { running != nil }

    public func slot(_ slot: Int) -> RetroStateSlot { slots[slot] }

    /// Whether the last save or load was a load the host answered `false`, and no status since said
    /// the game plays on. A load the core began but did not finish in time is answered so, and it
    /// ends the game with `errorCode` `other`; a PS1 game's memory card may then already be the
    /// state's, as the core finishes the load after the reply and the host writes the card when the
    /// game ends (protocol.md "The memory card"). The host ends the game before it replies, so a
    /// status asked after the reply that has not ended (`RetroHostGame.playingAfter(_:)`) shows the
    /// load was not given to the core in time and left the game untouched: a later ending is not the
    /// load's.
    public var loadAnsweredFalse: Bool {
        guard let replies = falseLoadAfter else { return false }
        return !game.playingAfter(replies)
    }

    /// Reads the slots from the folder again.
    public func refresh() async {
        let folder = self.folder
        let read = await Task.detached(priority: .userInitiated) { folder.read() }.value
        guard !disposed else { return }
        slots = read
        notify()
    }

    /// Saves the game's state into `slot`, replacing the one it held, with a picture of the frame
    /// shown; the slots are read again after. Only a save the core refused (it gave no state, so the
    /// host wrote nothing) is sure to have left the slot as it was, and keeps its picture. Any other
    /// save that did not work takes the picture away: after a `fileError` the host's late write may
    /// still put the new state in place (protocol.md "saveState and loadState"), and a host that went
    /// away after writing it answers `false` as one that never ran does, so no picture is better than
    /// one of a moment the slot may no longer hold.
    public func save(_ slot: Int) async -> RetroStateOutcome {
        await run(slot, saving: true) {
            let shown = self.game.picture.image
            self.falseLoadAfter = nil
            let outcome = await self.game.saveState(slot)
            switch outcome {
            case .done: await self.keepPicture(slot, shown)
            case .coreRefused: break
            default: await self.keepPicture(slot, nil)
            }
            await self.refresh()
            return outcome
        }
    }

    /// Loads the state in `slot` back into the game. A slot found empty is read again, so it shows
    /// as such.
    public func load(_ slot: Int) async -> RetroStateOutcome {
        await run(slot, saving: false) {
            let outcome = await self.game.loadState(slot)
            self.falseLoadAfter = outcome == .notNow ? self.game.stateReplies : nil
            if outcome == .noState { await self.refresh() }
            return outcome
        }
    }

    private func run(_ slot: Int, saving: Bool, _ work: () async -> RetroStateOutcome) async -> RetroStateOutcome {
        guard !busy, available else { return .notNow }
        running = (slot, saving)
        notify()
        defer {
            running = nil
            notify()
        }
        return await work()
    }

    /// The picture of the state just saved in `slot`, or none: a picture of the state before would
    /// show a moment the slot no longer holds.
    private func keepPicture(_ slot: Int, _ shown: CGImage?) async {
        var png: Data?
        if let shown {
            png = await picture(shown, game.aspect)
            if png == nil { log?("emulator host: no picture for state slot \(slot)") }
        }
        // A game closed while its picture was made writes nothing: the next game may already be
        // saving into the same slot. The state it saved shows without a picture, or with an older
        // one, which RetroStateFolder.read leaves out.
        guard !disposed else { return }
        do {
            try folder.keepPicture(slot, png)
        } catch {
            log?("emulator host: the picture of state slot \(slot) was not kept: \(error)")
        }
    }

    private func notify() {
        if !disposed { onChange?() }
    }

    /// Tells no one anything more, and writes no picture from here on.
    public func dispose() { disposed = true }
}
