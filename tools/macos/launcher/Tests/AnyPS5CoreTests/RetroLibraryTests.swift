import Darwin
import XCTest
@testable import AnyPS5Core

/// Emulator games, as on Windows and Linux (AnyPS5 Desktop's test/core/retro_library_test.dart):
/// the PS1, PS2 and PS3 discs a scan lists when Emulator games is on, their identifiers, files and
/// cache, the emulators' programs and arguments, and the scan without it, which is as before.
final class RetroLibraryTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        // The real path: the scan lists the temporary folder through /private.
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        base = URL(fileURLWithPath: try XCTUnwrap(realpath(made.path, nil).map { String(cString: $0) }))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Fixtures

    private func folder(_ relative: String, in root: URL? = nil) throws -> URL {
        let url = (root ?? base).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ data: Data, _ relative: String, in root: URL? = nil) throws -> URL {
        let url = (root ?? base).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    @discardableResult
    private func write(_ text: String, _ relative: String, in root: URL? = nil) throws -> URL {
        try write(Data(text.utf8), relative, in: root)
    }

    /// A data disc's cue sheet and its track, `bytes` long.
    private func cue(_ stem: String, in folder: String = "", bytes: Int = 0, root: URL? = nil) throws {
        let prefix = folder.isEmpty ? "" : folder + "/"
        try write(Data(count: bytes), prefix + stem + ".bin", in: root)
        try write("FILE \"\(stem).bin\" BINARY\n  TRACK 01 MODE2/2352\n", prefix + stem + ".cue", in: root)
    }

    @discardableResult
    private func dump(_ relative: String, title: String, name: String, in root: URL? = nil) throws -> URL {
        let folder = try folder(relative, in: root)
        let json = #"{"titleId":"\#(title)","contentVersion":"01.000","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"\#(name)"}}}"#
        try write(json, "sce_sys/param.json", in: folder)
        try write(Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0, 0]), "eboot.bin", in: folder)
        return folder
    }

    private func retroJSON(_ fields: [String: String], in folder: URL) throws {
        try write(JSONSerialization.data(withJSONObject: fields), "retro.json", in: folder)
    }

    /// A PARAM.SFO with these text values, as a PS3 disc has it.
    private func paramSFO(_ values: [(String, String)]) -> Data {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { u16(value & 0xFFFF) + u16(value >> 16) }
        let keyStart = 20 + values.count * 16
        var keys: [UInt8] = [], data: [UInt8] = [], index: [UInt8] = []
        for (key, value) in values {
            let text = Array(value.utf8) + [0]
            index += u16(keys.count) + u16(0x0204) + u32(text.count) + u32(text.count) + u32(data.count)
            keys += Array(key.utf8) + [0]
            data += text
        }
        let header: [UInt8] = [0x00, 0x50, 0x53, 0x46] + u32(0x0101) + u32(keyStart) + u32(keyStart + keys.count) + u32(values.count)
        return Data(header + index + keys + data)
    }

    /// An ISO 9660 image whose root holds SYSTEM.CNF with `system` in it.
    private func iso(_ system: String) -> Data {
        let sector = 2048
        var bytes = [UInt8](repeating: 0, count: 23 * sector)
        func put32(_ at: Int, _ value: Int) { for shift in 0..<4 { bytes[at + shift] = UInt8(value >> (shift * 8) & 0xFF) } }
        let descriptor = 16 * sector
        bytes[descriptor] = 1
        bytes.replaceSubrange((descriptor + 1)..<(descriptor + 6), with: Array("CD001".utf8))
        put32(descriptor + 158, 20)
        put32(descriptor + 166, sector)
        let name = Array("SYSTEM.CNF;1".utf8), text = Array(system.utf8)
        let record = 20 * sector
        bytes[record] = UInt8(33 + name.count + (name.count % 2 == 0 ? 1 : 0))
        put32(record + 2, 21)
        put32(record + 10, text.count)
        bytes[record + 32] = UInt8(name.count)
        bytes.replaceSubrange((record + 33)..<(record + 33 + name.count), with: name)
        bytes.replaceSubrange((21 * sector)..<(21 * sector + text.count), with: text)
        return Data(bytes)
    }

    private func path(_ relative: String, in root: URL? = nil) -> String { (root ?? base).appendingPathComponent(relative).path }

    // MARK: Discs side by side

    func testLooseCueSheetsAreSeparateGamesAndAPlaylistGathersADiscSet() throws {
        for stem in ["Game A", "Game B Disc 1", "Game B Disc 2"] { try cue(stem) }
        try write("Game B Disc 1.cue\nGame B Disc 2.cue\n", "Game B.m3u")
        try write("FILE \"Missing.bin\" BINARY\n  TRACK 01 MODE2/2352\n", "Missing.cue")
        let games = GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache())
        XCTAssertEqual(games.map(\.name), ["Game A", "Game B"], "a sheet whose track is not there is no game, nor the discs a playlist gathers")
        XCTAssertEqual(Set(games.map(\.id)).count, 2)
        XCTAssertEqual(Set(games.map(\.titleID)).count, 2)
        XCTAssertTrue(games.allSatisfy { $0.retro?.platform == .ps1 && $0.executable == .disc })
        XCTAssertEqual(games.last?.retro?.path.path, path("Game B.m3u"), "the emulator is handed the playlist")
        XCTAssertTrue(games.allSatisfy { $0.titleID.range(of: #"^PS1-[0-9A-F]{16}$"#, options: .regularExpression) != nil }, "\(games.map(\.titleID))")
    }

    func testOneLibraryListsPS5DumpsAndRetroJSONGamesWithTheirMedia() throws {
        try dump("PS5", title: "PPSA01234", name: "Astro")
        for (platform, id, title, disc) in [("ps1", "SCUS94426", "Crash Team Racing", "disc.cue"), ("ps2", "SLUS20552", "Vice City", "disc.iso")] {
            let shelf = try folder(platform)
            for file in [disc, "cover.png", "background.png", "theme.wav"] { try write(Data(), file, in: shelf) }
            try retroJSON(["platform": platform, "titleId": id, "name": title, "disc": disc, "icon": "cover.png", "background": "background.png", "music": "theme.wav"], in: shelf)
        }
        let games = GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache())
        XCTAssertEqual(games.map(\.name), ["Astro", "Crash Team Racing", "Vice City"])
        XCTAssertEqual(GameLibrary.scan(base).map(\.name), ["Astro"], "without Emulator games only the dump")
        XCTAssertEqual(games.dropFirst().map { $0.music?.lastPathComponent }, ["theme.wav", "theme.wav"])
        XCTAssertEqual(games.dropFirst().map { $0.background?.lastPathComponent }, ["background.png", "background.png"])
        XCTAssertEqual(games.dropFirst().map(\.titleID), ["PS1-SCUS94426", "PS2-SLUS20552"])
        XCTAssertEqual(games[1].id, "retro:ps1:SCUS94426:ps1/disc.cue")
        XCTAssertNil(games[1].files, "a game with its own folder is the whole folder")

        // A descriptor that names a file outside its folder lists nothing.
        try retroJSON(["platform": "ps2", "titleId": "SLUS20552", "name": "Vice City", "disc": "../ps1/disc.cue"], in: base.appendingPathComponent("ps2"))
        XCTAssertEqual(GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache()).map(\.name), ["Astro", "Crash Team Racing"])
    }

    func testADiscFileOutsideItsFolderIsNoGame() throws {
        let shelf = try folder("Shelf")
        try write(Data(), "Outside.bin")
        try write("FILE \"../Outside.bin\" BINARY\n  TRACK 01 MODE2/2352\n", "Up.cue", in: shelf)
        try write("FILE \"/etc/hosts\" BINARY\n  TRACK 01 MODE2/2352\n", "Absolute.cue", in: shelf)
        try write("FILE \"C:\\Games\\Disc.bin\" BINARY\n  TRACK 01 MODE2/2352\n", "Drive.cue", in: shelf)
        try cue("Inside", in: "Shelf/Tracks")
        try write("FILE \"Tracks/Inside.bin\" BINARY\n  TRACK 01 MODE2/2352\n", "Nested.cue", in: shelf)
        // A retro.json whose disc is a link out of its folder.
        let linked = try folder("Linked")
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("disc.iso"), withDestinationURL: base.appendingPathComponent("Outside.bin"))
        try retroJSON(["platform": "ps2", "titleId": "SLUS00001", "name": "Linked", "disc": "disc.iso"], in: linked)
        let names = GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache()).map(\.name)
        XCTAssertEqual(names, ["Inside", "Nested"], "only tracks inside the sheet's own folder count")
    }

    func testADiscKeepsItsIdentifierWhenItsGamesFolderMovesAndListsItsOwnFiles() throws {
        func discs(_ root: URL) throws -> [Game] {
            for stem in ["Game B Disc 1", "Game B Disc 2", "Solo"] { try cue(stem, in: "PS1", root: root) }
            try write("Game B Disc 1.cue\nGame B Disc 2.cue\n", "PS1/Game B.m3u", in: root)
            return GameLibrary.scan(root, includeRetro: true, cache: RetroScanCache())
        }
        let before = try discs(try folder("drive-e")), after = try discs(try folder("drive-f"))
        XCTAssertEqual(before.count, 2)
        XCTAssertNotNil(before[0].id.range(of: #"^retro:ps1:[0-9]+:PS1/Game B\.m3u$"#, options: .regularExpression), before[0].id)
        XCTAssertNotNil(before[1].id.range(of: #"^retro:ps1:[0-9]+:PS1/Solo\.cue$"#, options: .regularExpression), before[1].id)
        XCTAssertEqual(after.map(\.id), before.map(\.id), "the same games folder on another drive: the same identifiers")
        XCTAssertEqual(after.map(\.titleID), before.map(\.titleID))
        let shelf = base.appendingPathComponent("drive-e/PS1")
        XCTAssertEqual(before[0].files?.map(\.path), ["Game B.m3u", "Game B Disc 1.cue", "Game B Disc 1.bin", "Game B Disc 2.cue", "Game B Disc 2.bin"].map { shelf.appendingPathComponent($0).path })
        XCTAssertEqual(before[1].files?.map(\.path), ["Solo.cue", "Solo.bin"].map { shelf.appendingPathComponent($0).path })
    }

    func testTwoGamesFoldersWithADifferentDiscAtTheSamePathBothShowIt() throws {
        let roots = [try folder("one"), try folder("two")]
        for (index, root) in roots.enumerated() { try cue("Game", bytes: 100 * (index + 1), root: root) }
        let games = GameLibrary.survey(roots: roots, includeRetro: true, cache: RetroScanCache()).games
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(Set(games.map(\.id)).count, 2)
    }

    func testARescanReadsADiscFileAgainOnlyWhenItsSizeOrTimeChanged() throws {
        let cache = RetroScanCache()
        try write(Data(), "Game.bin")
        let sheet = try write("FILE \"Game.bin\" BINARY\n  TRACK 01 MODE2/2352\n", "Game.cue")
        let length = try XCTUnwrap(GameLibrary.fileLength(sheet.path))
        let modified = Date(timeIntervalSince1970: 1_793_534_400)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: sheet.path)
        func names() -> [String] { GameLibrary.survey(roots: [base], includeRetro: true, cache: cache).games.map(\.name) }
        XCTAssertEqual(names(), ["Game"])
        XCTAssertEqual(cache.count, 1)

        // The same size and time: what was read is used, the contents are not read again.
        let audio = "FILE \"Game.bin\" BINARY\n  TRACK 01 AUDIO/2352\n"
        try write(audio.padding(toLength: Int(length), withPad: " ", startingAt: 0), "Game.cue")
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: sheet.path)
        XCTAssertEqual(names(), ["Game"])

        try FileManager.default.setAttributes([.modificationDate: modified.addingTimeInterval(60)], ofItemAtPath: sheet.path)
        XCTAssertEqual(names(), [], "changed: read again, and an audio sheet is no game")
        XCTAssertEqual(GameLibrary.survey(roots: [base], cache: cache).games, [], "a PS5 scan reads no disc")

        try FileManager.default.removeItem(at: sheet)
        _ = GameLibrary.survey(roots: [base], includeRetro: true, cache: cache)
        XCTAssertEqual(cache.count, 0, "a file gone from the library is let go")
    }

    func testAPS2ImageIsOneWhoseSystemCnfHasABoot2Line() throws {
        try write(iso("BOOT2 = cdrom0:\\SLUS_200.62;1\r\nVER = 1.00\r\n"), "Vice City.iso")
        try write(iso("BOOT = cdrom:\\SLUS_000.01;1\r\n"), "Not PS2.iso")
        try write(Data(count: 4096), "Empty.iso")
        let games = GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache())
        XCTAssertEqual(games.map(\.name), ["Vice City"])
        XCTAssertEqual(games.first?.retro?.platform, .ps2)
    }

    func testCHDAndPBPGoByTheirHeaderAndTheConsoleTheirFolderNames() throws {
        let chd = Data("MComprHD".utf8) + Data(count: 64)
        try write(chd, "PS1/One.chd")
        try write(chd, "PlayStation 2/Two.chd")
        try write(chd, "Loose.chd")
        try write(Data([0x00, 0x50, 0x42, 0x50]) + Data(count: 64), "Pocket.pbp")
        try write(Data(count: 68), "Fake.pbp")
        try cue("Sheet", in: "PS2")
        let games = GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache())
        XCTAssertEqual(games.map(\.name), ["One", "Pocket", "Two"], "a CHD outside a console's folder, a PBP without its header and a cue sheet in a PS2 folder are none")
        XCTAssertEqual(games.map { $0.retro?.platform }, [.ps1, .ps1, .ps2])
    }

    func testAnExtractedPS3DiscIsNamedFromItsParamSFO() throws {
        let disc = try folder("Games/Retro Three")
        try write(Data(), "PS3_DISC.SFB", in: disc)
        try write(Data(), "PS3_GAME/USRDIR/EBOOT.BIN", in: disc)
        try write(paramSFO([("APP_VER", "01.02"), ("TITLE", "Retro Three"), ("TITLE_ID", "BLUS01234")]), "PS3_GAME/PARAM.SFO", in: disc)
        try write(Data(), "PS3_GAME/ICON0.PNG", in: disc)
        let game = try XCTUnwrap(GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache()).first)
        XCTAssertEqual(game.name, "Retro Three")
        XCTAssertEqual(game.titleID, "PS3-BLUS01234")
        XCTAssertEqual(game.version, "01.02")
        XCTAssertEqual(game.id, "retro:ps3:BLUS01234:Games/Retro Three/PS3_DISC.SFB")
        XCTAssertEqual(game.icon?.lastPathComponent, "ICON0.PNG")
        XCTAssertEqual(game.retro?.platform, .ps3)
        XCTAssertEqual(StandaloneEmulator.bootFile(try XCTUnwrap(game.retro), folder: game.folder).path, disc.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN").path)

        try write(paramSFO([("TITLE", "Retro Three"), ("TITLE_ID", "BLUS1234")]), "PS3_GAME/PARAM.SFO", in: disc)
        XCTAssertEqual(GameLibrary.scan(base, includeRetro: true, cache: RetroScanCache()).count, 0, "a title ID that is not one")
    }

    // MARK: With Emulator games off, as before

    /// A library with dumps (two of one name, one not whole yet) and every kind of disc.
    private func mixedLibrary() throws {
        try dump("A", title: "PPSA00001", name: "Alpha")
        try dump("B", title: "PPSA00002", name: "alpha")
        try dump("Deep/One/C", title: "PPSA00003", name: "Beta")
        try dump("Retro", title: "PPSA00004", name: "Retro")
        try write(Data(), "Half/sce_sys/param.json")
        try cue("Retro")
        try cue("Beta", in: "PS1")
        let shelf = try folder("Shelf")
        try write(Data(), "disc.iso", in: shelf)
        try retroJSON(["platform": "ps2", "titleId": "SLUS20552", "name": "Alpha", "disc": "disc.iso"], in: shelf)
        // A dump with a retro.json in it stays a PS5 game.
        try retroJSON(["platform": "ps1", "titleId": "SCUS00001", "name": "Not this", "disc": "eboot.bin"], in: base.appendingPathComponent("A"))
    }

    func testWithoutEmulatorGamesTheScanIsTheSameAsBefore() throws {
        try mixedLibrary()
        let before = GameLibrary.survey(base)
        let off = GameLibrary.survey(base, includeRetro: false)
        XCTAssertTrue(GameLibrary.sameListing(before.games, off.games))
        // Alpha and alpha in the order the folder lists them, as ever.
        XCTAssertEqual(before.games.map { $0.name.lowercased() }, ["alpha", "alpha", "beta", "retro"])
        XCTAssertEqual(before.incomplete.map(\.path), [path("Half")])
        XCTAssertEqual(before.games.map(\.id), before.games.map(\.folder.path), "a dump is still known by its folder")
        XCTAssertTrue(before.games.allSatisfy { $0.retro == nil && $0.libraryID == nil && $0.files == nil && $0.executable != .disc })
        XCTAssertEqual(GameLibrary.survey(roots: [base]).games.map(\.id), before.games.map(\.id))
        XCTAssertFalse(LibraryMonitor(roots: [base]) { _ in }.includeRetro, "the watch scans as before unless asked")

        let on = GameLibrary.survey(base, includeRetro: true, cache: RetroScanCache())
        XCTAssertEqual(on.games.filter { $0.retro == nil }.map(\.id), before.games.map(\.id), "the dumps keep their order among the discs")
        XCTAssertEqual(on.games.filter { $0.retro != nil }.map(\.name), ["Alpha", "Beta", "Retro"])
        XCTAssertEqual(on.incomplete, before.incomplete)
        XCTAssertEqual(on.games.map { $0.name.lowercased() }, ["alpha", "alpha", "alpha", "beta", "beta", "retro", "retro"])
        XCTAssertEqual(on.games.map { $0.retro != nil }, [false, false, true, false, true, false, true], "a disc comes after the dumps of its name")
    }

    func testDumpsSortAsTheyDidBeforeThereWereDiscs() throws {
        try mixedLibrary()
        let games = GameLibrary.survey(base).games
        for order in [games, games.reversed(), games.shuffled(), games.shuffled()] {
            let before = order.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            XCTAssertEqual(order.sorted(by: GameLibrary.byName).map(\.id), before.map(\.id))
        }
    }

    // MARK: The emulators

    func testAnApplicationIsStartedByItsOwnExecutable() throws {
        let app = try folder("PCSX2-v2.8.2.app/Contents")
        try write(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>PCSX2</string><key>CFBundleIdentifier</key><string>net.pcsx2.pcsx2.test\#(UUID().uuidString)</string></dict></plist>"#, "Info.plist", in: app)
        let executable = try write(Data(), "MacOS/PCSX2", in: app)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let program = try XCTUnwrap(StandaloneEmulator.executable(of: app.deletingLastPathComponent()))
        XCTAssertEqual(program.resolvingSymlinksInPath().path, app.appendingPathComponent("MacOS/PCSX2").path, "the bundle's CFBundleExecutable, whatever the bundle is called")
        let binary = try write(Data(), "duckstation")
        XCTAssertEqual(StandaloneEmulator.executable(of: binary), binary, "a program picked as it is")
        XCTAssertNil(StandaloneEmulator.executable(of: try folder("Not an app")))
        XCTAssertNil(StandaloneEmulator.executable(of: base.appendingPathComponent("gone")))
        XCTAssertNil(StandaloneEmulator.executable(of: try XCTUnwrap(URL(string: "https://example.com/emulator"))))
    }

    func testTheEmulatorsAreHandedTheDiscWithoutTheirWindow() {
        let disc = URL(fileURLWithPath: "/Games/PS1/Game.cue"), eboot = URL(fileURLWithPath: "/Games/Disc/PS3_GAME/USRDIR/EBOOT.BIN")
        XCTAssertEqual(StandaloneEmulator.arguments(.ps1, boot: disc), ["-nogui", "--", "/Games/PS1/Game.cue"])
        XCTAssertEqual(StandaloneEmulator.arguments(.ps2, boot: disc), ["-nogui", "--", "/Games/PS1/Game.cue"])
        XCTAssertEqual(StandaloneEmulator.arguments(.ps3, boot: eboot), ["--no-gui", "/Games/Disc/PS3_GAME/USRDIR/EBOOT.BIN"])
        XCTAssertEqual(RetroPlatform.allCases.map(\.emulator), ["DuckStation", "PCSX2", "RPCS3"])
    }

    func testADiscWhoseFileWentIsNotThere() throws {
        let disc = try folder("Disc")
        try write(Data(), "PS3_DISC.SFB", in: disc)
        let ps3 = RetroDisc(platform: .ps3, path: disc.appendingPathComponent("PS3_DISC.SFB"))
        XCTAssertFalse(StandaloneEmulator.discThere(ps3, folder: disc), "no EBOOT.BIN to boot")
        try write(Data(), "PS3_GAME/USRDIR/EBOOT.BIN", in: disc)
        XCTAssertTrue(StandaloneEmulator.discThere(ps3, folder: disc))
        XCTAssertFalse(StandaloneEmulator.discThere(RetroDisc(platform: .ps1, path: base.appendingPathComponent("gone.cue")), folder: base))
    }

    func testAnEmulatorIsAskedToEndAndItsExitCodeTold() async throws {
        let log = base.appendingPathComponent("Logs/PS1-TEST.log")
        let run = try EmulatorProcess.start(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], log: log)
        XCTAssertGreaterThan(run.processIdentifier, 0)
        XCTAssertTrue(run.stop())
        let code = await run.exitCode()
        XCTAssertEqual(code, -SIGTERM, "ended by the signal")
        XCTAssertFalse(run.stop(), "nothing is signalled once it has ended")
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8).components(separatedBy: "\n").first, "/bin/sleep 30")

        let failing = try EmulatorProcess.start(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], log: log)
        let failed = await failing.exitCode()
        XCTAssertEqual(failed, 1)
        XCTAssertThrowsError(try EmulatorProcess.start(executable: base.appendingPathComponent("gone"), arguments: [], log: log))
    }
}
