import AnyPS5Core
import AppKit
import SwiftUI

/// PS1, PS2 and PS3 discs in the games folders, played in an emulator installed on the Mac
/// (DuckStation, PCSX2, RPCS3), as on Windows and Linux: the library's switch, the emulators'
/// settings and what a disc's own settings show. The start and the end of an emulator are in
/// AppModel.swift (Emulator games), Stop in GameStop.swift.
extension AppModel {
    /// Settings › Library › Emulator games.
    var listsRetroGames: Bool { preferences.retroLibrary ?? false }

    /// Settings › Emulators › Show as folders.
    var showsRetroFolders: Bool { preferences.showRetroFolders ?? false }

    /// The game selected on Home when it is a PS5 game: what AnyTogether is told about (a party's
    /// game, Play Together, a post, Find players) is never a disc.
    var selectedPS5Game: Game? { selectedGame.flatMap { $0.retro == nil ? $0 : nil } }

    /// The application or program chosen for `platform`, as it was picked, while it still starts
    /// something.
    func chosenEmulator(_ platform: RetroPlatform) -> String? {
        standaloneEmulator(platform) == nil ? nil : preferences.retroEmulators?[platform.rawValue]
    }

    /// The program of the emulator chosen for `platform` (an application's own executable, or
    /// the file picked), while it is still there.
    func standaloneEmulator(_ platform: RetroPlatform) -> URL? {
        guard let chosen = preferences.retroEmulators?[platform.rawValue], chosen.hasPrefix("/") else { return nil }
        if let program = emulatorPrograms[chosen], FileManager.default.fileExists(atPath: program.path) { return program }
        let program = StandaloneEmulator.executable(of: URL(fileURLWithPath: chosen))
        emulatorPrograms[chosen] = program
        return program
    }

    /// Asks for `platform`'s emulator, an application or its program, and keeps it.
    func chooseStandaloneEmulator(_ platform: RetroPlatform) {
        let title = TRetro.format(.retroSelectExecutable, platform.emulator)
        let picked: URL?
        do {
            if let pickEmulator { picked = try pickEmulator(title) } else { picked = chooseEmulatorFile(title) }
        } catch {
            return show(TRetro.text(.retroEmulatorPickerFailed), symbol: "exclamationmark.triangle.fill")
        }
        guard let picked else { return }
        guard StandaloneEmulator.executable(of: picked) != nil else { return show(title, symbol: "questionmark.app") }
        var emulators = preferences.retroEmulators ?? [:]
        emulators[platform.rawValue] = picked.path
        preferences.retroEmulators = emulators
    }

    /// The file panel on Applications: an application counts as one file there.
    private func chooseEmulatorFile(_ title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Settings › Library › Emulator games: turns the discs' discovery on or off, and with it
    /// Settings › Emulators. The scan that follows announces none of the discs as new games.
    func setRetroLibrary(_ enabled: Bool) {
        guard listsRetroGames != enabled else { return }
        preferences.retroLibrary = enabled ? true : nil
        if !enabled, homeRetroFolder != nil { homeRetroFolder = nil }
        if persists { rescan() } else { scanAtOnce() }
    }

    /// The games folders scanned on the spot, for the previews and the tests, which have no
    /// watch over the folders (preview(games:root:)).
    func scanAtOnce(cache: RetroScanCache? = nil) {
        guard let first = libraryRoots.first else { return }
        preview(games: GameLibrary.survey(roots: libraryRoots, includeRetro: listsRetroGames, cache: cache).games, root: first)
        if selected >= games.count { selected = max(0, games.count - 1) }
    }

    /// Settings › Library's last row.
    func retroLibraryRow() -> PanelRow {
        PanelRow(id: "retroLibrary", title: TRetro.text(.retroLibrary), detail: TRetro.text(.retroLibraryDetail), symbol: "opticaldisc",
                 kind: .toggle(listsRetroGames) { [weak self] value in self?.setRetroLibrary(value) })
    }

    /// Settings › Emulators, shown while Emulator games is on.
    func standaloneEmulatorSettings() -> PanelCategory {
        var rows = RetroPlatform.allCases.map { platform in
            PanelRow(id: "retro-\(platform.rawValue)", title: platform.emulator, detail: chosenEmulator(platform) ?? TRetro.text(.retroChooseExecutable), symbol: "app.dashed",
                     kind: .action(destructive: false) { [weak self] in self?.chooseStandaloneEmulator(platform) })
        }
        rows.append(PanelRow(id: "retro-show-folders", title: TRetro.text(.retroShowFolders), symbol: "folder",
                             kind: .toggle(showsRetroFolders) { [weak self] value in self?.setShowRetroFolders(value) }))
        return PanelCategory(id: "emulators", title: TRetro.text(.retroEmulators), symbol: "opticaldisc", rows: rows)
    }

    /// A disc's own settings: its emulator and its log, nothing of a PS5 game's. Stop while it
    /// plays, as every game's settings have it here.
    func retroGameRows(_ game: Game, _ disc: RetroDisc) -> [PanelRow] {
        var rows = [
            PanelRow(id: "retro-emulator", title: disc.platform.emulator, detail: chosenEmulator(disc.platform), symbol: "app.dashed",
                     kind: .action(destructive: false) { [weak self] in self?.chooseStandaloneEmulator(disc.platform) }),
            PanelRow(id: "log", title: T.text(.openLog), symbol: "doc.text", kind: .action(destructive: false) { [weak self] in self?.openLog(game) }),
        ]
        if case .running = state(of: game) {
            rows.insert(PanelRow(id: "stopGame", title: TH.text(.stopGame), detail: TH.text(.stopGameDetail), symbol: "stop.circle",
                                 kind: .action(destructive: true) { [weak self] in
                self?.closeOverlay()
                self?.stopRunningGame()
            }), at: 0)
        }
        return rows
    }

    /// The emulator's window in front once it is up: macOS gives the front to no application
    /// that another one started without being asked.
    func bringEmulatorFront(_ run: EmulatorRun) {
        guard persists else { return }
        let pid = run.processIdentifier
        Task { @MainActor [weak self] in
            for _ in 0..<40 {
                guard let self, self.emulator?.run === run else { return }
                if let app = NSRunningApplication(processIdentifier: pid), app.isFinishedLaunching {
                    NSApp.yieldActivation(to: app)
                    app.activate()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
