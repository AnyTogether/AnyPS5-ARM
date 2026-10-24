import AnyPS5Core
import AppKit
import SwiftUI

/// The engine picker: which AnyPS5 toolkit (relinker, system libraries, MoltenVK, patches)
/// unlocks the games. The one inside the app, one downloaded from a release, or a folder the
/// user built; a default for every game and a choice per game. A game unlocked with another
/// engine than its own offers Update and Play.
extension AppModel {
    // MARK: Choosing

    func engineChoice(for game: Game) -> EngineChoice {
        EngineChoice.resolve(game: settings(for: game).engine, default: preferences.engine)
    }

    var defaultEngine: EngineChoice { EngineChoice(stored: preferences.engine) }

    /// The toolkit that unlocks the game now.
    func toolkit(for game: Game) -> Toolkit? {
        engineChoice(for: game).toolkit(builtIn: builtInToolkit, custom: customToolkit, installed: installedToolkits)
    }

    /// The version of that toolkit, without touching the disk for a downloaded one.
    func engineVersion(for game: Game) -> String? {
        engineVersion(of: engineChoice(for: game))
    }

    func engineVersion(of choice: EngineChoice) -> String? {
        switch choice {
        case .builtIn: return builtInToolkit?.version
        case .custom: return (customToolkit ?? builtInToolkit)?.version
        case .downloaded(let version): return installedToolkits.contains { $0.version == version } ? version : builtInToolkit?.version
        }
    }

    /// The engines at hand, in the order the choices list them.
    /// A download of the very toolkit inside the app is not listed twice.
    var engineOptions: [EngineChoice] {
        [.builtIn] + installedToolkits.filter { $0.version != builtInToolkit?.version }.map { .downloaded($0.version) } + (customToolkit == nil ? [] : [.custom])
    }

    func engineName(_ choice: EngineChoice) -> String {
        switch choice {
        case .builtIn: return TE.format(.engineBuiltIn, builtInToolkit.map { Toolkit.shortVersion($0.version) } ?? "—")
        case .custom: return TE.format(.engineCustomName, customToolkit.map { Toolkit.shortVersion($0.version) } ?? "—")
        case .downloaded(let version): return Toolkit.shortVersion(version)
        }
    }

    /// The downloaded versions chosen somewhere: as the default or by a game.
    var enginesInUse: Set<String> {
        var used = Set<String>()
        if case .downloaded(let version) = defaultEngine { used.insert(version) }
        for settings in preferences.games.values {
            if case .downloaded(let version) = EngineChoice(stored: settings.engine), settings.engine != nil { used.insert(version) }
        }
        return used
    }

    // MARK: Loading and downloading

    /// The downloaded toolkits, the catalogue as last seen and the custom folder, from disk.
    func loadEngines() {
        installedToolkits = toolkitStore.installed()
        if let cached = toolkitStore.cachedCatalogue() {
            engineCatalogue = cached.entries
            engineChecked = cached.checked
        }
        loadCustomToolkit()
    }

    /// A folder without version.txt is named by hashing it, so it is read off the main thread.
    func loadCustomToolkit() {
        guard let path = preferences.customToolkit else { customToolkit = nil; return }
        Task.detached(priority: .utility) {
            let root = URL(fileURLWithPath: path)
            let toolkit = Toolkit.layoutProblem(at: root) == nil ? Toolkit(root: root) : nil
            await MainActor.run { if self.preferences.customToolkit == path { self.customToolkit = toolkit } }
        }
    }

    /// Asks GitHub for the releases' toolkits; on its own at most every half hour and only while
    /// update checks are on, `told` (the Check for Engines row) at once, saying when GitHub did
    /// not answer.
    func refreshEngines(told: Bool = false) {
        guard persists, !checkingEngines else { return }
        if !told, preferences.checkUpdates == false { return }
        if !told, !engineOffline, let checked = engineChecked, Date().timeIntervalSince(checked) < 30 * 60 { return }
        checkingEngines = true
        let store = toolkitStore
        Task { @MainActor in
            let found = await EngineCatalogue.fetch()
            self.checkingEngines = false
            if let found {
                let now = Date()
                self.engineCatalogue = found
                self.engineChecked = now
                self.engineOffline = false
                store.saveCatalogue(found, checked: now)
            } else {
                self.engineOffline = true
                if told { self.show(TE.text(.engineCheckFailed), symbol: "wifi.exclamationmark") }
            }
        }
    }

