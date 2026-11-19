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
    /// The core library the game was started with: SwanStation.
    let core: String
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
    /// The section of the menu shown, or nil for the menu's first page.
    var menuSection: RetroOptionSection?
    /// The phase and the problem the launcher last acted on (`retroChanged`).
    var seenPhase: RetroHostGamePhase?
    var seenProblem: TRetro.Key??
    var listener: Int?
    private var released = false

    init(game: Game, host: RetroHostGame, controls: RetroHostControls, menu: RetroGameMenu, started: Date, program: String, core: String,
         unchecked: Bool) {
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
        controls.dispose()
        menu.dispose()
        host.dispose()
    }

    /// The game is starting or loading: the loading screen shows.
    var loading: Bool { host.phase == .starting || host.phase == .loading }

    /// Why the game stopped, as the key of the words to show the player; nil while it plays, and
    /// for a game that ended without an error or that the player closed.
    var problem: TRetro.Key? { closing ? nil : AppModel.retroHostProblem(host) }
}

extension AppModel {
    // MARK: What plays where

    /// The host this build runs: in a debug build the one `ANYPS5_RETRO_HOST` names, unchecked;
    /// otherwise the signed host downloaded in Settings › Emulators, checked before each start.
    var retroHostInstall: RetroHostInstall? { retroHostUnchecked ?? retroHostDownload.installed }

    /// Whether `platform`'s discs play in the emulator host: PS1 with its setting on and a host
    /// found. Otherwise they go to the emulator chosen in Settings › Emulators, as before.
    func playsInHost(_ platform: RetroPlatform) -> Bool {
        platform == .ps1 && preferences.retroHostPs1 == true && retroHostInstall != nil
    }

    /// Whether `platform`'s discs can be played now: in the host, or in the emulator chosen.
    func retroPlayable(_ platform: RetroPlatform) -> Bool {
        playsInHost(platform) || standaloneEmulator(platform) != nil
    }

