import AnyPS5Core
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// What the user chose, kept in UserDefaults.
struct Preferences: Codable, Equatable {
    enum Backdrop: String, Codable { case theme, image, video }

    var onboarded = false
    var language = Language.english
    var theme = Theme.cosmic
    var accent: AccentColor?
    /// A made or installed theme (ThemeDesign id) in place of the built-in theme and accent.
    var customTheme: String?
    var backdrop = Backdrop.theme
    var backdropFile: String?
    var gameArtwork = true
    var reducedMotion = false
    var sounds = true
    /// Interface sounds and the selected game's theme song, in percent; nil keeps the default.
    var soundVolume: Int?
    var musicVolume: Int?
    /// nil checks GitHub for a newer launcher, as true does.
    var checkUpdates: Bool?
    var hideWhilePlaying = false
    /// The running game on the user's Discord profile; nil means on.
    var discordPresence: Bool?
    /// Keeping the last seconds of the game playing, to save as a clip (Create, ⌥F12 or the
    /// phone); nil means off. clipLength is in seconds, nil for 30.
    var clips: Bool?
    var clipLength: Int?
    /// Keeping each game's saves in step through a folder other Macs see (SaveSync); nil means
    /// off. syncFolder nil is iCloud Drive.
    var saveSync: Bool?
    var syncFolder: String?
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
    /// Play on a game an older toolkit made: update it first, or play it as it is.
    case updateChoice
    case controls
    case trophies
    case advanced
    /// The selected game's F12 screenshots.
    case gallery
    /// The themes on this Mac and on the Hub, and the Theme Studio.
    case themes
    case studio
    /// Friends on AnyTogether.
    case friends
    /// Someone's AnyTogether profile, the user's own or a friend's.
    case profile
    /// Conversations and their threads on AnyTogether.
    case messages
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
    @Published var galleryIndex = 0
    /// One screenshot over the whole screen, instead of the grid.
    @Published var galleryViewing = false
    @Published private(set) var galleryShots: [URL] = []
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
    /// A phone asking to be allowed, shown over everything until the user answers.
    @Published var pairing: PairingRequest?
    /// The connected phone and its last reported latency.
    @Published private(set) var phone: (name: String, latency: Double?)?
    /// The device IDs of the phones connected now, by player.
    @Published private(set) var connectedPhones: [String] = []
    /// Which player each connected phone is in the game playing, from 1, by device ID.
    @Published private(set) var phonePlayers: [String: Int] = [:]
    /// What each game does with each pad button, by game, read from its own Unreal files the
    /// first time its controls are opened; empty when they say nothing.
    @Published private(set) var gameControls: [String: [PadAction: [String]]] = [:]

    /// The connected phones as the indicator shows them: by player in a game, a phone not
    /// pressed yet with no number; outside a game, numbered as they connected.
    var phoneBadges: [PhoneBadge] {
        if let previewBadges { return previewBadges }
        let playing = running != nil
        let badges = connectedPhones.enumerated().map { slot, id in
            PhoneBadge(id: id, name: phones.first { $0.id == id }?.name ?? id, number: playing ? phonePlayers[id] : slot + 1)
        }
        return badges.sorted { ($0.number ?? .max) < ($1.number ?? .max) }
    }
    /// A phone that said hello and is not connected yet (pairing, or about to be welcomed).
    @Published private(set) var phoneConnecting: String?
    /// The phones allowed so far, for the settings.
    @Published private(set) var phones: [PairedDevice] = []
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
    private let discord = DiscordPresence(applicationID: DiscordPresence.applicationID)
    private var starts: [String: Date] = [:]
    private(set) var remote: RemoteServer?
    /// iPhones on a cable reach the phone server through it, with no Wi-Fi.
    private var cable: UsbTunnel?
    /// Android phones on a cable, through adb when it is installed.
    private var androidCable: AdbTunnel?
    private let pairedDevices = PairedDevices()
    /// The library the phone was told last, and what keeps it told.
    private var phoneLibrary: RemoteMessage?
    private var librarySink: AnyCancellable?
    private var musicSink: AnyCancellable?
    private var updateTimer: Timer?
    /// A newer launcher on GitHub, and how far its download is once asked for.
    @Published private(set) var availableUpdate: Updates.Release?
    @Published private(set) var updateProgress: Double?
    /// The game the phone asked for while another one was still playing.
    private var launchAfterExit: String?
    /// The game to start as soon as its update finishes.
    private var playAfterUnlock: String?
    private var toastTask: Task<Void, Never>?
    private var startWatch: Task<Void, Never>?
    private var exitWatch: DispatchSourceProcess?

