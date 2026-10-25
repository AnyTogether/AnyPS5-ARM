import XCTest
@testable import AnyPS5Core

/// The fixtures are shortcuts.vdf files laid out as a 2024-2026 Steam client writes them (the
/// same files the Windows and Linux launcher's tests read): on Windows a Steam-made shortcut,
/// Heroic with launch options and two tags, a hidden game with Turkish letters; on a Steam Deck
/// EmulationStation-DE, a Flatpak app with FlatpakAppID and sortas, Lutris with three tags; and
/// an empty list.
final class SteamTests: XCTestCase {
    static func fixture(_ name: String) throws -> [UInt8] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Steam/\(name)")
        return [UInt8](try Data(contentsOf: url))
    }

    var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("steam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: Binary VDF

    func testFixturesReadAndWriteBackToTheSameBytes() throws {
        for name in ["windows_shortcuts.vdf", "deck_shortcuts.vdf", "empty_shortcuts.vdf"] {
            let bytes = try Self.fixture(name)
            XCTAssertEqual(BinaryVdf.encode(try BinaryVdf.decode(bytes)), bytes, name)
        }
    }

    func testFieldsReadAsSteamWroteThem() throws {
        let list = try XCTUnwrap(try BinaryVdf.decode(Self.fixture("windows_shortcuts.vdf")).root.map("shortcuts"))
        XCTAssertEqual(list.entries.map(\.name), ["0", "1", "2"])
        let notepad = try XCTUnwrap(list.map("0"))
        XCTAssertEqual(notepad.int32("appid"), -1408730215)
        XCTAssertEqual(notepad.string("Exe"), #""C:\Program Files\Notepad++\notepad++.exe""#)
        XCTAssertEqual(list.map("1")?.strings("tags"), ["Epic", "favorite"])
        XCTAssertEqual(list.map("2")?.string("appname"), "Pokémon Ünite Ç")
        XCTAssertEqual(list.map("2")?.int32("IsHidden"), 1)
        let deck = try XCTUnwrap(try BinaryVdf.decode(Self.fixture("deck_shortcuts.vdf")).root.map("shortcuts"))
        XCTAssertEqual(deck.map("1")?.string("FlatpakAppID"), "com.usebottles.bottles")
        XCTAssertEqual(deck.map("2")?.strings("tags"), ["Linux", "Lutris", "Tools"])
    }

    func testOtherTypesAreKeptToTheByte() throws {
        var bytes: [UInt8] = [0x00] + Array("root".utf8) + [0]
        bytes += [0x03] + Array("f".utf8) + [0, 0x00, 0x00, 0x80, 0x3F]
        bytes += [0x04] + Array("ptr".utf8) + [0, 1, 2, 3, 4]
        bytes += [0x05] + Array("w".utf8) + [0, 0x41, 0x00, 0x42, 0x00, 0x00, 0x00]
        bytes += [0x06] + Array("c".utf8) + [0, 9, 8, 7, 6]
        bytes += [0x07] + Array("u64".utf8) + [0, 1, 2, 3, 4, 5, 6, 7, 8]
        bytes += [0x0A] + Array("i64".utf8) + [0, 8, 7, 6, 5, 4, 3, 2, 1]
        bytes += [0x0B, 0x08, 0xAA, 0xBB]
        let document = try BinaryVdf.decode(bytes)
        XCTAssertEqual(document.root.map("root")?.entries.count, 6)
        XCTAssertEqual(document.trailing, [0xAA, 0xBB])
        XCTAssertEqual(BinaryVdf.encode(document), bytes)
    }

    func testCutOffOrUnknownFilesAreRefused() throws {
        let bytes = try Self.fixture("windows_shortcuts.vdf")
        XCTAssertThrowsError(try BinaryVdf.decode(Array(bytes.dropLast(40))))
        XCTAssertThrowsError(try BinaryVdf.decode([0x09, 0x41, 0x00, 0x08]))
        XCTAssertThrowsError(try ShortcutsFile(bytes: [0x00, 0x78, 0x00, 0x08, 0x08]))
    }

    func testLoginUsers() throws {
        let parsed = try TextVdf.parse(#"""
        "users"
        {
        	"76561198012345678"
        	{
        		"AccountName"		"siler"
        		"PersonaName"		"Siler \"S\" Bey"
        		"MostRecent"		"1"
        	}
        	// an older account
        	"76561197960287930" { "AccountName" "gaben" "mostrecent" "0" }
        }
        """#)
        XCTAssertEqual(parsed["USERS"]?.entries.map(\.0), ["76561198012345678", "76561197960287930"])
        XCTAssertEqual(parsed["users"]?["76561198012345678"]?["PersonaName"]?.text, #"Siler "S" Bey"#)
        XCTAssertEqual(parsed["users"]?["76561197960287930"]?["MostRecent"]?.text, "0")
        XCTAssertThrowsError(try TextVdf.parse(#""a" { "b" "c""#))
        XCTAssertThrowsError(try TextVdf.parse(#""a" "b" }"#))
    }

    // MARK: IDs

    func testShortcutIDs() {
        XCTAssertEqual(SteamAppID.crc32(Array("123456789".utf8)), 0xCBF4_3926)
        // Worked out with Python's zlib.crc32((exe + name).encode()) | 0x80000000; the same values
        // as the Windows and Linux launcher's tests.
        XCTAssertEqual(SteamAppID.shortcut(exe: #""/Applications/AnyPS5.app/Contents/MacOS/AnyPS5""#, appName: "AnyPS5"), 2_551_145_623)
        XCTAssertEqual(SteamAppID.shortcut(exe: #""C:\Program Files\AnyPS5\anyps5_desktop.exe""#, appName: "AnyPS5"), 3_980_285_510)
        XCTAssertEqual(SteamAppID.shortcut(exe: #""/home/deck/Applications/AnyPS5-Desktop-x86_64.AppImage""#, appName: "Hollow Knight: Silksong"), 3_816_483_209)
        XCTAssertEqual(SteamAppID.gameID(2_551_145_623), 10_957_087_018_152_099_840)
        let shortcut = SteamPlan.launcher(program: "/Applications/AnyPS5.app/Contents/MacOS/AnyPS5")
        XCTAssertEqual(UInt32(bitPattern: shortcut.vdf.int32("appid")!), shortcut.appID)
    }

    // MARK: The shortcuts

    let program = "/Applications/AnyPS5.app/Contents/MacOS/AnyPS5"

    func steam() -> SteamShortcuts { SteamShortcuts(install: SteamInstall(root: temp), user: SteamUser(id: "52079950")) }

    func existing(_ name: String) throws {
        let steam = steam()
        try FileManager.default.createDirectory(at: steam.config, withIntermediateDirectories: true)
        try Data(Self.fixture(name)).write(to: steam.shortcutsFile)
    }

    func art(_ seed: UInt8) -> [SteamArt: Data] {
        Dictionary(uniqueKeysWithValues: SteamArt.allCases.enumerated().map { ($0.element, Data([seed, UInt8($0.offset)])) })
    }

    func entries(games: Bool = false) -> [SteamEntry] {
        let steam = steam()
        var list = [SteamEntry(SteamPlan.launcher(program: program, fullscreen: true, into: steam), art: art(1))]
        if games {
            list.append(SteamEntry(SteamPlan.game(program: program, name: "Hollow Knight: Silksong", titleID: "PPSA12544", into: steam), art: art(2)))
        }
        return list
    }

    func bytes() throws -> [UInt8] { [UInt8](try Data(contentsOf: steam().shortcutsFile)) }

    func testTheLaunchersEntry() throws {
        try existing("deck_shortcuts.vdf")
        let change = try steam().put(entries())
        let entry = try XCTUnwrap(steam().ours().first)
        XCTAssertEqual(steam().ours().count, 1)
        XCTAssertEqual(entry.string("AppName"), "AnyPS5")
        XCTAssertEqual(entry.string("Exe"), "\"\(program)\"")
        XCTAssertEqual(entry.string("StartDir"), "\"/Applications/AnyPS5.app/Contents/MacOS\"")
        XCTAssertEqual(entry.string("LaunchOptions"), "--steam --fullscreen")
        XCTAssertEqual(entry.strings("tags"), ["AnyPS5"])
        XCTAssertEqual(entry.int32("AllowOverlay"), 1)
        XCTAssertEqual(ShortcutsFile.appID(of: entry), 2_551_145_623)
        XCTAssertEqual(entry.string("icon"), steam().artPath(2_551_145_623, .icon).path)
        XCTAssertEqual(change.appIDs, [2_551_145_623])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: steam().gridFolder.path)),
                       ["2551145623p.png", "2551145623.png", "2551145623_hero.png", "2551145623_logo.png", "2551145623_icon.png"])
        XCTAssertEqual(try BinaryVdf.decode(bytes()).root.map("shortcuts")?.entries.map(\.name), ["0", "1", "2", "3"])
    }

    func testOthersKeepTheirBytesAndRemovingGivesTheFileBack() throws {
        try existing("windows_shortcuts.vdf")
        let before = try Self.fixture("windows_shortcuts.vdf")
        func bodies(_ file: [UInt8]) throws -> [String: [UInt8]] {
            let list = try XCTUnwrap(try BinaryVdf.decode(file).root.map("shortcuts"))
            return Dictionary(uniqueKeysWithValues: list.entries.compactMap { entry -> (String, [UInt8])? in
                guard case .map(let map) = entry.value else { return nil }
                return (map.string("AppName") ?? "", BinaryVdf.encode(entry.renamed("x")))
            })
        }
        try steam().put(entries(games: true))
        let kept = try bodies(bytes())
        for (name, body) in try bodies(before) { XCTAssertEqual(kept[name], body, name) }
        XCTAssertNotNil(kept["Hollow Knight: Silksong"])
        let removed = try steam().remove()
        XCTAssertEqual(Set(removed.appIDs), [2_551_145_623, SteamPlan.game(program: program, name: "Hollow Knight: Silksong", titleID: "PPSA12544").appID])
        XCTAssertEqual(try bytes(), before)
    }

    func testAddingAgainChangesNothingAndGamesOffTakeTheirEntryAway() throws {
        try existing("deck_shortcuts.vdf")
        try steam().put(entries(games: true))
        let once = try bytes()
        try steam().put(entries(games: true))
        XCTAssertEqual(try bytes(), once)
        XCTAssertEqual(steam().ours().count, 2)
        try steam().put(entries())
        XCTAssertEqual(steam().ours().map { $0.string("AppName") }, ["AnyPS5"])
        let game = SteamPlan.game(program: program, name: "Hollow Knight: Silksong", titleID: "PPSA12544").appID
        XCTAssertFalse(FileManager.default.fileExists(atPath: steam().artPath(game, .hero).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: steam().artPath(2_551_145_623, .hero).path))
    }

    func testRemovingWithNoneOfOursWritesNothing() throws {
        try existing("deck_shortcuts.vdf")
        XCTAssertEqual(try steam().remove().appIDs, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: steam().backupFile.path))
        try steam().put(entries())
        XCTAssertEqual(try steam().remove().appIDs, [2_551_145_623])
        XCTAssertEqual(try steam().remove().appIDs, [])
        XCTAssertEqual(try bytes(), try Self.fixture("deck_shortcuts.vdf"))
    }

    func testOursBeforeOthersAreTakenOutAndTheRestRenumbered() throws {
        try existing("empty_shortcuts.vdf")
        try steam().put(entries())
        var document = try BinaryVdf.decode(bytes())
        let lutris = try XCTUnwrap(try BinaryVdf.decode(Self.fixture("deck_shortcuts.vdf")).root.map("shortcuts")?.entries.last)
        guard case .map(var list) = document.root.entries[0].value else { return XCTFail() }
        list.entries.append(lutris.renamed("1"))
        document.root.entries[0].value = .map(list)
        try Data(BinaryVdf.encode(document)).write(to: steam().shortcutsFile)
        try steam().remove()
        let left = try XCTUnwrap(try BinaryVdf.decode(bytes()).root.map("shortcuts"))
        XCTAssertEqual(left.entries.map(\.name), ["0"])
        XCTAssertEqual(BinaryVdf.encode(left.entries[0].renamed("2")), BinaryVdf.encode(lutris))
    }

    func testAShortcutTaggedByHandIsNotOurs() {
        let mine = SteamShortcut(appName: "AnyPS5 (mine)", exe: "\"/opt/anyps5\"", startDir: "\"/opt\"", launchOptions: "--trace").vdf
        XCTAssertFalse(ShortcutsFile.isOurs(mine))
        var file = ShortcutsFile.empty
        file.putOurs([SteamPlan.launcher(program: program)])
        XCTAssertEqual(file.ours.count, 1)
    }

    func testBackupBeforeEachWriteAndAFileMadeWhenThereIsNone() throws {
        try steam().put(entries())
        XCTAssertFalse(FileManager.default.fileExists(atPath: steam().backupFile.path))
        let first = try bytes()
        try steam().put(entries(games: true))
        XCTAssertEqual([UInt8](try Data(contentsOf: steam().backupFile)), first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: steam().shortcutsFile.path + ".anyps5-new"))
    }

    func testOtherPicturesStay() throws {
        try existing("deck_shortcuts.vdf")
        try FileManager.default.createDirectory(at: steam().gridFolder, withIntermediateDirectories: true)
        let foreign = steam().gridFolder.appendingPathComponent("3000000000p.png")
        try Data([7]).write(to: foreign)
        try steam().put(entries())
        try steam().remove()
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: steam().gridFolder.path).count, 1)
    }

    // MARK: Finding Steam

    func testFindingSteamAndItsAccounts() throws {
        XCTAssertEqual(SteamLocator.find(home: temp), [])
        let root = temp.appendingPathComponent("Library/Application Support/Steam")
        for id in ["0", "52079950", "22202", "99"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("userdata/\(id)/config"), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("config"), withIntermediateDirectories: true)
        try #"""
        "users"
        {
        	"76561197960287930" { "AccountName" "gaben" "PersonaName" "Gabe" "MostRecent" "0" "Timestamp" "1600000000" }
        	"76561198012345678" { "AccountName" "siler" "PersonaName" "Siler" "MostRecent" "1" "Timestamp" "1500000000" }
        }
        """#.write(to: root.appendingPathComponent("config/loginusers.vdf"), atomically: true, encoding: .utf8)
        let found = SteamLocator.find(home: temp)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(SteamUser.accountID(of: 76_561_198_012_345_678), 52_079_950)
        let users = try XCTUnwrap(found.first).users()
        XCTAssertEqual(users.map(\.id), ["52079950", "22202", "99"])
        XCTAssertEqual(users.map(\.label), ["Siler", "Gabe", "99"])
    }

    func testSteamRunningAndQuitting() async {
        var running = true
        var started: [[String]] = []
        let control = SteamControl(run: { path, arguments in
            XCTAssertEqual([path] + arguments, ["/usr/bin/pgrep", "-x", "steam_osx"])
            return running ? 0 : 1
        }, start: { path, arguments in
            started.append([path] + arguments)
            running = false
        })
        XCTAssertTrue(control.running())
        let closed = await control.shutdown(poll: 0.005)
        XCTAssertTrue(closed)
        XCTAssertEqual(started, [["/usr/bin/open", "steam://exit"]])
        running = true
        let stubborn = SteamControl(run: { _, _ in 0 }, start: { _, _ in })
        let gaveUp = await stubborn.shutdown(timeout: 0.03, poll: 0.005)
        XCTAssertFalse(gaveUp)
    }

    // MARK: Started from Steam

    func testStartedFromSteam() {
        XCTAssertFalse(SteamLaunch(arguments: [], environment: [:]).fromSteam)
        let launch = SteamLaunch(arguments: ["AnyPS5", "--steam", "--fullscreen", "--play", "ppsa12544"],
                                 environment: ["SDL_GAMECONTROLLER_IGNORE_DEVICES": "0x054c/0x0ce6, 0x28de/0x11ff"])
        XCTAssertTrue(launch.fromSteam)
        XCTAssertTrue(launch.fullscreen)
        XCTAssertEqual(launch.play, "PPSA12544")
        XCTAssertTrue(launch.skipPhysicalPad(vendor: 0x054C, product: 0x0CE6))
        XCTAssertFalse(launch.skipPhysicalPad(vendor: 0x28DE, product: 0x11FF))
        XCTAssertEqual(SteamLaunch(arguments: [], environment: ["SteamGameId": "123"]).gameID, "123")
        XCTAssertNil(SteamLaunch(arguments: ["--play", "--steam"], environment: [:]).play)
    }
}
