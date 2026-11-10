import XCTest
@testable import AnyPS5Core

/// Uninstall in two halves, as on Windows and Linux: the game is set aside in the store at once,
/// and its files are removed after, off the main thread. A big game removed in one piece on the
/// main thread kept the launcher from answering until it was gone (AnyPS5-Desktop issue 55).
final class UninstallTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testSettingAsideTakesTheGameAwayAtOnceAndRemovingClearsTheStore() throws {
        let dump = root.appendingPathComponent("PPSA01234")
        try write("eboot", to: dump.appendingPathComponent("eboot.bin"))
        let game = Game(folder: dump, titleID: "PPSA01234", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let bundle = Installer.bundle(for: game, root: root)
        let data = Installer.dataFolder(for: game, root: root)
        let kept = Installer.keptRelink(for: game, root: root)
        try write("eboot", to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        for index in 0..<300 {
            try write("file \(index)", to: data.appendingPathComponent("game/app0/data\(index % 10)/file\(index).bin"))
        }
        try write("save", to: data.appendingPathComponent("game/_sd/save.dat"))
        try write("relinked", to: kept.appendingPathComponent("out/eboot"))
        // What an uninstall left when the launcher quit before it was done.
        let removing = Installer.removingFolder(root: root)
        try write("old", to: removing.appendingPathComponent("left-over/file.bin"))

        let going = Installer.setAside(game, root: root)
        for item in [bundle, data, kept] {
            XCTAssertFalse(fm.fileExists(atPath: item.path), "\(item.lastPathComponent) is gone from its place at once")
        }
        XCTAssertEqual(going.count, 4, "the bundle, the data folder, the kept output and the leftover")
        for item in going {
            XCTAssertEqual(item.deletingLastPathComponent().resolvingSymlinksInPath().path, removing.resolvingSymlinksInPath().path, "\(item.path) waits in the Removing folder")
            XCTAssertTrue(fm.fileExists(atPath: item.path), "nothing is removed by setting aside")
        }
        XCTAssertEqual(Set(Installer.setAside(game, root: root).map(\.lastPathComponent)), Set(going.map(\.lastPathComponent)), "a second time finds nothing more of the game")

        Installer.remove(going)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: removing.path), [])
        XCTAssertTrue(fm.fileExists(atPath: dump.appendingPathComponent("eboot.bin").path), "the dump stays")
    }

    func testNothingInstalledSetsNothingAside() {
        let game = Game(folder: root.appendingPathComponent("PPSA09999"), titleID: "PPSA09999", name: "None", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        XCTAssertEqual(Installer.setAside(game, root: root), [])
    }
}
