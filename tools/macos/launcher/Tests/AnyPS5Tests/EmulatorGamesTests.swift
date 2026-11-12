@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import Darwin
import XCTest

/// An emulator run the test ends itself: Stop's SIGTERM ends it unless it ignores that, SIGKILL
/// always does.
final class FakeEmulatorRun: EmulatorRun, @unchecked Sendable {
    let processIdentifier: Int32 = 0
    let started = Date()
    private let ignoresTerm: Bool
    private let lock = NSLock()
    private var code: Int32?
    private var waiting: [CheckedContinuation<Int32, Never>] = []
    private var sent: [Int32] = []

    init(ignoresTerm: Bool = false) { self.ignoresTerm = ignoresTerm }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var signals: [Int32] { locked { sent } }
    var ended: Bool { locked { code != nil } }

    func stop() -> Bool {
        locked { sent.append(SIGTERM) }
        if !ignoresTerm { quit(-SIGTERM) }
        return true
    }

    func kill() {
        locked { sent.append(SIGKILL) }
        quit(-SIGKILL)
    }

    func quit(_ status: Int32 = 0) {
        let told: [CheckedContinuation<Int32, Never>] = locked {
            guard code == nil else { return [] }
            code = status
            defer { waiting = [] }
            return waiting
        }
        for continuation in told { continuation.resume(returning: status) }
    }

    func exitCode() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let code {
                lock.unlock()
                continuation.resume(returning: code)
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// The emulator starts the model asks for, each answered when the test says (or at once).
final class FakeEmulatorStarts: @unchecked Sendable {
    struct Call {
        let program: URL
        let arguments: [String]
    }

    private let lock = NSLock()
    private var made: [Call] = []
    private var answers: [Int: EmulatorRun] = [:]
    private var waiting: [Int: CheckedContinuation<EmulatorRun, Never>] = [:]
    /// Answered as soon as asked.
    private let immediate: EmulatorRun?

    init(immediate: EmulatorRun? = nil) { self.immediate = immediate }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var calls: [Call] { locked { made } }

    func start(_ program: URL, _ arguments: [String]) async -> EmulatorRun {
        let index: Int = locked {
            made.append(Call(program: program, arguments: arguments))
            return made.count - 1
        }
        if let immediate { return immediate }
        return await withCheckedContinuation { continuation in
            lock.lock()
            if let run = answers[index] {
                lock.unlock()
                continuation.resume(returning: run)
            } else {
                waiting[index] = continuation
                lock.unlock()
            }
        }
    }

    /// The start number `index` comes up with `run`.
    func answer(_ index: Int, with run: EmulatorRun) {
        let continuation: CheckedContinuation<EmulatorRun, Never>? = locked {
            answers[index] = run
            return waiting.removeValue(forKey: index)
        }
        continuation?.resume(returning: run)
    }
}

/// Emulator games in the launcher, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/standalone_retro_test.dart): the switch off by default, Settings › Emulators, the
/// start and its cancel, the console folders on Home, and the disc kept out of what follows a
/// PS5 game.
@MainActor
final class EmulatorGamesTests: XCTestCase {
    private var made: [URL] = []

    override func tearDown() {
        for url in made { try? FileManager.default.removeItem(at: url) }
        made = []
    }

    private func model(games count: Int = 3) throws -> (AppModel, URL) {
        let model = try LauncherFixture.model(games: count)
        let root = try XCTUnwrap(model.libraryRoots.first)
        made.append(root)
        return (model, root)
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-emulators-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        made.append(url)
        return url
    }

    @discardableResult
    private func write(_ data: Data, _ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func retroJSON(_ fields: [String: String], in folder: URL) throws {
        try write(JSONSerialization.data(withJSONObject: fields), folder.appendingPathComponent("retro.json"))
    }

    /// An application bundle as the emulators ship on the Mac: its program in Contents/MacOS.
    private func application(_ name: String, executable: String) throws -> (app: URL, program: URL) {
        let app = try scratch().appendingPathComponent(name)
        let plist = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>\#(executable)</string><key>CFBundleIdentifier</key><string>org.example.test\#(UUID().uuidString)</string></dict></plist>"#
        try write(Data(plist.utf8), app.appendingPathComponent("Contents/Info.plist"))
        let program = try write(Data(), app.appendingPathComponent("Contents/MacOS/\(executable)"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        return (app, program)
    }

    /// A PARAM.SFO naming TITLE_ID BLUS01234.
    private func paramSFO() -> Data {
        let key = Array("TITLE_ID".utf8) + [0], value = Array("BLUS01234".utf8) + [0]
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16) }
        let keyStart = 36
        let header: [UInt8] = [0x00, 0x50, 0x53, 0x46] + u32(0x0101) + u32(keyStart) + u32(keyStart + key.count) + u32(1)
        let entry = u16(0) + u16(0x0204) + u32(value.count) + u32(value.count) + u32(0)
        return Data(header + entry + key + value)
    }

    private func settle(_ condition: () -> Bool, _ message: String = "") async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), message)
    }

