@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import XCTest

/// Something a test opens by hand, and every call waiting for it.
final class PlayGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            opened = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in waiting { waiter.resume() }
    }
}

/// An emulator host the launcher's tests drive by hand: every call recorded, `status` what the
/// test set, `start` taken, and a shutdown that ends it cleanly. No process runs.
final class FakePlayHost: RetroHostSession, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, RetroJSON)] = []
    private var starts: [RetroJSON] = []
    private var current: RetroStatus?
    private var endValue: RetroHostEnd?
    private var waiting: [CheckedContinuation<RetroHostEnd, Never>] = []
    private var focus: [Bool] = []
    private(set) var shutdowns = 0

    private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    var methods: [String] { locked { calls.map(\.0) } }
    func args(_ method: String) -> [RetroJSON] { locked { calls.filter { $0.0 == method }.map(\.1) } }
    var started: [RetroJSON] { locked { starts } }
    var focusSent: [Bool] { locked { focus } }
    var gameStatus: RetroStatus? {
        get { locked { current } }
        set { locked { current = newValue } }
    }

    func ready() async throws {}

    func ended() async -> RetroHostEnd {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let endValue {
                lock.unlock()
                continuation.resume(returning: endValue)
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    var end: RetroHostEnd? { locked { endValue } }
    private var ps2 = false
    /// Whether the host's welcome lists `ps2`.
    var canPlayPs2: Bool {
        get { locked { ps2 } }
        set { locked { ps2 = newValue } }
    }

    private var states = false
    private var resolutionLimits = false
    /// Whether the host's welcome lists `ps2ResolutionLimits`.
    var limitsPs2Resolution: Bool {
        get { locked { resolutionLimits } }
        set { locked { resolutionLimits = newValue } }
    }
    /// Whether the host's welcome lists `saveStates`; false, as for the signed host v1.0.0, unless a
    /// test says.
    var canSaveStates: Bool {
        get { locked { states } }
        set { locked { states = newValue } }
    }
    private var results: [String: RetroJSON] = [:]
    private var errors: [String: RetroCallError] = [:]
    private var gate: PlayGate?
    private var hook: ((String, RetroJSON) -> Void)?
    private var stopCode: String?
    /// What `saveState` and `loadState` return, by method; `false` for one not set.
    func answer(_ method: String, _ result: RetroJSON) { locked { results[method] = result; errors[method] = nil } }
    /// The `error` reply `saveState` or `loadState` gets instead.
    func refuse(_ method: String, _ error: RetroCallError?) { locked { errors[method] = error } }
    /// When set, every call is answered only once it opens.
    var callGate: PlayGate? {
        get { locked { gate } }
        set { locked { gate = newValue } }
    }
    /// Runs as each call is taken, before it is answered: what the host does meanwhile (writes a
    /// state's file).
    var onCall: ((String, RetroJSON) -> Void)? {
        get { locked { hook } }
        set { locked { hook = newValue } }
    }
    /// The `errorCode` the game ends with when it is stopped.
    var stopErrorCode: String? {
        get { locked { stopCode } }
        set { locked { stopCode = newValue } }
    }

    func setInputFocus(_ focused: Bool) { locked { focus.append(focused) } }

    func startGame(_ args: RetroJSON) async throws -> Int {
        locked {
            starts.append(args)
            current = try? RetroHostPlayTests.status(ready: false)
            return starts.count
        }
    }

    func call(_ method: String, _ args: RetroJSON) async throws -> RetroJSON {
        let (waiting, taken) = locked {
            calls.append((method, args))
            return (gate, hook)
        }
        taken?(method, args)
        await waiting?.wait()
        let answer: Result<RetroJSON, Error> = locked {
            switch method {
            case "release":
                if current?.ended == true { current = nil }
                return .success(.null)
            case "connectedPorts", "changeDisc", "option": return .success(.bool(true))
            case "saveState", "loadState":
                if let error = errors[method] { return .failure(error) }
                return .success(results[method] ?? .bool(false))
            default: return .success(.null)
            }
        }
        return try answer.get()
    }

    func status() async throws -> RetroStatus? { locked { current } }

    func stopGame() async throws -> RetroStatus? {
        locked {
            calls.append(("stop", .null))
            guard var status = current else { return nil }
            status.ended = true
            if let stopCode { status.errorCode = stopCode }
            current = status
            return status
        }
    }

    func input(port: Int, buttons: Int, leftX: Int, leftY: Int, rightX: Int, rightY: Int) {}

    func shutdown() {
        locked { shutdowns += 1 }
        finish(.clean)
    }

    func close() async {}

    func setHandlers(frame: ((RetroFrameEvent) -> Void)?, rumble: ((RetroRumble) -> Void)?) {}

    /// The host ends by itself (it crashed).
    func finish(_ end: RetroHostEnd) {
        let told: [CheckedContinuation<RetroHostEnd, Never>] = locked {
            guard endValue == nil else { return [] }
            endValue = end
            defer { waiting = [] }
            return waiting
        }
        for continuation in told { continuation.resume(returning: end) }
    }
}

/// A PS1 disc played in the launcher's window through the emulator host, as on Windows and Linux
/// (AnyPS5 Desktop's test/ui/retro_host_play_test.dart), with a fake host: the setting and its
/// rows, the start and what it is given, PS and the game's menu with its sections in the host's
/// order, Close game keeping the host for the next game, the error and clean ends, captures, and
/// quitting.
@MainActor
final class RetroHostPlayTests: XCTestCase {
    private var made: [URL] = []

    override func tearDown() {
        for url in made { try? FileManager.default.removeItem(at: url) }
        made = []
    }

    /// A status as protocol.md "status" writes it, with options in this order: a console, a
    /// graphics, an audio, a hidden and an advanced one.
    nonisolated static func status(ready: Bool, ended: Bool = false, errorCode: String = "", progressLabel: String? = nil) throws -> RetroStatus {
        let label = progressLabel.map { "\"\($0)\"" } ?? "null"
        let text = """
        {"ready":\(ready),"ended":\(ended),"error":"\(errorCode.isEmpty ? "" : "failed")","errorCode":"\(errorCode)","aspect":1.3333333333333333,\
        "hardware":false,"resolutionError":"","graphicsPending":false,"progressLabel":\(label),"progressPercent":null,"cardUnreadable":false,\
        "options":{\
        "swanstation_Console_Region":{"title":"Console Region (Restart)","values":["Auto","NTSC-U"],"labels":["Auto-Detect","NTSC-U (US)"],"selected":0,"activeValue":"Auto","restart":true},\
        "swanstation_GPU_ResolutionScale":{"title":"Internal Resolution","values":["1","2"],"labels":["1x","2x"],"selected":0,"activeValue":"1","restart":false},\
        "swanstation_CDROM_MuteCDAudio":{"title":"Mute CD Audio","values":["false","true"],"labels":["Off","On"],"selected":0,"activeValue":"false","restart":false},\
        "swanstation_Display_ShowOSDMessages":{"title":"Display OSD Messages","values":["true","false"],"labels":["On","Off"],"selected":0,"activeValue":"true","restart":false},\
        "swanstation_CPU_ExecutionMode":{"title":"CPU Execution Mode","values":["Interpreter","Recompiler"],"labels":["Interpreter","Recompiler"],"selected":1,"activeValue":"Recompiler","restart":false},\
        "swanstation_BIOS_PatchFastBoot":{"title":"Fast Boot","values":["false","true"],"labels":["Off","On"],"selected":0,"activeValue":"false","restart":false}\
        }}
        """
        return try RetroStatus.parse(try RetroJSON.parse(Array(text.utf8)))
    }

    private func write(_ data: Data, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A launcher with one PS1 disc, emulator games on, and a debug build's host found unchecked.
    private func launcher(host: Bool = true, setting: Bool = true) throws -> (AppModel, Game, [FakePlayHost]) {
        let model = try LauncherFixture.model(games: 1)
        made.append(contentsOf: model.libraryRoots)
        let root = try XCTUnwrap(model.libraryRoots.first)
        let folder = root.appendingPathComponent("Night Racer")
        try write(Data(), folder.appendingPathComponent("game.cue"))
        try write(try JSONSerialization.data(withJSONObject: ["platform": "ps1", "titleId": "SLUS00001", "name": "Night Racer", "disc": "game.cue"]),
                  folder.appendingPathComponent("retro.json"))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-play-\(UUID().uuidString)")
        made.append(scratch)
        model.retroHostRoot = scratch.appendingPathComponent("RetroHost")
        model.retroFolder = scratch.appendingPathComponent("retro")
        model.retroHostUnchecked = host ? RetroHostInstall(host: "/test/anyps5-retro-host", core: "/test/swanstation_libretro.dylib") : nil
        model.retroStatusEvery = .seconds(3600)
        model.retroPads = RetroPadReader(pads: { [] }, state: { _ in nil })
        model.preferences.retroHostPs1 = setting ? true : nil
        model.setRetroLibrary(true)
        let game = try XCTUnwrap(model.games.first { $0.retro != nil })
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        return (model, game, hosts)
    }

    private func settle(_ condition: () -> Bool, _ message: String = "") async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), message)
    }

    /// Plays the disc and waits for its `start`; the fake host made for it.
    private func play(_ model: AppModel, _ game: Game, opened: () -> [FakePlayHost]) async throws -> FakePlayHost {
        let before = opened().count
        model.play(game)
        try await settle({ opened().count > before || (model.retroPlay != nil && opened().last?.started.isEmpty == false) }, "a host opened")
        let host = try XCTUnwrap(opened().last)
        try await settle({ !host.started.isEmpty && model.retroPlay?.host.phase == .loading }, "the game is loading")
        return host
    }

    // MARK: Settings › Emulators

    func testTheSettingShowsOnlyWhereAHostIsFoundAndOpensTheBiosFolder() throws {
        let (none, _, _) = try launcher(host: false)
        let ids = none.standaloneEmulatorSettings().rows.map(\.id)
        XCTAssertFalse(ids.contains("retro-host-ps1"), "no host, no setting")
        XCTAssertEqual(none.state(of: try XCTUnwrap(none.games.first { $0.retro != nil })), .needsEmulator, "DuckStation as before")

        let (model, game, _) = try launcher(setting: false)
        var rows = model.standaloneEmulatorSettings().rows
        XCTAssertEqual(rows.map(\.id), ["retro-ps1", "retro-ps2", "retro-ps3", "retro-host-unchecked", "retro-host-ps1", "retro-show-folders"])
        let toggle = try XCTUnwrap(rows.first { $0.id == "retro-host-ps1" })
        XCTAssertEqual(toggle.title, "Run PS1 games in the separate host")
        XCTAssertEqual(toggle.detail, "PS1 games play in this window through the AnyPS5 emulator host instead of DuckStation.")
        XCTAssertEqual(model.state(of: game), .needsEmulator)
        guard case .toggle(false, let set) = toggle.kind else { return XCTFail("a switch, off") }
        set(true)
        XCTAssertEqual(model.state(of: game), .installed(outdated: false), "a PS1 disc needs no DuckStation once it plays in the host")
        rows = model.standaloneEmulatorSettings().rows
        let bios = try XCTUnwrap(rows.first { $0.id == "retro-host-bios" })
        XCTAssertEqual(bios.title, "PS1 BIOS folder")
        var opened: [URL] = []
        model.openRetroFolder = { opened.append($0) }
        guard case .action(_, let open) = bios.kind else { return XCTFail("an action") }
        open()
        XCTAssertEqual(opened.map(\.path), [model.retroFolder.appendingPathComponent("system").path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.retroFolder.appendingPathComponent("system").path), "made when it was not there")
    }

    // MARK: Playing

    func testADiscStartsInTheHostWithThePlayersPathsVolumeAndShownOptions() async throws {
        var (model, game, hosts) = try launcher()
        model.openRetroHost = { install, checked, volume, muted in
            XCTAssertEqual(install.host, "/test/anyps5-retro-host")
            XCTAssertNil(checked, "a debug build's host is not checked")
            XCTAssertEqual(volume, 0.7)
            XCTAssertTrue(muted)
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        model.preferences.retroHostVolume = 70
        model.preferences.retroHostMuted = true
        model.preferences.retroHostOptions = ["swanstation_Console_Region": "NTSC-U", "swanstation_GPU_ResolutionScale": "2",
                                              "swanstation_Display_ShowOSDMessages": "false", "pcsx2_bios": "x"]
        let host = try await play(model, game) { hosts }
        let start = try XCTUnwrap(host.started.first?.objectValue)
        XCTAssertEqual(start["core"], .string("/test/swanstation_libretro.dylib"))
        XCTAssertEqual(start["disc"]?.stringValue.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       game.retro?.path.resolvingSymlinksInPath().path)
        XCTAssertEqual(start["system"], .string(model.retroFolder.appendingPathComponent("system").standardizedFileURL.path))
        XCTAssertEqual(start["saves"], .string(model.retroFolder.appendingPathComponent("saves/ps1").standardizedFileURL.path))
        XCTAssertEqual(start["options"], .object(["swanstation_Console_Region": .string("NTSC-U"), "swanstation_GPU_ResolutionScale": .string("2")]),
                       "the internal resolution goes, which the menu offers; a hidden option and another core's are not sent")
        XCTAssertNil(start["console"], "a PS1 start is the same on every host")
        XCTAssertEqual(model.retroPlay?.game, game)
        XCTAssertTrue(model.playing)
        XCTAssertTrue(model.retroInGame)
        XCTAssertNotNil(model.preferences.lastPlayed[game.id])
        XCTAssertEqual(AppModel.retroLoadingText(nil), "Loading the game…")
        XCTAssertEqual(AppModel.retroLoadingText(try Self.status(ready: false, progressLabel: "Reading the disc")), "Reading the disc",
                       "the host's own words where the launcher speaks English")
    }

    func testPsOpensTheMenuWithItsSectionsInTheHostsOrderAndResumes() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        host.gameStatus = try Self.status(ready: true)
        await model.retroPlay?.host.refresh()
        XCTAssertEqual(model.retroPlay?.host.phase, .playing)

        // The controller is the game's: Cross and Circle do nothing of the launcher.
        XCTAssertTrue(model.handle(.select))
        XCTAssertTrue(model.handle(.back))
        XCTAssertNil(model.overlay)
        XCTAssertTrue(model.handle(.home))
        XCTAssertEqual(model.overlay, .retroMenu)
        try await settle({ host.args("pause").contains(.bool(true)) }, "the game is paused under its menu")
        let rows = model.retroMenuPanelRows()
        XCTAssertEqual(rows.map(\.id), ["resume", "section-audio", "section-console", "section-advanced", "closeGame"],
                       "no Controller section without its options, and no Graphics one")
        XCTAssertEqual(rows.map(\.title), ["Resume", "Audio", "Console", "Advanced", "Close Game"])

        // Console: its options in the host's order, " (Restart)" said under the option instead.
        model.menuIndex = 2
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.retroMenuTitle, "Console")
        let console = model.retroMenuPanelRows()
        XCTAssertEqual(console.map(\.id), ["option-swanstation_Console_Region", "option-swanstation_BIOS_PatchFastBoot"])
        XCTAssertEqual(console.first?.title, "Console Region")
        XCTAssertEqual(console.first?.detail, "Changes take effect when the game is started again.")
        // Back goes to the first page, on Console.
        XCTAssertTrue(model.handle(.back))
        XCTAssertNil(model.retroPlay?.menuSection)
        XCTAssertEqual(model.menuIndex, 2)
        // Audio: Volume and Mute first.
        model.menuIndex = 1
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.retroMenuPanelRows().map(\.id), ["volume", "mute", "option-swanstation_CDROM_MuteCDAudio"])
        XCTAssertTrue(model.handle(.back))
        // PS resumes.
        XCTAssertTrue(model.handle(.home))
        XCTAssertNil(model.overlay)
        try await settle({ host.args("pause").last == .bool(false) }, "the game goes on")
    }

    func testCloseGameKeepsTheHostForTheNextGameAndLeavingThePs1GamesShutsItDown() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        host.gameStatus = try Self.status(ready: true)
        await model.retroPlay?.host.refresh()
        await model.closeRetroGame()
        XCTAssertNil(model.retroPlay, "the library is back")
        XCTAssertTrue(host.methods.contains("stop"), "the memory card is written")
        XCTAssertTrue(model.retroHostKeeper.holding, "the host stays for the next game")
        XCTAssertEqual(host.shutdowns, 0)

        _ = try await play(model, game) { hosts }
        XCTAssertEqual(hosts.count, 1, "the next game starts on the kept host")
        XCTAssertEqual(host.started.count, 2)
        host.gameStatus = try Self.status(ready: true)
        await model.retroPlay?.host.refresh()
        await model.closeRetroGame()
        XCTAssertTrue(model.retroHostKeeper.holding)

        // The player leaves the PS1 games: the setting off.
        model.setRetroHostPs1(false)
        try await settle({ host.shutdowns == 1 }, "the kept host is shut down")
    }

    func testAGameWithoutABiosStaysOnItsErrorScreenAndOffersTheFolder() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        var opened: [URL] = []
        model.openRetroFolder = { opened.append($0) }
        let host = try await play(model, game) { hosts }
        host.gameStatus = try Self.status(ready: false, ended: true, errorCode: RetroErrorCode.bios)
        await model.retroPlay?.host.refresh()
        let play = try XCTUnwrap(model.retroPlay, "an error stays on its screen")
        XCTAssertEqual(play.problem, .retroHostBiosDetail)
        XCTAssertEqual(TRetro.text(.retroHostBiosDetail),
                       "No PS1 BIOS was found. Put a BIOS file in the PS1 BIOS folder (Settings › Emulators) and start the game again.")
        XCTAssertTrue(model.handle(.options))
        XCTAssertEqual(opened.map(\.path), [model.retroFolder.appendingPathComponent("system").path])
        XCTAssertTrue(model.handle(.select))
        try await settle({ model.retroPlay == nil }, "Enter or Cross goes back to the library")
        XCTAssertEqual(AppModel.retroHostErrorKey("somethingNew"), .retroHostOtherDetail, "a code the launcher does not know")
        XCTAssertNil(AppModel.retroHostErrorKey(""))
    }

    func testAGameThatEndsWithoutAnErrorGoesBackToTheLibrary() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        host.gameStatus = try Self.status(ready: true, ended: true)
        await model.retroPlay?.host.refresh()
        try await settle({ model.retroPlay == nil }, "a clean end goes back to the library")
    }

    func testCapturesSayTheyAreNotThereYetAndDownloadsWait() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        _ = try await play(model, game) { hosts }
        model.saveClip()
        XCTAssertEqual(model.toast?.text, "Screenshots and clips are not available yet for PS1 games in the emulator host.")
        model.toast = nil
        model.takeScreenshot()
        XCTAssertEqual(model.toast?.text, "Screenshots and clips are not available yet for PS1 games in the emulator host.")
    }

    func testQuittingShutsTheHostDown() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        let quit = try XCTUnwrap(model.shutDownRetroHosts(limit: .seconds(2)))
        await quit.value
        XCTAssertEqual(host.shutdowns, 1, "the host is told to shut down, which writes the memory card")
    }

    // MARK: PS2 games, as on Windows and Linux (Desktop's test/ui/retro_host_ps2_test.dart)

    /// A launcher with one PS2 disc and a debug build's host, with LRPS2 beside it or not.
    private func ps2Launcher(lrps2: Bool) throws -> (AppModel, Game) {
        let (model, _, _) = try launcher()
        let root = try XCTUnwrap(model.libraryRoots.first)
        let folder = root.appendingPathComponent("Street Kings")
        try write(Data(), folder.appendingPathComponent("game.iso"))
        try write(try JSONSerialization.data(withJSONObject: ["platform": "ps2", "titleId": "SLUS20001", "name": "Street Kings", "disc": "game.iso"]),
                  folder.appendingPathComponent("retro.json"))
        model.retroHostUnchecked = RetroHostInstall(host: "/test/anyps5-retro-host", core: "/test/swanstation_libretro.dylib",
                                                    ps2Core: lrps2 ? "/test/pcsx2_libretro.dylib" : nil)
        model.scanAtOnce()
        let game = try XCTUnwrap(model.games.first { $0.retro?.platform == .ps2 })
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        return (model, game)
    }

    func testThePs2RowsShowOnlyWhereTheHostHasLrps2AndOpenItsBiosFolder() throws {
        let (without, _) = try ps2Launcher(lrps2: false)
        XCTAssertFalse(without.standaloneEmulatorSettings().rows.contains { $0.id.hasPrefix("retro-host-ps2") }, "no LRPS2, no PS2 rows")
        let (model, game) = try ps2Launcher(lrps2: true)
        XCTAssertEqual(model.state(of: game), .needsEmulator, "PCSX2 as before while the setting is off")
        var rows = model.standaloneEmulatorSettings().rows
        let toggle = try XCTUnwrap(rows.first { $0.id == "retro-host-ps2" })
        XCTAssertEqual(toggle.title, "Run PS2 games in the separate host")
        XCTAssertEqual(toggle.detail, "PS2 games play in this window through the AnyPS5 emulator host instead of PCSX2.")
        XCTAssertFalse(rows.contains { $0.id == "retro-host-ps2-bios" })
        model.setRetroHostPs2(true)
        XCTAssertEqual(model.state(of: game), .installed(outdated: false), "a PS2 disc needs no PCSX2 once it plays in the host")
        rows = model.standaloneEmulatorSettings().rows
        let bios = try XCTUnwrap(rows.first { $0.id == "retro-host-ps2-bios" })
        XCTAssertEqual(bios.title, "PS2 BIOS folder")
        var opened: [URL] = []
        model.openRetroFolder = { opened.append($0) }
        guard case .action(_, let open) = bios.kind else { return XCTFail("an action") }
        open()
        XCTAssertEqual(opened.map(\.path), [model.retroFolder.appendingPathComponent("system/pcsx2/bios").path])
    }

    func testAPs2DiscStartsOnLrps2WithItsOwnSavesAndOptions() async throws {
        let (model, game) = try ps2Launcher(lrps2: true)
        model.setRetroHostPs2(true)
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            fake.canPlayPs2 = true
            hosts.append(fake)
            return fake
        }
        model.preferences.retroHostOptions = ["pcsx2_fastboot": "enabled", "swanstation_Console_Region": "NTSC-U", "pcsx2_upscale_multiplier": "2x"]
        let host = try await play(model, game) { hosts }
        let start = try XCTUnwrap(host.started.first?.objectValue)
        XCTAssertEqual(start["console"], .string("ps2"))
        XCTAssertEqual(start["core"], .string("/test/pcsx2_libretro.dylib"))
        XCTAssertEqual(start["saves"], .string(model.retroFolder.appendingPathComponent("saves/ps2").standardizedFileURL.path))
        XCTAssertEqual(start["options"], .object(["pcsx2_fastboot": .string("enabled")]),
                       "only LRPS2's options, and its resolution not to a host without ps2ResolutionLimits")
        XCTAssertNil(start["initialDisc"])
    }

    func testAPs2GameOnAHostWithoutPs2SaysItNeedsUpdatingAndAMissingBiosOffersItsFolder() async throws {
        let (model, game) = try ps2Launcher(lrps2: true)
        model.setRetroHostPs2(true)
        var hosts: [FakePlayHost] = []
        var lists = false
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            fake.canPlayPs2 = lists
            hosts.append(fake)
            return fake
        }
        model.play(game)
        try await settle({ model.retroPlay?.host.phase == .ended }, "the game is never sent")
        XCTAssertEqual(hosts.first?.started.count, 0)
        XCTAssertEqual(model.retroPlay?.problem, .retroHostNoPs2Detail)
        XCTAssertEqual(TRetro.text(.retroHostNoPs2Detail), "This emulator host cannot play PS2 games. It needs updating.")
        await model.closeRetroGame()
        // That host, kept with no game, plays no PS2 game: a host that lists ps2 comes next.
        await model.retroHostKeeper.shutdown()

        lists = true
        let host = try await play(model, game) { hosts }
        host.gameStatus = try Self.status(ready: false, ended: true, errorCode: RetroErrorCode.bios)
        await model.retroPlay?.host.refresh()
        XCTAssertEqual(model.retroPlay?.problem, .retroHostPs2BiosDetail)
        var opened: [URL] = []
        model.openRetroFolder = { opened.append($0) }
        XCTAssertTrue(model.handle(.options))
        XCTAssertEqual(opened.map(\.path), [model.retroFolder.appendingPathComponent("system/pcsx2/bios").path])
    }

    func testTheInternalResolutionRowSitsAfterAudioAndKeepsAChoiceTheHostTook() async throws {
        let (model, game, _) = try launcher()
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        var status = try Self.status(ready: true)
        status.hardware = true
        host.gameStatus = status
        await model.retroPlay?.host.refresh()
        XCTAssertTrue(model.handle(.home))
        let rows = model.retroMenuPanelRows()
        XCTAssertEqual(rows.map(\.id), ["resume", "section-audio", "resolution", "section-console", "section-advanced", "closeGame"])
        let row = try XCTUnwrap(rows.first { $0.id == "resolution" })
        XCTAssertEqual(row.title, "Internal resolution")
        XCTAssertEqual(row.detail, "Draws the game sharper. Higher values need a faster graphics card.")
        guard case .choice(let options, let selected, let set) = row.kind else { return XCTFail("a choice") }
        XCTAssertEqual(options, ["Native", "2x"], "the values the launcher offers that the host lists")
        XCTAssertEqual(selected, 0)
        set(1)
        try await settle({ model.preferences.retroHostOptions?["swanstation_GPU_ResolutionScale"] == "2" }, "kept once the host took it")
        XCTAssertTrue(host.args("option").contains(.object(["key": .string("swanstation_GPU_ResolutionScale"), "value": .string("2")])))
        XCTAssertEqual(AppModel.retroResolutionDetail(try XCTUnwrap(RetroResolutionChoice.of({
            var refused = status
            refused.resolutionError = "too large"
            return refused
        }(), limitsPs2: false))), "The emulator can't show the resolution you saved, so the game uses Native.")
    }

    func testTheMenuWordsInTurkishSayKontrolcu() throws {
        let turkish = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: T.sourceFolder.appendingPathComponent("tr.json"))) as? [String: String])
        XCTAssertEqual(turkish["retroMenuController"], "Kontrolcü")
        XCTAssertEqual(turkish["retroHostLoading"], "Oyun yükleniyor…")
    }

    // MARK: Save states, as on Windows and Linux (Desktop's test/ui/retro_host_save_states_test.dart)

    /// What the recorded host built from the save-states branch answered (AnyPS5CoreTests'
    /// Fixtures/retro-host-save-states-recording.json, Desktop's recording): a save, a load, and the
    /// words of its refusals.
    private static let saved: RetroJSON = .object(["bytes": .int(88), "micros": .int(15207)])
    private static let loaded: RetroJSON = .object(["bytes": .int(88), "micros": .int(3253)])
    private static func refusal(_ code: String) -> RetroCallError {
        let words = [RetroCallError.otherCore: "The state was saved by another core or core build.",
                     RetroCallError.otherGame: "The state was saved from another game.",
                     RetroCallError.badState: "The file is not a state file this host reads.",
                     RetroCallError.coreRefused: "The core could not save or load the state.",
                     RetroCallError.fileError: "The state file could not be written or read.",
                     RetroCallError.noState: "There is no state file there."]
        return RetroCallError(code: code, message: words[code] ?? "")
    }

    private func ids(_ model: AppModel) -> [String] { model.retroMenuPanelRows().map(\.id) }

    private func row(_ model: AppModel, _ id: String) throws -> PanelRow {
        try XCTUnwrap(model.retroMenuPanelRows().first { $0.id == id }, "no row \(id)")
    }

    /// Chooses the row `id`, as Select on it does.
    private func choose(_ model: AppModel, _ id: String) throws {
        guard case .action(_, let run) = try row(model, id).kind else { return XCTFail("\(id) cannot be chosen") }
        run()
    }

    private func chosen(_ model: AppModel, _ id: String) throws -> Bool {
        if case .action = try row(model, id).kind { return true }
        return false
    }

    /// The game's states folder, as the launcher keeps it, for the disc `start.disc` names.
    private func folder(_ model: AppModel, _ game: Game, ps2: Bool = false) throws -> RetroStateFolder {
        RetroStateFolder(folder: model.retroStatesFolder(game, ps2: ps2).standardizedFileURL.path,
                         disc: try XCTUnwrap(game.retro?.path.standardizedFileURL.path))
    }

    private func saveCalls(_ host: FakePlayHost) -> [RetroJSON] { host.args("saveState") }

    /// A PS1 game playing on a host that lists `saveStates` (unless `lists` is false), with a state in
    /// each slot of `slots` (and a picture for each of `pictures`) before it starts, its first frame
    /// shown unless `ready` is false.
    private func playing(lists: Bool = true, slots: [Int] = [], pictures: [Int: Data] = [:],
                         ready: Bool = true) async throws -> (AppModel, Game, FakePlayHost) {
        let (model, game, _) = try launcher()
        let states = try folder(model, game)
        for slot in slots { try write(Data([1]), URL(fileURLWithPath: states.statePath(slot))) }
        for (slot, png) in pictures { try write(png, URL(fileURLWithPath: states.picturePath(slot))) }
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            fake.canSaveStates = lists
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        if ready {
            host.gameStatus = try Self.status(ready: true)
            await model.retroPlay?.host.refresh()
        }
        await model.retroPlay?.states.refresh()
        return (model, game, host)
    }

    /// PS in the game, and the game paused under its menu, so a gate set after it holds only what
    /// the test asks for.
    private func openMenu(_ model: AppModel, _ host: FakePlayHost) async throws {
        XCTAssertTrue(model.handle(.home))
        XCTAssertEqual(model.overlay, .retroMenu)
        try await settle({ host.args("pause").last == .bool(true) }, "the game is paused under its menu")
    }

    /// The host writes a state's file as it saves it, as the recorded host did.
    private func hostWritesStates(_ host: FakePlayHost, _ states: RetroStateFolder) {
        host.onCall = { method, args in
            guard method == "saveState", let slot = args.objectValue?["slot"]?.intValue else { return }
            let path = states.statePath(slot)
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
        }
    }

    func testAGameStartsWithItsOwnStatesFolderAndItsMenuHasSaveStateAndLoadState() async throws {
        let (model, game, host) = try await playing()
        let states = model.retroStatesFolder(game, ps2: false).standardizedFileURL.path
        XCTAssertEqual(host.started.first?.objectValue?["states"], .string(states))
        XCTAssertEqual((states as NSString).lastPathComponent, "PS1-SLUS00001", "named by the game's title ID")
        XCTAssertEqual(((states as NSString).deletingLastPathComponent as NSString).lastPathComponent, "ps1")
        XCTAssertEqual(TRetro.text(.retroMenuSaveState), "Save state", "sentence case, as every row")
        XCTAssertEqual(TRetro.text(.retroMenuLoadState), "Load state")
        XCTAssertTrue(model.handle(.home))
        XCTAssertEqual(ids(model), ["resume", "saveState", "loadState", "section-audio", "section-console", "section-advanced", "closeGame"],
                       "after the discs (none here), before the sections")
        XCTAssertEqual(try row(model, "saveState").detail, "Keep this moment in a slot, to come back to it later.")
        XCTAssertFalse(try chosen(model, "loadState"), "nothing to load yet")
        XCTAssertEqual(try row(model, "loadState").detail, "No state of this game is saved yet.")
        // Focus passes over Load state, which cannot be chosen.
        model.menuIndex = 1
        XCTAssertTrue(model.handle(.down))
        XCTAssertEqual(model.menuIndex, 3)
    }

    func testAPs2GamesStatesAreKeptApartFromPs1Games() async throws {
        let (model, game) = try ps2Launcher(lrps2: true)
        model.setRetroHostPs2(true)
        var hosts: [FakePlayHost] = []
        model.openRetroHost = { _, _, _, _ in
            let fake = FakePlayHost()
            fake.canPlayPs2 = true
            fake.canSaveStates = true
            hosts.append(fake)
            return fake
        }
        let host = try await play(model, game) { hosts }
        let states = model.retroStatesFolder(game, ps2: true).standardizedFileURL.path
        XCTAssertEqual(host.started.first?.objectValue?["states"], .string(states))
        XCTAssertTrue(states.hasSuffix("/retro/states/ps2/PS2-SLUS20001"), states)
    }

    func testTwoGamesWhoseDiscsHaveTheSameNameKeepTheirStatesApart() throws {
        let (model, night, _) = try launcher()
        let root = try XCTUnwrap(model.libraryRoots.first)
        let other = root.appendingPathComponent("Day Racer")
        try write(Data(), other.appendingPathComponent("game.cue"))
        try write(try JSONSerialization.data(withJSONObject: ["platform": "ps1", "titleId": "SLUS0-0001", "name": "Day Racer", "disc": "game.cue"]),
                  other.appendingPathComponent("retro.json"))
        model.scanAtOnce()
        let day = try XCTUnwrap(model.games.first { $0.name == "Day Racer" })
        let dayStates = try folder(model, day)
        let nightStates = try folder(model, night)
        XCTAssertEqual((dayStates.statePath(0) as NSString).lastPathComponent, (nightStates.statePath(0) as NSString).lastPathComponent,
                       "the host names both alike")
        XCTAssertNotEqual(dayStates.statePath(0), nightStates.statePath(0))
    }

    func testAHostWithoutSaveStatesIsSentNoStatesFolderAndTheMenuHasNoSaveState() async throws {
        let (model, _, host) = try await playing(lists: false)
        XCTAssertNil(host.started.first?.objectValue?["states"])
        XCTAssertTrue(model.handle(.home))
        XCTAssertFalse(ids(model).contains("saveState"))
        XCTAssertFalse(ids(model).contains("loadState"))
    }

    func testSaveStateAnEmptySlotSavesAtOnceAndAUsedOneAsksFirst() async throws {
        let (model, game, host) = try await playing()
        hostWritesStates(host, try folder(model, game))
        host.answer("saveState", Self.saved)
        try await openMenu(model, host)
        try choose(model, "saveState")
        XCTAssertEqual(model.retroMenuTitle, "Save state")
        XCTAssertEqual(ids(model), (0..<RetroStateFolder.slots).map { "state-\($0)" })
        XCTAssertEqual(try row(model, "state-0").title, "Slot 1")
        XCTAssertEqual(try row(model, "state-0").detail, "Empty")
        XCTAssertEqual(try row(model, "state-0").pictureAspect, model.retroPlay?.host.aspect, "its picture's place is kept")
        XCTAssertEqual(model.menuIndex, 0)

        try choose(model, "state-0")
        try await settle({ model.overlay == nil }, "back to the game once it is saved")
        XCTAssertEqual(saveCalls(host), [.object(["slot": .int(0)])])
        XCTAssertEqual(model.toast?.text, "Saved in slot 1")
        try await settle({ host.args("pause").last == .bool(false) }, "the game goes on")

        XCTAssertTrue(model.handle(.home))
        XCTAssertTrue(try chosen(model, "loadState"))
        XCTAssertEqual(try row(model, "loadState").detail, "Go back to a moment you saved. The memory card goes back to that moment too.",
                       "a PS1 card goes back too")
        try choose(model, "saveState")
        let when = try XCTUnwrap(try row(model, "state-0").detail)
        XCTAssertNotNil(when.range(of: #"^\d{4}-\d\d-\d\d \d\d:\d\d$"#, options: .regularExpression), when)
        model.menuIndex = 0
        try choose(model, "state-0")
        XCTAssertEqual(model.overlay, .retroOverwriteState)
        XCTAssertEqual(model.retroOverwriteQuestion?.title, "Overwrite slot 1?")
        XCTAssertEqual(model.retroOverwriteQuestion?.detail, "The state saved \(when) is replaced by this moment.")
        XCTAssertEqual(model.menuIndex, 0, "Cancel first, where the focus starts")

        XCTAssertTrue(model.handle(.back))
        XCTAssertEqual(model.overlay, .retroMenu, "Back goes back to Save state")
        XCTAssertEqual(model.retroMenuTitle, "Save state")
        XCTAssertEqual(saveCalls(host).count, 1)
        XCTAssertEqual(model.retroPlay?.menu.isOpen, true, "the game stays paused")

        try choose(model, "state-0")
        XCTAssertTrue(model.handle(.right))
        XCTAssertEqual(model.menuIndex, 1)
        XCTAssertTrue(model.handle(.select))
        try await settle({ model.overlay == nil }, "overwritten, back to the game")
        XCTAssertEqual(saveCalls(host).count, 2)

        try await openMenu(model, host)
        try choose(model, "saveState")
        XCTAssertTrue(model.handle(.back))
        XCTAssertNil(model.retroPlay?.statePage)
        XCTAssertEqual(model.menuIndex, 1, "on the Save state row")
    }

    func testSaveStateAndLoadStateShowOnceTheGameHasShownItsFirstFrameKeepingTheFocus() async throws {
        let (model, _, host) = try await playing(ready: false)
        XCTAssertEqual(model.retroPlay?.host.phase, .loading)
        // PS gives a start up while the game loads; the menu opened all the same.
        model.openRetroMenu()
        XCTAssertEqual(model.overlay, .retroMenu)
        XCTAssertEqual(ids(model), ["resume", "section-audio", "section-console", "section-advanced", "closeGame"], "the host saves nothing yet")
        model.menuIndex = 4
        host.gameStatus = try Self.status(ready: true)
        await model.retroPlay?.host.refresh()
        XCTAssertEqual(model.retroPlay?.host.phase, .playing)
        XCTAssertEqual(ids(model), ["resume", "saveState", "loadState", "section-audio", "section-console", "section-advanced", "closeGame"])
        XCTAssertEqual(ids(model)[model.menuIndex], "closeGame", "the focus stays on the row it was on")
    }

    func testASlotSaysSavingOrLoadingWhileItsCallRunsAndNothingElseStartsMeanwhile() async throws {
        let (model, game, host) = try await playing()
        hostWritesStates(host, try folder(model, game))
        host.answer("saveState", Self.saved)
        host.answer("loadState", Self.loaded)
        try await openMenu(model, host)
        try choose(model, "saveState")
        let gate = PlayGate()
        host.callGate = gate
        try choose(model, "state-2")
        try await settle({ (try? self.row(model, "state-2").detail) == "Saving…" })
        XCTAssertEqual(try row(model, "state-3").detail, "Empty")
        try choose(model, "state-3")
        await Task.yield()
        XCTAssertEqual(saveCalls(host).count, 1, "one at a time")
        host.callGate = nil
        gate.open()
        try await settle({ model.overlay == nil })

        try await openMenu(model, host)
        try choose(model, "loadState")
        let loading = PlayGate()
        host.callGate = loading
        try choose(model, "state-2")
        try await settle({ (try? self.row(model, "state-2").detail) == "Loading…" })
        host.callGate = nil
        loading.open()
        try await settle({ model.toast?.text == "Slot 3 loaded" })
    }

    func testASaveThatDoesNotWorkSaysSoAndStaysOnSaveState() async throws {
        let (model, _, host) = try await playing()
        host.refuse("saveState", RetroCallError(code: RetroCallError.fileError, message: "not written"))
        try await openMenu(model, host)
        try choose(model, "saveState")
        try choose(model, "state-3")
        try await settle({ model.toast != nil })
        XCTAssertEqual(model.toast?.text, "The state could not be saved.")
        XCTAssertEqual(model.overlay, .retroMenu)
        XCTAssertEqual(model.retroPlay?.statePage, .save)
    }

    func testLoadStateASavedSlotLoadsAndARefusedOneSaysWhyInPlainWords() async throws {
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let (model, _, host) = try await playing(slots: [1, 4], pictures: [1: png])
        try await openMenu(model, host)
        try choose(model, "loadState")
        XCTAssertEqual(model.retroMenuTitle, "Load state")
        XCTAssertFalse(try chosen(model, "state-0"), "an empty slot cannot be loaded")
        XCTAssertTrue(try chosen(model, "state-1"))
        XCTAssertEqual(try row(model, "state-1").picture, png)
        XCTAssertNil(try row(model, "state-4").picture)
        XCTAssertEqual(try row(model, "state-4").pictureAspect, model.retroPlay?.host.aspect, "its place is kept")
        XCTAssertEqual(model.menuIndex, 1, "on the first slot that holds a state")

        for (code, words) in [(RetroCallError.otherCore, "This state was saved by another version of the emulator, so it cannot be loaded."),
                              (RetroCallError.otherGame, "This state was saved from another game, so it cannot be loaded."),
                              (RetroCallError.badState, "This state file is damaged or was made by a newer emulator, so it cannot be loaded."),
                              (RetroCallError.coreRefused, "The state could not be loaded."),
                              (RetroCallError.fileError, "The state could not be loaded.")] {
            model.toast = nil
            host.refuse("loadState", Self.refusal(code))
            try choose(model, "state-1")
            try await settle({ model.toast != nil }, code)
            XCTAssertEqual(model.toast?.text, words, code)
            XCTAssertEqual(model.overlay, .retroMenu, "\(code): still on Load state")
            XCTAssertEqual(model.retroPlay?.statePage, .load)
        }

        host.refuse("loadState", nil)
        host.answer("loadState", Self.loaded)
        try choose(model, "state-4")
        try await settle({ model.overlay == nil }, "back to the game, which goes on from the state")
        XCTAssertEqual(host.args("loadState").last, .object(["slot": .int(4)]))
        XCTAssertEqual(model.toast?.text, "Slot 5 loaded")
    }

    func testALoadThatAnswersAfterTheMenuWasLeftAndOpenedAgainLeavesTheNewVisitAlone() async throws {
        let (model, _, host) = try await playing(slots: [0])
        host.answer("loadState", Self.loaded)
        try await openMenu(model, host)
        try choose(model, "loadState")
        let gate = PlayGate()
        host.callGate = gate
        try choose(model, "state-0")
        try await settle({ host.methods.contains("loadState") })
        model.resumeRetroGame()
        host.callGate = nil
        model.openRetroMenu()
        try choose(model, "loadState")
        gate.open()
        try await settle({ model.toast?.text == "Slot 1 loaded" })
        XCTAssertEqual(model.overlay, .retroMenu, "the menu opened again stays open")
        XCTAssertEqual(model.retroPlay?.statePage, .load)
    }

    func testASlotFoundEmptyOnLoadSaysItCouldNotBeLoadedAndShowsAsEmpty() async throws {
        let (model, game, host) = try await playing(slots: [2])
        try await openMenu(model, host)
        try choose(model, "loadState")
        try FileManager.default.removeItem(atPath: try folder(model, game).statePath(2))
        host.refuse("loadState", Self.refusal(RetroCallError.noState))
        try choose(model, "state-2")
        try await settle({ model.toast != nil })
        XCTAssertEqual(model.toast?.text, "The state could not be loaded.")
        try await settle({ (try? self.chosen(model, "state-2")) == false }, "read again, the slot is empty")
    }

    func testPsOnOverwriteSlotGoesBackToSaveStateAndTheGameEndingClosesBoth() async throws {
        let (model, _, host) = try await playing(slots: [0])
        host.answer("saveState", Self.saved)
        try await openMenu(model, host)
        try choose(model, "saveState")
        try choose(model, "state-0")
        XCTAssertEqual(model.overlay, .retroOverwriteState)
        XCTAssertTrue(model.handle(.home))
        XCTAssertEqual(model.overlay, .retroMenu)
        XCTAssertEqual(model.retroPlay?.statePage, .save)
        try choose(model, "state-0")
        XCTAssertTrue(model.handle(.options))
        XCTAssertEqual(model.overlay, .retroMenu, "Options goes back to Save state too")
        XCTAssertEqual(model.retroPlay?.statePage, .save)
        XCTAssertEqual(model.menuIndex, 0, "on that slot")
        XCTAssertTrue(saveCalls(host).isEmpty)
        try choose(model, "state-0")
        model.homeButton(hold: true)
        XCTAssertNil(model.overlay, "held PS goes back to the game")
        try await settle({ model.retroPlay?.menu.isOpen == false })

        model.openRetroMenu()
        try choose(model, "saveState")
        try choose(model, "state-0")
        XCTAssertEqual(model.overlay, .retroOverwriteState)
        host.gameStatus = try Self.status(ready: true, ended: true, errorCode: RetroErrorCode.core)
        await model.retroPlay?.host.refresh()
        XCTAssertNil(model.overlay, "the question goes with the game")
        XCTAssertNil(model.retroPlay?.statePage)
    }

    func testAPs1LoadAnsweredFalseThatEndedTheGameWithOtherSaysTheCardMayBeBackAtThatMoment() async throws {
        let (model, _, host) = try await playing(slots: [0])
        host.answer("loadState", .bool(false))
        try await openMenu(model, host)
        try choose(model, "loadState")
        try choose(model, "state-0")
        try await settle({ model.toast != nil })
        XCTAssertEqual(model.toast?.text, "The state could not be loaded.")
        host.gameStatus = try Self.status(ready: true, ended: true, errorCode: RetroErrorCode.other)
        await model.retroPlay?.host.refresh()
        XCTAssertEqual(model.toast?.text, "The game stopped while the state was loading, so the memory card may already be back at that moment.")
    }

    func testAPs1LoadAnsweredFalseThatLeftTheGamePlayingSaysNothingOfTheCardAtALaterOtherEnding() async throws {
        let (model, _, host) = try await playing(slots: [0])
        host.answer("loadState", .bool(false))
        try await openMenu(model, host)
        try choose(model, "loadState")
        try choose(model, "state-0")
        try await settle({ model.toast != nil })
        let play = try XCTUnwrap(model.retroPlay)
        XCTAssertTrue(play.states.loadAnsweredFalse)
        await play.host.refresh()
        XCTAssertFalse(play.states.loadAnsweredFalse, "a status after the reply says the game plays on")
        model.resumeRetroGame()
        host.gameStatus = try Self.status(ready: true, ended: true, errorCode: RetroErrorCode.other)
        await play.host.refresh()
        XCTAssertEqual(play.host.phase, .ended)
        XCTAssertFalse(play.loadCardWarned)
        XCTAssertNotEqual(model.toast?.text, TRetro.text(.retroStateCardAfterEnd), "that ending is not the load's")
    }

    func testClosingAPs1GameWhileALoadRunsThatThenEndsItWithOtherStillSaysSo() async throws {
        let (model, _, host) = try await playing(slots: [0])
        host.answer("loadState", .bool(false))
        try await openMenu(model, host)
        try choose(model, "loadState")
        let gate = PlayGate()
        host.callGate = gate
        try choose(model, "state-0")
        try await settle({ host.methods.contains("loadState") })
        let closing = Task { await model.closeRetroGame() }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(host.methods.contains("stop"), "stop waits for the reply")
        host.callGate = nil
        host.stopErrorCode = RetroErrorCode.other
        gate.open()
        await closing.value
        XCTAssertNil(model.retroPlay)
        XCTAssertEqual(model.toast?.text, TRetro.text(.retroStateCardAfterEnd))
    }

    func testTheWordsForAStateThatDidNotWork() {
        XCTAssertEqual(AppModel.retroStateProblem(.otherCore, saving: false), .retroStateOtherCore)
        XCTAssertEqual(AppModel.retroStateProblem(.otherGame, saving: false), .retroStateOtherGame)
        XCTAssertEqual(AppModel.retroStateProblem(.badState, saving: false), .retroStateBad)
        for outcome in [RetroStateOutcome.notNow, .fileError, .failed] {
            XCTAssertEqual(AppModel.retroStateProblem(outcome, saving: false), .retroStateLoadFailed)
            XCTAssertEqual(AppModel.retroStateProblem(outcome, saving: true), .retroStateSaveFailed)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 20, minute: 4))!
        XCTAssertEqual(AppModel.retroStateTime(date), "2026-11-08 20:04")
    }

    func testTheSaveStateWordsInTurkish() throws {
        let turkish = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: T.sourceFolder.appendingPathComponent("tr.json"))) as? [String: String])
        XCTAssertEqual(turkish["retroMenuSaveState"], "Durumu kaydet")
        XCTAssertEqual(turkish["retroStateOverwriteTitle"], "%@. yuvanın üzerine yazılsın mı?")
    }
}
