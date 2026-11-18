import AnyPS5Core
import AppKit
import Foundation
import GameController
import SwiftUI

/// A PS1 game playing in the launcher's window through the emulator host, as on Windows and Linux
/// (AnyPS5 Desktop's lib/ui/retro_host_play.dart): the game, its controllers and its in-game menu.
@MainActor
final class RetroPlay {
    let game: Game
    let host: RetroHostGame
    let controls: RetroHostControls
    let menu: RetroGameMenu
    let started: Date
    /// The host executable the game runs in, so its host is kept only for games of the same one.
    let program: String
    /// The core library the game was started with: SwanStation, or LRPS2 for a PS2 game.
    let core: String
    /// Whether the game is a PS2 one, started with `start.console` `ps2`.
    var ps2: Bool { game.retro?.platform == .ps2 }
    /// The host was started without the checks a signed release's gets (a debug build's
    /// `ANYPS5_RETRO_HOST`): the game is marked as such while it runs (RetroUncheckedMark).
    let unchecked: Bool
    /// The player chose Close game: the end that follows is not an error to show.
    var closing = false
    /// When the game stopped being played: it ended on its own, or Close game began. Play time is
    /// counted to here, not to when an error screen was left.
    var endedAt: Date?
    var over: Bool { endedAt != nil }
    /// Its play time went to the family rules (`countRetroPlay`); once only.
    var counted = false
    /// The player was told this game's memory card cannot be read; once per game.
    var cardWarned = false
    /// The host's last `resolutionError` the log was given, so each one is logged once.
    var resolutionErrorLogged = ""
    /// The player was told the memory card may be back at a state's moment after a load that ended
    /// the game (`warnRetroCardAfterLoad`); once per game.
    var loadCardWarned = false
    /// The section of the menu shown, or nil for the menu's first page.
    var menuSection: RetroOptionSection?
    /// The game's save states, in its menu's Save state and Load state where its host saves states
    /// (`RetroSaveStates.available`).
    let states: RetroSaveStates
    /// The menu's Save state or Load state page shown, or nil.
    var statePage: RetroStatePage?
    /// The slot Overwrite slot N? asks about (`Overlay.retroOverwriteState`).
    var overwriting: Int?
    /// A save or load was chosen and has not answered yet: set the moment it is chosen, before its
    /// task runs, so a second press meanwhile is let go, as on Windows and Linux, where the save
    /// marks itself under way before anything waits.
    var stateAsked = false
    /// How many times the menu was opened: a save or load goes back to the game only from the visit
    /// it was asked in, not from the menu opened again while it waited.
    var menuVisits = 0
    /// The ids of the menu's first page as last built: the rows it gains or loses as the status
    /// changes leave the focus on the row it was on (`keepRetroMenuRow`).
    var firstPageRows: [String] = []
    /// The phase and the problem the launcher last acted on (`retroChanged`).
    var seenPhase: RetroHostGamePhase?
    var seenProblem: TRetro.Key??
    var listener: Int?
    private var released = false

    init(game: Game, host: RetroHostGame, controls: RetroHostControls, menu: RetroGameMenu, started: Date, program: String, core: String,
         unchecked: Bool, states: RetroSaveStates) {
        self.states = states
        self.game = game
        self.host = host
        self.controls = controls
        self.menu = menu
        self.started = started
        self.program = program
        self.core = core
        self.unchecked = unchecked
    }

    /// Lets go of the controllers, the menu and the host, once, whoever asks first.
    func release() {
        guard !released else { return }
        released = true
        if let listener { host.removeListener(listener) }
        states.onChange = nil
        controls.dispose()
        menu.dispose()
        states.dispose()
        host.dispose()
    }

    /// The game is starting or loading: the loading screen shows.
    var loading: Bool { host.phase == .starting || host.phase == .loading }

    /// Why the game stopped, as the key of the words to show the player; nil while it plays, and
    /// for a game that ended without an error or that the player closed.
    var problem: TRetro.Key? { closing ? nil : AppModel.retroHostProblem(host, ps2: ps2) }
}

/// The pages of the game's menu that list its save state slots.
enum RetroStatePage {
    case save, load
}

extension AppModel {
    // MARK: What plays where

    /// The host this build runs: in a debug build the one `ANYPS5_RETRO_HOST` names, unchecked;
    /// otherwise the signed host downloaded in Settings › Emulators, checked before each start.
    var retroHostInstall: RetroHostInstall? { retroHostUnchecked ?? retroHostDownload.installed }

    /// Whether `platform`'s discs play in the emulator host: PS1 with its setting on and a host
    /// found, PS2 with its own setting on and a host that has LRPS2 beside it. Otherwise they go to
    /// the emulator chosen in Settings › Emulators, as before.
    func playsInHost(_ platform: RetroPlatform) -> Bool {
        switch platform {
        case .ps1: return preferences.retroHostPs1 == true && retroHostInstall != nil
        case .ps2: return preferences.retroHostPs2 == true && retroHostInstall?.ps2Core != nil
        case .ps3: return false
        }
    }

    /// Whether the library lists the PS2 discs only the emulator host plays (PS2 cue sheets):
    /// while PS2 discs play in the host.
    var retroHostListsPs2: Bool { listsRetroGames && playsInHost(.ps2) }

    /// Settings › Emulators › Run PS2 games in the separate host; the library is scanned again, as
    /// it lists PS2 cue sheets only while the host plays PS2 discs.
    func setRetroHostPs2(_ enabled: Bool) {
        guard (preferences.retroHostPs2 == true) != enabled else { return }
        preferences.retroHostPs2 = enabled ? true : nil
        if persists { rescan() } else { scanAtOnce() }
        scheduleRetroHostCheck()
    }

    /// Whether `platform`'s discs can be played now: in the host, or in the emulator chosen.
    func retroPlayable(_ platform: RetroPlatform) -> Bool {
        playsInHost(platform) || standaloneEmulator(platform) != nil
    }

    /// Whether the game's own screen is in front: a game in the host and no layer over it.
    var retroInGame: Bool { retroPlay != nil && overlay == nil }

    /// Whether the game's menu is shown, or the question one of its rows asks (Overwrite slot N?).
    var retroMenuShown: Bool { overlay == .retroMenu || overlay == .retroOverwriteState }

    /// Shuts down the host kept for the next game and waits until it has exited, so its files are
    /// no longer held: before the host is replaced by a download.
    func stopKeptRetroHost() async { await retroHostKeeper.shutdown() }

    /// Settings › Emulators › Run PS1 games in the separate host.
    func setRetroHostPs1(_ enabled: Bool) {
        guard (preferences.retroHostPs1 == true) != enabled else { return }
        preferences.retroHostPs1 = enabled ? true : nil
        scheduleRetroHostCheck()
    }

