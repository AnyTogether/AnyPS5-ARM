import AnyPS5Core
import AppKit
import SwiftUI

/// What Settings → Steam shows and waits for.
struct SteamState {
    enum Task { case add, remove }

    /// nil until Steam was looked for.
    var installs: [SteamInstall]?
    var accounts: [(install: SteamInstall, user: SteamUser)] = []
    /// AnyPS5's entries in the chosen account now.
    var inSteam = 0
    /// Steam was open when asked: the rows offer to quit it.
    var waiting: Task?
    /// What is going on (quitting Steam, drawing), nil when idle.
    var working: String?
    /// Steam was quit by the launcher to write: the rows offer to open it again.
    var closedSteam = false
}

/// Settings → Steam: AnyPS5 (and, opted in, every unlocked game) as non-Steam games in the Steam
/// library with artwork, for Big Picture and Steam Input. The same flow as the Windows and Linux
/// launcher's (lib/ui/steam_model.dart).
extension AppModel {
    /// The program the shortcuts start: this app's executable.
    var steamProgram: String { Bundle.main.executablePath ?? "/Applications/AnyPS5.app/Contents/MacOS/AnyPS5" }

    func scanSteam() {
        let installs = SteamLocator.find()
        steam.installs = installs
        steam.accounts = installs.flatMap { install in install.users().map { (install, $0) } }
        countSteam()
    }

    var steamAccount: (install: SteamInstall, user: SteamUser)? {
        guard !steam.accounts.isEmpty else { return nil }
        let chosen = preferences.steamUser
        return steam.accounts.first { "\($0.install.root.path)|\($0.user.id)" == chosen } ?? steam.accounts.first
    }

    private var steamShortcuts: SteamShortcuts? { steamAccount.map { SteamShortcuts(install: $0.install, user: $0.user) } }

    private func countSteam() { steam.inSteam = steamShortcuts?.ours().count ?? 0 }

    private func chooseSteamAccount(_ index: Int) {
        guard steam.accounts.indices.contains(index) else { return }
        let account = steam.accounts[index]
        preferences.steamUser = "\(account.install.root.path)|\(account.user.id)"
        countSteam()
    }

    func addToSteam(quitSteam: Bool = false) { runSteam(.add, quitSteam: quitSteam) }
    func removeFromSteam(quitSteam: Bool = false) { runSteam(.remove, quitSteam: quitSteam) }

    private func runSteam(_ task: SteamState.Task, quitSteam: Bool) {
        guard let account = steamAccount, steam.working == nil else { return }
        let control = SteamControl()
        if control.running() {
            // Quitting Steam from a launcher Steam started would end the launcher's session too.
            if steamLaunch.fromSteam {
                steam.waiting = nil
                return show(TSteam.text(.fromSteam), symbol: "exclamationmark.triangle")
            }
            guard quitSteam else {
                steam.waiting = task
                return
            }
            steam.working = TSteam.text(.closing)
            Task { @MainActor in
                let closed = await control.shutdown()
                guard closed else {
                    self.steam.working = nil
                    return self.show(TSteam.text(.wouldNotClose), symbol: "exclamationmark.triangle")
                }
                self.steam.closedSteam = true
                self.writeSteam(task, account: account)
            }
            return
        }
        writeSteam(task, account: account)
    }

    private func writeSteam(_ task: SteamState.Task, account: (install: SteamInstall, user: SteamUser)) {
        steam.waiting = nil
        steam.working = TSteam.text(.working)
        // A turn of the run loop first, so the row says what is going on while the art is drawn.
        DispatchQueue.main.async { [weak self] in self?.finishSteam(task, account: account) }
    }

    private func finishSteam(_ task: SteamState.Task, account: (install: SteamInstall, user: SteamUser)) {
        let shortcuts = SteamShortcuts(install: account.install, user: account.user)
        do {
            switch task {
            case .add:
                let fullscreen = preferences.steamFullscreen ?? true
                let program = steamProgram
                let games = (preferences.steamGames ?? false) ? self.games.filter { installedRecords[$0.id] != nil } : []
                var entries = [SteamEntry(SteamPlan.launcher(program: program, fullscreen: fullscreen, into: shortcuts),
                                          art: SteamArtist.launcher(accent: accent).compactMapValues { $0 })]
                for game in games {
                    entries.append(SteamEntry(SteamPlan.game(program: program, name: game.name, titleID: game.titleID, fullscreen: fullscreen, into: shortcuts),
                                              art: SteamArtist.game(name: game.name, background: game.background, cover: game.icon, accent: accent).compactMapValues { $0 }))
                }
                try shortcuts.put(entries)
                show(TSteam.format(.added, games.isEmpty ? TSteam.text(.inSteamLauncher) : TSteam.format(.inSteamGames, games.count)), symbol: "checkmark.circle")
            case .remove:
                let change = try shortcuts.remove()
                show(TSteam.text(change.appIDs.isEmpty ? .nothing : .removed), symbol: "trash")
            }
        } catch {
            show(TSteam.format(.failed, error.localizedDescription), symbol: "exclamationmark.triangle")
        }
        steam.working = nil
        countSteam()
    }