    // MARK: Choosing an emulator and playing

    func testEachConsolePicksAnApplicationAndStartsTheDiscInItsProgram() async throws {
        for (platform, discName, emulator) in [(RetroPlatform.ps1, "Game disc.cue", "DuckStation"), (.ps2, "Game disc.iso", "PCSX2"), (.ps3, "PS3_DISC.SFB", "rpcs3")] {
            let (model, root) = try model(games: 1)
            let folder = root.appendingPathComponent("Retro Game")
            let disc = try write(Data(), folder.appendingPathComponent(discName))
            var boot = disc
            if platform == .ps3 {
                boot = try write(Data(), folder.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN"))
                try write(paramSFO(), folder.appendingPathComponent("PS3_GAME/PARAM.SFO"))
            } else {
                try retroJSON(["platform": platform.rawValue, "titleId": "TEST12345", "name": "Retro game", "disc": discName], in: folder)
            }
            model.setRetroLibrary(true)
            let game = try XCTUnwrap(model.games.first { $0.retro != nil }, "\(platform)")
            XCTAssertNil(model.installedRecords[game.id], "nothing of a disc is unlocked")
            XCTAssertEqual(model.state(of: game), .needsEmulator)

            var picked: URL?
            var asked: [String] = []
            model.pickEmulator = { title in asked.append(title); return picked }
            // Select on a disc without its emulator asks for one.
            model.primaryAction(game)
            XCTAssertEqual(asked, ["Select the \(platform.emulator) executable"])
            XCTAssertNil(model.preferences.retroEmulators?[platform.rawValue], "given up: nothing kept")
            let (app, program) = try application("\(platform.emulator).app", executable: emulator)
            picked = app
            model.chooseStandaloneEmulator(platform)
            XCTAssertEqual(model.preferences.retroEmulators?[platform.rawValue], app.path, "the application, as it was picked")
            XCTAssertEqual(model.state(of: game), .installed(outdated: false))

            let run = FakeEmulatorRun()
            let starts = FakeEmulatorStarts(immediate: run)
            model.startEmulator = { program, arguments, _ in await starts.start(program, arguments) }
            model.play(game)
            try await settle({ model.emulator != nil }, "\(platform) plays")
            let call = try XCTUnwrap(starts.calls.first)
            XCTAssertEqual(call.program.resolvingSymlinksInPath().path, program.resolvingSymlinksInPath().path, "the bundle's own program")
            // The temporary folder is listed through /private: both written the same way.
            let real = { (path: String) in path.hasPrefix("/") ? URL(fileURLWithPath: path).resolvingSymlinksInPath().path : path }
            let bootPath = real(boot.path)
            XCTAssertEqual(call.arguments.map(real), platform == .ps3 ? ["--no-gui", bootPath] : ["-nogui", "--", bootPath])
            XCTAssertNotNil(model.preferences.lastPlayed[game.id])
            XCTAssertEqual(model.state(of: game), .running)
            XCTAssertNil(model.running, "the PS5 game's slot, which presence, Discord and sessions follow, stays empty")
            XCTAssertEqual(model.playingGame, game)
            run.quit()
            try await settle({ model.emulator == nil }, "the emulator closed")
            XCTAssertEqual(model.state(of: game), .installed(outdated: false))

            try FileManager.default.removeItem(at: boot)
            model.play(game)
            XCTAssertEqual(starts.calls.count, 1, "a disc whose file went does not start")
            XCTAssertEqual(model.toast?.text, "The game file is missing. Put it back or scan the library again.")
        }
    }

    func testAStartGivenUpLetsTheSlotGoAndALateEmulatorIsStopped() async throws {
        let (model, root) = try model(games: 1)
        let folder = root.appendingPathComponent("Retro game")
        try write(Data(), folder.appendingPathComponent("game.iso"))
        try retroJSON(["platform": "ps2", "titleId": "TEST12345", "name": "Retro game", "disc": "game.iso"], in: folder)
        model.setRetroLibrary(true)
        let game = try XCTUnwrap(model.games.first { $0.retro != nil })
        model.preferences.retroEmulators = ["ps2": try write(Data(), try scratch().appendingPathComponent("emulator")).path]
        model.gameStopGrace = .milliseconds(20)
        let late = FakeEmulatorRun(ignoresTerm: true), second = FakeEmulatorRun()
        let starts = FakeEmulatorStarts()
        model.startEmulator = { program, arguments, _ in await starts.start(program, arguments) }

        model.play(game)
        try await settle({ starts.calls.count == 1 })
        XCTAssertEqual(model.state(of: game), .starting)
        model.cancelStart()
        XCTAssertNil(model.starting)
        XCTAssertEqual(model.state(of: game), .installed(outdated: false))

        model.play(game)
        try await settle({ starts.calls.count == 2 }, "a start that never answered does not hold the next one back")
        XCTAssertEqual(model.starting, game)
        starts.answer(0, with: late)
        try await settle({ late.ended }, "the emulator of the start given up is ended")
        XCTAssertEqual(late.signals, [SIGTERM, SIGKILL], "asked first, then ended after the grace, even one that ignores SIGTERM")
        XCTAssertEqual(model.starting, game, "the start under way is left alone")
        XCTAssertNil(model.emulator)

        starts.answer(1, with: second)
        try await settle({ model.emulator != nil })
        XCTAssertTrue(model.emulator?.run === second)
        second.quit()
        try await settle({ model.emulator == nil })
    }

    func testStopAsksTheEmulatorToEndAndEndsItAfterTheGrace() async throws {
        let (model, root) = try model(games: 1)
        let folder = root.appendingPathComponent("Retro game")
        try write(Data(), folder.appendingPathComponent("game.cue"))
        try retroJSON(["platform": "ps1", "titleId": "TEST12345", "name": "Retro game", "disc": "game.cue"], in: folder)
        model.setRetroLibrary(true)
        let game = try XCTUnwrap(model.games.first { $0.retro != nil })
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        model.preferences.retroEmulators = ["ps1": try write(Data(), try scratch().appendingPathComponent("emulator")).path]
        model.gameStopGrace = .milliseconds(30)
        let run = FakeEmulatorRun(ignoresTerm: true)
        let starts = FakeEmulatorStarts(immediate: run)
        model.startEmulator = { program, arguments, _ in await starts.start(program, arguments) }
        model.play(game)
        try await settle({ model.emulator != nil })

        // Game Settings while it plays: Stop, its emulator and its log, nothing of a PS5 game's.
        model.overlay = .gameSettings
        let rows = model.panelCategories().flatMap(\.rows)
        XCTAssertEqual(rows.map(\.id), ["stopGame", "retro-emulator", "log"])
        guard case .action(_, let stop) = rows[0].kind else { return XCTFail("an action row") }
        stop()
        XCTAssertEqual(model.state(of: game), .stopping)
        try await settle({ run.ended })
        XCTAssertEqual(run.signals, [SIGTERM, SIGKILL])
        try await settle({ model.emulator == nil })
        XCTAssertNil(model.toast, "an emulator Stop ended says no exit code")
    }

    func testAFailedFilePanelLeavesTheEmulatorsAlone() throws {
        let (model, _) = try model()
        struct Unavailable: Error {}
        model.pickEmulator = { _ in throw Unavailable() }
        model.chooseStandaloneEmulator(.ps2)
        XCTAssertNil(model.preferences.retroEmulators)
        XCTAssertEqual(model.toast?.text, "Could not open the emulator file picker")
    }

    // MARK: Off by default

    func testAPS5LibraryIsAsBeforeUntilEmulatorGamesIsTurnedOn() throws {
        let (model, root) = try model()
        try write(Data(), root.appendingPathComponent("Loose.bin"))
        try write(Data("FILE \"Loose.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8), root.appendingPathComponent("Loose.cue"))
        let before = model.games
        XCTAssertNil(model.preferences.retroLibrary, "off until turned on")
        model.scanAtOnce()
        XCTAssertTrue(GameLibrary.sameListing(before, model.games))
        XCTAssertEqual(model.games.map(\.id), before.map(\.folder.path))
        XCTAssertTrue(model.games.allSatisfy { $0.retro == nil })

        // Home as before: one tile a game, no folder, the selected game's facts.
        XCTAssertEqual(model.homeTiles.map(\.gameIndex), Array(model.games.indices))
        XCTAssertTrue(model.homeTiles.allSatisfy { $0.folder == nil })
        XCTAssertEqual(model.homePreviewGame, model.selectedGame)
        XCTAssertTrue(model.handle(.right))
        XCTAssertEqual(model.selected, 1)
        XCTAssertTrue(model.handle(.down))
        XCTAssertEqual(model.focus, .actions(0))

        model.overlay = .settings
        func categories() -> [String] { model.panelCategories().map(\.id) }
        XCTAssertFalse(categories().contains("emulators"))
        let library = try XCTUnwrap(model.panelCategories().first { $0.id == "library" })
        XCTAssertEqual(library.rows.last?.id, "retroLibrary")
        XCTAssertEqual(library.rows.last?.title, "Emulator games")
        guard case .toggle(let on, let set) = library.rows.last?.kind else { return XCTFail("a switch") }
        XCTAssertFalse(on)

        set(true)
        XCTAssertEqual(model.preferences.retroLibrary, true)
        XCTAssertEqual(model.games.filter { $0.retro != nil }.map(\.name), ["Loose"])
        XCTAssertEqual(categories().suffix(2), ["emulators", "about"], "Settings › Emulators, before About")
        XCTAssertNil(model.toast, "turning it on announces no new games")
        let emulators = try XCTUnwrap(model.panelCategories().first { $0.id == "emulators" })
        XCTAssertEqual(emulators.rows.map(\.id), ["retro-ps1", "retro-ps2", "retro-ps3", "retro-show-folders"])
        XCTAssertEqual(emulators.rows.prefix(3).map(\.title), ["DuckStation", "PCSX2", "RPCS3"])
        XCTAssertEqual(emulators.rows.first?.detail, "Choose an installed executable")

        model.setRetroLibrary(false)
        XCTAssertNil(model.preferences.retroLibrary)
        XCTAssertTrue(GameLibrary.sameListing(before, model.games))
        XCTAssertFalse(categories().contains("emulators"))
    }

    func testADiscBesideOthersCountsOnlyItsOwnFiles() throws {
        let (model, root) = try model()
        let shelf = root.appendingPathComponent("PS1")
        let tracks = try write(Data(repeating: 1, count: 3000), shelf.appendingPathComponent("A.bin"))
        let sheet = try write(Data("FILE \"A.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8), shelf.appendingPathComponent("A.cue"))
        try write(Data(repeating: 1, count: 50000), shelf.appendingPathComponent("B.bin"))
        try write(Data("FILE \"B.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8), shelf.appendingPathComponent("B.cue"))
        model.setRetroLibrary(true)
        let a = try XCTUnwrap(model.games.first { $0.name == "A" })
        XCTAssertEqual(a.id, "retro:ps1:3042:PS1/A.cue")
        XCTAssertEqual(model.sizes[a.id], GameLibrary.size(of: tracks) + GameLibrary.size(of: sheet))
        XCTAssertLessThan(model.sizes[a.id] ?? .max, GameLibrary.size(of: shelf), "not the whole folder")
    }

    // MARK: Home

    func testAConsoleFolderGroupsItsGamesOnlyOnceItsEmulatorIsChosen() throws {
        let (model, root) = try model()
        for name in ["Game A", "Game B"] {
            let folder = root.appendingPathComponent(name)
            try write(Data(), folder.appendingPathComponent("disc.iso"))
            try retroJSON(["platform": "ps2", "titleId": name.replacingOccurrences(of: " ", with: "").uppercased(), "name": name, "disc": "disc.iso"], in: folder)
        }
        model.setRetroLibrary(true)
        model.setShowRetroFolders(true)
        XCTAssertTrue(model.homeTiles.allSatisfy { $0.folder == nil }, "no emulator yet: the discs are tiles of their own")

        model.preferences.retroEmulators = ["ps2": try write(Data(), try scratch().appendingPathComponent("pcsx2")).path]
        XCTAssertEqual(model.homeTiles.last?.folder, .ps2)
        XCTAssertEqual(model.homeTiles.count, 4, "three PS5 games and the PS2 folder")
        model.selectHomeTile(model.homeTiles.count - 1)
        XCTAssertEqual(model.selectedHomeFolder, .ps2)
        XCTAssertNil(model.homePreviewGame, "a folder shows no game's facts")
        XCTAssertEqual(model.homeFolderTiles.count, 2)

        XCTAssertTrue(model.handle(.options))
        XCTAssertNil(model.overlay, "a folder has no settings")
        XCTAssertTrue(model.handle(.down))
        XCTAssertEqual(model.homePreviewGame?.name, "Game A")
        XCTAssertEqual(model.activeHomeRetroFolder, .ps2)
        XCTAssertTrue(model.handle(.right))
        XCTAssertEqual(model.homePreviewGame?.name, "Game B")
        XCTAssertTrue(model.handle(.up))
        XCTAssertEqual(model.selectedHomeFolder, .ps2)
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.activeHomeRetroFolder, .ps2, "Select opens it too")
        XCTAssertTrue(model.handle(.back))
        XCTAssertEqual(model.selectedHomeFolder, .ps2, "Back closes it")
        XCTAssertTrue(model.handle(.left))
        XCTAssertNil(model.homeFolderPlatform)
        XCTAssertEqual(model.homePreviewGame?.name, "Game 3")
    }

    /// Home with a disc that needs its emulator, the console folder closed and open, and
    /// Settings › Emulators and the switch, kept as pictures when ANYPS5_TEST_SHOTS says where
    /// (CI uploads them).
    func testTheEmulatorScreensDraw() throws {
        let (_, root) = try model()
        for name in ["Crash Team Racing", "Spyro"] {
            let folder = root.appendingPathComponent(name)
            try write(Data(), folder.appendingPathComponent("disc.cue"))
            try retroJSON(["platform": "ps1", "titleId": name.filter(\.isLetter).uppercased(), "name": name, "disc": "disc.cue"], in: folder)
        }
        let vice = root.appendingPathComponent("Vice City")
        try write(Data(), vice.appendingPathComponent("disc.iso"))
        try retroJSON(["platform": "ps2", "titleId": "SLUS20552", "name": "Vice City", "disc": "disc.iso"], in: vice)
        let games = GameLibrary.survey(roots: [root], includeRetro: true, cache: RetroScanCache()).games
        XCTAssertEqual(games.filter { $0.retro != nil }.count, 3)
        var preferences = Preferences()
        preferences.onboarded = true
        preferences.sounds = false
        preferences.libraryFolders = [root.path]
        preferences.retroLibrary = true
        preferences.showRetroFolders = true
        preferences.retroEmulators = ["ps1": try write(Data(), try scratch().appendingPathComponent("DuckStation")).path]
        let folder: URL
        if let kept = ProcessInfo.processInfo.environment["ANYPS5_TEST_SHOTS"], !kept.isEmpty {
            folder = URL(fileURLWithPath: kept)
        } else {
            folder = try scratch()
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func select(_ model: AppModel, _ name: String) { model.selected = model.games.firstIndex { $0.name == name } ?? 0 }
        let screens: [(String, (AppModel) -> Void)] = [
            ("home-emulator-required-en", { model in select(model, "Vice City") }),
            ("home-retro-folder-en", { model in model.selectHomeTile(model.homeTiles.count - 1) }),
            ("home-retro-folder-open-en", { model in
                model.selectHomeTile(model.homeTiles.count - 1)
                model.openSelectedHomeFolder()
            }),
            ("settings-emulators-en", { model in
                model.overlay = .settings
                model.panelCategory = model.panelCategories().firstIndex { $0.id == "emulators" } ?? 0
            }),
            ("settings-emulator-games-en", { model in
                model.overlay = .settings
                model.panelCategory = model.panelCategories().firstIndex { $0.id == "library" } ?? 0
                model.panelInRows = true
                model.panelRow = max(0, (model.panelCategories().first { $0.id == "library" }?.rows.count ?? 1) - 1)
            }),
        ]
        for (name, configure) in screens {
            let file = folder.appendingPathComponent(name + ".png")
            try? FileManager.default.removeItem(at: file)
            PreviewRenderer.render(preferences, games, root, nil, file, configure: configure)
            let picture = try XCTUnwrap(NSImage(contentsOf: file)?.representations.first, "no picture of \(name)")
            XCTAssertEqual(picture.pixelsWide, Int(PreviewRenderer.size.width))
        }
    }

    // MARK: Kept out of what follows a PS5 game

    func testADiscIsNoGameForAnyTogetherPlayTogetherOrTheQuickMenusSharing() async throws {
        let (model, root) = try model(games: 1)
        let folder = root.appendingPathComponent("Retro game")
        try write(Data(), folder.appendingPathComponent("game.cue"))
        try retroJSON(["platform": "ps1", "titleId": "TEST12345", "name": "Retro game", "disc": "game.cue"], in: folder)
        model.setRetroLibrary(true)
        let game = try XCTUnwrap(model.games.first { $0.retro != nil })
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        XCTAssertNil(model.selectedPS5Game, "a post, Find players and a party's game never name a disc")
        XCTAssertNil(model.listingGame)
        XCTAssertFalse(model.togetherCopies().contains { $0.id == game.id }, "Play Together's join check has no disc")

        model.preferences.retroEmulators = ["ps1": try write(Data(), try scratch().appendingPathComponent("duckstation")).path]
        let run = FakeEmulatorRun()
        let starts = FakeEmulatorStarts(immediate: run)
        model.startEmulator = { program, arguments, _ in await starts.start(program, arguments) }
        model.play(game)
        try await settle({ model.emulator != nil })
        XCTAssertNil(model.running, "presence, Discord and game sessions follow this slot only")
        // Signed in, the quick menu offers Share play and Broadcast for a PS5 game only.
        model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        XCTAssertNil(model.listingGame)
        let titles = model.quickMenuRows().map(\.title)
        XCTAssertFalse(titles.contains(SP.format(.start, game.name)), "no Share play of an emulator")
        XCTAssertFalse(titles.contains(TB.text(.setUpFirst)), "no Broadcast of an emulator")
        XCTAssertEqual(titles.last, TH.text(.closeGame))
        run.quit()
        try await settle({ model.emulator == nil })
    }
}
