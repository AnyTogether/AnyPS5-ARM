import AnyPS5Core
import AnyPS5Online
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import os

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
    /// The Glass theme's window: how much of the desktop shows through, in percent (nil for
    /// GlassWindowRecipe.defaultTransparency), and whether the selected game's key art is laid
    /// over it (nil means off: the desktop is Glass's background).
    var glassTransparency: Int?
    var glassArtwork: Bool?
    var reducedMotion = false
    var sounds = true
    /// Interface sounds and the selected game's theme song, in percent; nil keeps the default.
    var soundVolume: Int?
    var musicVolume: Int?
    /// nil checks GitHub for a newer launcher, as true does.
    var checkUpdates: Bool?
    /// Which releases the update check offers (Updates.Channel); nil is Stable.
    var updateChannel: String?
    var hideWhilePlaying = false
    /// The party's voice sends only while ⌥V is held; nil means off (open microphone).
    var pushToTalk: Bool?
    /// A session friends can join while a game runs; nil means on.
    var friendsJoin: Bool?
    /// Play from a browser (BrowserPlay.swift): nil is on; browserPlayAlways keeps its server up.
    var browserPlay: Bool?
    var browserPlayAlways: Bool?
    /// Another AnyTogether server than AnyTogether's own; nil is AnyTogether's.
    var togetherServer: String?
    /// The running game on the user's Discord profile; nil means on.
    var discordPresence: Bool?
    /// A Join button with it, opening the party's or share play's join code page; nil means on.
    var discordJoin: Bool?
    /// Keeping the last seconds of the game playing, to save as a clip (Create, ⌥F12 or the
    /// phone); nil means off. clipLength is in seconds, nil for 30.
    var clips: Bool?
    var clipLength: Int?
    /// Keeping each game's saves in step through a folder other Macs see (SaveSync); nil means
    /// off. syncFolder nil is iCloud Drive.
    var saveSync: Bool?
    var syncFolder: String?
    /// Save Sync through the AnyTogether cloud ("together") instead of the folder; nil is the folder.
    var syncThrough: String?
    var profileName = NSFullUserName().components(separatedBy: " ").first ?? "Player"
    /// The games folders, in order (Settings → Game Library): the library is all of them, and a
    /// game in several shows from the first that has it. nil until set; `libraryFolders` reads
    /// an older launcher's single `gamesFolder` as a list of one.
    var gamesFolders: [String]?
    /// The first games folder, kept beside the list so an older launcher still finds it.
    var gamesFolder: String?
    /// Where F12 saves screenshots, nil for ~/Pictures/AnyPS5.
    var screenshotsFolder: String?
    /// The user's own system font files for the games, before the launcher's (SystemFonts); nil
    /// for none.
    var fontsFolder: String?
    /// The games (title IDs) that opened a font set with Japanese, Chinese or Korean in it: their
    /// start waits for those fonts to be downloaded.
    var cjkGames: [String]?
    /// Hidden trophies show what they are before they are earned; nil means off.
    var alwaysShowHiddenTrophies: Bool?
    /// Soft pulses in the controller for select, back, errors, trophies, calls and the end of a
    /// row; nil means on.
    var controllerVibration: Bool?
    /// Settings → Steam: the account the shortcuts go to ("<Steam folder>|<account ID>"; nil for
    /// the one signed in last), each unlocked game its own shortcut too (nil: off), the launcher
    /// full screen when Steam starts it (nil: on).
    var steamUser: String?
    var steamGames: Bool?
    var steamFullscreen: Bool?
    /// Settings → Controllers: the light bar's colour (PadLight; nil is the theme's accent),
    /// Circle confirming (nil means Cross) and the sticks' dead zone in percent (nil is none).
    var controllerLight: String?
    var confirmCircle: Bool?
    var stickDeadzone: Int?
    /// Settings → Controllers → Assist Player 1 (AssistTarget): nil off, "controllers", or the
    /// device ID of the phone or browser pad that helps.
    var assistPlayerOne: String?
    /// The engine toolkit that unlocks games without one of their own (EngineChoice: nil is
    /// the built-in one, "custom" the folder below, else a downloaded version).
    var engine: String?
    /// A toolkit folder the user built (Settings → Engine → Engine Folder), nil for none.
    var customToolkit: String?
    /// Settings → Game Library: new games unlocked in the background (PrepareQueue); nil means on.
    var prepareNewGames: Bool?
    /// The window full screen at start (WindowStart): nil the first time, then as it was left.
    var fullScreen: Bool?
    /// Settings → Behaviour → Pause Game When Opening the Menu: nil means on.
    var pauseOnMenu: Bool?
    /// Settings → Shortcuts: what differs from the defaults; nil for none.
    var shortcuts: ShortcutMap?
    /// Settings → Battery & Heat (PowerProfiles); nil for the defaults.
    var powerProfiles: PowerProfiles?
    var games: [String: GameSettings] = [:]
    /// Settings › Default Display, for every game that leaves its display at Default; nil until
    /// changed (the built-in values). Machine-wide, like the game settings.
    var displayDefaults: DisplayDefaults?
    var lastPlayed: [String: Date] = [:]

    var accentColor: Color { (accent ?? theme.defaultAccent).color }

    /// The games folders; setting them keeps the first in `gamesFolder` too.
    var libraryFolders: [String] {
        get { LibraryFolders.list(gamesFolders, legacy: gamesFolder) }
        set {
            gamesFolders = newValue.isEmpty ? nil : newValue
            gamesFolder = newValue.first
        }
    }

    static let key = "AnyPS5.preferences.v1"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key), var saved = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        // One games folder from an older launcher becomes a list of one.
        saved.libraryFolders = saved.libraryFolders
        return saved
    }

    func save() {
        // Every game's display keys as before, so an older launcher still reads the file.
        let encoder = JSONEncoder()
        encoder.userInfo[GameSettings.legacyDisplayKeys] = true
        if let data = try? encoder.encode(self) { UserDefaults.standard.set(data, forKey: Preferences.key) }
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
    /// The update notice's buttons, left of the top bar's: 0 Restart Now, 1 Later.
    case notice(Int)
    case tiles
    case actions(Int)
}

extension Overlay {
    /// Panels drawn over the whole screen rather than sliding in at its side.
    var coversScreen: Bool {
        switch self {
        case .settings, .library, .log, .messages, .profile, .compare, .feed, .captures, .leaderboard, .crashReport, .cropPicture, .trophies, .gallery, .findPlayers, .gameHub, .controllerTest,
             .profilePicker, .addProfile, .signIn:
            return true
        default:
            return false
        }
    }
}

enum Overlay: Equatable {
    case settings
    case gameSettings
    case library
    case log
    case confirmUninstall
    /// Play on a game an older toolkit made: update it first, or play it as it is.
    case updateChoice
    /// AnyTogether no longer answers this launcher's version: update (UpdateRequired.swift).
    case updateRequired
    /// An unlock that did not start for want of room (spaceShortage): how much, and what to do.
    case noSpace
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
    /// The party the user is in, or invites and friends' open parties.
    case party
    /// Friends' activity on AnyTogether.
    case feed
    /// Screenshots and clips posted on AnyTogether, their likes and comments (CapturesView.swift).
    case captures
    /// A game's leaderboard, or overall trophy points.
    case leaderboard
    /// AnyTogether's notifications, from the bell.
    case notifications
    /// "How did it run?" after a session.
    case compat
    /// A game's last start: why it stopped, the report to export and the issue to open.
    case crashReport
    /// Find players: the looking-for-group board, the user's posts, Live now and public parties, people.
    case findPlayers
    /// "Find players for <game>": a post being written.
    case lfgPost
    /// One game's hub: who plays it now, posts, public share plays and parties, its players.
    case gameHub
    /// The profile picture being cut square.
    case cropPicture
    /// Settings → Cloud Storage: the usage, the cloud saves and the media on AnyTogether.
    case cloudStorage
    /// Trophies compared with someone: the games, then one game's trophies side by side.
    case compare
    /// Settings → Controllers → Test Buttons and Sticks.
    case controllerTest
    /// Settings → Advanced → Play from a browser: the QR code a phone scans (BrowserPlay.swift).
    case browserPlay
    /// PS in a game: Resume, Game Settings, Close Game, over the launcher (HomeMenus.swift).
    case quickMenu
    /// PS held in a game: "Close <game>?".
    case closeGame
    /// PS held in the launcher: Switch Profile, Quit AnyPS5.
    case homeMenu
    /// Esc on the home screen: "Quit AnyPS5?", Cancel first.
    case confirmQuit
    /// The launcher's own crash or stall last time: Send Report, Not Now (LauncherReport.swift).
    case launcherReport
    /// "Who's playing?": the profiles' tiles and Add Profile (Profiles.swift).
    case profilePicker
    /// A new profile: its name, then offline or online.
    case addProfile
    /// Signing in to AnyTogether for a profile (a new one, one going online or signing in again).
    case signIn
    /// Options (or a right click) on Home: the game's settings, Switch Profile, online or offline.
    case profileMenu
}

/// A newer launcher downloaded and checked, unpacked in a folder of its own, waiting for a restart.
struct ReadyUpdate: Equatable {
    var release: Updates.Release
    var app: URL
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    /// A game's icon in place of the symbol.
    var icon: URL? = nil
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
    /// Settings → Game Presets of the profile playing, in a file of their own in its folder
    /// (GamePresetsStore): every game it starts begins with them.
    @Published var gamePresets = GamePresets() {
        didSet {
            guard gamePresets != oldValue, persists, !loadingGamePresets else { return }
            try? gamePresetsStore.save(gamePresets)
        }
    }
    private var loadingGamePresets = false
    var gamePresetsStore: GamePresetsStore {
        GamePresetsStore(file: profiles.gamePresetsFile(for: profileBook.currentProfile?.id ?? LauncherProfile.legacyID))
    }

