import XCTest
@testable import AnyPS5Core

final class GameAddonsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-addons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    @discardableResult
    private func write(_ relative: String, _ text: String) throws -> URL {
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    private func makeGame(_ relative: String, title: String, version: String = "01.000.000") throws {
        try write(relative + "/sce_sys/param.json", #"{"titleId":"\#(title)","contentVersion":"\#(version)","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"Game \#(title)"}}}"#)
        try write(relative + "/eboot.bin", "\u{7F}ELF")
    }

    private func makeAddon(_ relative: String, name: String? = nil, contentID: String? = nil) throws {
        var fields: [String] = []
        if let contentID { fields.append(#""contentId":"\#(contentID)""#) }
        if let name { fields.append(#""localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"\#(name)"}}"#) }
        try write(relative + "/sce_sys/param.json", "{" + fields.joined(separator: ",") + "}")
        try write(relative + "/data.pak", "data")
    }

    // MARK: Finding them

    func testTheUpdateAndAddonsBesideAGameAreFoundAndAreNotGamesThemselves() throws {
        try makeGame("PPSA01234", title: "PPSA01234")
        // The update is a whole patch dump: it would scan as a game of its own.
        try makeGame("PPSA01234-UPDATE", title: "PPSA01234", version: "01.004.000")
        try makeAddon("PPSA01234-DLC/EXPANSION0000001", name: "The Island")
        try makeAddon("PPSA01234-DLC/UP0000-PPSA01234_00-COSTUMEPACK00002")
        try makeAddon("UP0000-PPSA01234_00-SOUNDTRACK000003", name: "Soundtrack")
        try write("PPSA01234-DLC/not a label/sce_sys/param.json", "{}")
        try makeGame("PPSA05678", title: "PPSA05678")

        let survey = GameLibrary.survey(root)
        XCTAssertEqual(survey.games.map(\.titleID), ["PPSA01234", "PPSA05678"])
        let game = try XCTUnwrap(survey.games.first)
        XCTAssertEqual(game.update?.version, "01.004.000")
        XCTAssertEqual(game.update?.shortVersion, "01.004")
        XCTAssertEqual(game.update?.folder.lastPathComponent, "PPSA01234-UPDATE")
        XCTAssertEqual(game.addons.map(\.label), ["EXPANSION0000001", "COSTUMEPACK00002", "SOUNDTRACK000003"])
        XCTAssertEqual(game.addons.map(\.name), ["The Island", "COSTUMEPACK00002", "Soundtrack"])
        XCTAssertEqual(survey.incomplete, [], "the add-on folders are not half-copied games")
        let other = survey.games[1]
        XCTAssertNil(other.update)
        XCTAssertEqual(other.addons, [], "another game's add-ons are not this one's")
    }

    func testTheGamesFolderNameOrItsTitleIDNameTheUpdateAnyCaseAndPatchToo() throws {
        try makeGame("Astro Bot", title: "PPSA01234")
        try makeGame("astro bot-patch", title: "PPSA01234", version: "01.010.000")
        try makeAddon("ppsa01234-dlc/EXPANSION0000001")
        let game = try XCTUnwrap(GameLibrary.scan(root).first)
        XCTAssertEqual(GameLibrary.scan(root).count, 1)
        XCTAssertEqual(game.update?.version, "01.010.000")
        XCTAssertEqual(game.addons.map(\.label), ["EXPANSION0000001"])
    }

    func testAnUpdateFolderWithoutItsParamJsonIsNotTakenForOne() throws {
        try makeGame("PPSA01234", title: "PPSA01234")
        try write("PPSA01234-UPDATE/eboot.bin", "still copying")
        let game = try XCTUnwrap(GameLibrary.inspect(root.appendingPathComponent("PPSA01234")))
        XCTAssertNil(game.update)
        XCTAssertEqual(game.addons, [])
    }

    func testAContentIDFolderOfAnotherGameOrWithAnEbootIsNotAnAddon() throws {
        try makeGame("PPSA01234", title: "PPSA01234")
        try makeAddon("UP0000-PPSA09999_00-EXPANSION0000001")
        try makeGame("UP0000-PPSA01234_00-FULLGAME00000000", title: "PPSA01234")
        let game = try XCTUnwrap(GameLibrary.inspect(root.appendingPathComponent("PPSA01234")))
        XCTAssertEqual(game.addons, [])
    }

    func testLabelsComeFromTheContentIDOrAFolderNamedByTheLabel() {
        XCTAssertEqual(GameAddons.labelOfContentID("UP0000-PPSA01234_00-EXPANSION0000001"), "EXPANSION0000001")
        XCTAssertNil(GameAddons.labelOfContentID("UP0000-PPSA01234-00-EXPANSION0000001"))
        XCTAssertNil(GameAddons.labelOfContentID("UP0000-PPSA01234_00-EXPANSION00000!1"))
        XCTAssertEqual(GameAddons.label(ofFolderNamed: "SEASONPASS"), "SEASONPASS")
        XCTAssertNil(GameAddons.label(ofFolderNamed: "Season Pass"))
        XCTAssertNil(GameAddons.label(ofFolderNamed: "SEASONPASS0000000"), "seventeen characters is too long for a label")
        XCTAssertEqual(GameAddons.shortVersion("01.004.000"), "01.004")
        XCTAssertEqual(GameAddons.shortVersion("01.04"), "01.04")
    }

    // MARK: Passing them on

    func testTheEngineGetsTheUpdateAndTheAddonFolders() throws {
        try makeGame("PPSA01234", title: "PPSA01234")
        try makeGame("PPSA01234-UPDATE", title: "PPSA01234", version: "01.004.000")
        try makeAddon("PPSA01234-DLC/EXPANSION0000001")
        try makeAddon("PPSA01234-DLC/COSTUMEPACK00002")
        let game = try XCTUnwrap(GameLibrary.scan(root).first)
        let environment = GameAddons.environment(for: game)
        XCTAssertEqual(environment["ANYPS5_UPDATE_DIR"].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       root.appendingPathComponent("PPSA01234-UPDATE").resolvingSymlinksInPath().path)
        XCTAssertEqual(environment["ANYPS5_ADDCONT_DIRS"]?.split(separator: ":").map { URL(fileURLWithPath: String($0)).lastPathComponent }, ["COSTUMEPACK00002", "EXPANSION0000001"])
        let plain = Game(folder: root, titleID: "PPSA00000", name: "Plain", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        XCTAssertEqual(GameAddons.environment(for: plain), [:], "a game without them starts as before")
    }

    func testTheUpdatesExecutableAndModulesAreTheOnesRelinked() throws {
        try makeGame("PPSA01234", title: "PPSA01234")
        try write("PPSA01234/sce_module/libshared.prx", "base shared")
        try write("PPSA01234/sce_module/libbase.prx", "base only")
        try makeGame("PPSA01234-UPDATE", title: "PPSA01234", version: "01.004.000")
        try write("PPSA01234-UPDATE/eboot.bin", "\u{7F}ELF updated")
        try write("PPSA01234-UPDATE/sce_module/libshared.prx", "updated shared")
        try write("PPSA01234-UPDATE/sce_module/libnew.prx", "update only")
        let game = try XCTUnwrap(GameLibrary.scan(root).first)
        XCTAssertEqual(Installer.modules(of: game).map(\.relativePath), ["sce_module/libbase.prx", "sce_module/libnew.prx", "sce_module/libshared.prx"])
        func source(_ relative: String) -> String { Installer.source(URL(fileURLWithPath: relative), of: game).deletingLastPathComponent().pathComponents.suffix(2).joined(separator: "/") }
        XCTAssertEqual(Installer.source(URL(fileURLWithPath: "eboot.bin"), of: game).deletingLastPathComponent().lastPathComponent, "PPSA01234-UPDATE")
        XCTAssertEqual(source("sce_module/libshared.prx"), "PPSA01234-UPDATE/sce_module")
        XCTAssertEqual(source("sce_module/libbase.prx"), "PPSA01234/sce_module")
        XCTAssertEqual(source("sce_module/libnew.prx"), "PPSA01234-UPDATE/sce_module")
    }

    func testAnUpdateChangesTheRelinkKeySoTheKeptRelinkIsNotReused() throws {
        try makeGame("PPSA01234", title: "PPSA01234")
        let toolkit = Toolkit(root: try write(".toolkit/version.txt", "test").deletingLastPathComponent())
        let before = try XCTUnwrap(GameLibrary.scan(root).first)
        let base = Installer.relinkKey(game: before, toolkit: toolkit, modules: Installer.modules(of: before))
        try makeGame("PPSA01234-UPDATE", title: "PPSA01234", version: "01.004.000")
        let after = try XCTUnwrap(GameLibrary.scan(root).first)
        XCTAssertNotEqual(Installer.relinkKey(game: after, toolkit: toolkit, modules: Installer.modules(of: after)), base)
    }

    func testOldInstallRecordsHaveNoUpdate() throws {
        let old = #"{"source":"/games/A","titleID":"PPSA01234","toolkit":"1","date":"2026-10-01T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNil(try decoder.decode(InstallRecord.self, from: Data(old.utf8)).update)
    }
}
