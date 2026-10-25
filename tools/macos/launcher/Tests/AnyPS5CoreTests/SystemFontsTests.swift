import Foundation
import XCTest
@testable import AnyPS5Core

final class SystemFontsTests: XCTestCase {
    // The expectations follow SystemFont.cpp's FamilyOf and FallbackFamilies by hand.
    func testFontSetsOpenTheScriptsTheEngineOpens() {
        XCTAssertEqual(SystemFontSet.scripts(0x18070044), [.latin])
        XCTAssertEqual(SystemFontSet.scripts(0x18170044), [.latinItalic])
        XCTAssertEqual(SystemFontSet.scripts(0x18370044), [.typewriter])
        XCTAssertEqual(SystemFontSet.scripts(0x18370447), [.typewriter, .japanese])
        XCTAssertEqual(SystemFontSet.scripts(0x18080444), [.japanese])
        XCTAssertEqual(SystemFontSet.scripts(0x18080454), [.vietnamese, .japanese])
        XCTAssertEqual(SystemFontSet.scripts(0x180C8044), [.chinese])
        XCTAssertEqual(SystemFontSet.scripts(0x1807A044), [.latin, .chinese, .korean])
        XCTAssertEqual(SystemFontSet.scripts(0x180700C4), [.latin, .arabic])
        XCTAssertEqual(SystemFontSet.scripts(0x18071054), [.thai, .vietnamese])
        XCTAssertEqual(SystemFontSet.scripts(0x1A0805C3), [.japanese, .arabic])
    }

    func testATypeTheConsoleDoesNotHaveOpensNothing() {
        XCTAssertEqual(SystemFontSet.scripts(0x12345678), [])
        XCTAssertEqual(SystemFontSet.types.count, 120)
    }

    func testTheLogSaysWhichSetsTheGameOpened() {
        let log = """
        [anyps5-launcher] start 2026-10-25T07:00:00Z PPSA01234
        [Open.cpp:418 sceFontOpenFontSet] fontSetType=0x18070044 file=/fonts/NotoSans-Regular.ttf
        [Open.cpp:446 sceFontOpenFontSet] fontSetType=0x18070044 fallback=/fonts/NotoSansThai-Regular.ttf
        [Open.cpp:418 sceFontOpenFontSet] fontSetType=0x18080447 file=(none)
        [libSceFont] no file for system font set 0x18080447 in /fonts.
        [Open.cpp:418 sceFontOpenFontSet] fontSetType=0x1807A0
        """
        XCTAssertEqual(SystemFontSet.opened(inLog: log), [0x18070044, 0x18080447])
        XCTAssertEqual(SystemFontSet.scripts(inLog: log), [.latin, .japanese])
        XCTAssertTrue(SystemFontSet.scripts(inLog: log).contains { $0.isCJK })
        XCTAssertFalse(SystemFontSet.scripts(inLog: "[Open.cpp:418 sceFontOpenFontSet] fontSetType=0x180700C4 file=(none)").contains { $0.isCJK })
    }

    func testTheNotoNamesAreTheOnesTheEngineLooksFor() {
        XCTAssertEqual(FontScript.latin.notoFiles[1], "NotoSans-Regular.ttf")
        XCTAssertEqual(FontScript.latinItalic.notoFiles[3], "NotoSans-BoldItalic.ttf")
        XCTAssertEqual(FontScript.korean.notoFiles, ["NotoSansCJK-Light.ttc", "NotoSansCJK-Regular.ttc", "NotoSansCJK-Medium.ttc", "NotoSansCJK-Bold.ttc"])
        XCTAssertEqual(FontScript.japanese.consoleFiles[1], "SSTJpPro-Regular.otf")
    }