    /// Whether the game's own screen is in front: a game in the host and no layer over it.
    var retroInGame: Bool { retroPlay != nil && overlay == nil }

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
        return rows
    }

    /// Where the host looks for the PS1 BIOS: retro/system in the launcher's own folder.
    var retroSystemFolder: URL { retroFolder.appendingPathComponent("system") }
    /// Where the PS1 memory cards are kept: retro/saves/ps1 beside it.
    var retroSavesFolder: URL { retroFolder.appendingPathComponent("saves/ps1") }

    /// The folder the host looks for the PS1 BIOS in, made if it is not there yet, opened in Finder.
    func openRetroBiosFolder() {
        let folder = retroSystemFolder
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
        guard let install = retroHostInstall else { return }
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
        let play = RetroPlay(game: game, host: host, controls: controls, menu: menu, started: Date(), program: install.host, core: install.core,
                             unchecked: !install.checked)
        play.listener = host.addListener { [weak self] in self?.retroChanged() }
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
            core: install.core, disc: disc.path.standardizedFileURL.path, system: retroSystemFolder.standardizedFileURL.path,
            saves: retroSavesFolder.standardizedFileURL.path,
            options: (preferences.retroHostOptions ?? [:]).filter { RetroOptionSection.sent($0.key) }))
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
        let problem = play.problem
        if play.seenPhase == play.host.phase, let seen = play.seenProblem, seen == problem {
            if overlay == .retroMenu { objectWillChange.send() }
            return
        }
        play.seenPhase = play.host.phase
        play.seenProblem = .some(problem)
        if play.host.phase == .ended, !play.closing {
            if !play.over {
                play.endedAt = Date()
                countRetroPlay(play)
            }
            if play.menu.isOpen || overlay == .retroMenu {
                if overlay == .retroMenu { withAnimation(Motion.overlay) { overlay = nil } }
                play.menuSection = nil
                Task { await play.menu.close() }
            }
            NSLog("[anyps5-launcher] emulator host: the game ended (%@)", play.host.endStatus?.error ?? play.host.failure ?? "no error")
            if problem == nil {
                Task { await closeRetroGame() }
                return
            }
        }
        objectWillChange.send()
    }

    /// PS in the game: its menu, the game paused and the controllers kept out of it.
    func openRetroMenu() {
        guard let play = retroPlay, !play.closing, play.host.loaded, overlay != .retroMenu else { return }
        play.menuSection = nil
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
        play.menuSection = nil
        if overlay == .retroMenu {
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
        play.menuSection = nil
        countRetroPlay(play)
        if overlay == .retroMenu { withAnimation(Motion.overlay) { overlay = nil } }
        objectWillChange.send()
        if await play.host.detach() {
            retroHostKeeper.keep(play.host.session, program: play.program)
            NSLog("[anyps5-launcher] emulator host: kept for the next game")
        }
        play.release()
        if retroPlay === play {
            withAnimation(Motion.overlay) { retroPlay = nil }
        }
        if overlay == .retroMenu { overlay = nil }
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
        if overlay != nil { return false }
        if let problem = play.problem {
            switch command {
            case .select, .back, .home:
                Sounds.shared.play(.back)
                Task { await closeRetroGame() }
            case .options where problem == .retroHostBiosDetail:
                Sounds.shared.play(.select)
                openRetroBiosFolder()
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

    /// The heading of the menu: the section's name on its page, else the game's name.
    var retroMenuTitle: String? {
        guard let play = retroPlay else { return nil }
        guard let section = play.menuSection, let words = Self.retroMenuSections.first(where: { $0.0 == section }) else { return play.game.name }
        return TRetro.text(words.1)
    }

    /// The game's menu, as on Windows and Linux. Its first page: Resume, the discs of a multi-disc
    /// game, a row for each section that has rows, and Close game. A section's page: its options in
    /// the order the host lists them, with Volume and Mute first in Audio.
    func retroMenuPanelRows() -> [PanelRow] {
        guard let play = retroPlay else { return [] }
        if let section = play.menuSection { return retroSectionRows(play, section) }
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
        for (section, title, detail) in Self.retroMenuSections where !retroSectionRows(play, section).isEmpty {
            rows.append(PanelRow(id: "section-\(section.rawValue)", title: TRetro.text(title), detail: TRetro.text(detail), symbol: Self.retroSectionSymbol(section),
                                 kind: .action(destructive: false) { [weak self] in self?.openRetroMenuSection(play, section) }))
        }
        rows.append(PanelRow(id: "closeGame", title: TH.text(.closeGame), symbol: "xmark.circle",
                             kind: .action(destructive: true) { [weak self] in Task { await self?.closeRetroGame() } }))
        return rows
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
        func move(_ delta: Int) {
            let next = min(rows.count - 1, max(0, menuIndex + delta))
            guard next != menuIndex else { return Sounds.shared.play(.bump) }
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
        case .back where play.menuSection != nil:
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

    /// Back from a section's page to the first page, on the section's row.
    private func leaveRetroMenuSection(_ play: RetroPlay) {
        let section = play.menuSection
        play.menuSection = nil
        let index = retroMenuPanelRows().firstIndex { $0.id == "section-\(section?.rawValue ?? "")" }
        menuIndex = index ?? 0
        Sounds.shared.play(.back)
        objectWillChange.send()
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
    static func retroHostProblem(_ host: RetroHostGame) -> TRetro.Key? {
        guard host.phase == .ended else { return nil }
        if host.hostEnd == .unsupported { return .retroHostOutdatedDetail }
        guard let status = host.endStatus else { return host.failure == nil ? nil : .retroHostNotStartedDetail }
        return retroHostErrorKey(status.errorCode) ?? (host.failure == nil ? nil : .retroHostOtherDetail)
    }

    /// The words for a status's `errorCode` (protocol.md "status" and "Host failure"): nil for "",
    /// a game stopped without an error. A code this launcher does not know is a game that ended
    /// with an error (protocol.md "Compatibility").
    static func retroHostErrorKey(_ errorCode: String) -> TRetro.Key? {
        switch errorCode {
        case RetroErrorCode.none: return nil
        case RetroErrorCode.bios: return .retroHostBiosDetail
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