    /// The current profile's presets; the previews start with none.
    func loadGamePresets() {
        loadingGamePresets = true
        gamePresets = persists ? gamePresetsStore.load() : GamePresets()
        loadingGamePresets = false
    }
    @Published private(set) var games: [Game] = []
    @Published private(set) var scanning = false
    @Published var selected = 0 {
        didSet { if selected != oldValue { selectionMoved(from: oldValue) } }
    }
    @Published var focus = HomeFocus.tiles
    @Published var overlay: Overlay? {
        didSet {
            if oldValue != overlay {
                discoverOverlayChanged()
                // Friends' private picture links run out (6 to 12 hours): the list is read again.
                if let overlay, [.friends, .party, .profile].contains(overlay), togetherUser != nil, identityBook.learnedAt != nil, identityBook.stale() { refreshFriends() }
                askingRow = nil
                if overlay == nil { offerLauncherReportSoon() }
                if rowEditor.editing != nil { rowEditor.stop() }
                if shortcutCapture != nil { endShortcutCapture() }
            }
            // The controller test takes the pads' buttons: only PS acts while it is open.
            Input.shared.testing = overlay == .controllerTest
        }
    }
    @Published var panelCategory = 0
    /// Controllers.shared's roster changes redraw the screens (ControllersPanel.swift).
    var controllerSink: AnyCancellable?
    @Published var panelRow = 0 {
        didSet {
            if !keepingFocus { panelFocusID = nil }
            if panelRow != oldValue, rowEditor.editing != nil { rowEditor.stop() }
        }
    }
    /// The item the panel's focus is on, so rows coming in above it do not move it to another.
    var panelFocusID: String?
    private var keepingFocus = false

    /// Focuses row `index` of `rows`, remembering which item that is.
    func focusRow(_ index: Int, in rows: [PanelRow]) {
        keepingFocus = true
        // Only what changes is written, so a move that went nowhere changes nothing.
        if panelRow != index { panelRow = index }
        let id = rows.indices.contains(index) ? rows[index].id : nil
        if panelFocusID != id { panelFocusID = id }
        keepingFocus = false
    }

    /// Where the focused item is in `rows` now.
    func focusedRow(in rows: [PanelRow]) -> Int { ListFocus.index(of: panelFocusID, in: rows.map(\.id), fallback: panelRow) }
    @Published var panelInRows = false
    /// The choice row the pad is changing (✕ starts, ✕ or ○ end).
    @Published var rowEditor = RowEditor()
    /// The focused item of the quick menu, the close question and the home menu.
    @Published var menuIndex = 0
    /// The shortcut waiting for a key or a chord in Settings → Shortcuts.
    @Published var shortcutCapture: ShortcutCapture?
    /// The quick menu went up after the launcher pressed Options in the game.
    @Published var pausedGame = false
    /// The pad action waiting for a key in the controls panel.
    @Published var capturing: PadAction?
    @Published var libraryIndex = 0
    /// The focused row of the trophy list.
    @Published var trophyIndex = 0
    /// The hidden trophies shown in the list this time (Show), by game and trophy; forgotten
    /// when the list closes.
    @Published var revealedTrophies: Set<String> = []
    @Published var galleryIndex = 0
    /// One screenshot over the whole screen, instead of the grid.
    @Published var galleryViewing = false
    /// What the mouse's Forward button opens again (BackForward.swift).
    var forwardStep: ForwardStep?
    /// The launcher's own crash or stall last time, until offered (LauncherReport.swift).
    var launcherReport: LauncherReportState?
    /// Opens a link in the browser; the tests keep it.
    var openLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @Published private(set) var galleryShots: [URL] = []
    @Published var onboardingStep = 0
    @Published var onboardingChoices: [Int: Int] = [:]
    @Published private(set) var progress: [String: (Installer.Step, Double)] = [:]
    @Published private(set) var queue: [String] = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var running: (game: Game, app: NSRunningApplication)? {
        didSet { if (oldValue == nil) != (running == nil) { prepareSoon() } }
    }
    /// The game from the press of Play until its first window shows.
    @Published private(set) var starting: Game? {
        didSet { if (oldValue == nil) != (starting == nil) { prepareSoon() } }
    }

    /// A game starting or ending: the background preparation stops for it or goes on, once the
    /// change has settled.
    private func prepareSoon() {
        guard persists else { return }
        DispatchQueue.main.async { [weak self] in self?.stepPrepare() }
    }
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var installedRecords: [String: InstallRecord] = [:]
    @Published private(set) var trophies: [String: TrophySet] = [:]
    /// Why each game stopped the last time it was started, when it stopped on an error.
    @Published private(set) var diagnoses: [String: Diagnosis] = [:]
    /// The crash panel's report, while it is open.
    @Published var sessionReport: SessionReportState?
    /// What each game's last start was beyond its log: its process, detailed logging, its end.
    var lastSessions: [String: LastSession] = [:]
    /// Keeps a detailed log under its cap while the game runs.
    private var traceTrim: Task<Void, Never>?
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
    /// Settings → Steam (SteamPanel.swift).
    @Published var steam = SteamState()
    /// How this launch came from Steam (set before the app starts, from the arguments).
    static var steamLaunch = SteamLaunch()
    var steamLaunch: SteamLaunch { Self.steamLaunch }
    /// The game a Steam shortcut started: the launcher quits when it ends well, so Steam sees it end.
    var steamQuitAfter: String?
    @Published var active = true
    @Published private(set) var rosettaMissing = false
    @Published private(set) var logText = ""
    @Published var translocated = AppLocation.isTranslocated

    /// The toolkit inside the app (or ANYPS5_TOOLKIT); the default engine.
    let builtInToolkit = Toolkit.locate()
    /// Downloaded engine toolkits (Settings → Engine); the previews keep theirs apart.
    let toolkitStore: ToolkitStore
    @Published var installedToolkits: [InstalledToolkit] = []
    /// The toolkits on GitHub's releases, as last seen, and when.
    @Published var engineCatalogue: [EngineCatalogue.Entry] = []
    @Published var engineChecked: Date?
    @Published var engineOffline = false
    @Published var checkingEngines = false
    /// How far each release's toolkit download is.
    @Published var engineDownloads: [String: Double] = [:]
    /// The custom toolkit folder, when it holds a toolkit.
    @Published var customToolkit: Toolkit?
    /// The Noto fonts inside the app (SystemFontsPanel.swift).
    let builtInFonts = SystemFonts.locateBuiltIn()
    /// The Japanese, Chinese and Korean fonts, downloaded the first time a game needs them.
    let fontDownloads: FontDownloads
    /// The folder of links to the fonts a game gets (ANYPS5_SYSTEM_FONTS).
    let gameFonts: URL
    /// How far the Japanese, Chinese and Korean fonts' download is, while it runs.
    @Published var cjkProgress: Double?
    @Published var cjkInstalled = false
    /// The game waiting for those fonts before it starts.
    @Published var fontWait: Game?
    var cjkWaiters: [@MainActor (Bool) -> Void] = []
    /// Where each start's lines begin in the game's log, until the fonts it opened are known.
    var fontLogOffsets: [String: UInt64] = [:]
    var fontWatch: Task<Void, Never>?
    private var installer: Installer?
    /// New games prepared in the background (PrepareQueue) and the unlock doing it.
    @Published private(set) var prepare = PrepareQueue()
    private var preparer: Installer?
    private var prepareTimer: Timer?
    /// The unlock the no-space panel is about.
    @Published var spaceShortage: (game: Game, shortage: SpaceShortage)?
    private var installLog: [String: [String]] = [:]
    /// Watches the games folders and scans them again when something is copied in (LibraryWatch.swift).
    private var libraryMonitor: LibraryMonitor?
    /// Game ID to the games folder it was found in: its unlocked copy is in that folder's store.
    private var gameRoots: [String: URL] = [:]
    /// Each games folder as the last scan found it (Settings → Game Library).
    @Published private(set) var libraryFolders: [GameLibrary.FolderStatus] = []
    /// Bumped whenever an unlock or an uninstall changes the records, so a scan read before does
    /// not put back what they replaced.
    private nonisolated let recordsStamp = OSAllocatedUnfairLock(initialState: 0)
    private var recordsGeneration: Int {
        get { recordsStamp.withLock { $0 } }
        set { recordsStamp.withLock { $0 = newValue } }
    }
    private(set) var trophiesRead: Set<String> = []
    /// The game whose folder is being measured, or whose trophies are being read, for the
    /// selection: one at a time, so moving fast through the games starts no walk per game passed.
    private var sizeWalk: String?
    private var trophyRead: String?
    /// How a game's folder is measured (off the main thread); the tests count the walks.
    var folderSize: @Sendable (URL) -> Int64 = { GameLibrary.size(of: $0) }
    /// The game whose key art is behind the home screen while the selection moves: the one it
    /// rested on last; nil follows the selection.
    @Published private(set) var backdropID: String?
    /// Off for the offscreen previews, which draw the selection they set at once.
    var settlesSelection: Bool
    private var settleTask: Task<Void, Never>?
    let discord = DiscordPresence(applicationID: DiscordPresence.applicationID)
    private var starts: [String: Date] = [:]
    private(set) var remote: RemoteServer?
    /// iPhones on a cable reach the phone server through it, with no Wi-Fi.
    private var cable: UsbTunnel?
    /// Android phones on a cable, through adb when it is installed.
    private var androidCable: AdbTunnel?
    let pairedDevices = PairedDevices()
    /// Play from a browser's server and what its screen shows.
    let browserPlay = BrowserPlay()
    /// The library the phone was told last, and what keeps it told.
    private var phoneLibrary: RemoteMessage?
    private var librarySink: AnyCancellable?
    private var musicSink: AnyCancellable?
    private var updateTimer: Timer?
    /// A newer launcher on GitHub, and how far its download is once asked for.
    @Published private(set) var availableUpdate: Updates.Release?
    @Published private(set) var updateProgress: Double?
    /// The newer launcher downloaded, its signature and sums checked, unpacked and waiting for a
    /// restart (or for the launcher to quit).
    @Published private(set) var readyUpdate: ReadyUpdate?
    /// The last check found no answer (offline, a rate limit).
    @Published private(set) var updateCheckFailed = false
    /// Later on the home screen's notice, by version.
    @Published var updateNotice = UpdateNotice()
    /// Restart Now with a game running: the restart waits for the game to close.
    @Published private(set) var restartAfterGame = false
    /// The update was handed to the replacement script already.
    private var updatePlaced = false
    /// Counts every change of the model, for Input's edge bump.
    private(set) var changeCount = 0
    private var changeSink: AnyCancellable?
    /// The game the phone asked for while another one was still playing.
    private var launchAfterExit: String?
    /// The game to start as soon as its update finishes.
    private var playAfterUnlock: String?
    private var toastTask: Task<Void, Never>?
    private var startWatch: Task<Void, Never>?
    private var exitWatch: DispatchSourceProcess?
    /// The Mac's power and the battery and heat profiles in force (PowerWatch.swift).
    let power = PowerWatch()