    /// Settings › Emulators' rows of the host once one is found: the setting and the BIOS folder.
    func retroHostPlayRows() -> [PanelRow] {
        guard retroHostInstall != nil else { return [] }
        var rows = [PanelRow(id: "retro-host-ps1", title: TRetro.text(.retroHostPs1), detail: TRetro.text(.retroHostPs1Detail), symbol: "opticaldisc",
                             kind: .toggle(preferences.retroHostPs1 == true) { [weak self] value in self?.setRetroHostPs1(value) })]
        if preferences.retroHostPs1 == true {
            rows.append(PanelRow(id: "retro-host-bios", title: TRetro.text(.retroHostBiosFolder), detail: TRetro.text(.retroHostBiosFolderDetail),
                                 symbol: "folder", kind: .action(destructive: false) { [weak self] in self?.openRetroBiosFolder() }))
        }
        // PS2 under them, only where the host has LRPS2 beside it.
        guard retroHostInstall?.ps2Core != nil else { return rows }
        rows.append(PanelRow(id: "retro-host-ps2", title: TRetro.text(.retroHostPs2), detail: TRetro.text(.retroHostPs2Detail), symbol: "opticaldisc",
                             kind: .toggle(preferences.retroHostPs2 == true) { [weak self] value in self?.setRetroHostPs2(value) }))
        if preferences.retroHostPs2 == true {
            rows.append(PanelRow(id: "retro-host-ps2-bios", title: TRetro.text(.retroHostPs2BiosFolder), detail: TRetro.text(.retroHostPs2BiosFolderDetail),
                                 symbol: "folder", kind: .action(destructive: false) { [weak self] in self?.openRetroBiosFolder(ps2: true) }))
        }
        return rows
    }

    /// Where the host looks for the PS1 BIOS: retro/system in the launcher's own folder.
    var retroSystemFolder: URL { retroFolder.appendingPathComponent("system") }
    /// Where the PS1 memory cards are kept: retro/saves/ps1 beside it.
    var retroSavesFolder: URL { retroFolder.appendingPathComponent("saves/ps1") }
    /// Where LRPS2 looks for the PS2 BIOS: pcsx2/bios in the same system folder.
    var retroPs2BiosFolder: URL { retroSystemFolder.appendingPathComponent("pcsx2/bios") }
    /// Where the PS2 memory cards are kept: retro/saves/ps2.
    var retroPs2SavesFolder: URL { retroFolder.appendingPathComponent("saves/ps2") }
    /// Where the host keeps the save states of `game`, a PS1 one or with `ps2` a PS2 one, beside
    /// their memory cards: retro/states/<ps1|ps2>/<title ID>, the folder `start.states` names
    /// (anyps5-retro-host docs/protocol.md "saveState and loadState"), one per game, as the host
    /// names a slot only after its disc and checks a state's game only by that name. The title ID
    /// keeps its hyphens, so two games whose IDs differ only by one stay apart.
    func retroStatesFolder(_ game: Game, ps2: Bool) -> URL {
        retroFolder.appendingPathComponent("states/\(ps2 ? "ps2" : "ps1")/\(game.titleID)")
    }

