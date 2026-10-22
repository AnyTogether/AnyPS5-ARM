import AnyPS5Core
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the user chose, kept in UserDefaults.
struct Preferences: Codable, Equatable {
    enum Backdrop: String, Codable { case theme, image, video }

    var onboarded = false
    var language = Language.system
    var theme = Theme.cosmic
    var accent: AccentColor?
    var backdrop = Backdrop.theme
    var backdropFile: String?
    var gameArtwork = true
    var reducedMotion = false
    var sounds = true
    var hideWhilePlaying = false
    /// The running game on the user's Discord profile; nil means on.
    var discordPresence: Bool?
    var profileName = NSFullUserName().components(separatedBy: " ").first ?? "Player"
    var gamesFolder: String?
    /// Where F12 saves screenshots, nil for ~/Pictures/AnyPS5.
    var screenshotsFolder: String?
    /// Console system font files for the games (ANYPS5_SYSTEM_FONTS), nil for none.
    var fontsFolder: String?
    var games: [String: GameSettings] = [:]
    var lastPlayed: [String: Date] = [:]

    var accentColor: Color { (accent ?? theme.defaultAccent).color }

    static let key = "AnyPS5.preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Preferences.key) }
    }
}

enum GameState: Equatable {
    case unreadable
    case locked
    case queued
    case installing(step: Installer.Step, fraction: Double)
    case failed(String)
    case installed(outdated: Bool)
    case starting
    case running
}

enum HomeFocus: Equatable {
    case top(Int)
    case tiles
    case actions(Int)
}