    func downloadEngine(_ entry: EngineCatalogue.Entry) {
        guard engineDownloads[entry.release] == nil else { return }
        engineDownloads[entry.release] = 0
        let store = toolkitStore
        let current = AppModel.runningVersion
        Task { @MainActor in
            do {
                let installed = try await store.download(entry, launcherVersion: current) { fraction in
                    Task { @MainActor in if self.engineDownloads[entry.release] != nil { self.engineDownloads[entry.release] = fraction } }
                }
                self.engineDownloads[entry.release] = nil
                self.installedToolkits = store.installed()
                Sounds.shared.play(.unlocked)
                self.show(TE.format(.engineReady, Toolkit.shortVersion(installed.version)), symbol: "checkmark.seal.fill")
            } catch {
                self.engineDownloads[entry.release] = nil
                self.show(TE.text(.engineDownloadFailed) + ": " + error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func deleteEngine(_ version: String) {
        guard !enginesInUse.contains(version) else { return show(TE.text(.engineInUseNoDelete), symbol: "exclamationmark.triangle.fill") }
        try? toolkitStore.remove(version: version)
        installedToolkits = toolkitStore.installed()
        show(TE.format(.engineDeleted, Toolkit.shortVersion(version)), symbol: "trash")
    }

    func deleteUnusedEngines() {
        let removed = toolkitStore.removeUnused(keeping: enginesInUse)
        installedToolkits = toolkitStore.installed()
        show(removed.isEmpty ? TE.text(.engineNothingUnused) : TE.format(.engineDeleted, removed.map(Toolkit.shortVersion).joined(separator: ", ")), symbol: "trash")
    }

    func chooseEngineFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = TE.text(.engineFolderPick)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let problem = Toolkit.layoutProblem(at: url) {
            return show(TE.format(.engineFolderInvalid, problem), symbol: "exclamationmark.triangle.fill")
        }
        preferences.customToolkit = url.path
        loadCustomToolkit()
        show(TE.format(.engineFolderUsed, url.abbreviatedPath), symbol: "folder.badge.gearshape")
    }

    func forgetEngineFolder() {
        preferences.customToolkit = nil
        customToolkit = nil
    }

    // MARK: Rows

    /// Settings → Engine.
    func engineRows() -> [PanelRow] {
        let options = engineOptions
        let current = options.firstIndex(of: defaultEngine) ?? 0
        var rows: [PanelRow] = [
            PanelRow(id: "engineDefault", title: TE.text(.engineDefault), detail: TE.text(.engineDefaultDetail), symbol: "gearshape.2",
                     kind: .choice(options: options.map(engineName), selected: current) { [weak self] index in
                         self?.preferences.engine = options[index].stored
                     }),
        ]
        let used = enginesInUse
        let notes = Dictionary(engineCatalogue.map { ($0.release, $0) }, uniquingKeysWith: { first, _ in first })
        if !installedToolkits.isEmpty {
            rows.append(PanelRow(id: "engineDownloaded", title: TE.text(.engineDownloadedSection), kind: .info("")))
            for installed in installedToolkits {
                let built = installed.manifest.built.map { TE.format(.engineBuilt, $0.formatted(date: .abbreviated, time: .omitted)) }
                let state = used.contains(installed.version) ? TE.text(.engineInUse) : TE.text(.engineDeleteHint)
                let detail = [built, notes[installed.release]?.summary.nilIfEmpty, state].compactMap { $0 }.joined(separator: " · ")
                rows.append(PanelRow(id: "engine-" + installed.version, title: Toolkit.shortVersion(installed.version), detail: detail,
                                     symbol: used.contains(installed.version) ? "checkmark.seal.fill" : "shippingbox",
                                     kind: .action(destructive: !used.contains(installed.version)) { [weak self] in self?.deleteEngine(installed.version) }))
            }
            let unused = installedToolkits.filter { !used.contains($0.version) }.count
            if unused > 0 {
                rows.append(PanelRow(id: "engineDeleteUnused", title: TE.text(.engineDeleteUnused), detail: TE.format(.engineDeleteUnusedDetail, unused), symbol: "trash",
                                     kind: .action(destructive: true) { [weak self] in self?.deleteUnusedEngines() }))
            }
        }
        rows.append(PanelRow(id: "engineAvailable", title: TE.text(.engineAvailableSection), kind: .info("")))
        // The release the app itself comes from carries the built-in toolkit.
        let downloaded = Set(installedToolkits.map(\.release) + [builtInToolkit.map { Toolkit.release(of: $0.version) }].compactMap { $0 })
        for entry in engineCatalogue where !downloaded.contains(entry.release) {
            let date = entry.date?.formatted(date: .abbreviated, time: .omitted)
            let detail = engineDownloads[entry.release].map { TE.format(.engineDownloading, Int($0 * 100)) }
                ?? [date, entry.summary.nilIfEmpty ?? TE.text(.engineDownloadHint)].compactMap { $0 }.joined(separator: " · ")
            let title = entry.release + (entry.prerelease ? " · " + TE.text(.enginePrerelease) : "")
            rows.append(PanelRow(id: "engineGet-" + entry.release, title: title, detail: detail,
                                 symbol: engineDownloads[entry.release] == nil ? "arrow.down.circle" : "arrow.down.circle.dotted",
                                 kind: .action(destructive: false) { [weak self] in self?.downloadEngine(entry) }))
        }
        let checked: String
        if checkingEngines {
            checked = TE.text(.engineChecking)
        } else if let date = engineChecked {
            let when = date.formatted(date: .abbreviated, time: .shortened)
            checked = engineOffline ? TE.format(.engineOffline, when) : engineCatalogue.isEmpty ? TE.text(.engineNoneYet) : TE.format(.engineChecked, when)
        } else {
            checked = engineOffline ? TE.text(.engineCheckFailed) : TE.text(.engineNeverChecked)
        }
        rows.append(PanelRow(id: "engineRefresh", title: TE.text(.engineRefresh), detail: checked, symbol: "arrow.triangle.2.circlepath",
                             kind: .action(destructive: false) { [weak self] in self?.refreshEngines(told: true) }))
        rows.append(PanelRow(id: "engineCustom", title: TE.text(.engineCustomSection), kind: .info("")))
        rows.append(PanelRow(id: "engineFolder", title: TE.text(.engineFolder),
                             detail: preferences.customToolkit.map { URL(fileURLWithPath: $0).abbreviatedPath + (customToolkit.map { " · " + Toolkit.shortVersion($0.version) } ?? "") } ?? TE.text(.engineFolderNone),
                             symbol: "folder.badge.gearshape", kind: .action(destructive: false) { [weak self] in self?.chooseEngineFolder() }))
        if preferences.customToolkit != nil {
            rows.append(PanelRow(id: "engineFolderReset", title: TE.text(.engineFolderReset), symbol: "xmark.circle", kind: .action(destructive: false) { [weak self] in self?.forgetEngineFolder() }))
        }
        rows.append(PanelRow(id: "engineHint", title: TE.text(.engineHint), kind: .info("")))
        return rows
    }

    /// A game's engine: the default, or one of its own; the detail says which unlocked it.
    func gameEngineRow(_ game: Game) -> PanelRow {
        let options = engineOptions
        let own = settings(for: game).engine.map(EngineChoice.init(stored:))
        let selected = own.map { choice in options.firstIndex(of: choice).map { $0 + 1 } ?? 1 } ?? 0
        let names = [TE.format(.engineFollow, engineName(defaultEngine))] + options.map(engineName)
        let detail: String
        if let record = installedRecords[game.id] {
            detail = TE.format(.engineUnlockedWith, Toolkit.shortVersion(record.toolkit))
        } else {
            detail = TE.text(.engineNotUnlocked)
        }
        return PanelRow(id: "engine", title: TE.text(.engineTitle), detail: detail, symbol: "gearshape.2",
                        kind: .choice(options: names, selected: selected) { [weak self] index in
                            self?.update(game) { $0.engine = index == 0 ? nil : options[index - 1].gameStored }
                        })
    }

    /// Fills the engine picker without the disk or GitHub (offscreen previews).
    func previewEngines(installed: [InstalledToolkit], catalogue: [EngineCatalogue.Entry], checked: Date?, downloads: [String: Double] = [:], custom: Toolkit? = nil) {
        installedToolkits = installed
        engineCatalogue = catalogue
        engineChecked = checked
        engineDownloads = downloads
        customToolkit = custom
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