    init(preferences: Preferences? = nil) {
        self.persists = preferences == nil
        self.preferences = preferences ?? Preferences.load()
        themes = preferences == nil ? ThemeLibrary() : ThemeLibrary(folder: FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-themes"))
        designs = themes.all
        if persists {
            togetherUser = together.user
            if togetherUser != nil { DispatchQueue.main.async { [weak self] in self?.startTogetherSocket() } }
        }
        apply()
        if persists {
            AppModel.opener = { [weak self] urls in self?.open(urls) }
            let waiting = AppModel.pending
            AppModel.pending = []
            if !waiting.isEmpty { DispatchQueue.main.async { [weak self] in self?.open(waiting) } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.active = true
                if let self, Date().timeIntervalSince(self.lastScan) > 3 { self.rescan() }
                // Coming back to the launcher after a while asks again, so a new release shows
                // without a restart.
                if let self, self.lastUpdateCheck.map({ Date().timeIntervalSince($0) > 30 * 60 }) ?? false { self.checkForUpdate() }
                if let self, let game = self.selectedGame { self.loadTrophies(game, again: true) }
            }
        }
        // The game settings say what Low Power Mode does as soon as it is turned on or off.
        NotificationCenter.default.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
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
        if persists {
            // The theme song follows whatever the launcher shows.
            musicSink = objectWillChange.debounce(for: .milliseconds(120), scheduler: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMusic() }
            }
            startRemote()
            // Once soon after start, then every six hours while the launcher stays open.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                self.checkForUpdate()
            }
            updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkForUpdate() }
            }
            let discord = self.discord
            DiscordGames.load { games in discord.use(games) }
        }
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
        Sounds.shared.volume = Float(preferences.soundVolume ?? 100) / 100
        ThemeMusic.shared.volume = Float(musicVolume) / 100
    }

    static let defaultMusicVolume = 50

    var musicVolume: Int { preferences.musicVolume ?? AppModel.defaultMusicVolume }

    // MARK: Updates

    static var runningVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    func checkForUpdate() {
        guard persists, preferences.checkUpdates ?? true, updateProgress == nil, !checkingUpdates else { return }
        lookUpUpdate(told: false)
    }

    /// Check for Updates in About: at once, whatever the setting, and it says what it found.
    func checkForUpdatesNow() {
        guard updateProgress == nil, !checkingUpdates else { return }
        lookUpUpdate(told: true)
    }

    /// When the launcher last asked GitHub, and whether it is asking now.
    @Published private(set) var lastUpdateCheck: Date?
    @Published private(set) var checkingUpdates = false

    private func lookUpUpdate(told: Bool) {
        let current = AppModel.runningVersion
        checkingUpdates = true
        Task { @MainActor in
            let found = await Updates.lookup(current: current)
            self.checkingUpdates = false
            switch found {
            case .newer(let release):
                self.lastUpdateCheck = Date()
                let first = self.availableUpdate?.tag != release.tag
                self.availableUpdate = release
                if first || told { self.show(T.format(.launcherUpdateAvailable, release.version), symbol: "arrow.down.circle.fill") }
            case .current:
                self.lastUpdateCheck = Date()
                self.availableUpdate = nil
                if told { self.show(T.format(.launcherUpToDate, current), symbol: "checkmark.circle.fill") }
            case .failed:
                if told { self.show(T.text(.updateCheckFailed), symbol: "exclamationmark.triangle.fill") }
            }
        }
    }

    /// Downloads the update, then quits so that it takes this app's place and opens.
    func installUpdate() {
        guard let release = availableUpdate, updateProgress == nil else { return }
        guard running == nil, starting == nil else { return show(T.text(.updateCloseGame), symbol: "exclamationmark.triangle.fill") }
        let app = Bundle.main.bundleURL
        guard !AppLocation.isTranslocated, FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            return show(T.text(.updateNotWritable), symbol: "exclamationmark.triangle.fill")
        }
        updateProgress = 0
        let identifier = Bundle.main.bundleIdentifier ?? "org.anyps5.launcher"
        let current = AppModel.runningVersion
        Task { @MainActor in
            do {
                let new = try await Updates.prepare(release, bundleIdentifier: identifier, current: current) { fraction in
                    Task { @MainActor in self.updateProgress = fraction }
                }
                try Updates.replace(app, with: new, pid: ProcessInfo.processInfo.processIdentifier)
                NSApp.terminate(nil)
            } catch {
                self.updateProgress = nil
                self.show(T.text(.updateFailed) + ": \(error)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The selected game's song while the launcher is in front and idle, silence otherwise.
    private func updateMusic() {
        let quiet = !preferences.onboarded || !active || running != nil || starting != nil || musicVolume == 0
        let menuMusic = activeDesign.flatMap { themes.file($0.music, of: $0) }
        ThemeMusic.shared.play(quiet ? nil : selectedGame, fallback: quiet ? nil : menuMusic)
    }

    var accent: Color { activeDesign.map { Color(rgb: $0.accentRGB) } ?? preferences.accentColor }

    // MARK: AnyTogether

    let together = AppModel.makeTogetherClient()
    @Published var togetherUser: TogetherUser?
    @Published var togetherStep = TogetherStep.idle
    @Published var togetherConnected = false
    var togetherEmail = ""
    var togetherCode = ""
    var togetherSocket: TogetherSocket?
    var togetherWait: Task<Void, Never>?
    var togetherFlush: Task<Void, Never>?
    lazy var togetherSync = TogetherSync(client: together, deviceName: Host.current().localizedName ?? "Mac", model: AppModel.machineModel)
    /// When the running game started, for the play session AnyTogether keeps.
    var sessionStart: Date?
    @Published var togetherFriends: [TogetherFriend] = []
    @Published var togetherRequests = TogetherRequests(incoming: [], outgoing: [])
    var friendHandle = ""
    /// The profile open: who (known before it loads), what came back, and the focused row.
    @Published var profileCard: TogetherPerson?
    @Published var profilePage: TogetherProfilePage?
    @Published var profileFailed = false
    @Published var profileColumn = 0
    @Published var profileIndex = 0
    var profileReturn: ProfileReturn?
    /// The user's own profile with its privacy, and the edits typed in Settings → AnyTogether.
    @Published var togetherProfile: TogetherOwnProfile?
    var profileDraft = ProfileDraft()
    /// Messages: the conversations and threads, the row selected on the left, whether the thread
    /// has the focus (a quick reply, or the field at the end), and whether the field is typed in.
    @Published var inbox: TogetherInbox?
    @Published var messagesIndex = 0
    @Published var messagesInThread = false
    @Published var messageFocus = 0
    @Published var composing = false
    @Published var messageDraft = ""
    var profileTask: Task<Void, Never>?

    // MARK: Themes

    /// Previews keep their themes in a folder of their own.
    let themes: ThemeLibrary
    /// The themes on this Mac, made here or installed.
    @Published var designs: [ThemeDesign] = []
    @Published var hub = HubState.idle

    /// The theme in use, when it is a made or installed one.
    var activeDesign: ThemeDesign? { preferences.customTheme.flatMap { id in designs.first { $0.id == id } } }

    /// The animated background drawn: the made theme's, else the built-in theme.
    var lookStyle: Theme { activeDesign.flatMap { Theme(rawValue: $0.style) } ?? preferences.theme }
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
            await MainActor.run {
                self.trophies[game.id] = set
                if let set { self.recordTrophies(game, set) }
            }
        }
    }

    /// The trophy texts follow the language the game runs in.
    func trophyLanguages(_ game: Game) -> [String] {
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
                    if self.playAfterUnlock == id {
                        self.playAfterUnlock = nil
                        self.play(game)
                    }
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

    /// The update the Play prompt offers: unlock the game again, then start it.
    func updateAndPlay(_ game: Game) {
        playAfterUnlock = game.id
        unlock(game)
    }

    func cancelUnlock(_ game: Game) {
        if playAfterUnlock == game.id { playAfterUnlock = nil }
        if let index = queue.firstIndex(of: game.id) { queue.remove(at: index); return }
        if progress[game.id] != nil { installer?.cancel() }
        Sounds.shared.play(.back)
    }

    func uninstall(_ game: Game) {
        guard let root else { return }
        try? FileManager.default.removeItem(at: Installer.bundle(for: game, root: root))
        try? FileManager.default.removeItem(at: Installer.dataFolder(for: game, root: root))
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
        case .installed(let outdated): outdated ? open(.updateChoice) : play(game)
        case .locked, .failed: unlock(game)
        case .installing, .queued: cancelUnlock(game)
        case .running: running?.app.activate()
        case .starting: break
        case .unreadable: show(T.text(.unreadableDump), symbol: "xmark.octagon")
        }
    }

    /// Plays the game, its saves brought in step first where save sync is on.
    func play(_ game: Game) {
        guard root != nil, starting == nil, running == nil, syncing == nil else { return }
        syncSaves(game) { self.start(game) }
    }

    private func start(_ game: Game) {
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
            .merging(remote?.bridgeEnvironment ?? [:]) { _, phone in phone }
        markStart(of: game)
        Sounds.shared.play(.select)
        preferences.lastPlayed[game.id] = Date()
        withAnimation(Motion.overlay) { starting = game }
        // A bundle made by an older launcher still carries the marks that make macOS verify it.
        Installer.clearMarks(bundle)
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { app, error in
            Task { @MainActor in
                guard self.starting?.id == game.id else {
                    app?.forceTerminate()
                    return
                }
                if let app {
                    self.running = (game, app)
                    self.sessionStart = Date()
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

    // MARK: Links and folders

    /// What macOS hands the app before the model is there, and where it goes once it is.
    private static var pending: [URL] = []
    private static var opener: (([URL]) -> Void)?

    static func received(_ urls: [URL]) {
        if let opener { opener(urls) } else { pending += urls }
    }

    private func open(_ urls: [URL]) {
        guard preferences.onboarded else { return }
        for url in urls {
            if url.isFileURL && url.pathExtension.lowercased() == ThemeDesign.fileExtension {
                installTheme(url)
            } else if url.isFileURL {
                openFolder(url)
            } else if let link = DeepLink(url: url) {
                follow(link)
            }
        }
    }

    private func follow(_ link: DeepLink) {
        bringLauncherFront()
        switch link {
        case .library: open(.library)
        case .settings: open(.settings)
        case .game(let id), .play(let id):
            guard let index = games.firstIndex(where: { $0.titleID == id }) else {
                return show(T.format(.linkNoGame, id), symbol: "questionmark.folder")
            }
            if overlay != nil { closeOverlay() }
            withAnimation(Motion.focus) { selected = index }
            if case .play = link { primaryAction(games[index]) }
        }
    }

    /// A folder opened with AnyPS5: a game in the library is selected; a game or a folder of
    /// games elsewhere becomes the games folder, once the user agrees.
    private func openFolder(_ folder: URL) {
        bringLauncherFront()
        if let index = games.firstIndex(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) {
            if overlay != nil { closeOverlay() }
            withAnimation(Motion.focus) { selected = index }
            return
        }
        let single = GameLibrary.inspect(folder)
        let root = single != nil ? folder.deletingLastPathComponent() : folder
        let found = GameLibrary.scan(root)
        guard !found.isEmpty else { return show(T.text(.folderNoGames), symbol: "questionmark.folder") }
        let alert = NSAlert()
        alert.messageText = T.format(.useGamesFolder, root.lastPathComponent)
        alert.informativeText = T.format(.useGamesFolderDetail, found.count, root.abbreviatedPath)
        alert.addButton(withTitle: T.text(.useGamesFolderConfirm))
        alert.addButton(withTitle: T.text(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        chooseFolder(root)
        if let single, let index = games.firstIndex(where: { $0.titleID == single.titleID }) { selected = index }
    }

    func copyLink(_ game: Game) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DeepLink.game(game.titleID).url.absoluteString, forType: .string)
        show(T.text(.linkCopied), symbol: "link")
    }

    // MARK: Save sync

    /// The game whose saves are being synced, so it does not start twice meanwhile.
    @Published private(set) var syncing: String?

    var syncRoot: URL? { preferences.syncFolder.map { URL(fileURLWithPath: $0) } ?? SaveSync.iCloudDrive }

    private func saveSync(for game: Game) -> SaveSync? {
        guard preferences.saveSync == true, let root = syncRoot, let folder = gameFolder(game) else { return nil }
        return SaveSync(game: folder, cloud: SaveSync.folder(in: root, titleID: game.titleID), backups: SaveBackup.folder(for: game), mac: Host.current().localizedName ?? "Mac")
    }

    /// Syncs the game's saves off the main thread, says what came from another Mac, then goes on.
    private func syncSaves(_ game: Game, then: @escaping @MainActor () -> Void) {
        guard let sync = saveSync(for: game) else { return then() }
        syncing = game.id
        Task.detached {
            let result = Result { try sync.sync(date: Date()) }
            await MainActor.run {
                self.syncing = nil
                switch result {
                case .success(.downloaded(let mac)): self.show(T.format(.savesSyncedFrom, mac), symbol: "icloud.and.arrow.down")
                case .failure(let error): self.show(T.text(.saveSyncFailed) + ": \(error)", symbol: "exclamationmark.icloud")
                default: break
                }
                then()
            }
        }
    }

    func chooseSyncFolder() {
        if let url = chooseDirectory(start: syncRoot) {
            preferences.syncFolder = url.path
            preferences.saveSync = true
        }
    }

    // MARK: Remote Play

    let remotePlay = RemotePlay()
    /// The running game has a window to send.
    private var gameWindowShown = false

    /// Sends the running game to the phones that ask for it, at the largest size one asked for
    /// up to 720p; stops when none asks or no game plays.
    func updateRemotePlay() {
        guard let remote else { return }
        let wishes = remote.streamWishes
        guard !wishes.isEmpty else {
            remotePlay.stop()
            return
        }
        guard let pid = running?.app.processIdentifier, gameWindowShown else {
            remotePlay.stop()
            for wish in wishes { remote.tell(.streaming(state: "noGame"), deviceID: wish.deviceID) }
            return
        }
        // The phone's long side across: the size it asked for, no more than 1280 x 720.
        let height = min(720, wishes.map { min($0.width, $0.height) }.max() ?? 720)
        let width = min(1280, wishes.map { max($0.width, $0.height) }.max() ?? 1280)
        Task { @MainActor in
            do {
                try await self.remotePlay.start(pid: pid, width: width, height: height) { [weak remote] packets in remote?.sendStream(packets) }
                for wish in wishes { remote.tell(.streaming(state: "on"), deviceID: wish.deviceID) }
            } catch RemotePlay.Failure.noPermission {
                for wish in wishes { remote.tell(.streaming(state: "noPermission"), deviceID: wish.deviceID) }
                TrophyBanner.shared.notice(T.text(.remotePlayPermissionTitle), detail: T.text(.remotePlayNeedsPermission), symbol: "iphone.gen3", sounds: self.preferences.sounds)
            } catch {
                // `log stream --predicate 'subsystem == "org.anyps5.launcher"'` shows why.
                RemoteServer.log.error("remote play: \(String(describing: error), privacy: .public)")
                for wish in wishes { remote.tell(.streaming(state: "noGame"), deviceID: wish.deviceID) }
            }
        }
    }

    // MARK: Clips

    let clipRecorder = ClipRecorder()
    var clipSeconds: Int { preferences.clipLength ?? 30 }

    /// With clips on, the game that just showed its window is kept from now on.
    private func startClips(for app: NSRunningApplication) {
        guard preferences.clips == true else { return }
        let pid = app.processIdentifier
        let seconds = Double(clipSeconds)
        Task { @MainActor in
            do {
                try await self.clipRecorder.start(pid: pid, length: seconds)
            } catch ClipRecorder.Failure.noPermission {
                TrophyBanner.shared.notice(T.text(.clipsNeedPermission), detail: T.text(.clipsNeedPermissionDetail), symbol: "record.circle", sounds: self.preferences.sounds)
            } catch {
                self.show(T.text(.clipFailed) + ": \(error)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Clips turned on: macOS asks for the screen recording permission now rather than at a game.
    func clipsChanged(_ on: Bool) {
        preferences.clips = on
        guard on else { return clipRecorder.stop() }
        Task { @MainActor in
            if !(await ClipRecorder.allowed()) { self.show(T.text(.clipsNeedPermissionDetail), symbol: "record.circle") }
            if let app = self.running?.app, self.clipRecorder.recordingPid == nil { self.startClips(for: app) }
        }
    }

    /// Create, ⌥F12 or the phone: the last seconds of the game playing go to the gallery.
    func saveClip() {
        guard let game = running?.game else { return }
        guard preferences.clips == true else {
            return TrophyBanner.shared.notice(T.text(.clipsOff), detail: T.text(.clipsOffDetail), symbol: "record.circle", sounds: preferences.sounds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = screenshotsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(game.titleID)-\(formatter.string(from: Date())).mp4")
        Task { @MainActor in
            do {
                try await self.clipRecorder.save(to: file)
                Sounds.shared.play(.select)
                TrophyBanner.shared.notice(T.text(.clipSaved), detail: T.format(.clipSavedDetail, self.clipSeconds), symbol: "film", sounds: false)
            } catch {
                TrophyBanner.shared.notice(T.text(.clipFailed), detail: "\(error)", symbol: "exclamationmark.triangle.fill", sounds: self.preferences.sounds)
            }
        }
    }

    /// Games told this run that Low Power Mode holds them at 60 Hz, so it is said once a game.
    private var toldLowPower: Set<String> = []

    /// What Low Power Mode does to this display now, for the game's settings.
    var lowPowerNotice: PowerNotice? {
        PowerNotice.kind(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, displayMaximumFPS: NSScreen.main?.maximumFramesPerSecond ?? 60, frameGeneration: true)
    }

    /// A card over the game that just started when Low Power Mode holds the display at 60 Hz.
    private func tellLowPower(about game: Game) {
        guard let kind = PowerNotice.kind(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, displayMaximumFPS: NSScreen.main?.maximumFramesPerSecond ?? 60,
                                          frameGeneration: settings(for: game).frameGeneration == true),
              toldLowPower.insert(game.id).inserted else { return }
        TrophyBanner.shared.notice(T.text(.lowPowerTitle), detail: T.text(kind == .frameGeneration ? .lowPowerFrameGeneration : .lowPowerRefresh), symbol: "battery.25", sounds: preferences.sounds)
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
            if let game = running?.game { tellLowPower(about: game) }
            startClips(for: app)
            gameWindowShown = true
            updateRemotePlay()
            updateTogetherPresence()
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
        if let start = sessionStart { recordPlay(running.game, from: start) }
        sessionStart = nil
        clipRecorder.stop()
        gameWindowShown = false
        updateRemotePlay()
        updateTogetherPresence()
        syncSaves(running.game) {}
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
        if let next = launchAfterExit, let game = games.first(where: { $0.id == next }) {
            launchAfterExit = nil
            selected = games.firstIndex(of: game) ?? selected
            primaryAction(game)
        }
    }

    // MARK: Phone

    /// Starts the phone server; a launcher that cannot open it still works without phones.
    private func startRemote() {
        phones = pairedDevices.all
        let events = RemoteServer.Events(
            pairing: { request in Task { @MainActor in self.askToPair(request) } },
            connected: { name in Task { @MainActor in
                withAnimation(Motion.overlay) {
                    // With several phones the first one's name and latency stand for them all.
                    if self.phone == nil { self.phone = (name, nil) }
                    self.phoneConnecting = nil
                    self.connectedPhones = self.remote?.connectedDeviceIDs ?? []
                }
                self.phones = self.pairedDevices.all
                self.show(T.format(.phoneConnected, name), symbol: "iphone.gen3")
                // A game in front hears of it through a card over it.
                if !NSApp.isActive {
                    TrophyBanner.shared.notice(T.format(.phoneConnected, name), detail: T.text(.phoneConnectedDetail), symbol: "iphone.gen3", sounds: self.preferences.sounds)
                }
                self.phoneLibrary = nil
                self.phoneLookSent = nil
                self.phoneActivity = nil
                self.tellPhone()
            } },
            disconnected: { Task { @MainActor in
                withAnimation(Motion.overlay) {
                    self.phone = self.remote?.connectedDevice.map { ($0, nil) }
                    self.connectedPhones = self.remote?.connectedDeviceIDs ?? []
                    self.phonePlayers = self.remote?.phonePlayers ?? [:]
                }
            } },
            latency: { milliseconds in Task { @MainActor in if let phone = self.phone { self.phone = (phone.name, milliseconds) } } },
            request: { message in Task { @MainActor in self.phoneAsked(message) } },
            connecting: { name in Task { @MainActor in
                guard self.phone == nil || name != nil else { return }
                withAnimation(Motion.overlay) { self.phoneConnecting = name }
            } },
            players: { Task { @MainActor in
                withAnimation(Motion.overlay) { self.phonePlayers = self.remote?.phonePlayers ?? [:] }
            } },
            streamWishes: { Task { @MainActor in self.updateRemotePlay() } })
        // Whatever the launcher shows changes the library the phone shows.
        librarySink = objectWillChange.debounce(for: .milliseconds(150), scheduler: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.tellPhone() }
        }
        // A fixed port lets a phone on a network without Bonjour connect by address alone.
        for (port, bridge) in [(RemoteServer.preferredPort, RemoteServer.preferredBridgePort), (0, 0)] {
            let server = RemoteServer(name: Host.current().localizedName ?? "Mac", devices: pairedDevices, events: events, controlPort: port, bridgePort: bridge)
            if (try? server.start()) != nil {
                remote = server
                if let port = server.controlPort {
                    cable = UsbTunnel(targetPort: port)
                    cable?.start()
                    androidCable = AdbTunnel.locate().map { AdbTunnel(adb: $0, targetPort: port) }
                    androidCable?.start()
                }
                return
            }
        }
        show(T.text(.phoneServerFailed), symbol: "exclamationmark.triangle.fill")
    }

    private func askToPair(_ request: PairingRequest) {
        withAnimation(Motion.overlay) { pairing = request }
        Sounds.shared.play(.select)
        // A game in front keeps its focus: the phone asks through a card over it instead.
        if !NSApp.isActive { TrophyBanner.shared.notice(T.text(.phonePairingTitle), detail: T.format(.phoneOpenLauncher, request.deviceName), symbol: "iphone.gen3", sounds: preferences.sounds) }
    }

    func answerPairing(_ allow: Bool) {
        guard let request = pairing else { return }
        remote?.respond(to: request.id, allow: allow)
        Sounds.shared.play(allow ? .select : .back)
        withAnimation(Motion.overlay) { pairing = nil }
    }

    func removePhone(_ id: String) {
        pairedDevices.remove(id: id)
        phones = pairedDevices.all
    }

    func previewPairing(_ request: PairingRequest) { pairing = request }

    func previewPhone(_ name: String, latency: Double?) { phone = (name, latency) }

    func previewPhoneConnecting(_ name: String) { phoneConnecting = name }

    func previewThemes(_ shown: [ThemeDesign], active: ThemeDesign?, hub shared: [ThemeDesign]) {
        designs = shown
        preferences.customTheme = active?.id
        hub = .loaded(shared.map { ThemeHub.Theme(design: $0, package: URL(string: "https://example.com/\($0.id).anyps5theme")!, preview: nil) })
    }

    func previewGameControls(_ controls: [PadAction: [String]]) {
        if let game = selectedGame { gameControls[game.id] = controls }
    }

    private var previewBadges: [PhoneBadge]?
    func previewPhones(_ badges: [PhoneBadge]) {
        previewBadges = badges
        phone = (badges[0].name, 9)
    }

    func previewUpdate(_ release: Updates.Release, progress: Double?) {
        availableUpdate = release
        updateProgress = progress
    }

    func discordOff() { discord.clear() }

    /// Turned on again with a game in front: Discord shows it at once, from when it started.
    func discordOn() {
        guard let game = running?.game else { return }
        discord.playing(game.name, since: sessionStart ?? Date())
    }

    /// A trophy just earned shows on the phone too, with its icon made small.
    private func tellPhone(_ trophy: TrophySet.Trophy) {
        guard let remote, phone != nil else { return }
        let grade: String
        switch trophy.grade {
        case .platinum: grade = "platinum"
        case .gold: grade = "gold"
        case .silver: grade = "silver"
        case .bronze: grade = "bronze"
        }
        let icon = trophy.icon.flatMap { data -> String? in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-trophy-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: file) }
            guard (try? data.write(to: file)) != nil else { return nil }
            return RemoteArt.jpeg(file, longestSide: 160)
        }
        remote.publish(.trophy(name: trophy.name, detail: trophy.detail, grade: grade, icon: icon))
    }

    /// The library as the phone shows it, sent when it differs from what the phone has.
    private func tellPhone() {
        guard let remote, phone != nil else { return }
        let activity = activityForPhone()
        if phoneActivity == nil || !RemoteActivity.same(phoneActivity!, activity) {
            phoneActivity = .some(activity)
            remote.publish(.activity(activity))
        }
        let look = phoneLook
        if look != phoneLookSent {
            phoneLookSent = look
            remote.publish(look)
        }
        let library = RemoteMessage.library(games: games.map(remoteGame), selected: selectedGame?.id, running: (running?.game ?? starting)?.id,
                                            language: preferences.language.rawValue)
        guard library != phoneLibrary else { return }
        phoneLibrary = library
        remote.publish(library)
    }

    /// The theme in use, as the phone wears it.
    private var phoneLook: RemoteMessage {
        let (deep, middle, _) = activeDesign?.palette ?? preferences.theme.palette
        let accent = NSColor(accent).usingColorSpace(.sRGB) ?? .systemBlue
        return .look(deep: ThemeDesign.hex(deep), middle: ThemeDesign.hex(middle),
                     accent: ThemeDesign.hex(SIMD3(Float(accent.redComponent), Float(accent.greenComponent), Float(accent.blueComponent))))
    }

    private var phoneLookSent: RemoteMessage?

    /// What the phone last heard the launcher doing; nil before it heard anything.
    private var phoneActivity: RemoteActivity??
    /// The game the launcher is busy with and since when, so the phone counts the whole of it:
    /// waiting, updating and starting.
    private var activityStart: (id: String, date: Date)?

    /// The game starting, else the one installing, else the next one waiting.
    private func activityForPhone() -> RemoteActivity? {
        guard let game = starting ?? games.first(where: { progress[$0.id] != nil }) ?? games.first(where: { queue.contains($0.id) }) else {
            activityStart = nil
            return nil
        }
        if activityStart?.id != game.id { activityStart = (game.id, Date()) }
        var phase = RemoteActivity.Phase.queued
        var fraction: Double?
        switch state(of: game) {
        case .starting: phase = .starting
        case .installing(let step, let done):
            phase = RemoteActivity.Phase(rawValue: "\(step)") ?? .queued
            fraction = step.overall(done)
        default: break
        }
        return RemoteActivity(id: game.id, phase: phase, updating: installedRecords[game.id] != nil, fraction: fraction,
                              elapsed: Date().timeIntervalSince(activityStart?.date ?? Date()))
    }

    private func remoteGame(_ game: Game) -> RemoteGame {
        let state: RemoteGame.State
        switch self.state(of: game) {
        case .unreadable: state = .unavailable
        case .locked, .failed: state = .locked
        case .queued, .installing: state = .installing
        case .installed(let outdated): state = outdated ? .update : .installed
        case .starting: state = .starting
        case .running: state = .running
        }
        let set = trophies[game.id]
        return RemoteGame(id: game.id, name: game.name, state: state, trophies: set.map { "\($0.unlockedCount)/\($0.trophies.count)" },
                          art: RemoteArt.tag(icon: game.icon, background: game.background), layout: settings(for: game).phoneLayout)
    }

    /// The phone in launcher mode: it moves around the launcher, picks, starts and stops games.
    private func phoneAsked(_ message: RemoteMessage) {
        switch message {
        case .wantArt(let id):
            guard let game = games.first(where: { $0.id == id }), let remote else { return }
            Task.detached(priority: .utility) {
                remote.publish(.art(id: id, icon: RemoteArt.jpeg(game.icon, longestSide: RemoteArt.iconSide),
                                    background: RemoteArt.jpeg(game.background, longestSide: RemoteArt.backgroundSide)))
            }
        case .keyFrame:
            remotePlay.wantKey()
        case .command("capture"):
            // Create on the phone's pad: a clip of the game, the game staying in front.
            saveClip()
        case .command(let name):
            let commands: [String: Command] = ["left": .left, "right": .right, "up": .up, "down": .down, "select": .select, "back": .back, "options": .options,
                                               "l1": .previousGame, "r1": .nextGame]
            guard let command = commands[name] else { return }
            bringLauncherFront()
            _ = Input.shared.handler?(command)
        case .select(let id):
            guard let index = games.firstIndex(where: { $0.id == id }), index != selected else { return }
            Sounds.shared.play(.move)
            withAnimation(Motion.overlay) { selected = index }
        case .launch(let id):
            guard let index = games.firstIndex(where: { $0.id == id }) else { return }
            if let running, running.game.id != id {
                // One game at a time: the one playing stops, then the new one starts.
                launchAfterExit = id
                running.app.forceTerminate()
                return
            }
            withAnimation(Motion.overlay) { selected = index }
            if let running {
                NSApp.yieldActivation(to: running.app)
                running.app.activate()
            } else {
                primaryAction(games[index])
            }
        case .close:
            if starting != nil { cancelStart() } else { running?.app.forceTerminate() }
        case .home:
            bringLauncherFront()
        case .saveLayout(let id, let layout):
            guard let game = games.first(where: { $0.id == id }) else { return }
            update(game) { $0.phoneLayout = layout }
        case .togetherHandoff, .togetherHandoffAnswer:
            togetherPhoneAsked(message)
        default:
            break
        }
    }

    /// PS on a controller: from the game to the launcher, and from the launcher back to the game
    /// playing.
    func togglePlaying() {
        guard let running, starting == nil else { return bringLauncherFront() }
        if NSApp.isActive {
            Sounds.shared.play(.select)
            NSApp.yieldActivation(to: running.app)
            running.app.activate()
        } else {
            bringLauncherFront()
            Sounds.shared.play(.select)
        }
    }

    private func bringLauncherFront() {
        guard !NSApp.isActive else { return }
        showWindows()
        NSApp.activate(ignoringOtherApps: true)
    }

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
                    self.recordTrophies(game, set)
                    for trophy in earned {
                        TrophyBanner.shared.show(trophy, sounds: self.preferences.sounds)
                        self.tellPhone(trophy)
                    }
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

    // MARK: Screenshots and saves

    func screenshots(of game: Game) -> [URL] { Screenshots.list(titleID: game.titleID, in: screenshotsFolder) }

    func loadGallery() {
        galleryShots = selectedGame.map(screenshots) ?? []
        galleryIndex = 0
        galleryViewing = false
    }

    /// The folder the unlocked game reads and writes, its saves included.
    func gameFolder(_ game: Game) -> URL? {
        guard let root else { return nil }
        return Installer.bundle(for: game, root: root).appendingPathComponent("Contents/Resources/game").resolvingSymlinksInPath()
    }

    func lastBackup(of game: Game) -> Date? {
        SaveBackup.backups(in: SaveBackup.folder(for: game)).first.flatMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }
    }

    func backUpSaves(_ game: Game) {
        guard let folder = gameFolder(game) else { return }
        do {
            try SaveBackup.backUp(folder, to: SaveBackup.folder(for: game), date: Date())
            show(T.text(.savesBackedUp), symbol: "externaldrive.fill.badge.checkmark")
            objectWillChange.send()
        } catch {
            show(T.text(.backupFailed) + ": \(error)", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// A backup chosen in a panel takes the saves' place; the game must not be running.
    func restoreSaves(_ game: Game) {
        guard running?.game.id != game.id, starting?.id != game.id else { return show(T.text(.closeGameFirst), symbol: "exclamationmark.triangle.fill") }
        guard let folder = gameFolder(game) else { return }
        let backups = SaveBackup.folder(for: game)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: backups.path) ? backups : nil
        panel.prompt = T.text(.restoreSaves)
        guard panel.runModal() == .OK, let backup = panel.url else { return }
        do {
            try SaveBackup.restore(backup, into: folder, keepingIn: backups, date: Date())
            loadTrophies(game, again: true)
            show(T.text(.savesRestored), symbol: "arrow.counterclockwise.circle.fill")
        } catch {
            show(T.text(.backupFailed) + ": \(error)", symbol: "exclamationmark.triangle.fill")
        }
    }

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

    private func readControls(_ game: Game) {
        guard gameControls[game.id] == nil else { return }
        gameControls[game.id] = [:]
        let folder = game.folder, id = game.id
        Task.detached(priority: .utility) {
            let controls = UnrealControls.read(game: folder) ?? [:]
            await MainActor.run { withAnimation(Motion.overlay) { self.gameControls[id] = controls } }
        }
    }

    func open(_ next: Overlay) {
        panelCategory = 0
        panelRow = 0
        panelInRows = next == .gameSettings || next == .confirmUninstall || next == .controls || next == .updateChoice
        // The controls panel opens on its first key, below the hint.
        if next == .controls {
            panelRow = 1
            if let game = selectedGame { readControls(game) }
        }
        if next == .trophies { trophyIndex = 0 }
        if next == .gallery { loadGallery() }
        if next == .advanced { panelRow = 1 }
        panelInRows = panelInRows || next == .advanced || next == .themes || next == .studio || next == .friends
        if next == .friends { refreshFriends() }
        if next == .themes {
            panelRow = themeRows().firstIndex { row in row.id == "design-\(preferences.customTheme ?? "")" || row.id == "builtin-\(preferences.theme.rawValue)" && preferences.customTheme == nil } ?? 1
            loadHub()
        }
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