enum Overlay: Equatable {
    case settings
    case gameSettings
    case library
    case log
    case confirmUninstall
    case controls
    case trophies
    case advanced
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            if persists { preferences.save() }
            apply()
        }
    }
    /// Off for the offscreen previews, which must not touch the user's settings.
    let persists: Bool
    @Published private(set) var games: [Game] = []
    @Published private(set) var scanning = false
    @Published var selected = 0
    @Published var focus = HomeFocus.tiles
    @Published var overlay: Overlay?
    @Published var panelCategory = 0
    @Published var panelRow = 0
    @Published var panelInRows = false
    /// The pad action waiting for a key in the controls panel.
    @Published var capturing: PadAction?
    @Published var libraryIndex = 0
    /// The focused row of the trophy list.
    @Published var trophyIndex = 0
    @Published var onboardingStep = 0
    @Published var onboardingChoices: [Int: Int] = [:]
    @Published private(set) var progress: [String: (Installer.Step, Double)] = [:]
    @Published private(set) var queue: [String] = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var running: (game: Game, app: NSRunningApplication)?
    /// The game from the press of Play until its first window shows.
    @Published private(set) var starting: Game?
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var installedRecords: [String: InstallRecord] = [:]
    @Published private(set) var trophies: [String: TrophySet] = [:]
    /// Why each game stopped the last time it was started, when it stopped on an error.
    @Published private(set) var diagnoses: [String: Diagnosis] = [:]
    @Published var toast: Toast?
    @Published var active = true
    @Published private(set) var rosettaMissing = false
    @Published private(set) var logText = ""
    @Published var translocated = AppLocation.isTranslocated

    let toolkit = Toolkit.locate()
    private var installer: Installer?
    private var installLog: [String: [String]] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var lastScan = Date.distantPast
    private var trophiesRead: Set<String> = []
    private let discord = DiscordPresence(applicationID: DiscordPresence.anyps5ApplicationID)
    private var starts: [String: Date] = [:]
    private var toastTask: Task<Void, Never>?
    private var startWatch: Task<Void, Never>?
    private var exitWatch: DispatchSourceProcess?

    init(preferences: Preferences? = nil) {
        self.persists = preferences == nil
        self.preferences = preferences ?? Preferences.load()
        apply()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.active = true
                if let self, Date().timeIntervalSince(self.lastScan) > 3 { self.rescan() }
                if let self, let game = self.selectedGame { self.loadTrophies(game, again: true) }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.active = false }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            if let pid, Self.isAlive(pid) { return }
            MainActor.assumeIsolated { self?.applicationEnded(pid) }
        }
        Task.detached {
            let missing = !Rosetta.installed
            await MainActor.run { self.rosettaMissing = missing }
        }
        if self.preferences.onboarded && persists { rescan() }
    }

    /// Fills the library at once (offscreen previews).
    func preview(games: [Game], root: URL) {
        self.games = games
        installedRecords = Dictionary(uniqueKeysWithValues: games.compactMap { game in Installer.record(of: Installer.bundle(for: game, root: root)).map { (game.id, $0) } })
        for game in games {
            sizes[game.id] = GameLibrary.size(of: game.folder)
            trophies[game.id] = Trophies.load(game, bundle: Installer.bundle(for: game, root: root), languages: trophyLanguages(game))
            trophiesRead.insert(game.id)
        }
    }

    func previewProgress(_ game: Game, step: Installer.Step, fraction: Double) {
        progress[game.id] = (step, fraction)
    }

    func previewStarting(_ game: Game) {
        starting = game
    }

    private func apply() {
        T.language = preferences.language
        Motion.reduced = preferences.reducedMotion
        Sounds.shared.enabled = preferences.sounds
    }

    var accent: Color { preferences.accentColor }
    var root: URL? { preferences.gamesFolder.map { URL(fileURLWithPath: $0) } }
    var selectedGame: Game? { games.indices.contains(selected) ? games[selected] : nil }

    // MARK: Library

    func rescan() {
        guard let root else { return }
        lastScan = Date()
        scanning = true
        if installer == nil { Installer.removeLeftovers(root: root) }
        let current = selectedGame?.id
        Task.detached(priority: .userInitiated) {
            let found = GameLibrary.scan(root)
            let records = Dictionary(uniqueKeysWithValues: found.compactMap { game in Installer.record(of: Installer.bundle(for: game, root: root)).map { (game.id, $0) } })
            await MainActor.run {
                self.games = found
                self.installedRecords = records
                self.scanning = false
                if let current, let index = found.firstIndex(where: { $0.id == current }) { self.selected = index } else { self.selected = min(self.selected, max(0, found.count - 1)) }
                self.measureSelected()
            }
        }
        watch(root)
    }

    private func watch(_ root: URL) {
        watcher?.cancel()
        let descriptor = Darwin.open(root.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastScan) > 2, self.progress.isEmpty else { return }
                self.rescan()
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher = source
    }

    func chooseFolder(_ url: URL) {
        preferences.gamesFolder = url.path
        selected = 0
        rescan()
    }

    func measureSelected() {
        guard let game = selectedGame else { return }
        loadTrophies(game)
        guard sizes[game.id] == nil else { return }
        sizes[game.id] = -1
        Task.detached(priority: .utility) {
            let size = GameLibrary.size(of: game.folder)
            await MainActor.run { self.sizes[game.id] = size }
        }
    }

    func state(of game: Game) -> GameState {
        if starting?.id == game.id { return .starting }
        if running?.game.id == game.id { return .running }
        if let (step, fraction) = progress[game.id] { return .installing(step: step, fraction: fraction) }
        if queue.contains(game.id) { return .queued }
        if let failure = failures[game.id] { return .failed(failure) }
        if let record = installedRecords[game.id] { return .installed(outdated: toolkit.map { $0.version != record.toolkit } ?? false) }
        if game.executable == .unreadable { return .unreadable }
        return .locked
    }

    // MARK: Trophies

    /// Reads the game's trophies once, or `again` after it may have unlocked some.
    func loadTrophies(_ game: Game, again: Bool = false) {
        guard let root, again || !trophiesRead.contains(game.id) else { return }
        trophiesRead.insert(game.id)
        let bundle = Installer.bundle(for: game, root: root)
        let languages = trophyLanguages(game)
        Task.detached(priority: .utility) {
            let set = Trophies.load(game, bundle: bundle, languages: languages)
            await MainActor.run { self.trophies[game.id] = set }
        }
    }

    /// The trophy texts follow the language the game runs in.
    private func trophyLanguages(_ game: Game) -> [String] {
        let number = settings(for: game).language ?? preferences.language.consoleLanguage
        return ConsoleLanguage.tag(number).map { [$0] } ?? []
    }

    func settings(for game: Game) -> GameSettings {
        preferences.games[game.id] ?? GameSettings()
    }

    func update(_ game: Game, _ change: (inout GameSettings) -> Void) {
        var value = settings(for: game)
        let language = value.language
        change(&value)
        preferences.games[game.id] = value
        if value.language != language { loadTrophies(game, again: true) }
    }

    /// Where a game's keyboard and mouse layout is written before it starts.
    static func inputFile(for game: Game) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnyPS5/Controls/\(game.id).ini")
    }

    // MARK: Controls

    func startCapture(_ action: PadAction) {
        capturing = action
        Sounds.shared.play(.select)
        Input.shared.capture = { [weak self] event in
            guard let self else { return false }
            if event.type == .keyDown && event.keyCode == 53 {
                self.endCapture()
                Sounds.shared.play(.back)
                return true
            }
            guard let name = Controls.keyName(forKeyCode: event.keyCode) else { return true }
            if event.type == .flagsChanged && !Input.pressesModifier(event) { return true }
            self.assign("KEY:\(name)", to: action)
            return true
        }
    }

    func endCapture() {
        capturing = nil
        Input.shared.capture = nil
    }

    private func assign(_ key: String, to action: PadAction) {
        guard let game = selectedGame else { return endCapture() }
        update(game) { settings in
            let changes = Controls.assign(key, to: action, settings.controls ?? [:])
            settings.controls = changes.isEmpty ? nil : changes
        }
        endCapture()
        Sounds.shared.play(.move)
    }

    func resetControls(_ game: Game) {
        update(game) { $0.controls = nil }
    }

    func resolutionChoices(for game: Game) -> [String] {
        guard let toolkit, let patches = GamePatches.load(titleID: game.titleID, from: toolkit.patches) else { return [] }
        return patches.resolution?.choices ?? []
    }

    // MARK: Unlocking

    func unlock(_ game: Game) {
        guard let root else { return }
        guard toolkit != nil else { show(T.text(.noToolkit), symbol: "exclamationmark.triangle"); return }
        failures[game.id] = nil
        guard !queue.contains(game.id), progress[game.id] == nil else { return }
        queue.append(game.id)
        Sounds.shared.play(.select)
        startNext(root: root)
    }

    private func startNext(root: URL) {
        guard installer == nil, let toolkit, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let game = games.first(where: { $0.id == id }) else { startNext(root: root); return }
        progress[id] = (.unwrap, 0)
        installLog[id] = []
        let installer = Installer(game: game, toolkit: toolkit, progress: { step, fraction in
            Task { @MainActor in
                // The relinker reports thousands of times; the bar moves in visible steps.
                guard let current = self.progress[id] else { return }
                if current.0 != step || abs(current.1 - fraction) >= 0.005 || fraction >= 1 { self.progress[id] = (step, fraction) }
            }
        }, log: { line in
            Task { @MainActor in
                self.installLog[id, default: []].append(line)
                if self.installLog[id]!.count > 600 { self.installLog[id]!.removeFirst(100) }
            }
        })
        self.installer = installer
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error> = Result { try installer.run(root: root) }
            await MainActor.run {
                self.installer = nil
                self.progress[id] = nil
                switch result {
                case .success(let bundle):
                    if let record = Installer.record(of: bundle) { self.installedRecords[id] = record }
                    Sounds.shared.play(.unlocked)
                    self.show(game.name + " · " + T.text(.ready), symbol: "lock.open.fill")
                case .failure(let error) where error is CancellationError:
                    break
                case .failure(let error):
                    self.failures[id] = error.localizedDescription
                    self.show(T.text(.unlockFailed) + ": " + game.name, symbol: "exclamationmark.triangle.fill")
                }
                self.startNext(root: root)
            }
        }
    }

    func cancelUnlock(_ game: Game) {
        if let index = queue.firstIndex(of: game.id) { queue.remove(at: index); return }
        if progress[game.id] != nil { installer?.cancel() }
        Sounds.shared.play(.back)
    }

    func uninstall(_ game: Game) {
        guard let root else { return }
        try? FileManager.default.removeItem(at: Installer.bundle(for: game, root: root))
        installedRecords[game.id] = nil
        show(T.text(.uninstallDone), symbol: "trash")
    }

    func clearShaderCache(_ game: Game) {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/\(game.bundleIdentifier)")
        try? FileManager.default.removeItem(at: cache)
        show(T.text(.cacheCleared), symbol: "sparkles")
    }

    // MARK: Playing

    func primaryAction(_ game: Game) {
        switch state(of: game) {
        case .installed: play(game)
        case .locked, .failed: unlock(game)
        case .installing, .queued: cancelUnlock(game)
        case .running: running?.app.activate()
        case .starting: break
        case .unreadable: show(T.text(.unreadableDump), symbol: "xmark.octagon")
        }
    }

    func play(_ game: Game) {
        guard let root, starting == nil, running == nil else { return }
        let bundle = Installer.bundle(for: game, root: root)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        let settings = settings(for: game)
        let inputFile = AppModel.inputFile(for: game)
        // Without the file the game keeps the engine's built-in keys.
        let written = (try? settings.writeInputFile(to: inputFile)) != nil
        let screenshots = screenshotsFolder
        try? FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        configuration.environment = settings.environment(launcherLanguage: preferences.language.consoleLanguage, inputFile: written ? inputFile : nil, screenshots: screenshots, fonts: fontsFolder)
        markStart(of: game)
        Sounds.shared.play(.select)
        preferences.lastPlayed[game.id] = Date()
        withAnimation(Motion.overlay) { starting = game }
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { app, error in
            Task { @MainActor in
                guard self.starting?.id == game.id else {
                    app?.forceTerminate()
                    return
                }
                if let app {
                    self.running = (game, app)
                    self.watchTrophies(game)
                    self.watchForExit(of: app.processIdentifier)
                    self.watchForWindow(of: app)
                } else {
                    withAnimation(Motion.overlay) { self.starting = nil }
                    self.show(T.text(.startFailed) + (error.map { ": " + $0.localizedDescription } ?? ""), symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// The process starts long before the game draws anything (Rosetta translates it and the
    /// shaders compile first), so the splash stays up until the game's first window shows.
    /// macOS does not let an app that shows its window that late take the front by itself, so
    /// the launcher hands it over; a window left behind the launcher gets no frames presented.
    private func watchForWindow(of app: NSRunningApplication) {
        startWatch?.cancel()
        let pid = app.processIdentifier
        startWatch = Task {
            let deadline = Date().addingTimeInterval(240)
            while !Task.isCancelled, Date() < deadline, Self.isAlive(pid), !Self.hasWindow(pid) {
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard !Task.isCancelled else { return }
            guard Self.isAlive(pid) else {
                applicationEnded(pid)
                return
            }
            NSApp.yieldActivation(to: app)
            app.activate()
            if let game = running?.game, preferences.discordPresence ?? true { discord.playing(game.name, since: Date()) }
            withAnimation(Motion.overlay) { starting = nil }
            if preferences.hideWhilePlaying { hideWindows() }
        }
    }

    /// A game that dies before it opens a window never checks in with the window server, so
    /// NSWorkspace sends no termination notice for it: the process itself is watched.
    private func watchForExit(of pid: pid_t) {
        exitWatch?.cancel()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.applicationEnded(pid) } }
        source.resume()
        exitWatch = source
        if !Self.isAlive(pid) { applicationEnded(pid) }
    }

    nonisolated private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    private static func hasWindow(_ pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID] as? pid_t) == pid, (window[kCGWindowLayer] as? Int) == 0,
                  let bounds = window[kCGWindowBounds] as? [String: CGFloat] else { return false }
            return (bounds["Width"] ?? 0) > 200 && (bounds["Height"] ?? 0) > 150
        }
    }

    /// Esc on the splash: the game is stopped before it ever shows.
    func cancelStart() {
        guard starting != nil else { return }
        startWatch?.cancel()
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { starting = nil }
        running?.app.forceTerminate()
    }

    private func applicationEnded(_ pid: pid_t?) {
        guard let running, running.app.processIdentifier == pid else { return }
        self.running = nil
        discord.clear()
        loadTrophies(running.game, again: true)
        diagnose(running.game)
        trophyWatch?.cancel()
        trophyWatch = nil
        exitWatch?.cancel()
        exitWatch = nil
        if starting != nil {
            startWatch?.cancel()
            withAnimation(Motion.overlay) { starting = nil }
            startedWithoutWindow = true
        }
        showWindows()
        NSApp.activate(ignoringOtherApps: true)
    }

    func discordOff() { discord.clear() }

    // MARK: Trophy notifications

    private var trophyWatch: Task<Void, Never>?
    private var hiddenWindows: [NSWindow] = []

    /// Checks the game's trophy records every second while it runs and shows each new one at the
    /// top of the screen, over the game.
    private func watchTrophies(_ game: Game) {
        trophyWatch?.cancel()
        guard let root else { return }
        let bundle = Installer.bundle(for: game, root: root)
        let languages = trophyLanguages(game)
        trophyWatch = Task.detached(priority: .utility) {
            var known = Trophies.earned(bundle: bundle)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let now = Trophies.earned(bundle: bundle)
                let fresh = now.subtracting(known)
                known = now
                guard !fresh.isEmpty, let set = Trophies.load(game, bundle: bundle, languages: languages) else { continue }
                let earned = set.trophies.filter { fresh.contains($0.id) }
                await MainActor.run {
                    self.trophies[game.id] = set
                    for trophy in earned { TrophyBanner.shared.show(trophy, sounds: self.preferences.sounds) }
                }
            }
        }
    }

    /// The launcher's windows step aside while a game runs. The app itself stays unhidden: a
    /// hidden app's windows, the trophy banner among them, never show.
    private func hideWindows() {
        hiddenWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
        for window in hiddenWindows { window.orderOut(nil) }
    }

    private func showWindows() {
        for window in hiddenWindows { window.makeKeyAndOrderFront(nil) }
        hiddenWindows = []
    }

    // MARK: Diagnosis

    /// Set when the game that just ended never showed a window, so the toast says it did not start.
    private var startedWithoutWindow = false

    nonisolated static func logFile(for game: Game) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AnyPS5/\(game.titleID).log")
    }

    /// The log line the diagnosis reads from, so only this start's output counts.
    private func markStart(of game: Game) {
        diagnoses[game.id] = nil
        starts[game.id] = Date()
        let file = AppModel.logFile(for: game)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = "\n\(Diagnosis.startMarker) \(ISO8601DateFormatter().string(from: Date())) \(game.titleID)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }

    /// The log of the game's last start, read from the end of its log file.
    nonisolated static func lastSession(of game: Game) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logFile(for: game)) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 4_000_000 ? end - 4_000_000 : 0)
        return Diagnosis.lastSession(String(decoding: handle.readDataToEndOfFile(), as: UTF8.self))
    }

    private func diagnose(_ game: Game) {
        let start = starts[game.id] ?? Date().addingTimeInterval(-600)
        let withoutWindow = startedWithoutWindow
        startedWithoutWindow = false
        Task.detached(priority: .userInitiated) {
            // macOS writes the crash report a moment after the process is gone.
            try? await Task.sleep(for: .seconds(1.5))
            let report = Diagnosis.crashReport(since: start, bundleIdentifier: game.bundleIdentifier)
            let found = Diagnosis.read(session: AppModel.lastSession(of: game), crashReport: report)
            await MainActor.run {
                self.diagnoses[game.id] = found
                if let found {
                    self.show(game.name + ": " + found.summary, symbol: "exclamationmark.triangle.fill")
                } else if withoutWindow {
                    self.show(T.text(.startFailed), symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// Writes a report for a bug report or a Discord message and shows it in Finder.
    func makeReport(_ game: Game) {
        let settings = settings(for: game)
        let diagnosis = diagnoses[game.id]?.summary
        let launcher = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let toolkitVersion = toolkit?.version ?? "none"
        let start = starts[game.id] ?? Date().addingTimeInterval(-86_400)
        Task.detached(priority: .userInitiated) {
            let crash = Diagnosis.crashReport(since: start, bundleIdentifier: game.bundleIdentifier)
            let text = DiagnosticReport.text(game: game, settings: settings, launcherVersion: launcher, toolkitVersion: toolkitVersion,
                                             diagnosis: diagnosis, session: AppModel.lastSession(of: game), crashReport: crash)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AnyPS5/Reports")
            let file = folder.appendingPathComponent("\(game.titleID)-\(formatter.string(from: Date())).txt")
            let written = (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
                && (try? Data(text.utf8).write(to: file)) != nil
            await MainActor.run {
                if written {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    self.show(T.text(.reportSaved), symbol: "doc.badge.checkmark")
                } else {
                    self.show(T.text(.reportFailed), symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    // MARK: Sharing settings

    func exportSettings(_ game: Game) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(game.name) - AnyPS5.json".replacingOccurrences(of: "/", with: "-")
        panel.prompt = T.text(.exportSettings)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SharedSettings(game: game, settings: settings(for: game)).data().write(to: url, options: .atomic)
            show(T.text(.settingsExported), symbol: "square.and.arrow.up")
        } catch {
            show(T.text(.settingsFileFailed), symbol: "exclamationmark.triangle.fill")
        }
    }

    func importSettings(_ game: Game) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = T.text(.importSettings)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let shared = try? SharedSettings.read(data) else {
            show(T.text(.settingsFileFailed), symbol: "exclamationmark.triangle.fill")
            return
        }
        var imported = shared.settings
        // A resolution only applies to the title whose patch offers it.
        if let resolution = imported.resolution, !resolutionChoices(for: game).contains(resolution) { imported.resolution = nil }
        update(game) { $0 = imported }
        show(shared.titleID == game.titleID ? T.text(.settingsImported) : T.format(.settingsImportedOther, shared.game), symbol: "square.and.arrow.down")
    }

    // MARK: Folders

    var screenshotsFolder: URL {
        preferences.screenshotsFolder.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/AnyPS5")
    }

    var fontsFolder: URL? { preferences.fontsFolder.map { URL(fileURLWithPath: $0) } }

    private func chooseDirectory(start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = T.text(.pickFolder)
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseScreenshotsFolder() {
        if let url = chooseDirectory(start: screenshotsFolder) { preferences.screenshotsFolder = url.path }
    }

    func chooseFontsFolder() {
        if let url = chooseDirectory(start: fontsFolder) { preferences.fontsFolder = url.path }
    }

    func showScreenshots() {
        try? FileManager.default.createDirectory(at: screenshotsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(screenshotsFolder)
    }

    // MARK: Files

    func showInFinder(_ game: Game) {
        guard let root else { return }
        let bundle = Installer.bundle(for: game, root: root)
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: bundle.path) ? bundle : game.folder])
    }

    func openLog(_ game: Game) {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AnyPS5/\(game.titleID).log")
        var text = ""
        if let lines = installLog[game.id], !lines.isEmpty { text += lines.joined(separator: "\n") + "\n\n" }
        if let failure = failures[game.id] { text += failure + "\n\n" }
        if let handle = try? FileHandle(forReadingFrom: file) {
            let end = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: end > 60_000 ? end - 60_000 : 0)
            text += String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
            try? handle.close()
        }
        logText = text.isEmpty ? "—" : text
        open(.log)
    }

    // MARK: Overlays and toasts

    func open(_ next: Overlay) {
        panelCategory = 0
        panelRow = 0
        panelInRows = next == .gameSettings || next == .confirmUninstall || next == .controls
        // The controls panel opens on its first key, below the hint.
        if next == .controls { panelRow = 1 }
        if next == .trophies { trophyIndex = 0 }
        if next == .advanced { panelRow = 1 }
        panelInRows = panelInRows || next == .advanced
        withAnimation(Motion.overlay) { overlay = next }
        Sounds.shared.play(.select)
    }

    func closeOverlay() {
        endCapture()
        withAnimation(Motion.overlay) { overlay = nil }
        Sounds.shared.play(.back)
    }

    func show(_ text: String, symbol: String) {
        toastTask?.cancel()
        withAnimation(Motion.overlay) { toast = Toast(text: text, symbol: symbol) }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.overlay) { self.toast = nil }
        }
    }

    func installRosetta() {
        Task.detached {
            let installed = Rosetta.install()
            await MainActor.run { self.rosettaMissing = !installed }
        }
    }
}

enum Rosetta {
    static var installed: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func install() -> Bool {
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil && installed
    }
}