    /// The folder the host looks for the PS1 BIOS in, or with `ps2` the one LRPS2 looks for the
    /// PS2 BIOS in, made if it is not there yet, opened in Finder. The launcher never reads, checks
    /// or copies a BIOS.
    func openRetroBiosFolder(ps2: Bool = false) {
        let folder = ps2 ? retroPs2BiosFolder : retroSystemFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("[anyps5-launcher] emulator host: no BIOS folder: %@", String(describing: error))
            return
        }
        if let openRetroFolder { openRetroFolder(folder) } else { NSWorkspace.shared.open(folder) }
    }

    // MARK: Starting

    /// Starts `game`'s PS1 disc in the emulator host and shows it in the launcher's window.
    func playInHost(_ game: Game, _ disc: RetroDisc) {
        guard !playing, retroPlay == nil else { return }
        if retroHostDownload.installing { return show(TRetro.text(.retroHostUpdating), symbol: "opticaldisc") }
        guard let install = retroHostInstall, disc.platform != .ps2 || install.ps2Core != nil else { return }
        familyGate(game) { [weak self] in
            guard let self, !self.playing, self.retroPlay == nil else { return }
            guard StandaloneEmulator.discThere(disc, folder: game.folder) else { return self.show(TRetro.text(.retroDiscMoved), symbol: "opticaldisc") }
            do {
                try FileManager.default.createDirectory(at: self.retroSystemFolder, withIntermediateDirectories: true)
            } catch {
                NSLog("[anyps5-launcher] emulator host: no BIOS folder: %@", String(describing: error))
            }
            guard self.retroHostDownload.holdForStart() else { return self.show(TRetro.text(.retroHostUpdating), symbol: "opticaldisc") }
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.retroHostDownload.releaseStart() }
                await self.playInHeldHost(game, disc, install)
            }
        }
    }

    /// `playInHost` once the installed host is held for the start, so no download replaces it
    /// between its check and the game's play being set.
    private func playInHeldHost(_ game: Game, _ disc: RetroDisc, _ install: RetroHostInstall) async {
        let volume = Double(preferences.retroHostVolume ?? 100) / 100
        let muted = preferences.retroHostMuted == true
        if install.checked, retroHostKeeper.keeps(program: install.host), !(await recheckKeptRetroHost(install)) { return }
        let kept = retroHostKeeper.take(program: install.host)
        let session: RetroHostSession
        if let kept {
            session = kept
            NSLog("[anyps5-launcher] emulator host: the kept %@ plays the next game", install.host)
        } else {
            var checked: RetroHostChecked?
            if install.checked {
                guard let check = await checkRetroHost(install) else { return }
                checked = check
                if disc.platform == .ps2, check.ps2Core == nil {
                    check.release()
                    NSLog("[anyps5-launcher] emulator host: %@ has no checked PS2 core", install.host)
                    return show(TRetro.text(.retroHostNoPs2Detail), symbol: "exclamationmark.triangle.fill")
                }
                if playing || retroPlay != nil {
                    check.release()
                    return
                }
            }
            do {
                session = try await openRetroHost(install, checked, volume, muted)
            } catch {
                checked?.release()
                NSLog("[anyps5-launcher] emulator host: %@ did not start: %@", install.host, String(describing: error))
                return show(TRetro.text(.retroHostNotStartedDetail), symbol: "exclamationmark.triangle.fill")
            }
            if playing || retroPlay != nil {
                session.shutdown()
                _ = await session.ended()
                await session.close()
                return
            }
        }
        let host = RetroHostGame(session: session, statusEvery: retroStatusEvery, volume: volume, muted: muted)
        if kept != nil { Task { await host.setVolume(level: volume, muted: muted) } }
        let settings = settings(for: game)
        let keyboard = RetroKeyboard(changes: settings.controls ?? [:], modifierScale: Double((settings.tuning ?? InputTuning()).stickModifierScale) / 100)
        let controls = RetroHostControls(game: host, pads: retroPads ?? retroPadReaderFromControllers(), motors: retroPadMotors ?? RetroControllerMotors(),
                                         keyboard: { [weak self] in keyboard.state(held: self?.retroKeysHeld ?? []) })
        controls.deadzonePercent = preferences.stickDeadzone ?? 0
        controls.vibration = preferences.controllerVibration ?? true
        let menu = RetroGameMenu(game: host, controls: controls)
        let ps2 = disc.platform == .ps2
        let core = ps2 ? install.ps2Core ?? install.core : install.core
        let discPath = disc.path.standardizedFileURL.path
        let statesPath = retroStatesFolder(game, ps2: ps2).standardizedFileURL.path
        let saveStates = RetroSaveStates(game: host, folder: RetroStateFolder(folder: statesPath, disc: discPath))
        saveStates.log = { NSLog("[anyps5-launcher] %@", $0) }
        let play = RetroPlay(game: game, host: host, controls: controls, menu: menu, started: Date(), program: install.host, core: core,
                             unchecked: !install.checked, states: saveStates)
        play.listener = host.addListener { [weak self] in self?.retroChanged() }
        saveStates.onChange = { [weak self] in self?.retroChanged() }
        Task { await saveStates.refresh() }
        retroKeysHeld = []
        Input.shared.stopRepeating()
        withAnimation(Motion.overlay) {
            retroPlay = play
            overlay = nil
        }
        Sounds.shared.play(.select)
        preferences.lastPlayed[game.id] = play.started
        sessionStart = play.started
        familyGameStarted()
        NSLog("[anyps5-launcher] emulator host: %@ plays %@", install.host, disc.path.path)
        await host.setFocused(active)
        await host.start(RetroHostStartRequest(
            core: core, disc: discPath, system: retroSystemFolder.standardizedFileURL.path,
            saves: (ps2 ? retroPs2SavesFolder : retroSavesFolder).standardizedFileURL.path,
            options: (preferences.retroHostOptions ?? [:]).filter { RetroOptionSection.sent($0.key, ps2: ps2) },
            console: ps2 ? RetroConsole.ps2 : nil, states: statesPath))
    }

    /// The checks before a start of a signed release's host (protocol.md "Finding and checking the
    /// host"), whose files then stay held until that host has exited. A host that fails them is
    /// not started: the player is told to download it again, and its row in Settings › Emulators
    /// offers it again.
    private func checkRetroHost(_ install: RetroHostInstall) async -> RetroHostChecked? {
        do {
            return try await retroHostDownload.store.check()
        } catch {
            let failure = error as? RetroHostReleaseFailure
            let reason = failure?.message ?? String(describing: error)
            NSLog("[anyps5-launcher] emulator host: %@ failed its check%@: %@", install.host, failure?.file.map { " (\($0) failed)" } ?? "", reason)
            retroHostDownload.failedCheck(reason)
            show(TRetro.text(.retroHostCheckFailed), symbol: "exclamationmark.triangle.fill")
            return nil
        }
    }

    /// The checks again before a kept signed host loads its next game: SwanStation is loaded again
    /// for every game, so it is checked again (a second check, let go at once; the host's own
    /// stays held). One that fails is shut down through the keeper, which a download waits for.
    private func recheckKeptRetroHost(_ install: RetroHostInstall) async -> Bool {
        guard let check = await checkRetroHost(install) else {
            Task { await retroHostKeeper.shutdown() }
            return false
        }
        check.release()
        return !playing && retroPlay == nil
    }

    /// The launcher's controllers as a PS1 game reads them: Player 1 first, then the others in
    /// the order they came.
    func retroPadReaderFromControllers() -> RetroPadReader {
        RetroPadReader(pads: {
            let controllers = Controllers.shared
            let ids = controllers.pads.map(\.id)
            guard let first = controllers.roster.playerOne, ids.contains(first) else { return ids }
            return [first] + ids.filter { $0 != first }
        }, state: { Controllers.shared.live.states[$0] })
    }

    // MARK: While it plays

    /// The game moved on: a memory card the host cannot read is said once; a game that ended
    /// without an error, and was not closed by the player, goes back to the library; one with an
    /// error stays on its error screen.
    func retroChanged() {
        guard let play = retroPlay else { return }
        if !play.cardWarned, play.host.status?.cardUnreadable == true {
            play.cardWarned = true
            show(TRetro.text(.retroHostCardUnreadable), symbol: "sdcard")
        }
        // The host's English refusal of a saved resolution goes to the log once per change, never to
        // the screen.
        let refusal = play.host.status?.resolutionError ?? ""
        if refusal != play.resolutionErrorLogged {
            play.resolutionErrorLogged = refusal
            if !refusal.isEmpty { NSLog("[anyps5-launcher] emulator host: %@", refusal) }
        }
        let problem = play.problem
        if play.seenPhase == play.host.phase, let seen = play.seenProblem, seen == problem {
            keepRetroMenuRow(play)
            if retroMenuShown { objectWillChange.send() }
            return
        }
        play.seenPhase = play.host.phase
        play.seenProblem = .some(problem)
        keepRetroMenuRow(play)
        if play.host.phase == .ended, !play.closing {
            if !play.over {
                play.endedAt = Date()
                countRetroPlay(play)
            }
            if play.menu.isOpen || retroMenuShown {
                if retroMenuShown { withAnimation(Motion.overlay) { overlay = nil } }
                leaveRetroPages(play)
                Task { await play.menu.close() }
            }
            warnRetroCardAfterLoad(play)
            NSLog("[anyps5-launcher] emulator host: the game ended (%@)", play.host.endStatus?.error ?? play.host.failure ?? "no error")
            if problem == nil {
                Task { await closeRetroGame() }
                return
            }
        }
        objectWillChange.send()
    }

    /// A PS1 game that ended with `errorCode` `other` after a load the host answered `false`: the
    /// core may have finished that load after the reply, and the host writes the card when the game
    /// ends, so protocol.md "The memory card" asks the launcher to say the card may now be the
    /// state's. Also when the player closed the game while that load ran, as Close game waits for its
    /// reply and its stop then reports that ending.
    private func warnRetroCardAfterLoad(_ play: RetroPlay) {
        guard !play.ps2, !play.loadCardWarned, play.states.loadAnsweredFalse else { return }
        guard let status = play.host.status, status.ended, status.errorCode == RetroErrorCode.other else { return }
        play.loadCardWarned = true
        show(TRetro.text(.retroStateCardAfterEnd), symbol: "sdcard")
    }

    /// PS in the game: its menu, the game paused and the controllers kept out of it.
    func openRetroMenu() {
        guard let play = retroPlay, !play.closing, play.host.loaded, !retroMenuShown else { return }
        leaveRetroPages(play)
        play.menuVisits += 1
        menuIndex = 0
        withAnimation(Motion.overlay) { overlay = .retroMenu }
        Sounds.shared.play(.select)
        Task { await play.menu.open() }
    }

    /// Any layer over the game (its menu, a family notice) pauses it and keeps the controllers and
    /// keys out of it; the game's own screen back in front gives both back.
    func syncRetroMenu() {
        guard let play = retroPlay, !play.closing else { return }
        if overlay != nil, !play.menu.isOpen, play.host.loaded {
            retroKeysHeld = []
            Task { await play.menu.open() }
        }
        if overlay == nil, play.menu.isOpen { Task { await play.menu.close() } }
    }

    /// Back to the game from its menu.
    func resumeRetroGame() {
        guard let play = retroPlay else { return }
        leaveRetroPages(play)
        if retroMenuShown {
            withAnimation(Motion.overlay) { overlay = nil }
            Sounds.shared.play(.back)
        }
        Task { await play.menu.close() }
    }

    /// Closes the game: it is stopped (its memory card written) and forgotten in the host, and the
    /// library comes back. The host is kept for the next game when it is left with no game loaded;
    /// otherwise it is shut down.
    func closeRetroGame() async {
        guard let play = retroPlay, !play.closing else { return }
        play.closing = true
        leaveRetroPages(play)
        countRetroPlay(play)
        if retroMenuShown { withAnimation(Motion.overlay) { overlay = nil } }
        objectWillChange.send()
        if await play.host.detach() {
            retroHostKeeper.keep(play.host.session, program: play.program)
            NSLog("[anyps5-launcher] emulator host: kept for the next game")
        }
        warnRetroCardAfterLoad(play)
        play.release()
        if retroPlay === play {
            withAnimation(Motion.overlay) { retroPlay = nil }
        }
        if retroMenuShown { overlay = nil }
        retroKeysHeld = []
        scheduleRetroHostCheck()
    }

    /// What a command does while a game plays in the host; false when it is not the game's to
    /// take. On the game's own screen the controller is the game's: only PS acts (its menu). Its
    /// error screen goes back to the library, and offers the BIOS folder for a missing BIOS.
    func retroCommand(_ command: Command) -> Bool {
        guard let play = retroPlay else { return false }
        // Create (Share): screenshots and clips take nothing of a game in the host yet.
        if command == .capture { return noRetroCapture() }
        if overlay == .retroMenu { return retroMenuCommand(command) }
        if overlay == .retroOverwriteState { return retroOverwriteCommand(command) }
        if overlay != nil { return false }
        if let problem = play.problem {
            switch command {
            case .select, .back, .home:
                Sounds.shared.play(.back)
                Task { await closeRetroGame() }
            case .options where Self.retroBiosFolderOf(problem) != nil:
                Sounds.shared.play(.select)
                openRetroBiosFolder(ps2: problem == .retroHostPs2BiosDetail)
            default:
                break
            }
            return true
        }
        if play.loading, command == .home {
            Sounds.shared.play(.back)
            Task { await closeRetroGame() }
            return true
        }
        if command == .home { openRetroMenu() }
        return true
    }

    /// The keyboard's Esc, the mouse's right or Back button over the game: its menu, or while it
    /// loads, the start given up. False when no game plays in the host on its own screen.
    func retroPointerBack() -> Bool {
        guard retroInGame, let play = retroPlay else { return false }
        if play.problem != nil { return false }
        if play.loading {
            Sounds.shared.play(.back)
            Task { await closeRetroGame() }
        } else {
            openRetroMenu()
        }
        return true
    }

    /// The keys while a PS1 game in the host is on its own screen: the game reads them itself (its
    /// Controls), so they move nothing of the launcher. Esc gives a start up while the game
    /// loads. The error screen takes the keys as any screen does.
    func retroKey(_ event: NSEvent) -> Bool {
        guard retroInGame, let play = retroPlay, play.problem == nil else {
            if !retroKeysHeld.isEmpty { retroKeysHeld = [] }
            return false
        }
        let name = Controls.keyName(forKeyCode: event.keyCode)
        switch event.type {
        case .keyDown:
            if event.isARepeat { return true }
            if play.loading, name == "Escape" { return retroPointerBack() }
            if let name { retroKeysHeld.insert(name) }
        case .keyUp:
            if let name { retroKeysHeld.remove(name) }
        case .flagsChanged:
            guard let name else { return true }
            if retroKeysHeld.contains(name) { retroKeysHeld.remove(name) } else { retroKeysHeld.insert(name) }
        default:
            return false
        }
        return true
    }

    /// The window's focus: the game pauses while the launcher is not in front, and the keys held
    /// are let go.
    func retroFocusChanged() {
        if !active { retroKeysHeld = [] }
        guard let play = retroPlay else { return }
        let focused = active
        Task { await play.host.setFocused(focused) }
    }

    // MARK: The menu

    /// The menu's sections, in the order its first page lists them, each with the words of its
    /// row and heading and of the row's detail. Graphics is not among them.
    static let retroMenuSections: [(RetroOptionSection, TRetro.Key, TRetro.Key)] = [
        (.audio, .retroMenuAudio, .retroMenuAudioDetail),
        (.controller, .retroMenuController, .retroMenuControllerDetail),
        (.console, .retroMenuConsole, .retroMenuConsoleDetail),
        (.advanced, .retroMenuAdvanced, .retroMenuAdvancedDetail),
    ]

    /// The heading of the menu: the section's name on its page, Save state or Load state on theirs,
    /// else the game's name.
    var retroMenuTitle: String? {
        guard let play = retroPlay else { return nil }
        if let page = play.statePage { return TRetro.text(page == .save ? .retroMenuSaveState : .retroMenuLoadState) }
        guard let section = play.menuSection, let words = Self.retroMenuSections.first(where: { $0.0 == section }) else { return play.game.name }
        return TRetro.text(words.1)
    }

    /// The game's menu, as on Windows and Linux. Its first page: Resume, the discs of a multi-disc
    /// game, Save state and Load state where its host saves states, a row for each section that has
    /// rows, and Close game. A section's page: its options in the order the host lists them, with
    /// Volume and Mute first in Audio. Save state's and Load state's pages: the game's slots.
    func retroMenuPanelRows() -> [PanelRow] {
        guard let play = retroPlay else { return [] }
        if let page = play.statePage { return retroStateRows(play, page) }
        if let section = play.menuSection { return retroSectionRows(play, section) }
        let rows = retroFirstPageRows(play)
        play.firstPageRows = rows.map(\.id)
        return rows
    }

    private func retroFirstPageRows(_ play: RetroPlay) -> [PanelRow] {
        let menu = play.menu
        var rows = [PanelRow(id: "resume", title: TH.text(.resume), symbol: "play.fill",
                             kind: .action(destructive: false) { [weak self] in self?.resumeRetroGame() })]
        for disc in menu.discs {
            let detail: String? = disc.inserted
                ? TRetro.text(menu.discChangeFailed ? .retroMenuDiscFailedDetail : .retroMenuDiscInsertedDetail)
                : (disc.enabled ? nil : TRetro.text(.retroMenuDiscChangingDetail))
            rows.append(PanelRow(id: "disc-\(disc.index)", title: disc.label, detail: detail, symbol: disc.inserted ? "opticaldisc.fill" : "opticaldisc",
                                 kind: .action(destructive: false) { [weak self] in self?.chooseRetroDisc(disc) }))
        }
        rows += retroStateMenuRows(play)
        for (section, title, detail) in Self.retroMenuSections {
            if !retroSectionRows(play, section).isEmpty {
                rows.append(PanelRow(id: "section-\(section.rawValue)", title: TRetro.text(title), detail: TRetro.text(detail),
                                     symbol: Self.retroSectionSymbol(section),
                                     kind: .action(destructive: false) { [weak self] in self?.openRetroMenuSection(play, section) }))
            }
            // The internal resolution after Audio's row, also when Audio has none.
            if section == .audio, let resolution = retroResolutionRow(play) { rows.append(resolution) }
        }
        rows.append(PanelRow(id: "closeGame", title: TH.text(.closeGame), symbol: "xmark.circle",
                             kind: .action(destructive: true) { [weak self] in Task { await self?.closeRetroGame() } }))
        return rows
    }

    /// The first page's Internal resolution row: the values the launcher offers that the host
    /// lists (`RetroResolutionChoice.of`), or nil when the menu offers none.
    private func retroResolutionRow(_ play: RetroPlay) -> PanelRow? {
        guard let choice = play.menu.resolution else { return nil }
        return PanelRow(id: "resolution", title: TRetro.text(.retroResolution), detail: Self.retroResolutionDetail(choice), symbol: "sparkles.tv",
                        kind: .choice(options: choice.values.map(Self.retroResolutionLabel), selected: choice.selected) { [weak self] index in
            guard choice.values.indices.contains(index) else { return }
            self?.chooseRetroResolution(play, choice.values[index].value)
        })
    }

    /// An internal resolution chosen in the menu: sent to the game, and kept for every later game
    /// of its console once the host took it. A PS1 game draws at it in a moment, a PS2 game from
    /// its next start.
    private func chooseRetroResolution(_ play: RetroPlay, _ value: String) {
        guard let key = play.menu.resolution?.key else { return }
        Task { @MainActor [weak self] in
            guard await play.menu.chooseResolution(value), let self else { return }
            var kept = self.preferences.retroHostOptions ?? [:]
            kept[key] = value
            self.preferences.retroHostOptions = kept
        }
    }

    /// A value's words: Native, a scale ("2x"), or the host's own label for one the launcher does
    /// not offer.
    static func retroResolutionLabel(_ value: RetroResolutionValue) -> String {
        switch value.scale {
        case nil: return value.label
        case 1: return TRetro.text(.retroResolutionNative)
        case let scale?: return TRetro.format(.retroResolutionScale, "\(scale)")
        }
    }

    /// The line under the row: the refusal naming the value the game draws at, when the next start
    /// takes it, that it shows in a moment, or what it does.
    static func retroResolutionDetail(_ choice: RetroResolutionChoice) -> String {
        switch choice.note {
        case .none: return TRetro.text(.retroResolutionDetail)
        case .applying: return TRetro.text(.retroMenuOptionPendingDetail)
        case .nextStart: return TRetro.text(.retroMenuOptionRestartDetail)
        case .changesAtNextStart: return TRetro.text(.retroMenuOptionRestartOnlyDetail)
        case .refused: return TRetro.format(.retroResolutionRefusedDetail, retroResolutionLabel(choice.active))
        }
    }

    private static func retroSectionSymbol(_ section: RetroOptionSection) -> String {
        switch section {
        case .audio: return "speaker.wave.2.fill"
        case .controller: return "gamecontroller.fill"
        case .console: return "cpu"
        case .advanced, .graphics: return "wrench.and.screwdriver"
        }
    }

    /// The rows of one section's page: Volume and Mute first in Audio, then the section's
    /// options. An option that takes effect only when the game starts again says so; a chosen
    /// value not yet in effect says when it will be.
    private func retroSectionRows(_ play: RetroPlay, _ section: RetroOptionSection) -> [PanelRow] {
        var rows: [PanelRow] = []
        if section == .audio {
            rows.append(PanelRow(id: "volume", title: TRetro.text(.retroMenuVolume), symbol: "speaker.wave.2",
                                 kind: .stepper(value: Int((play.host.volume * 100).rounded()), range: 0...100, step: 10, format: { "\($0)%" },
                                                set: { [weak self] value in self?.setRetroVolume(value) })))
            rows.append(PanelRow(id: "mute", title: TRetro.text(.retroMenuMute), symbol: "speaker.slash",
                                 kind: .toggle(play.host.muted) { [weak self] muted in self?.setRetroMuted(muted) }))
        }
        for option in play.menu.optionsIn(section) {
            let detail: String? = option.pending
                ? TRetro.text(option.restartNeeded ? .retroMenuOptionRestartDetail : .retroMenuOptionPendingDetail)
                : (option.restartNeeded ? TRetro.text(.retroMenuOptionRestartOnlyDetail) : nil)
            rows.append(PanelRow(id: "option-\(option.key)", title: option.title, detail: detail, symbol: "slider.horizontal.3",
                                 kind: .choice(options: option.option.labels, selected: option.option.selected) { [weak self] index in
                self?.chooseRetroOption(option.option, index)
            }))
        }
        return rows
    }

    /// The menu's rows as the PS menu card draws them.
    func retroMenuRows() -> [QuickMenuRow] {
        retroMenuPanelRows().enumerated().map { index, row in
            var item = QuickMenuRow(id: index, title: row.title, detail: row.detail, symbol: row.symbol ?? "circle", key: row.id)
            item.picture = row.picture
            item.pictureAspect = row.pictureAspect
            switch row.kind {
            case .action(let destructive, let run):
                item.destructive = destructive
                item.run = run
            case .toggle(let on, _):
                item.value = T.text(on ? .on : .off)
                item.control = row
                item.run = { [weak self] in self?.activate(row) }
            case .stepper(let value, _, _, let format, _):
                item.value = format(value)
                item.control = row
                item.run = { [weak self] in self?.activate(row) }
            case .choice(let options, let selected, _):
                item.value = options.indices.contains(selected) ? options[selected] : nil
                item.control = row
                item.run = { [weak self] in self?.activate(row) }
            default:
                break
            }
            return item
        }
    }

    /// The menu from the keys and the pad: up and down move, left and right change a setting,
    /// Select chooses, Back leaves a section's page or the menu, PS and Options resume.
    private func retroMenuCommand(_ command: Command) -> Bool {
        guard let play = retroPlay else { return false }
        let rows = retroMenuRows()
        if menuIndex >= rows.count, !rows.isEmpty { menuIndex = rows.count - 1 }
        // A row that cannot be chosen (Load state with nothing saved, an empty slot on its page) is
        // passed over, as on Windows and Linux.
        func move(_ delta: Int) {
            var next = menuIndex + delta
            while rows.indices.contains(next), rows[next].run == nil { next += delta }
            guard rows.indices.contains(next), next != menuIndex else { return Sounds.shared.play(.bump) }
            withAnimation(Motion.focus) { menuIndex = next }
            Sounds.shared.play(.move)
        }
        switch command {
        case .up: move(-1)
        case .down: move(1)
        case .left, .right:
            if rows.indices.contains(menuIndex), let control = rows[menuIndex].control {
                change(control, by: command == .left ? -1 : 1)
            }
        case .select:
            if rows.indices.contains(menuIndex) { rows[menuIndex].run?() }
        case .back where play.menuSection != nil || play.statePage != nil:
            leaveRetroMenuSection(play)
        case .back, .home, .options:
            resumeRetroGame()
        default:
            break
        }
        return true
    }

    private func openRetroMenuSection(_ play: RetroPlay, _ section: RetroOptionSection) {
        guard retroPlay === play, overlay == .retroMenu else { return }
        play.menuSection = section
        menuIndex = 0
        Sounds.shared.play(.select)
        objectWillChange.send()
    }

    /// Back from a section's or a state page to the first page, on the row that opened it.
    private func leaveRetroMenuSection(_ play: RetroPlay) {
        let id = play.menuSection.map { "section-\($0.rawValue)" } ?? play.statePage.map { $0 == .save ? "saveState" : "loadState" }
        leaveRetroPages(play)
        let index = retroMenuPanelRows().firstIndex { $0.id == id }
        menuIndex = index ?? 0
        Sounds.shared.play(.back)
        objectWillChange.send()
    }

    /// The menu opens, or is left, on its first page.
    private func leaveRetroPages(_ play: RetroPlay) {
        play.menuSection = nil
        play.statePage = nil
        play.overwriting = nil
    }

    /// The menu's first page gained or lost rows as the game's status changed (Save state and Load
    /// state once the first frame is up, the discs and sections once the status lists them): the
    /// focus stays on the row it was on, wherever that row now is.
    private func keepRetroMenuRow(_ play: RetroPlay) {
        guard overlay == .retroMenu, play.menuSection == nil, play.statePage == nil else { return }
        let before = play.firstPageRows
        guard before.indices.contains(menuIndex) else { return }
        let focused = before[menuIndex]
        let now = retroFirstPageRows(play).map(\.id)
        play.firstPageRows = now
        if let index = now.firstIndex(of: focused) { menuIndex = index }
    }

    // MARK: Save states

    /// Save state and Load state on the menu's first page, where the game's host saves states and
    /// once the game has shown its first frame (`status.ready`), before which the host saves and
    /// loads nothing. Load state says what a load takes back with it (a PS1 game's memory card), or
    /// that nothing is saved yet, when it cannot be chosen.
    private func retroStateMenuRows(_ play: RetroPlay) -> [PanelRow] {
        let states = play.states
        guard states.available, play.host.phase == .playing else { return [] }
        let loadDetail: TRetro.Key = !states.anySaved ? .retroMenuNoStatesDetail : (play.ps2 ? .retroMenuLoadStateDetail : .retroMenuLoadStatePs1Detail)
        return [
            PanelRow(id: "saveState", title: TRetro.text(.retroMenuSaveState), detail: TRetro.text(.retroMenuSaveStateDetail), symbol: "square.and.arrow.down",
                     kind: .action(destructive: false) { [weak self] in self?.openRetroStatePage(play, .save) }),
            PanelRow(id: "loadState", title: TRetro.text(.retroMenuLoadState), detail: TRetro.text(loadDetail), symbol: "clock.arrow.circlepath",
                     kind: states.anySaved ? .action(destructive: false) { [weak self] in self?.openRetroStatePage(play, .load) } : .info("")),
        ]
    }

    /// A state page's rows: every slot, from 1, with when its state was saved and its picture at the
    /// game's aspect (its place kept empty without one), or Saving… or Loading… while that is under
    /// way. On Save state each slot can be chosen; on Load state only a slot that holds a state.
    private func retroStateRows(_ play: RetroPlay, _ page: RetroStatePage) -> [PanelRow] {
        let running = play.states.running
        return play.states.slots.map { slot in
            let detail: String
            if let running, running.slot == slot.slot {
                detail = TRetro.text(running.saving ? .retroStateSaving : .retroStateLoading)
            } else if let savedAt = slot.savedAt {
                detail = Self.retroStateTime(savedAt)
            } else {
                detail = TRetro.text(.retroStateEmpty)
            }
            let kind: PanelRow.Kind = page == .load && slot.empty ? .info("") : .action(destructive: false) { [weak self] in
                guard let self else { return }
                if page == .save {
                    self.chooseRetroSaveSlot(play, slot)
                } else {
                    self.chooseRetroLoadSlot(play, slot.slot)
                }
            }
            return PanelRow(id: "state-\(slot.slot)", title: TRetro.format(.retroStateSlot, "\(slot.slot + 1)"), detail: detail, symbol: "square.stack",
                            kind: kind, picture: slot.picture, pictureAspect: play.host.aspect)
        }
    }

    private func openRetroStatePage(_ play: RetroPlay, _ page: RetroStatePage) {
        guard retroPlay === play, overlay == .retroMenu else { return }
        play.statePage = page
        let rows = retroStateRows(play, page)
        menuIndex = rows.firstIndex { row in
            if case .info = row.kind { return false }
            return true
        } ?? 0
        Sounds.shared.play(.select)
        objectWillChange.send()
    }

    /// A slot chosen on Save state: an empty one is saved into at once; one that holds a state asks
    /// Overwrite slot N? first, in the same two-answer card as Close game, Cancel first.
    private func chooseRetroSaveSlot(_ play: RetroPlay, _ slot: RetroStateSlot) {
        guard !play.states.busy, !play.stateAsked, retroPlay === play else { return }
        if slot.empty {
            play.stateAsked = true
            Task { await saveRetroState(play, slot.slot) }
            return
        }
        play.overwriting = slot.slot
        menuIndex = 0
        withAnimation(Motion.overlay) { overlay = .retroOverwriteState }
        Sounds.shared.play(.select)
    }

    /// Overwrite slot N?: its question, and the detail of Overwrite, which says when the state it
    /// replaces was saved.
    var retroOverwriteQuestion: (title: String, detail: String?)? {
        guard let play = retroPlay, let slot = play.overwriting else { return nil }
        let savedAt = play.states.slot(slot).savedAt
        return (TRetro.format(.retroStateOverwriteTitle, "\(slot + 1)"),
                savedAt.map { TRetro.format(.retroStateOverwriteDetail, Self.retroStateTime($0)) })
    }

    /// Overwrite slot N? from the keys and the pad: its two answers take the arrows and Select;
    /// Back, PS and Options go back to Save state on that slot.
    private func retroOverwriteCommand(_ command: Command) -> Bool {
        guard let play = retroPlay else { return false }
        func move(_ delta: Int) {
            let next = min(1, max(0, menuIndex + delta))
            guard next != menuIndex else { return }
            withAnimation(Motion.focus) { menuIndex = next }
            Sounds.shared.play(.move)
        }
        switch command {
        case .up, .left: move(-1)
        case .down, .right: move(1)
        case .back, .home, .options: cancelRetroOverwrite(play)
        case .select: if menuIndex == 1 { confirmRetroOverwrite(play) } else { cancelRetroOverwrite(play) }
        default: break
        }
        return true
    }

    /// Back from Overwrite slot N? to Save state, on that slot.
    private func cancelRetroOverwrite(_ play: RetroPlay) {
        let slot = play.overwriting
        play.overwriting = nil
        guard overlay == .retroOverwriteState else { return }
        withAnimation(Motion.overlay) { overlay = .retroMenu }
        menuIndex = slot ?? 0
        Sounds.shared.play(.back)
    }

    private func confirmRetroOverwrite(_ play: RetroPlay) {
        guard let slot = play.overwriting, overlay == .retroOverwriteState else { return }
        play.overwriting = nil
        withAnimation(Motion.overlay) { overlay = .retroMenu }
        menuIndex = slot
        Sounds.shared.play(.select)
        guard !play.states.busy, !play.stateAsked else { return }
        play.stateAsked = true
        Task { await saveRetroState(play, slot) }
    }

    /// A slot chosen on Load state: loaded, unless a save or load already runs, when the press is
    /// let go.
    private func chooseRetroLoadSlot(_ play: RetroPlay, _ slot: Int) {
        guard !play.states.busy, !play.stateAsked, retroPlay === play else { return }
        play.stateAsked = true
        Task { await loadRetroState(play, slot) }
    }

    /// Saves the game into `slot`: back to the game once it is saved, the slot said; still on Save
    /// state when it did not work, which is said.
    private func saveRetroState(_ play: RetroPlay, _ slot: Int) async {
        let visit = play.menuVisits
        let outcome = await play.states.save(slot)
        play.stateAsked = false
        guard retroPlay === play else { return }
        NSLog("[anyps5-launcher] emulator host: save state slot %d: %@", slot, outcome.rawValue)
        guard outcome == .done else {
            show(TRetro.text(Self.retroStateProblem(outcome, saving: true)), symbol: "exclamationmark.triangle.fill")
            objectWillChange.send()
            return
        }
        show(TRetro.format(.retroStateSaved, "\(slot + 1)"), symbol: "square.and.arrow.down")
        if onRetroStatePage(play, .save, visit) { resumeRetroGame() }
    }

    /// Loads the state in `slot`: back to the game, which goes on from it; still on Load state when
    /// the host refused it (a state of another emulator build or game, or a damaged file), which is
    /// said.
    private func loadRetroState(_ play: RetroPlay, _ slot: Int) async {
        let visit = play.menuVisits
        let outcome = await play.states.load(slot)
        play.stateAsked = false
        guard retroPlay === play else { return }
        NSLog("[anyps5-launcher] emulator host: load state slot %d: %@", slot, outcome.rawValue)
        guard outcome == .done else {
            show(TRetro.text(Self.retroStateProblem(outcome, saving: false)), symbol: "exclamationmark.triangle.fill")
            objectWillChange.send()
            return
        }
        show(TRetro.format(.retroStateLoaded, "\(slot + 1)"), symbol: "clock.arrow.circlepath")
        if onRetroStatePage(play, .load, visit) { resumeRetroGame() }
    }

    /// Whether the menu still shows `page` of the visit `visit` a save or load was asked in.
    private func onRetroStatePage(_ play: RetroPlay, _ page: RetroStatePage, _ visit: Int) -> Bool {
        overlay == .retroMenu && play.statePage == page && play.menuVisits == visit
    }

    /// The words for a save or load of a state that did not work: a load the host refused for a
    /// state of another emulator build, of another game or damaged says so; anything else says only
    /// that it did not work.
    static func retroStateProblem(_ outcome: RetroStateOutcome, saving: Bool) -> TRetro.Key {
        switch outcome {
        case .otherCore where !saving: return .retroStateOtherCore
        case .otherGame where !saving: return .retroStateOtherGame
        case .badState where !saving: return .retroStateBad
        default: return saving ? .retroStateSaveFailed : .retroStateLoadFailed
        }
    }

    /// "2026-11-18 14:03": when a slot's state was saved, in local time, as the cloud saves show
    /// theirs.
    static func retroStateTime(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    private func chooseRetroDisc(_ disc: RetroDiscRow) {
        guard let play = retroPlay else { return }
        Task { _ = await play.menu.chooseDisc(disc) }
    }

    /// A core option chosen in the menu: sent to the game, and kept for every later one once the
    /// host took it.
    private func chooseRetroOption(_ option: RetroOption, _ index: Int) {
        guard let play = retroPlay, index != option.selected, option.values.indices.contains(index) else { return }
        Task { @MainActor [weak self] in
            guard await play.menu.stepOption(option.key, index - option.selected), let self else { return }
            var kept = self.preferences.retroHostOptions ?? [:]
            kept[option.key] = option.values[index]
            self.preferences.retroHostOptions = kept
        }
    }

    private func setRetroVolume(_ percent: Int) {
        guard let play = retroPlay else { return }
        let steps = Int(((Double(percent) - play.host.volume * 100) / 10).rounded())
        guard steps != 0 else { return }
        Task { @MainActor [weak self] in
            await play.menu.stepVolume(steps)
            self?.keepRetroVolume(play)
        }
    }

    private func setRetroMuted(_ muted: Bool) {
        guard let play = retroPlay, play.host.muted != muted else { return }
        Task { @MainActor [weak self] in
            await play.menu.toggleMute()
            self?.keepRetroVolume(play)
        }
    }

    private func keepRetroVolume(_ play: RetroPlay) {
        let level = Int((play.host.volume * 100).rounded())
        preferences.retroHostVolume = level == 100 ? nil : level
        preferences.retroHostMuted = play.host.muted ? true : nil
    }

    // MARK: The kept host and the end

    /// The kept host is checked against what the launcher shows, once per change: it is shut
    /// down once the player has left the host's games.
    func scheduleRetroHostCheck() {
        guard !retroHostCheckPending else { return }
        retroHostCheckPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retroHostCheckPending = false
            self.letUnwantedRetroHostGo()
        }
    }

    /// The kept host is shut down once the player has left the host's games: the game selected is
    /// not a disc that plays in the host, or another game starts or runs.
    func letUnwantedRetroHostGo() {
        guard retroHostKeeper.holding, retroPlay == nil else { return }
        let platform = selectedGame?.retro?.platform
        let wanted = running == nil && starting == nil && emulator == nil && platform.map(playsInHost) == true
        if !wanted { Task { await retroHostKeeper.shutdown() } }
    }

    /// How long quitting the launcher waits for the emulator hosts to save and exit.
    static let retroQuitLimit: Duration = .seconds(3)

    /// The launcher is quitting: the host download stops, and every emulator host is shut down,
    /// the game's and the kept one, and waited for up to `limit`. A host told to shut down stops
    /// its game as `stop` does, its memory card written (protocol.md "shutdown").
    func shutDownRetroHosts(limit: Duration = AppModel.retroQuitLimit) -> Task<Void, Never>? {
        retroHostDownload.close()
        let play = retroPlay
        guard play != nil || retroHostKeeper.holding else { return nil }
        if let play { countRetroPlay(play) }
        let keeper = retroHostKeeper
        let hosts = Task { @MainActor in
            await play?.host.shutdown()
            await keeper.shutdown()
        }
        return QuitWait.bounded(hosts, within: limit)
    }

    /// The game is over: the family play-time watcher lets it go, and its time from start to
    /// `endedAt` is counted, once.
    func countRetroPlay(_ play: RetroPlay) {
        if play.endedAt == nil { play.endedAt = Date() }
        guard !play.counted else { return }
        play.counted = true
        if let start = sessionStart, sessionStart == play.started { familyPlayed(play.game, from: start, session: nil) }
        sessionStart = nil
        familyGameEnded()
    }

    /// No capture: a PS1 game in the emulator host has none yet, which the player is told.
    func noRetroCapture() -> Bool {
        guard retroPlay != nil else { return false }
        show(TRetro.text(.retroHostNoCapture), symbol: "camera")
        return true
    }

    // MARK: Words

    /// Why `host`'s game stopped, as the key of the words to show the player; nil while it plays
    /// or after a clean end. A host that speaks another protocol version needs updating, and one
    /// that never greeted the launcher could not be started.
    static func retroHostProblem(_ host: RetroHostGame, ps2: Bool = false) -> TRetro.Key? {
        guard host.phase == .ended else { return nil }
        if host.hostEnd == .unsupported { return .retroHostOutdatedDetail }
        // A PS2 game a host without `ps2` was never given needs a newer host.
        if host.consoleRefused { return .retroHostNoPs2Detail }
        guard let status = host.endStatus else { return host.failure == nil ? nil : .retroHostNotStartedDetail }
        return retroHostErrorKey(status.errorCode, ps2: ps2) ?? (host.failure == nil ? nil : .retroHostOtherDetail)
    }

    /// The words of the BIOS folder a problem sends the player to, on its error screen's options
    /// key: the PS1 or the PS2 BIOS folder for a missing BIOS; nil for any other problem.
    static func retroBiosFolderOf(_ problem: TRetro.Key?) -> TRetro.Key? {
        switch problem {
        case .retroHostBiosDetail: return .retroHostBiosFolder
        case .retroHostPs2BiosDetail: return .retroHostPs2BiosFolder
        default: return nil
        }
    }

    /// The words for a status's `errorCode` (protocol.md "status" and "Host failure"): nil for "",
    /// a game stopped without an error. A code this launcher does not know is a game that ended
    /// with an error (protocol.md "Compatibility").
    static func retroHostErrorKey(_ errorCode: String, ps2: Bool = false) -> TRetro.Key? {
        switch errorCode {
        case RetroErrorCode.none: return nil
        case RetroErrorCode.bios: return ps2 ? .retroHostPs2BiosDetail : .retroHostBiosDetail
        case RetroErrorCode.disc: return .retroHostDiscDetail
        case RetroErrorCode.core: return .retroHostCoreDetail
        case RetroErrorCode.stalled: return .retroHostStalledDetail
        case RetroErrorCode.didNotStart: return .retroHostDidNotStartDetail
        case RetroErrorCode.frameTooLarge: return .retroHostFrameTooLargeDetail
        case RetroErrorCode.hostExited: return .retroHostExitedDetail
        case RetroErrorCode.hostHung: return .retroHostHungDetail
        default: return .retroHostOtherDetail
        }
    }

    /// The loading screen's line: the host's own words for what it loads where the launcher speaks
    /// English, as the host's are English; the launcher's otherwise.
    static func retroLoadingText(_ status: RetroStatus?) -> String {
        (T.language.code == Language.english.code ? status?.progressLabel : nil) ?? TRetro.text(.retroHostLoading)
    }
}

/// The controllers' motors for a PS1 game in the host: the core's vibration on the controller at
/// its port, through Core Haptics, or the launcher's own reader for a DualShock 3.
@MainActor
final class RetroControllerMotors: RetroPadMotors {
    private var haptics: [String: PadHaptics] = [:]

    func canRumble(_ pad: String) -> Bool {
        if let controller = Controllers.shared.gameController(pad) { return controller.haptics != nil }
        return Controllers.shared.roster.pad(pad)?.kind == .dualShock3
    }

    func rumble(_ pad: String, strong: Double, weak: Double, hold: Duration) {
        let output = haptics[pad] ?? {
            let made = PadHaptics()
            if let controller = Controllers.shared.gameController(pad) { made.use(controller) } else { made.use(external: pad) }
            haptics[pad] = made
            return made
        }()
        guard strong > 0 || weak > 0 else { return output.stop() }
        let seconds = Double(hold.components.seconds) + Double(hold.components.attoseconds) / 1e18
        output.play([HapticPulse(start: 0, length: seconds, strong: strong, weak: weak)])
    }
}