    private func folder(_ name: String, files: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fonts-\(UUID().uuidString)/\(name)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files { try Data("\(name)/\(file)".utf8).write(to: folder.appendingPathComponent(file)) }
        addTeardownBlock { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        return folder
    }

    func testTheUsersFolderComesFirstAndTheLaunchersFillIn() throws {
        let builtIn = try folder("builtin", files: ["NotoSans-Regular.ttf", "NotoSansThai-Regular.ttf", "NotoSansArabic-Regular.ttf", "OFL.txt"])
        let downloaded = try folder("cjk", files: ["NotoSansCJK-Regular.ttc", "LICENSE-NotoSansCJK.txt"])
        let user = try folder("user", files: ["SST-Roman.otf", "NotoSansArabic-Regular.ttf", "readme.md"])
        let fonts = SystemFonts(user: user, downloaded: downloaded, builtIn: builtIn)
        XCTAssertEqual(fonts.pick(.latin), .init(file: "SST-Roman.otf", source: .user))
        XCTAssertTrue(fonts.pick(.latin)!.isConsole)
        XCTAssertEqual(fonts.pick(.arabic), .init(file: "NotoSansArabic-Regular.ttf", source: .user))
        XCTAssertEqual(fonts.pick(.thai), .init(file: "NotoSansThai-Regular.ttf", source: .builtIn))
        XCTAssertEqual(fonts.pick(.chinese), .init(file: "NotoSansCJK-Regular.ttc", source: .downloaded))
        XCTAssertNil(fonts.pick(.typewriter))
        XCTAssertEqual(Set(fonts.files().keys), ["NotoSans-Regular.ttf", "NotoSansThai-Regular.ttf", "NotoSansArabic-Regular.ttf", "NotoSansCJK-Regular.ttc", "SST-Roman.otf"])
        XCTAssertNil(SystemFonts(user: nil, downloaded: downloaded.appendingPathComponent("missing"), builtIn: builtIn).pick(.japanese))
    }

    func testTheGamesFolderLinksEachFontToTheFileThatWins() throws {
        let builtIn = try folder("builtin", files: ["NotoSans-Regular.ttf", "NotoSansThai-Regular.ttf"])
        let user = try folder("user", files: ["NotoSansThai-Regular.ttf"])
        let games = builtIn.deletingLastPathComponent().appendingPathComponent("games")
        var fonts = SystemFonts(user: user, downloaded: nil, builtIn: builtIn)
        XCTAssertEqual(try fonts.assemble(in: games), games)
        XCTAssertEqual(try String(contentsOf: games.appendingPathComponent("NotoSansThai-Regular.ttf"), encoding: .utf8), "user/NotoSansThai-Regular.ttf")
        XCTAssertEqual(try String(contentsOf: games.appendingPathComponent("NotoSans-Regular.ttf"), encoding: .utf8), "builtin/NotoSans-Regular.ttf")

        // A font that comes in later is added; one whose folder went now points at the next.
        let downloaded = try folder("cjk", files: ["NotoSansCJK-Bold.ttc"])
        fonts = SystemFonts(user: nil, downloaded: downloaded, builtIn: builtIn)
        try fonts.assemble(in: games)
        XCTAssertEqual(try String(contentsOf: games.appendingPathComponent("NotoSansThai-Regular.ttf"), encoding: .utf8), "builtin/NotoSansThai-Regular.ttf")
        XCTAssertEqual(try String(contentsOf: games.appendingPathComponent("NotoSansCJK-Bold.ttc"), encoding: .utf8), "cjk/NotoSansCJK-Bold.ttc")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: games.path).count, 3)

        // No fonts anywhere: no folder, so the engine looks beside the game as before.
        XCTAssertNil(try SystemFonts(user: nil, downloaded: nil, builtIn: nil).assemble(in: games))
        XCTAssertFalse(FileManager.default.fileExists(atPath: games.path))
    }

    func testTheAppsFontsAreFoundInsideItOrWhereTheEnvironmentSays() throws {
        let builtIn = try folder("builtin", files: ["NotoSans-Regular.ttf"])
        XCTAssertEqual(SystemFonts.locateBuiltIn(environment: ["ANYPS5_LAUNCHER_FONTS": builtIn.path])?.path, builtIn.path)
        let empty = try folder("empty", files: [])
        XCTAssertNil(SystemFonts.locateBuiltIn(environment: ["ANYPS5_LAUNCHER_FONTS": empty.path], bundle: Bundle(for: SystemFontsTests.self)))
    }

    /// The fonts the app carries are the files the engine looks for, each under the licence.
    func testTheBundledFontsAreTheEnginesSubstitutes() throws {
        let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Fonts").standardizedFileURL
        let bundled = Set(SystemFonts.fonts(in: fonts))
        let wanted = Set([FontScript.latin, .latinItalic, .typewriter, .thai, .arabic].flatMap(\.notoFiles))
        XCTAssertEqual(bundled, wanted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fonts.appendingPathComponent("OFL.txt").path))
        let sources = try String(contentsOf: fonts.appendingPathComponent("SOURCES.txt"), encoding: .utf8)
        for name in bundled {
            let digest = try FontDownloads.sha256(of: fonts.appendingPathComponent(name))
            XCTAssertTrue(sources.contains("\(digest)  \(name)"), "\(name) is not in SOURCES.txt as it is")
        }
    }
}