    init(preferences: Preferences? = nil) {
        self.persists = preferences == nil
        self.settlesSelection = preferences == nil
        let loaded = preferences ?? Preferences.load()
        self.preferences = loaded
        // Profiles: a launcher set up before them becomes its first profile at once, its session
        // moving from the old file into that profile's Keychain item.
        let vault: SecretVault = preferences == nil ? KeychainVault() : MemoryVault()
        self.vault = vault
        let legacyUser = preferences == nil ? TokenStore(file: TokenStore.legacyFile).user : nil
        profiles = ProfileStore(folder: preferences == nil ? ProfileStore.defaultFolder : FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-profiles-\(UUID().uuidString)"),
                                existing: .init(onboarded: loaded.onboarded, user: legacyUser, name: loaded.profileName), persists: preferences == nil)
        if preferences == nil, let owner = profiles.book.legacyOwner {
            _ = TokenStore.migrate(file: TokenStore.legacyFile, into: vault, account: ProfileSessions.account(for: owner))
        }
        if preferences == nil, let current = profiles.book.currentProfile { ProfilePicture.file = profiles.pictureFile(for: current.id) }
        toolkitStore = preferences == nil ? ToolkitStore() : ToolkitStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-toolkits-\(UUID().uuidString)"))
        themes = preferences == nil ? ThemeLibrary() : ThemeLibrary(folder: FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-themes"))
        let fonts = preferences == nil ? FontDownloads.root : FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-fonts-\(UUID().uuidString)")
        fontDownloads = FontDownloads(folder: fonts.appendingPathComponent("CJK"))
        gameFonts = fonts.appendingPathComponent("Games")
        cjkInstalled = fontDownloads.installed
        designs = themes.all
        profileBook = profiles.book
        // Settings → Game Presets of the profile playing.
        loadGamePresets()
        if persists {
            // An offline profile keeps its session (if it has one) unused.
            togetherUser = currentProfile?.mode == .offline ? nil : together.user
            DispatchQueue.main.async { [weak self] in self?.startFamily() }
            // With the picker up, the socket waits for the profile picked.
            if profiles.launchScreen == .picker && self.preferences.onboarded {
                DispatchQueue.main.async { [weak self] in self?.openProfilePicker(atLaunch: true) }
            } else if togetherUser != nil {
                DispatchQueue.main.async { [weak self] in self?.startTogetherSocket() }
            }
        }
        apply()
        changeSink = objectWillChange.sink { [weak self] _ in MainActor.assumeIsolated { self?.changeCount &+= 1 } }
        startPowerWatch()
        if persists { loadEngines(); loadProfilePicture(); watchFullScreen(); watchLauncher() }
        if persists {
            // Online play's packets ride WebRTC data channels; their signals go out on the socket.
            OnlinePlayHost.configure(transport: { OnlinePeerMesh(context: $0) }, signal: { [weak self] to, device, session, kind, data in
                DispatchQueue.main.async { self?.togetherSocket?.signal(to: to, device: device, gameSession: session, kind: kind, json: data) }
            })
            AppModel.opener = { [weak self] urls in self?.open(urls) }
            AppModel.beforeQuit = { [weak self] in
                // A ready update goes in as the launcher quits: the next launch is the new version.
                self?.placeUpdate(relaunch: false)
                return self?.leaveTogetherOnQuit()
            }
            let waiting = AppModel.pending
            AppModel.pending = []
            if !waiting.isEmpty { DispatchQueue.main.async { [weak self] in self?.open(waiting) } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.active = true
                // Something copied in while the launcher was away shows at once.
                self?.libraryMonitor?.rescan()
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
        // Unlocks going on stop with the launcher; a relinker paused for a game would otherwise
        // stay stopped.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preparer?.cancel()
                self?.installer?.cancel()
                // Quit as it should: no crash to offer next time.
                LauncherWatch.shared.quitting()
            }
        }
        // A games folder on an external drive: watched again and scanned when the drive comes or goes.
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let volume = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.standardizedFileURL.path
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let roots = self.libraryRoots.map(\.standardizedFileURL.path)
                    if roots.contains(where: { root in volume.map { root == $0 || root.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") } ?? true }) { self.libraryMonitor?.refresh() }
                }
            }
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
        if persists { startControllers() }
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
        gameRoots = Dictionary(games.map { ($0.id, root) }, uniquingKeysWith: { first, _ in first })
        // Each folder of the settings: one that is not there shows as not connected.
        libraryFolders = libraryRoots.map { folder in
            let there = FileManager.default.fileExists(atPath: folder.path)
            let prefix = folder.standardizedFileURL.path + "/"
            return GameLibrary.FolderStatus(url: folder, connected: there, games: there ? games.filter { $0.folder.standardizedFileURL.path.hasPrefix(prefix) }.count : 0)
        }
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

    /// Shows `game` being prepared in the background (paused for a game, or not), and `waiting`
    /// in line, without unlocking anything.
    func previewPreparing(_ game: Game, paused: Bool = false, waiting: [Game] = []) {
        var queue = PrepareQueue()
        queue.add([game.id] + waiting.map(\.id))
        _ = queue.step(.idle) { _ in nil }
        if paused { _ = queue.step(PrepareConditions(playing: true)) { _ in nil } }
        prepare = queue
    }

    private func apply() {
        T.language = preferences.language
        if persists { DispatchQueue.main.async { [weak self] in self?.stepPrepare() } }
        power.profiles = preferences.powerProfiles ?? PowerProfiles()
        Motion.reduced = preferences.reducedMotion || power.adjustment.dimEffects
        Sounds.shared.enabled = preferences.sounds
        Sounds.shared.volume = Float(preferences.soundVolume ?? 100) / 100
        Feel.shared.vibration = preferences.controllerVibration ?? true
        ThemeMusic.shared.volume = Float(musicVolume) / 100
        Input.shared.circleConfirms = preferences.confirmCircle == true
        if persists, Input.shared.shortcuts != shortcutMap { Input.shared.apply(shortcutMap) }
        Input.shared.deadzone = preferences.stickDeadzone ?? 0
        applyAssist()
        let controllers = Controllers.shared
        controllers.light = preferences.controllerLight.flatMap(PadLight.init(rawValue:)) ?? .theme
        if let rgb = NSColor(accent).usingColorSpace(.sRGB) {
            controllers.accent = (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        }
    }

    static let defaultMusicVolume = 50

    var musicVolume: Int { preferences.musicVolume ?? AppModel.defaultMusicVolume }

    // MARK: Updates

    static var runningVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var updateChannel: Updates.Channel { preferences.updateChannel.flatMap(Updates.Channel.init(rawValue:)) ?? .stable }

    /// Settings → About → Update Channel: the new channel is asked at once. Nightly offers its
    /// newest build; Stable offers its release only when it is newer than this version, so going
    /// back to Stable never installs an older launcher.
    func setUpdateChannel(_ channel: Updates.Channel) {
        guard channel != updateChannel else { return }
        preferences.updateChannel = channel == .stable ? nil : channel.rawValue
        availableUpdate = nil
        // A build of the other channel waiting for a restart is not this channel's.
        if let ready = readyUpdate {
            try? FileManager.default.removeItem(at: ready.app.deletingLastPathComponent().deletingLastPathComponent())
            readyUpdate = nil
            restartAfterGame = false
        }
        guard updateProgress == nil else { return }
        // A check on its way asks again for the new channel when it ends.
        guard !checkingUpdates else { return }
        lookUpUpdate(told: true)
    }

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

    /// Update Required: look for the newer launcher at once, quietly, so the screen can offer it.
    func lookUpUpdateQuietly() {
        guard updateProgress == nil, !checkingUpdates, readyUpdate == nil else { return }
        lookUpUpdate(told: false)
    }

    private func lookUpUpdate(told: Bool) {
        let current = AppModel.runningVersion
        let channel = updateChannel
        checkingUpdates = true
        Task { @MainActor in
            let found = await Updates.lookup(current: current, channel: channel)
            self.checkingUpdates = false
            // The channel changed meanwhile: this answer is the other channel's.
            if channel != self.updateChannel { return self.lookUpUpdate(told: true) }
            switch found {
            case .newer(let release):
                self.lastUpdateCheck = Date()
                self.updateCheckFailed = false
                let first = self.availableUpdate?.tag != release.tag
                self.availableUpdate = release
                if self.readyUpdate?.release.tag == release.tag { return }
                if self.canReplaceItself {
                    // Downloaded quietly; the notice comes once it is ready.
                    self.downloadUpdate(told: told)
                } else if first || told {
                    self.show(T.format(.launcherUpdateAvailable, release.version), symbol: "arrow.down.circle.fill")
                }
            case .current:
                self.lastUpdateCheck = Date()
                self.updateCheckFailed = false
                if self.readyUpdate == nil { self.availableUpdate = nil }
                // On Stable after a nightly: this version stays until a newer release.
                if told, channel == .stable, Updates.Version(current)?.isNightly == true {
                    self.show(T.format(.updateChannelStays, current), symbol: "checkmark.circle.fill")
                } else if told {
                    self.show(T.format(.launcherUpToDate, current), symbol: "checkmark.circle.fill")
                }
            case .failed:
                self.updateCheckFailed = true
                if told { self.show(T.text(.updateCheckFailed), symbol: "exclamationmark.triangle.fill") }
            }
        }
    }

    /// Where the launcher's own update stands (About, the home screen's notice).
    var launcherUpdateState: LauncherUpdateState {
        .of(checking: checkingUpdates, newer: availableUpdate?.version, progress: updateProgress, ready: readyUpdate?.release.version,
            lastCheck: lastUpdateCheck, failed: updateCheckFailed)
    }

    /// The home screen's quiet notice: an update ready, or a restart waiting for the game.
    var showsUpdateNotice: Bool { restartAfterGame || updateNotice.shows(launcherUpdateState) }

    /// This copy can put a new version in its own place: not run from a translocated or
    /// read-only folder.
    var canReplaceItself: Bool {
        !AppLocation.isTranslocated && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    /// Downloads the newer launcher, checks its signature and sums (Updates.prepare) and keeps it
    /// ready for a restart. Nothing is replaced yet.
    func downloadUpdate(told: Bool = true) {
        guard let release = availableUpdate, updateProgress == nil, readyUpdate?.release.tag != release.tag else { return }
        guard canReplaceItself else { return show(T.text(.updateNotWritable), symbol: "exclamationmark.triangle.fill") }
        updateProgress = 0
        let identifier = Bundle.main.bundleIdentifier ?? "org.anyps5.launcher"
        let current = AppModel.runningVersion
        Task { @MainActor in
            do {
                let new = try await Updates.prepare(release, bundleIdentifier: identifier, current: current) { fraction in
                    Task { @MainActor in if self.updateProgress != nil { self.updateProgress = fraction } }
                }
                self.updateProgress = nil
                if let old = self.readyUpdate, old.app != new {
                    try? FileManager.default.removeItem(at: old.app.deletingLastPathComponent().deletingLastPathComponent())
                }
                self.readyUpdate = ReadyUpdate(release: release, app: new)
            } catch {
                self.updateProgress = nil
                // The periodic check says nothing over a game or a screen; About shows it.
                if told { self.show(T.text(.updateFailed) + ": \(error)", symbol: "exclamationmark.triangle.fill") }
            }
        }
    }

    /// Settings → About → Update: the download, or Restart Now once it is ready.
    func installUpdate() {
        if readyUpdate != nil { return restartForUpdate() }
        downloadUpdate(told: true)
    }

    /// Restart Now: the new version takes this one's place and opens; with a game running, the
    /// restart waits for it to close.
    func restartForUpdate() {
        guard readyUpdate != nil else { return }
        switch UpdateRestart.decide(gameRunning: running != nil || starting != nil) {
        case .afterGame:
            restartAfterGame = true
        case .now:
            restartAfterGame = false
            guard placeUpdate(relaunch: true) else { return }
            NSApp.terminate(nil)
        }
    }

    func cancelRestartAfterGame() {
        restartAfterGame = false
    }

    /// Later: the update goes in when the launcher quits; the notice does not come back for it.
    func updateLater() {
        updateNotice.later(launcherUpdateState)
        restartAfterGame = false
        Sounds.shared.play(.back)
    }

    /// Hands the ready update to the replacement script, which waits for this app to end.
    @discardableResult
    private func placeUpdate(relaunch: Bool) -> Bool {
        guard let ready = readyUpdate, !updatePlaced, persists else { return false }
        do {
            try Updates.replace(Bundle.main.bundleURL, with: ready.app, pid: ProcessInfo.processInfo.processIdentifier, relaunch: relaunch)
            updatePlaced = true
            return true
        } catch {
            show(T.text(.updateFailed) + ": \(error)", symbol: "exclamationmark.triangle.fill")
            return false
        }
    }

    /// A game closed while a restart waited for it: a moment for its saves, then the restart.
    private func restartIfWaiting() {
        guard restartAfterGame else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard self.restartAfterGame, self.running == nil, self.starting == nil else { return }
            self.restartForUpdate()
        }
    }

    /// Previews of the notice and of About's update rows.
    func previewUpdate(_ state: LauncherUpdateState, waitingForGame: Bool = false) {
        let release = Updates.Release(tag: "v0.2.20-arm", version: "0.2.20", page: URL(string: "https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.20-arm")!,
                                      download: nil, size: nil)
        lastUpdateCheck = Date(timeIntervalSince1970: 1_793_000_000)
        switch state {
        case .checking: checkingUpdates = true
        case .failed: updateCheckFailed = true
        case .available: availableUpdate = release
        case .downloading(_, let fraction): availableUpdate = release; updateProgress = fraction
        case .ready: availableUpdate = release; readyUpdate = ReadyUpdate(release: release, app: URL(fileURLWithPath: "/tmp/AnyPS5.app"))
        case .idle: lastUpdateCheck = nil
        case .upToDate: break
        }
        restartAfterGame = waitingForGame
    }

    /// The selected game's song while the launcher is in front and idle, silence otherwise.
    private func updateMusic() {
        let quiet = !preferences.onboarded || !active || running != nil || starting != nil || musicVolume == 0
        let menuMusic = activeDesign.flatMap { themes.file($0.music, of: $0) }
        ThemeMusic.shared.play(quiet ? nil : selectedGame, fallback: quiet ? nil : menuMusic)
    }

    var accent: Color { activeDesign.map { Color(rgb: $0.accentRGB) } ?? preferences.accentColor }

    // MARK: AnyTogether

    /// The client for the server chosen in Settings → AnyTogether (or ANYTOGETHER_URL), with the
    /// session of the profile playing.
    lazy var together = wireTogether(AppModel.makeTogetherClient(base: TogetherServer.base(chosen: preferences.togetherServer), store: sessionStore(for: sessionProfileID)))
    /// Who plays on this Mac (Profiles.swift), their sessions in the Keychain.
    let profiles: ProfileStore
    let vault: SecretVault
    @Published var profileBook = ProfileBook() {
        didSet {
            // Another profile plays: its own Game Presets come.
            if profileBook.currentProfile?.id != oldValue.currentProfile?.id { loadGamePresets() }
        }
    }
    @Published var profileFlow = ProfileFlow()
    /// The friends' private names and pictures as the friends list last said.
    @Published var identityBook = TogetherIdentityBook()
    var privateNameDraft: String?
    var serverDraft = ""
    @Published var togetherUser: TogetherUser?
    @Published var togetherStep = TogetherStep.idle
    @Published var togetherConnected = false
    var togetherEmail = ""
    var togetherCode = ""
    var togetherSocket: TogetherSocket?
    var togetherWait: Task<Void, Never>?
    var togetherFlush: Task<Void, Never>?
    /// The social screens' state: activity, leaderboards, notifications.
    lazy var social = SocialState(owner: self)
    /// Cloud saves and media: whether the server keeps files, Settings → Cloud Storage.
    lazy var cloud = CloudState(owner: self)
    /// Captures: the post written over the gallery, the Captures feed and its comments.
    lazy var captures = CapturesState(owner: self)
    lazy var togetherSync = TogetherSync(client: together, deviceName: Host.current().localizedName ?? "Mac", model: AppModel.machineModel)
    /// When the running game started, for the play session AnyTogether keeps.
    var sessionStart: Date?
    /// Family limits on this Mac, and the watch over play time (FamilyGate.swift).
    @Published var family = FamilyStanding.free
    lazy var familyCache = persists ? FamilyCache() : FamilyCache(folder: FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-family"), defaults: UserDefaults(suiteName: "AnyPS5-preview-family") ?? .standard)
    let familyWatch = FamilyWatch()
    @Published var togetherFriends: [TogetherFriend] = [] {
        didSet { if togetherFriends != oldValue { identityBook.learn(friends: togetherFriends) } }
    }
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
    /// The profile picture (ProfilePicture.file), the crop open on a new one, and an upload or
    /// download of AnyTogether's on its way.
    @Published var profilePicture: NSImage?
    @Published var pictureCrop: PictureCrop?
    @Published var pictureBusy = false
    var profileDraft = ProfileDraft()
    /// Messages: the conversations and threads, the row selected on the left, whether the thread
    /// has the focus (a quick reply, or the field at the end), and whether the field is typed in.
    @Published var inbox: TogetherInbox?
    @Published var messagesIndex = 0
    @Published var messagesInThread = false
    @Published var messageFocus = 0
    @Published var composing = false
    @Published var messageDraft = ""
    /// Who is typing in which conversation, and what forgets them when they stop.
    @Published var typing = TogetherTyping()
    var typingExpiry: Task<Void, Never>?
    /// A new group: the friends picked, its name, and the row focused (the name, each friend, Create).
    @Published var groupPicked: Set<String> = []
    @Published var groupName = ""
    @Published var groupFocus = 0
    /// The open thread's actions: the message picked, the menu over it, a reply or an edit on its way.
    @Published var messageActions = MessageActions()
    /// The party the user is in, the invites waiting, and whether a new party is open to friends.
    @Published var party: TogetherParty? {
        didSet { partyChanged() }
    }
    @Published var partyInvites: [TogetherPartyInvite] = []
    @Published var partyStartsOpen = false
    /// "Join with a code": what was typed, what it opens, and asking with it.
    @Published var joinEntry = JoinEntry()
    var joinLookup: Task<Void, Never>?
    /// Parties and share plays (by ID) whose code the user stopped this session, or for which one
    /// was made for Discord already: no code is made for the Join button again.
    var codeStopped: Set<String> = []
    var codeMakingForDiscord: Set<String> = []
    /// Who asked with the code (party.request / share_play.request said so), by user ID.
    @Published var codeAskers: Set<String> = []
    /// The Discord link typed for the party, sent once it reads as one.
    var discordLinkSend: Task<Void, Never>?
    /// What Discord was shown last, and since when the user is in the party.
    var discordShown: DiscordActivity?
    var discordCleared = true
    /// When the running game's window showed: its time on Discord.
    var discordSince: Date?
    var partySince: (id: String, at: Date)?
    /// Discord looked at again when the code its Join button opens runs out, and when.
    var discordRefresh: (task: Task<Void, Never>, at: Date)?
    /// The game session the user hosts or joined, and invitations to friends' games.
    @Published var gameSession: TogetherGameSession?
    @Published var gameInvites: [TogetherGameInvite] = []
    var openingSession = false
    /// Play Together: party members' games to join, how each other player is reached (by user
    /// ID), a join waiting for its game to unlock, and the poll of the links.
    @Published var playTogetherOffers: [PlayTogetherOffer] = []
    @Published var peerLinks: [String: OnlinePeerLinkInfo] = [:]
    var togetherAfterUnlock: (String, PlayTogetherOffer)?
    /// Play Together games the user chose to join with a game version that does not fit (Try
    /// anyway), and games the server refused for the version though the check here let them by.
    @Published var togetherTryAnyway: Set<String> = []
    @Published var togetherVersionRefused: Set<String> = []
    /// The row whose social step is asking first (AskFirst.swift): it shows the question instead.
    @Published var askingRow: String?
    /// AnyTogether answered client_too_old: the minimum version and where to update.
    @Published var updateRequired: TogetherClientTooOld?
    var togetherLinkPoll: Task<Void, Never>?
    /// Find players, Live now, public parties, discovery and game hubs.
    @Published var discover = DiscoverState()
    /// Share play: what the friends panel shows, and the running share play's pieces.
    @Published var share = ShareState() {
        didSet {
            // Discord's Join button follows the share play hosted and its code.
            if oldValue.hosting?.id != share.hosting?.id || oldValue.hosting?.joinCode != share.hosting?.joinCode { updateDiscord() }
        }
    }
    var shareSession: ShareSession?
    var shareWatch: ShareWatchSession?
    /// The party's voice: the call joined, the mesh, the microphone, ⌥V held, who speaks.
    @Published var voiceCall: String?
    var partyVoice: PartyVoice?
    /// The microphone's switch and deafening.
    @Published var mic = TogetherVoiceMic()
    var micOn: Bool { mic.on }
    var deafened: Bool { mic.deafened }
    @Published var talkHeld = false
    @Published var voiceSpeaking: Set<String> = []
    /// Who in the call muted or deafened themselves, as the server says.
    @Published var voiceMuted: Set<String> = []
    @Published var voiceDeafened: Set<String> = []
    /// What the server was last told about the user (nil: nothing yet in this call).
    var voiceSent: TogetherVoiceMic.State?
    /// The friend in a direct call (nil in the party's voice), and whether they have not answered yet.
    @Published var callFriend: TogetherPerson?
    @Published var callWaiting = false
    /// A friend calling now, and what rings and gives up on it.
    @Published var ringing: TogetherRinging?
    var ringTask: Task<Void, Never>?
    /// New relay credentials before the call's run out.
    var iceRenewal: Task<Void, Never>?
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
    /// The games folders, in order.
    var libraryRoots: [URL] { preferences.libraryFolders.map { URL(fileURLWithPath: $0) } }

    /// The games folder `game` was found in, whose store holds its unlocked copy: on the game's
    /// own drive, so the copy is an APFS clone and goes with the drive.
    func root(of game: Game) -> URL? {
        if let root = gameRoots[game.id] { return root }
        let path = game.folder.standardizedFileURL.path
        return libraryRoots.first { path.hasPrefix($0.standardizedFileURL.path + "/") }
    }
    var selectedGame: Game? { games.indices.contains(selected) ? games[selected] : nil }

    // MARK: Library

    /// Scans the games folders now, and watches them from then on: games copied in later show up
    /// by themselves, with a "New game" notice. A folder that is not there is looked at again on
    /// the next scan, and when a drive mounts.
    func rescan() {
        let roots = libraryRoots
        guard !roots.isEmpty else {
            // The last folder removed: the library is empty again.
            libraryMonitor?.stop()
            libraryMonitor = nil
            scanning = false
            games = []
            gameRoots = [:]
            libraryFolders = []
            installedRecords = [:]
            selected = 0
            libraryIndex = 0
            return
        }
        scanning = true
        if installer == nil && preparer == nil {
            for root in roots where FileManager.default.fileExists(atPath: root.path) { Installer.removeLeftovers(root: root) }
        }
        if let monitor = libraryMonitor, monitor.roots == roots {
            monitor.rescan()
            return
        }
        libraryMonitor?.stop()
        let stamp = recordsStamp
        let monitor = LibraryMonitor(roots: roots) { [weak self] update in
            // The records are read off the main thread too; each game's is one small file.
            let generation = stamp.withLock { $0 }
            let records = AppModel.records(of: update.games, roots: update.roots)
            Task { @MainActor in self?.libraryScanned(update, records: records, generation: generation, roots: roots) }
        }
        libraryMonitor = monitor
        monitor.start()
    }

    nonisolated private static func records(of games: [Game], roots: [String: URL]) -> [String: InstallRecord] {
        Dictionary(games.compactMap { game in roots[game.id].flatMap { Installer.record(of: Installer.bundle(for: game, root: $0)) }.map { (game.id, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// A scan's result: the library follows without moving the selection off the game it is on,
    /// and games that were not there before are announced.
    private func libraryScanned(_ update: LibraryMonitor.Update, records scanned: [String: InstallRecord], generation: Int, roots: [URL]) {
        guard libraryMonitor?.roots == roots, libraryRoots == roots else { return }
        scanning = false
        gameRoots = update.roots
        if libraryFolders != update.folders { libraryFolders = update.folders }
        let records = generation == recordsGeneration ? scanned : AppModel.records(of: update.games, roots: update.roots)
        let listingChanged = !GameLibrary.sameListing(games, update.games)
        if records.mapValues(\.toolkit) != installedRecords.mapValues(\.toolkit) || records.mapValues(\.date) != installedRecords.mapValues(\.date) {
            installedRecords = records
        }
        if listingChanged {
            let current = selectedGame?.id
            let focusedInLibrary = games.indices.contains(libraryIndex) ? games[libraryIndex].id : nil
            games = update.games
            if let current, let index = games.firstIndex(where: { $0.id == current }) { selected = index } else { selected = min(selected, max(0, games.count - 1)) }
            if let focusedInLibrary, let index = games.firstIndex(where: { $0.id == focusedInLibrary }) { libraryIndex = index } else { libraryIndex = min(libraryIndex, max(0, games.count - 1)) }
        }
        if !update.added.isEmpty { announceNewGames(update.added) }
        measureSelected()
    }

    /// "New game: <name>" (or "3 new games"): a toast while the launcher is in front, the banner
    /// over everything otherwise, and the game selected when the home screen shows.
    private func announceNewGames(_ added: [Game]) {
        guard preferences.onboarded else { return }
        let prepared = prepareNewGames(added)
        let text = AppModel.newGameText(added.map(\.name), preparing: prepared.preparing, waiting: prepared.waiting, skipped: prepared.skipped)
        let icon = added.count == 1 ? added[0].icon : nil
        if overlay == nil, running == nil, starting == nil, let index = games.firstIndex(of: added[0]) {
            withAnimation(Motion.focus) {
                selected = index
                focus = .tiles
            }
        }
        if NSApp.isActive {
            show(text, symbol: "gamecontroller.fill", icon: icon)
            if preferences.sounds { Sounds.shared.play(.select) }
        } else {
            let detail = added.count == 1 ? T.text(.newGameDetail) : ListFormatter.localizedString(byJoining: added.prefix(3).map(\.name)) + (added.count > 3 ? "…" : "")
            TrophyBanner.shared.notice(text, detail: detail, symbol: "gamecontroller.fill", icon: icon, cue: .select, sounds: preferences.sounds)
        }
    }

    /// "New game: <name>", with what happens to it when it is prepared in the background.
    static func newGameText(_ names: [String], preparing: Bool, waiting: Bool, skipped: PrepareSkip?) -> String {
        let one = names.count == 1
        switch skipped {
        case .battery: return TPrep.format(.newGameNotPreparedBattery, names[0])
        case .space: return TPrep.format(.newGameNotPreparedSpace, names[0])
        case nil: break
        }
        if preparing { return one ? TPrep.format(.newGamePreparing, names[0]) : TPrep.format(.newGamesPreparing, names.count) }
        if waiting { return one ? TPrep.format(.newGameWaiting, names[0]) : TPrep.format(.newGamesWaiting, names.count) }
        return one ? T.format(.newGame, names[0]) : T.format(.newGames, names.count)
    }

    /// A games folder added at the end of the list (Settings, the empty library, a folder opened
    /// with AnyPS5), or put first (`first`: the first-run setup choosing it).
    func chooseFolder(_ url: URL, first: Bool = false) {
        let folders = preferences.libraryFolders
        let chosen = first ? LibraryFolders.replacingFirst(with: url.path, in: folders) : LibraryFolders.adding(url.path, to: folders)
        if chosen != folders {
            preferences.libraryFolders = chosen
            selected = 0
        }
        rescan()
    }

    /// A games folder out of the list; its games leave the library, nothing on the drive changes.
    func removeFolder(_ path: String) {
        preferences.libraryFolders = LibraryFolders.removing(path, from: preferences.libraryFolders)
        rescan()
        show(T.text(.folderRemoved), symbol: "folder.badge.minus")
    }

    /// The selected game's size and trophies, once the selection rests on it. A folder walk (tens
    /// of thousands of files in a dump) and a trophy read go one at a time: when one ends, the
    /// game the selection rests on then is next, and the games passed on the way are skipped.
    func measureSelected() {
        // While a held direction moves the selection, once it rests (selectionMoved).
        guard let game = selectedGame, backdropID == nil else { return }
        readSelectedTrophies()
        guard sizes[game.id] == nil, sizeWalk == nil else { return }
        sizeWalk = game.id
        sizes[game.id] = -1
        let measure = folderSize
        Task.detached(priority: .utility) {
            let size = measure(game.folder)
            await MainActor.run {
                self.sizes[game.id] = size
                self.sizeWalk = nil
                self.measureSelected()
            }
        }
    }

    private func readSelectedTrophies() {
        guard let game = selectedGame, root(of: game) != nil, !trophiesRead.contains(game.id), trophyRead == nil else { return }
        trophyRead = game.id
        loadTrophies(game) { [weak self] in
            self?.trophyRead = nil
            self?.readSelectedTrophies()
        }
    }

    /// The tests and the benchmark: the library as if nothing had been measured yet.
    func forgetMeasurements() {
        sizes = [:]
        forgetTrophies()
    }

    /// The key art behind the home screen: the game the selection rests on. A held direction
    /// passes a game every 60 to 80 ms; a 0.55 s fade and a 4K decode for each would pile up.
    var backdropGame: Game? {
        if let id = backdropID, let game = games.first(where: { $0.id == id }) { return game }
        return selectedGame
    }

    static let selectionSettle: Duration = .milliseconds(180)

    private func selectionMoved(from old: Int) {
        guard settlesSelection else { return }
        if backdropID == nil, games.indices.contains(old) { backdropID = games[old].id }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.selectionSettle)
            guard let self, !Task.isCancelled else { return }
            self.backdropID = nil
            self.measureSelected()
        }
    }

    func state(of game: Game) -> GameState {
        if starting?.id == game.id { return .starting }
        if running?.game.id == game.id { return .running }
        if let (step, fraction) = progress[game.id] { return .installing(step: step, fraction: fraction) }
        if queue.contains(game.id) { return .queued }
        if let failure = failures[game.id] { return .failed(failure) }
        // An update dumped (or removed) since the unlock needs its executable relinked: unlocking again applies it.
        if let record = installedRecords[game.id], record.update == game.update?.version { return .installed(outdated: engineVersion(for: game).map { $0 != record.toolkit } ?? false) }
        if game.executable == .unreadable { return .unreadable }
        return .locked
    }

    // MARK: Trophies

    /// Reads the game's trophies once, or `again` after it may have unlocked some.
    /// Another profile plays: its trophies are read again.
    func forgetTrophies() {
        trophies = [:]
        trophiesRead = []
    }

    func loadTrophies(_ game: Game, again: Bool = false, then done: (@MainActor () -> Void)? = nil) {
        guard let root = root(of: game), again || !trophiesRead.contains(game.id) else { return }
        trophiesRead.insert(game.id)
        let bundle = Installer.bundle(for: game, root: root)
        let languages = trophyLanguages(game)
        Task.detached(priority: .utility) {
            let set = Trophies.load(game, bundle: bundle, languages: languages)
            await MainActor.run {
                self.trophies[game.id] = set
                if let set { self.recordTrophies(game, set) }
                done?()
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

    var displayDefaults: DisplayDefaults { preferences.displayDefaults ?? DisplayDefaults() }

    /// The settings a game starts with: its own, and Settings › Default Display for the display
    /// choices it left at Default.
    func launchSettings(for game: Game) -> GameSettings {
        settings(for: game).withDefaults(displayDefaults)
    }

    func updateDisplayDefaults(_ change: (inout DisplayDefaults) -> Void) {
        var value = displayDefaults
        change(&value)
        preferences.displayDefaults = value.isBuiltIn ? nil : value
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
        guard let toolkit = toolkit(for: game), let patches = GamePatches.load(titleID: game.titleID, from: toolkit.patches) else { return [] }
        return patches.resolution?.choices ?? []
    }

    // MARK: Unlocking

    func unlock(_ game: Game) {
        guard let root = root(of: game) else { return }
        guard let toolkit = toolkit(for: game) else { show(T.text(.noToolkit), symbol: "exclamationmark.triangle"); return }
        // Asked for while it is being prepared: it becomes the user's own and goes on at full speed.
        if prepare.active == game.id { return promotePreparation(game) }
        prepare.cancel(game.id)
        failures[game.id] = nil
        guard !queue.contains(game.id), progress[game.id] == nil else { return }
        // The room first: a drive that is short says so before anything is written.
        if let shortage = Installer.plan(game: game, toolkit: toolkit, root: root).shortage(free: FreeSpace.available(at: root), volume: FreeSpace.volumeName(at: root)) {
            return tellShortage(shortage, for: game)
        }
        queue.append(game.id)
        Sounds.shared.play(.select)
        startNext()
        stepPrepare()
    }

    /// The unlock of `game` did not start for want of room: the panel says how much is needed and
    /// free, and what to do.
    private func tellShortage(_ shortage: SpaceShortage, for game: Game) {
        if playAfterUnlock == game.id { playAfterUnlock = nil }
        spaceShortage = (game, shortage)
        Sounds.shared.play(.back)
        Feel.shared.vibrate(.error)
        if let index = games.firstIndex(of: game) { selected = index }
        open(.noSpace)
    }

    /// The next game in the queue, into the store of the games folder it is in.
    private func startNext() {
        guard installer == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let game = games.first(where: { $0.id == id }), let toolkit = toolkit(for: game), let root = root(of: game) else { startNext(); return }
        installer = runUnlock(game, toolkit: toolkit, root: root, background: false) { [weak self] result in
            guard let self else { return }
            self.installer = nil
            switch result {
            case .success:
                Sounds.shared.play(.unlocked)
                self.show(game.name + " · " + T.text(.ready), symbol: "lock.open.fill")
                if self.playAfterUnlock == id {
                    self.playAfterUnlock = nil
                    self.play(game)
                }
                self.togetherUnlockDone(id, succeeded: true)
            case .failure(let error) where error is CancellationError:
                self.togetherUnlockDone(id, succeeded: false)
            case .failure(let shortage as SpaceShortage):
                self.tellShortage(shortage, for: game)
            case .failure(let error):
                self.failures[id] = error.localizedDescription
                self.togetherUnlockDone(id, succeeded: false)
                self.show(T.text(.unlockFailed) + ": " + game.name, symbol: "exclamationmark.triangle.fill")
            }
            self.startNext()
            self.stepPrepare()
        }
    }

    /// Starts unlocking `game`: its progress, its log, the toolkit checked again where it was
    /// downloaded or put together by the user. `done` runs on the main actor after the log and
    /// the record are written.
    private func runUnlock(_ game: Game, toolkit: Toolkit, root: URL, background: Bool, done: @escaping (Result<URL, Error>) -> Void) -> Installer {
        let id = game.id
        // A downloaded engine is checked against its manifest again before anything of it runs
        // (once per change of its files); a custom folder must still hold a whole toolkit.
        let downloaded = installedToolkits.first { $0.folder == toolkit.root }?.version
        let custom = customToolkit?.root == toolkit.root
        let store = toolkitStore
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
        installer.background = background
        Task.detached(priority: background ? .utility : .userInitiated) {
            let result: Result<URL, Error> = Result {
                if let downloaded { _ = try store.verifiedToolkit(version: downloaded) }
                if custom, let problem = Toolkit.layoutProblem(at: toolkit.root) { throw InstallError("the engine folder is incomplete: \(problem)") }
                return try installer.run(root: root)
            }
            await MainActor.run {
                self.progress[id] = nil
                switch result {
                case .success(let bundle):
                    try? GameLog.writeUnlockLog(self.installLog[id] ?? [], failure: nil, titleID: game.titleID)
                    if let record = Installer.record(of: bundle) { self.installedRecords[id] = record }
                    self.recordsGeneration += 1
                case .failure(let error) where error is CancellationError || error is SpaceShortage:
                    break
                case .failure(let error):
                    try? GameLog.writeUnlockLog(self.installLog[id] ?? [], failure: error.localizedDescription, titleID: game.titleID)
                }
                done(result)
                // Ready without some of the dump's modules: one short sentence.
                if case .success = result, let text = AppModel.leftOutText(game.name, installer.leftOut) {
                    self.show(text, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
        return installer
    }

    /// What an unlock that left modules of the dump out says once the game is ready: one short
    /// sentence, encrypted files first since dumping again fixes those. The files themselves are in
    /// the unlock's log; a list of them here was too long to read before the notice went.
    nonisolated static func leftOutText(_ name: String, _ leftOut: [LeftOutModule]) -> String? {
        guard !leftOut.isEmpty else { return nil }
        let encrypted = leftOut.contains { $0.reason == .encrypted }
        return T.format(encrypted ? .unlockLeftOutEncrypted : .unlockLeftOutNotRelinked, name)
    }

    /// The update the Play prompt offers: unlock the game again, then start it.
    func updateAndPlay(_ game: Game) {
        playAfterUnlock = game.id
        unlock(game)
    }

    func cancelUnlock(_ game: Game) {
        if playAfterUnlock == game.id { playAfterUnlock = nil }
        if prepare.contains(game.id) {
            if prepare.cancel(game.id) { preparer?.cancel() }
            Sounds.shared.play(.back)
            return
        }
        if let index = queue.firstIndex(of: game.id) { queue.remove(at: index); stepPrepare(); return }
        if progress[game.id] != nil { installer?.cancel() }
        Sounds.shared.play(.back)
    }

    // MARK: Preparing new games

    /// Settings → Game Library → Prepare New Games Automatically; on unless turned off.
    var preparesNewGames: Bool { preferences.prepareNewGames ?? true }

    /// The game being prepared in the background.
    func isPreparing(_ game: Game) -> Bool { prepare.active == game.id && !prepare.promoted }

    /// What the background preparation looks at now.
    private var prepareConditions: PrepareConditions {
        PrepareConditions(enabled: preparesNewGames && preferences.onboarded && persists, playing: running != nil || starting != nil,
                          unlocking: installer != nil || !queue.isEmpty, power: PowerState.current())
    }

    /// Takes the queue's steps until it has nothing more to do now; the skips it makes are told
    /// (unless `quiet`, when the caller tells them) and returned.
    @discardableResult
    func stepPrepare(quiet: Bool = false) -> [(String, PrepareSkip)] {
        guard !libraryRoots.isEmpty else { return [] }
        let conditions = prepareConditions
        var skipped: [(String, PrepareSkip)] = []
        while true {
            let action = prepare.step(conditions) { [weak self] id in
                guard let self, let game = self.games.first(where: { $0.id == id }), let toolkit = self.toolkit(for: game), let root = self.root(of: game) else { return nil }
                return Installer.plan(game: game, toolkit: toolkit, root: root).shortage(free: FreeSpace.available(at: root), volume: FreeSpace.volumeName(at: root))
            }
            switch action {
            case .none:
                schedulePrepareCheck()
                if !quiet { for (id, reason) in skipped { tellSkipped(id, reason) } }
                return skipped
            case .start(let id): startPreparing(id)
            case .pause: preparer?.pause()
            case .resume: preparer?.resume()
            case .skip(let id, let reason): skipped.append((id, reason))
            }
        }
    }

    /// While games wait or one is being prepared, the power is looked at again now and then
    /// (plugged in, or the battery charged past the line).
    private func schedulePrepareCheck() {
        let waiting = !prepare.pending.isEmpty || prepare.active != nil
        if !waiting { prepareTimer?.invalidate(); prepareTimer = nil; return }
        guard prepareTimer == nil else { return }
        prepareTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.stepPrepare() }
        }
    }

    private func startPreparing(_ id: String) {
        guard let game = games.first(where: { $0.id == id }), state(of: game) == .locked, let toolkit = toolkit(for: game), let root = root(of: game) else {
            prepare.finished(id)
            return
        }
        preparer = runUnlock(game, toolkit: toolkit, root: root, background: true) { [weak self] result in
            guard let self else { return }
            let promoted = self.prepare.promoted
            self.preparer = nil
            self.prepare.finished(id)
            switch result {
            case .success:
                Sounds.shared.play(.unlocked)
                let text = TPrep.format(.readyToPlay, game.name)
                if NSApp.isActive || !self.persists {
                    self.show(text, symbol: "checkmark.circle.fill", icon: game.icon)
                } else if self.running == nil && self.starting == nil {
                    TrophyBanner.shared.notice(text, detail: TPrep.text(.readyToPlayDetail), symbol: "checkmark.circle.fill", icon: game.icon, cue: .unlocked, sounds: self.preferences.sounds)
                }
                if promoted, self.playAfterUnlock == id {
                    self.playAfterUnlock = nil
                    self.play(game)
                }
            case .failure(let error) where error is CancellationError:
                if self.playAfterUnlock == id { self.playAfterUnlock = nil }
            case .failure(let shortage as SpaceShortage):
                // The room went while it waited: told like a skip.
                if promoted { self.tellShortage(shortage, for: game) } else { self.tellSkipped(id, .space(shortage)) }
            case .failure(let error):
                if self.playAfterUnlock == id { self.playAfterUnlock = nil }
                self.failures[id] = error.localizedDescription
                self.show(T.text(.unlockFailed) + ": " + game.name, symbol: "exclamationmark.triangle.fill")
            }
            self.startNext()
            self.stepPrepare()
        }
    }

    /// Play on a game being prepared: it no longer waits for anything but a game playing, runs at
    /// full speed and starts when it is ready.
    private func promotePreparation(_ game: Game) {
        prepare.promote(game.id)
        preparer?.background = false
        playAfterUnlock = game.id
        Sounds.shared.play(.select)
        show(TPrep.format(.startsWhenReady, game.name), symbol: "play.circle.fill", icon: game.icon)
        stepPrepare()
    }

    private func tellSkipped(_ id: String, _ reason: PrepareSkip) {
        guard let game = games.first(where: { $0.id == id }) else { return }
        switch reason {
        case .battery:
            show(TPrep.format(.notPreparedBattery, game.name), symbol: "battery.25percent", icon: game.icon)
        case .space(let shortage):
            show(TPrep.format(.notPreparedSpace, game.name, shortage.needed.byteText, shortage.free.byteText), symbol: "externaldrive.badge.exclamationmark", icon: game.icon)
        }
    }

    /// New games from a scan: the locked ones go to the background queue, and the "New game"
    /// notice says what happens to them.
    private func prepareNewGames(_ added: [Game]) -> (preparing: Bool, waiting: Bool, skipped: PrepareSkip?) {
        guard preparesNewGames, persists else { return (false, false, nil) }
        let locked = added.filter { state(of: $0) == .locked }
        guard !locked.isEmpty else { return (false, false, nil) }
        prepare.add(locked.map(\.id))
        let skips = stepPrepare(quiet: true)
        let first = locked[0].id
        if let skip = skips.first(where: { $0.0 == first }) { return (false, false, skip.1) }
        return (prepare.active == first, prepare.pending.contains(first), nil)
    }

    func uninstall(_ game: Game) {
        guard let root = root(of: game) else { return }
        try? FileManager.default.removeItem(at: Installer.bundle(for: game, root: root))
        try? FileManager.default.removeItem(at: Installer.dataFolder(for: game, root: root))
        try? FileManager.default.removeItem(at: Installer.keptRelink(for: game, root: root))
        installedRecords[game.id] = nil
        recordsGeneration += 1
        show(T.text(.uninstallDone), symbol: "trash")
    }

    func clearShaderCache(_ game: Game) {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/\(game.bundleIdentifier)")
        try? FileManager.default.removeItem(at: cache)
        show(T.text(.cacheCleared), symbol: "sparkles")
    }

    // MARK: Playing

    func primaryAction(_ game: Game) {
        if familyPrimaryAction(game) { return }
        switch state(of: game) {
        case .installed(let outdated): outdated ? open(.updateChoice) : play(game)
        case .locked, .failed: unlock(game)
        case .installing where isPreparing(game): promotePreparation(game)
        case .installing, .queued: cancelUnlock(game)
        case .running: running?.app.activate()
        case .starting: break
        case .unreadable: show(T.text(.unreadableDump), symbol: "xmark.octagon")
        }
    }

    /// Plays the game, its saves brought in step first where save sync is on; `trace` turns
    /// detailed logging on for this start only.
    func play(_ game: Game, trace: Bool = false) {
        guard root(of: game) != nil, starting == nil, running == nil, syncing == nil, fontWait == nil else { return }
        // The profile's own saves and trophies in the game folder before anything reads them.
        activateProfileSaves(game)
        familyGate(game) { self.syncSaves(game) { self.ensureFonts(game) { self.start(game, trace: trace) } } }
    }

    private func start(_ game: Game, trace: Bool = false) {
        guard let root = root(of: game), starting == nil, running == nil else { return }
        let bundle = Installer.bundle(for: game, root: root)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        var settings = launchSettings(for: game)
        // Settings → Controllers → Stick Dead Zone, for a game that set none of its own.
        if let deadzone = preferences.stickDeadzone, deadzone > 0 { settings.tuning = StickDeadzone.tuning(settings.tuning, percent: deadzone) }
        // Settings → Battery & Heat: one resolution step down while a profile asks for it.
        if let lower = powerResolution(for: game, current: settings.resolution) { settings.resolution = lower }
        let inputFile = AppModel.inputFile(for: game)
        // Without the file the game keeps the engine's built-in keys.
        let written = (try? settings.writeInputFile(to: inputFile)) != nil
        let screenshots = screenshotsFolder
        try? FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        configuration.environment = settings.environment(launcherLanguage: preferences.language.consoleLanguage, inputFile: written ? inputFile : nil, screenshots: screenshots, fonts: gameFontsFolder(), trace: trace)
            .merging(remote?.bridgeEnvironment ?? [:]) { _, phone in phone }
            // The update and add-ons dumped beside the game.
            .merging(GameAddons.environment(for: game)) { own, _ in own }
            // Settings → Game Presets, for the games that ask the console for them.
            .merging(gamePresets.environment) { own, _ in own }
            .merging(OnlinePlayHost.environment(for: game, client: together, engineBuild: engineBuild(for: game))) { _, online in online }
            // Where the engine's online bridge finds the AnyTogether game session, once there is one.
            .merging(togetherUser == nil ? [:] : ["ANYPS5_TOGETHER_SESSION": TogetherGameSession.bridgeFile.path]) { own, _ in own }
            // The battery and heat profiles' frame cap, and the file they change it through live.
            .merging(powerEnvironment()) { _, power in power }
        markStart(of: game, traced: trace || settings.trace == true)
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
                    self.lastSessions[game.id]?.pid = app.processIdentifier
                    self.sessionStart = Date()
                    self.familyGameStarted()
                    self.watchTrophies(game)
                    self.watchFonts(game)
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
    /// What has to reach a server before the app quits (leaving a call), when there is any.
    static var beforeQuit: (() -> Task<Void, Never>?)?

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
        case .theme(let id): installHubTheme(id)
        case .game(let id), .play(let id):
            guard let index = games.firstIndex(where: { $0.titleID == id }) else {
                return show(T.format(.linkNoGame, id), symbol: "questionmark.folder")
            }
            if overlay != nil { closeOverlay() }
            withAnimation(Motion.focus) { selected = index }
            if case .play = link {
                // A game's Steam shortcut: the launcher goes with the game.
                if steamLaunch.fromSteam, steamLaunch.play == id, steamQuitAfter == nil { steamQuitAfter = games[index].id }
                primaryAction(games[index])
            }
        }
    }

    /// A folder opened with AnyPS5: a game in the library is selected; a game or a folder of
    /// games elsewhere joins the games folders, once the user agrees.
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
    @Published var syncing: String?

    var syncRoot: URL? { preferences.syncFolder.map { URL(fileURLWithPath: $0) } ?? SaveSync.iCloudDrive }

    private func saveSync(for game: Game) -> SaveSync? {
        guard preferences.saveSync == true, let root = syncRoot, let folder = gameFolder(game) else { return nil }
        let profile = saveSyncProfile
        return SaveSync(game: folder, cloud: SaveSync.folder(in: root, titleID: game.titleID, profile: profile), backups: SaveBackup.folder(for: game),
                        mac: Host.current().localizedName ?? "Mac", profile: profile)
    }

    /// Syncs the game's saves off the main thread, says what came from another Mac, then goes on.
    private func syncSaves(_ game: Game, then: @escaping @MainActor () -> Void) {
        if preferences.syncThrough == AppModel.syncThroughTogether, preferences.saveSync == true {
            // Through AnyTogether's cloud; signed out or a server without files, nothing syncs.
            guard let cloudSync = cloudSave(for: game) else { return then() }
            return syncThroughCloud(cloudSync, game: game, then: then)
        }
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

    // MARK: Broadcasting

    /// Live to Twitch, YouTube or an RTMP server (Broadcaster.swift, BroadcastPanel.swift).
    lazy var broadcaster: Broadcaster = makeBroadcaster()

    // MARK: Clips

    let clipRecorder = ClipRecorder()
    var clipSeconds: Int { ReplayBudget.length(preferences.clipLength) }

    // MARK: PS, the quick menu and Settings → Shortcuts (HomeMenus.swift)

    /// The last PS that switched between the game and the launcher.
    var lastHome: Date? {
        get { lastToggle }
        set { lastToggle = newValue }
    }
    /// The remote pad channel the quick menu's Options press goes through on an engine without
    /// presses, held a few seconds.
    var pauseBridge: Int?
    var pauseSequence: UInt32 = 0
    let pauseSession = UInt64.random(in: 1 ... UInt64.max)
    var pauseRelease: Task<Void, Never>?
    /// The id of the last press (GamePause.pressPackets); the engine counts copies of one once.
    var pausePress = UInt32.random(in: 1 ... UInt32.max)
    /// The chord being recorded for a shortcut.
    var chordRecorder: ChordRecorder?

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

    /// Settings → Behaviour → Clip Length: a game being recorded starts again at the new length.
    func setClipLength(_ seconds: Int) {
        guard seconds != clipSeconds else { return }
        preferences.clipLength = seconds
        if let app = running?.app, clipRecorder.recordingPid != nil { startClips(for: app) }
    }

    /// The buffer's memory once full at the main display's size, for the setting's line.
    var clipMegabytes: Int {
        let frame = NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return ReplayBudget.megabytes(width: Int(frame.width * scale), height: Int(frame.height * scale), seconds: clipSeconds)
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
        guard familyAllows(.mediaSharing) else { return TrophyBanner.shared.notice(FS.refusal(.mediaSharing), detail: "", symbol: "hand.raised.fill", sounds: preferences.sounds) }
        // With the replay buffer off there is nothing kept: Create takes a screenshot instead.
        guard preferences.clips == true else { return takeScreenshot() }
        let folder = screenshotsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(game.titleID)-\(Self.captureStamp()).mp4")
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
            discordSince = Date()
            if let game = running?.game { tellLowPower(about: game) }
            startClips(for: app)
            gameWindowShown = true
            updateDiscord()
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
        // A game that has already quit reports -1, and makeProcessSource traps on a negative pid.
        guard pid > 0 else { return applicationEnded(pid) }
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
        defer { restartIfWaiting() }
        // The game's own menus go with it.
        pausedGame = false
        if overlay == .quickMenu || overlay == .closeGame { overlay = nil }
        OnlinePlayHost.stop()
        if let start = sessionStart { recordPlay(running.game, from: start) }
        sessionStart = nil
        familyGameEnded()
        clipRecorder.stop()
        broadcaster.stop()
        gameWindowShown = false
        updateRemotePlay()
        followSharePlay()
        updateTogetherPresence()
        syncSaves(running.game) {}
        discordSince = nil
        updateDiscord()
        loadTrophies(running.game, again: true)
        lastSessions[running.game.id]?.ended = Date()
        lastSessions[running.game.id]?.withoutWindow = starting != nil
        traceTrim?.cancel()
        traceTrim = nil
        diagnose(running.game, pid: running.app.processIdentifier)
        checkFontsAfterEnd(running.game)
        trophyWatch?.cancel()
        trophyWatch = nil
        exitWatch?.cancel()
        exitWatch = nil
        if starting != nil {
            startWatch?.cancel()
            withAnimation(Motion.overlay) { starting = nil }
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
                self.tellPhoneBroadcast(self.broadcaster.phase.active)
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
            // The phone says when this Mac uses another AnyTogether server than its own.
            server.togetherServer = together.base.absoluteString
            if (try? server.start()) != nil {
                remote = server
                applyAssist()
                updateBrowserPlay()
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

    func discordOff() { updateDiscord() }

    /// Turned on again with a game in front: Discord shows it at once, from when it started.
    func discordOn() { updateDiscord() }

    /// Since when the user is in the party, for Discord; a party left forgets who asked with its code.
    func partyChanged() {
        guard party?.id != partySince?.id else { return updateDiscord() }
        partySince = party.map { ($0.id, Date()) }
        codeAskers = []
        updateDiscord()
    }

    /// What the user's Discord profile shows, when the presence setting is on: the game once its
    /// window is up, the party they are in ("In a party", with its size, even with no game), and
    /// the Join button with the share play's or party's code. The party's leader or the share
    /// play's host gets a code made for the button when none works, but not where they stopped
    /// it themselves; a code running out is such a time, with nothing else changing. Discord is
    /// told only when something changed.
    func updateDiscord() {
        guard persists else { return }
        let game = gameWindowShown ? running?.game : nil
        var refresh: Date?
        defer { refreshDiscord(at: refresh) }
        guard preferences.discordPresence ?? true, game != nil || party != nil else {
            discordShown = nil
            if !discordCleared {
                discordCleared = true
                discord.clear()
            }
            return
        }
        var button: DiscordActivity.Button?
        if preferences.discordJoin ?? true, let me = togetherUser?.id {
            let allowed = familyAllows(.publicMatchmaking)
            let hosting = share.hosting.map {
                DiscordJoin.Source(id: $0.id, code: $0.joinCode, mine: true, mayMake: allowed && !codeStopped.contains($0.id) && !codeMakingForDiscord.contains($0.id))
            }
            let partySource = party.map {
                DiscordJoin.Source(id: $0.id, code: $0.joinCode, mine: $0.isLeader(me), mayMake: allowed && !codeStopped.contains($0.id) && !codeMakingForDiscord.contains($0.id))
            }
            refresh = DiscordJoin.refresh(share: hosting, party: partySource)
            switch DiscordJoin.plan(share: hosting, party: partySource) {
            case .button(let url): button = DiscordActivity.Button(label: JS.text(.discordJoinLabel), url: url)
            case .makeShare(let id): makeCodeForDiscord(id, sharePlay: true)
            case .makeParty(let id): makeCodeForDiscord(id, sharePlay: false)
            case .none: break
            }
        }
        let activity = DiscordActivity(game: game?.name, since: game != nil ? discordSince ?? sessionStart : partySince?.at,
                                       party: party.map { DiscordActivity.Party(id: $0.id, size: $0.members.count, max: TogetherParty.maxSize) },
                                       button: button, partyText: JS.text(.inParty))
        guard activity != discordShown else { return }
        discordShown = activity
        discordCleared = false
        discord.show(activity)
    }

    /// Discord again once `date` passes (the code its button opens ran out): the button opens the
    /// other code, a new one made for it, or goes; the panels stop showing the old code too.
    private func refreshDiscord(at date: Date?) {
        guard date != discordRefresh?.at else { return }
        discordRefresh?.task.cancel()
        discordRefresh = date.map { date in
            (Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow) + 1))
                guard let self, !Task.isCancelled else { return }
                self.discordRefresh = nil
                self.objectWillChange.send()
                self.updateDiscord()
            }, date)
        }
    }

    /// A code for the Join button, made once; one that fails is not tried again this session.
    private func makeCodeForDiscord(_ id: String, sharePlay: Bool) {
        codeMakingForDiscord.insert(id)
        let client = together
        Task {
            do {
                let code = sharePlay ? try await client.makeJoinCode(sharePlay: id) : try await client.makeJoinCode(party: id)
                codeMakingForDiscord.remove(id)
                if sharePlay, let hosting = share.hosting, hosting.id == id {
                    share.hosting = hosting.with(joinCode: code)
                } else if !sharePlay, let current = party, current.id == id {
                    party = current.with(joinCode: code)
                }
            } catch {
                // Refused (family settings, a muted account, too many): no button for it.
            }
        }
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
        case .command("broadcastStart"), .command("broadcastStop"):
            // Go live and Stop broadcast in the phone's PS menu.
            phoneBroadcast(message == .command(name: "broadcastStart"))
        case .command(let name):
            // The phone's pad is a pad: the screens show its glyphs.
            InputModeState.shared.usedPad()
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
            // The phone's PS: the quick menu over a game in front, as a controller's does.
            InputModeState.shared.usedPad()
            if running != nil, !NSApp.isActive { shortcut(.home, hold: false) } else { bringLauncherFront() }
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
    /// playing. One press is one switch: a press within `toggleDebounce` of the last switch does
    /// nothing (macOS tells the launcher it is active a moment after the switch, and the same press
    /// seen again then would switch straight back).
    func togglePlaying() {
        guard let running, starting == nil else { return bringLauncherFront() }
        let now = Date()
        if let last = lastToggle, now.timeIntervalSince(last) < Self.toggleDebounce, now >= last { return }
        lastToggle = now
        if NSApp.isActive {
            Sounds.shared.play(.select)
            NSApp.yieldActivation(to: running.app)
            running.app.activate()
        } else {
            bringLauncherFront()
            Sounds.shared.play(.select)
        }
    }

    static let toggleDebounce: TimeInterval = 0.45
    private var lastToggle: Date?

    func bringLauncherFront() {
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
        guard let root = root(of: game) else { return }
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
                        Feel.shared.vibrate(.trophy)
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

    nonisolated static func logFile(for game: Game) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AnyPS5/\(game.titleID).log")
    }

    /// The log line the diagnosis reads from, so only this start's output counts. A log grown
    /// too big is set aside first; a detailed one is kept under its cap while the game runs.
    private func markStart(of game: Game, traced: Bool) {
        diagnoses[game.id] = nil
        starts[game.id] = Date()
        lastSessions[game.id] = LastSession(traced: traced)
        let file = AppModel.logFile(for: game)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        GameLog.rollForStart(file)
        traceTrim?.cancel()
        traceTrim = nil
        if traced {
            traceTrim = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    GameLog.trim(file, cap: TraceMode.cap)
                }
            }
            TrophyBanner.shared.notice(TC.text(.traceOnNotice), detail: TC.text(.traceOnNoticeDetail), symbol: "text.magnifyingglass", sounds: false)
        }
        // The controllers connected at the start, in the log a crash report reads.
        let pads = Controllers.shared.reportLines.map { "[anyps5-launcher] controllers: \($0)\n" }.joined()
        let line = "\n\(Diagnosis.startMarker) \(ISO8601DateFormatter().string(from: Date())) \(game.titleID)\(traced ? " trace" : "")\n" + pads
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
        markFontLog(of: game, at: UInt64(max(0, GameLog.size(of: file))))
    }

    /// The log of the game's last start, read from the end of its log file.
    nonisolated static func lastSession(of game: Game) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logFile(for: game)) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 4_000_000 ? end - 4_000_000 : 0)
        return Diagnosis.lastSession(String(decoding: handle.readDataToEndOfFile(), as: UTF8.self))
    }

    /// Reads why the game stopped once macOS has had a few seconds to write its crash report,
    /// and offers the report when it stopped abnormally.
    private func diagnose(_ game: Game, pid: pid_t) {
        let start = starts[game.id] ?? Date().addingTimeInterval(-600)
        let withoutWindow = lastSessions[game.id]?.withoutWindow ?? false
        Task.detached(priority: .userInitiated) {
            // macOS writes the crash report a moment after the process is gone: up to six
            // seconds, less for a log that ends on the engine's orderly shutdown.
            var report: String?
            for attempt in 1...12 {
                try? await Task.sleep(for: .milliseconds(500))
                report = Diagnosis.crashReport(since: start, bundleIdentifier: game.bundleIdentifier, pid: pid)
                if report != nil { break }
                if attempt == 3 && Diagnosis.cleanShutdown(AppModel.lastSession(of: game)) { break }
            }
            let found = Diagnosis.read(session: AppModel.lastSession(of: game), crashReport: report)
            await MainActor.run {
                self.diagnoses[game.id] = found
                if found != nil || withoutWindow { self.offerReport(game) }
                // Started from the game's Steam shortcut: the launcher goes when it ended well, so
                // Steam sees the game end; a crash keeps it open on the report.
                if self.steamQuitAfter == game.id {
                    self.steamQuitAfter = nil
                    if found == nil && !withoutWindow { NSApp.terminate(nil) }
                }
            }
        }
    }

    /// The crash panel for the last session of the game, from its options or the log.
    func makeReport(_ game: Game) {
        openSessionReport(game, afterCrash: false)
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
        guard let root = root(of: game) else { return nil }
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
        guard let root = root(of: game) else { return }
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
        panelInRows = next == .gameSettings || next == .confirmUninstall || next == .controls || next == .updateChoice || next == .crashReport || next == .noSpace
            || next == .updateRequired
        // The controls panel opens on its first key, below the hint.
        if next == .controls {
            panelRow = 1
            if let game = selectedGame { readControls(game) }
        }
        if next == .trophies {
            trophyIndex = 0
            revealedTrophies = []
        }
        if next == .gallery { loadGallery() }
        if next == .advanced || next == .updateRequired { panelRow = 1 }
        panelInRows = panelInRows || next == .advanced || next == .themes || next == .studio || next == .friends || next == .party
        if next == .friends { refreshFriends() }
        if next == .party {
            loadParty()
            if togetherFriends.isEmpty { refreshFriends() }
        }
        if next == .settings { refreshEngines() }
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

    func show(_ text: String, symbol: String, icon: URL? = nil) {
        // Something went wrong: two short taps in the controller.
        if symbol.hasPrefix("exclamationmark") { Feel.shared.vibrate(.error) }
        toastTask?.cancel()
        withAnimation(Motion.overlay) { toast = Toast(text: text, symbol: symbol, icon: icon) }
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