    func steamRows() -> [PanelRow] {
        guard steam.installs != nil else {
            // Not in the offscreen previews: they never read the Mac's own Steam.
            if persists { DispatchQueue.main.async { [weak self] in if self?.steam.installs == nil { self?.scanSteam() } } }
            return [PanelRow(id: "steamLooking", title: TSteam.text(.title), symbol: "magnifyingglass", kind: .info(TSteam.text(.looking)))]
        }
        guard let account = steamAccount else {
            return [PanelRow(id: "steamMissing", title: TSteam.text(.notFound), symbol: "questionmark.circle", kind: .info(TSteam.text(.notFoundDetail)))]
        }
        let count = steam.inSteam
        var rows: [PanelRow] = [
            PanelRow(id: "steamWhere", title: TSteam.text(.title), symbol: "folder", kind: .info(account.install.root.abbreviatedPath)),
        ]
        if steam.accounts.count > 1 {
            rows.append(PanelRow(id: "steamAccount", title: TSteam.text(.account), symbol: "person.crop.circle",
                                 kind: .choice(options: steam.accounts.map(\.user.label), selected: steam.accounts.firstIndex { $0.install == account.install && $0.user == account.user } ?? 0) { [weak self] index in
                self?.chooseSteamAccount(index)
            }))
        } else {
            rows.append(PanelRow(id: "steamAccount", title: TSteam.text(.account), symbol: "person.crop.circle", kind: .info(account.user.label)))
        }
        rows.append(PanelRow(id: "steamInSteam", title: TSteam.text(.inSteam), symbol: "books.vertical",
                             kind: .info(count == 0 ? TSteam.text(.notInSteam) : count == 1 ? TSteam.text(.inSteamLauncher) : TSteam.format(.inSteamGames, count - 1))))
        rows.append(PanelRow(id: "steamGames", title: TSteam.text(.games), detail: TSteam.text(.gamesDetail), symbol: "square.stack",
                             kind: .toggle(preferences.steamGames ?? false) { [weak self] value in self?.preferences.steamGames = value }))
        rows.append(PanelRow(id: "steamFullscreen", title: TSteam.text(.fullscreen), symbol: "arrow.up.left.and.arrow.down.right",
                             kind: .toggle(preferences.steamFullscreen ?? true) { [weak self] value in self?.preferences.steamFullscreen = value }))
        if let working = steam.working {
            rows.append(PanelRow(id: "steamWorking", title: working, symbol: "hourglass", kind: .info("")))
        } else if let task = steam.waiting {
            rows.append(PanelRow(id: "steamRunning", title: TSteam.text(.running), symbol: "exclamationmark.triangle", kind: .info(TSteam.text(.runningDetail))))
            rows.append(PanelRow(id: "steamClose", title: TSteam.text(task == .add ? .closeAndAdd : .closeAndRemove), symbol: "power",
                                 kind: .action(destructive: task == .remove) { [weak self] in
                task == .add ? self?.addToSteam(quitSteam: true) : self?.removeFromSteam(quitSteam: true)
            }))
            rows.append(PanelRow(id: "steamCancel", title: T.text(.cancel), kind: .action(destructive: false) { [weak self] in self?.steam.waiting = nil }))
        } else {
            rows.append(PanelRow(id: "steamAdd", title: TSteam.text(count > 0 ? .update : .add), detail: TSteam.text(.addDetail), symbol: "plus.app",
                                 kind: .action(destructive: false) { [weak self] in self?.addToSteam() }))
            if steam.closedSteam {
                rows.append(PanelRow(id: "steamOpen", title: TSteam.text(.open), symbol: "arrow.up.forward.app", kind: .action(destructive: false) { [weak self] in
                    self?.steam.closedSteam = false
                    if let url = URL(string: "steam://open/games") { NSWorkspace.shared.open(url) }
                }))
            }
            if count > 0 {
                rows.append(PanelRow(id: "steamRemove", title: TSteam.text(.remove), detail: TSteam.text(.removeDetail), symbol: "trash",
                                     kind: .action(destructive: true) { [weak self] in self?.removeFromSteam() }))
            }
        }
        return rows
    }
}
