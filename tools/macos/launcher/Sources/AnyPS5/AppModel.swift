import AnyPS5Core
import AppKit
import SwiftUI

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
    var profileName = NSFullUserName().components(separatedBy: " ").first ?? "Player"
    var gamesFolder: String?
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
    @Published var libraryIndex = 0
    @Published var onboardingStep = 0
    @Published var onboardingChoices: [Int: Int] = [:]
    @Published private(set) var progress: [String: (Installer.Step, Double)] = [:]
    @Published private(set) var queue: [String] = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var running: (game: Game, app: NSRunningApplication)?
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var installedRecords: [String: InstallRecord] = [:]
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
    private var toastTask: Task<Void, Never>?

    init(preferences: Preferences? = nil) {
        self.persists = preferences == nil
        self.preferences = preferences ?? Preferences.load()
        apply()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.active = true
                if let self, Date().timeIntervalSince(self.lastScan) > 3 { self.rescan() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.active = false }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
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
        for game in games { sizes[game.id] = GameLibrary.size(of: game.folder) }
    }

    func previewProgress(_ game: Game, step: Installer.Step, fraction: Double) {
        progress[game.id] = (step, fraction)
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
        guard let game = selectedGame, sizes[game.id] == nil else { return }
        sizes[game.id] = -1
        Task.detached(priority: .utility) {
            let size = GameLibrary.size(of: game.folder)
            await MainActor.run { self.sizes[game.id] = size }
        }
    }

    func state(of game: Game) -> GameState {
        if running?.game.id == game.id { return .running }
        if let (step, fraction) = progress[game.id] { return .installing(step: step, fraction: fraction) }
        if queue.contains(game.id) { return .queued }
        if let failure = failures[game.id] { return .failed(failure) }
        if let record = installedRecords[game.id] { return .installed(outdated: toolkit.map { $0.version != record.toolkit } ?? false) }
        if game.executable == .unreadable { return .unreadable }
        return .locked
    }

    func settings(for game: Game) -> GameSettings {
        preferences.games[game.id] ?? GameSettings()
    }

    func update(_ game: Game, _ change: (inout GameSettings) -> Void) {
        var value = settings(for: game)
        change(&value)
        preferences.games[game.id] = value
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
        case .unreadable: show(T.text(.unreadableDump), symbol: "xmark.octagon")
        }
    }

    func play(_ game: Game) {
        guard let root else { return }
        let bundle = Installer.bundle(for: game, root: root)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.environment = settings(for: game).environment(launcherLanguage: preferences.language.consoleLanguage)
        Sounds.shared.play(.select)
        preferences.lastPlayed[game.id] = Date()
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { app, error in
            Task { @MainActor in
                if let app {
                    self.running = (game, app)
                    if self.preferences.hideWhilePlaying { NSApp.hide(nil) }
                } else {
                    self.show(T.text(.startFailed) + (error.map { ": " + $0.localizedDescription } ?? ""), symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    private func applicationEnded(_ pid: pid_t?) {
        guard let running, running.app.processIdentifier == pid else { return }
        self.running = nil
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        panelInRows = next == .gameSettings || next == .confirmUninstall
        withAnimation(Motion.overlay) { overlay = next }
        Sounds.shared.play(.select)
    }

    func closeOverlay() {
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
