import XCTest
@testable import AnyPS5Core

final class ThemeLibraryTests: XCTestCase {
    var folder: URL!
    var library: ThemeLibrary!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString.prefix(8))")
        library = ThemeLibrary(folder: folder.appendingPathComponent("Themes"))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func design(_ name: String = "Midnight") -> ThemeDesign {
        ThemeDesign(name: name, author: "Utku", style: 1, deep: "#05070F", middle: "#1B3A7A", bright: "#9EC5FF", accent: "#4F94FF")
    }

    func testColorsAreReadFromHex() {
        XCTAssertEqual(ThemeDesign.rgb("#FF8000"), SIMD3<Float>(1, 128.0 / 255, 0))
        XCTAssertEqual(ThemeDesign.rgb("4f94ff"), SIMD3<Float>(79.0 / 255, 148.0 / 255, 1))
        XCTAssertNil(ThemeDesign.rgb("#12"))
        XCTAssertEqual(ThemeDesign.hex(SIMD3<Float>(1, 0.5, 0)), "#FF8000")
    }

    /// A theme with its own background and music goes into a file and comes back from it.
    func testAThemeGoesIntoAFileAndBack() throws {
        let picture = folder.appendingPathComponent("my picture.jpg")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("jpeg".utf8).write(to: picture)
        var saved = try library.save(design(), background: picture, music: nil)
        XCTAssertEqual(saved.background, "background.jpg")
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(library.file(saved.background, of: saved))), Data("jpeg".utf8))
        let file = folder.appendingPathComponent("Midnight.anyps5theme")
        try library.export(saved, to: file)

        let other = ThemeLibrary(folder: folder.appendingPathComponent("Other"))
        let installed = try other.install(file)
        XCTAssertEqual(installed.name, "Midnight")
        XCTAssertEqual(installed.id, saved.id)
        XCTAssertEqual(other.all.map(\.id), [saved.id])
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(other.file(installed.background, of: installed))), Data("jpeg".utf8))

        saved.name = "Midnight 2"
        _ = try library.save(saved, background: nil, music: nil)
        XCTAssertEqual(library.all.map(\.name), ["Midnight 2"], "saved again in place, the picture kept")
        XCTAssertNotNil(library.file(library.all[0].background, of: library.all[0]))
    }

    func testARemovedThemeIsGone() throws {
        let saved = try library.save(design(), background: nil, music: nil)
        try library.remove(saved.id)
        XCTAssertTrue(library.all.isEmpty)
    }

    /// A theme file only brings what a theme is: names that would reach outside its folder and
    /// files the theme does not name are left behind.
    func testAThemeFileCannotReachOutsideItsFolder() throws {
        let stage = folder.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        var bad = design()
        bad.id = "../../escape"
        bad.background = "../secret.jpg"
        try JSONEncoder().encode(bad).write(to: stage.appendingPathComponent("theme.json"))
        try Data("x".utf8).write(to: stage.appendingPathComponent("extra.sh"))
        let file = folder.appendingPathComponent("bad.anyps5theme")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", stage.path, file.path]
        try zip.run()
        zip.waitUntilExit()
        let installed = try library.install(file)
        XCTAssertNil(installed.background)
        XCTAssertFalse(installed.id.contains("/"))
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Themes/\(installed.id)").path)
        XCTAssertEqual(kept, ["theme.json"])
    }

    func testSomethingElseIsNotATheme() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("nothing.anyps5theme")
        try Data("not a zip".utf8).write(to: file)
        XCTAssertThrowsError(try library.install(file))
    }

    func testTheHubIndexIsRead() throws {
        let json = """
        {"themes":[{"id":"neon","name":"Neon","author":"Ada","version":2,"style":0,"deep":"#000000","middle":"#330066","bright":"#FF00FF","accent":"#FF4FD8",
        "package":"themes/neon.anyps5theme","preview":"themes/neon.jpg"}]}
        """
        let index = try ThemeHub.index(from: Data(json.utf8), base: URL(string: "https://example.com/hub/")!)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index[0].name, "Neon")
        XCTAssertEqual(index[0].package.absoluteString, "https://example.com/hub/themes/neon.anyps5theme")
        XCTAssertEqual(index[0].preview?.absoluteString, "https://example.com/hub/themes/neon.jpg")
        XCTAssertEqual(index[0].design.accent, "#FF4FD8")
    }
}

final class ThemeKnobsTests: XCTestCase {
    /// The Studio's few knobs make a theme's colors, and the colors give the knobs back.
    func testKnobsMakeColorsAndComeBackFromThem() {
        let knobs = ThemeKnobs(hue: 210, highlight: 20, depth: 6, accentHue: 330)
        var design = ThemeDesign(name: "Test", author: "", style: 0, deep: "", middle: "", bright: "", accent: "")
        knobs.apply(to: &design)
        XCTAssertNotNil(ThemeDesign.rgb(design.middle))
        let back = ThemeKnobs(design)
        XCTAssertEqual(back.hue, 210, accuracy: 5)
        XCTAssertEqual(back.highlight, 20, accuracy: 5)
        XCTAssertEqual(back.depth, 6)
        XCTAssertEqual(back.accentHue, 330, accuracy: 5)
    }

    func testABuiltInLookGivesKnobsInRange() {
        let cosmic = ThemeDesign(name: "", author: "", style: 0, deep: "#03061A", middle: "#0A266B", bright: "#6BA3FF", accent: "#4F94FF")
        let knobs = ThemeKnobs(cosmic)
        XCTAssertTrue((0..<360).contains(knobs.hue))
        XCTAssertTrue((-90...90).contains(knobs.highlight))
        XCTAssertTrue((1...10).contains(knobs.depth))
    }
}

/// The Hub in this repository: its index reads, and every theme in it installs.
final class HubFolderTests: XCTestCase {
    func testEveryThemeOnTheHubInstalls() throws {
        let hub = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../../hub").standardizedFileURL
        // The launcher alone (its own branch) has no Hub folder beside it.
        try XCTSkipUnless(FileManager.default.fileExists(atPath: hub.appendingPathComponent("themes.json").path), "no hub/ in this checkout")
        let themes = try ThemeHub.index(from: Data(contentsOf: hub.appendingPathComponent("themes.json")), base: hub.appendingPathComponent("/"))
        XCTAssertFalse(themes.isEmpty)
        let library = ThemeLibrary(folder: FileManager.default.temporaryDirectory.appendingPathComponent("hub-\(UUID().uuidString.prefix(8))"))
        defer { try? FileManager.default.removeItem(at: library.folder) }
        for theme in themes {
            let installed = try library.install(theme.package)
            XCTAssertEqual(installed.id, theme.id)
            XCTAssertEqual(installed.accent, theme.design.accent)
        }
        XCTAssertEqual(library.all.count, themes.count)
    }
}
