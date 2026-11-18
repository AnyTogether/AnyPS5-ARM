@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import XCTest

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

    func setInputFocus(_ focused: Bool) { locked { focus.append(focused) } }

    func startGame(_ args: RetroJSON) async throws -> Int {
        locked {
            starts.append(args)
            current = try? RetroHostPlayTests.status(ready: false)
            return starts.count
        }
    }

    func call(_ method: String, _ args: RetroJSON) async throws -> RetroJSON {
        locked {
            calls.append((method, args))
            switch method {
            case "release":
                if current?.ended == true { current = nil }
                return .null
            case "connectedPorts", "changeDisc", "option": return .bool(true)
            default: return .null
            }
        }
    }

    func status() async throws -> RetroStatus? { locked { current } }

    func stopGame() async throws -> RetroStatus? {
        locked {
            calls.append(("stop", .null))
            guard var status = current else { return nil }
            status.ended = true
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
        XCTAssertEqual(start["options"], .object(["swanstation_Console_Region": .string("NTSC-U")]),
                       "a graphics option, a hidden one and another core's are not sent")
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
                       "only LRPS2's options, and not its resolution scale, a graphics option")
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

    func testTheMenuWordsInTurkishSayKontrolcu() throws {
        let turkish = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: T.sourceFolder.appendingPathComponent("tr.json"))) as? [String: String])
        XCTAssertEqual(turkish["retroMenuController"], "Kontrolcü")
        XCTAssertEqual(turkish["retroHostLoading"], "Oyun yükleniyor…")
    }
}
