import XCTest
@testable import AnyPS5Core

final class PlaceTests: XCTestCase {
    var store: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        store = fm.temporaryDirectory.appendingPathComponent("place-\(UUID().uuidString)/.AnyPS5")
        try fm.createDirectory(at: store.appendingPathComponent("Games"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: store.deletingLastPathComponent()) }

    /// A bundle as the installer builds it: code in MacOS, the game in Resources/game.
    func partial(_ name: String) throws -> URL {
        let bundle = store.appendingPathComponent("Games/\(name).partial")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        let game = bundle.appendingPathComponent("Contents/Resources/game")
        try fm.createDirectory(at: macOS.appendingPathComponent("libs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: game.appendingPathComponent("app0"), withIntermediateDirectories: true)
        try Data("lib".utf8).write(to: macOS.appendingPathComponent("libs/libc.prx"))
        try Data("eboot".utf8).write(to: game.appendingPathComponent("app0/eboot.bin"))
        try fm.createSymbolicLink(atPath: game.appendingPathComponent("libs").path, withDestinationPath: "../../MacOS/libs")
        try fm.createSymbolicLink(atPath: game.appendingPathComponent("app0/libs").path, withDestinationPath: "../../../MacOS/libs")
        try fm.createSymbolicLink(atPath: macOS.appendingPathComponent("app0").path, withDestinationPath: "../Resources/game/app0")
        return bundle
    }

    func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

    func testTheGameLivesOutsideTheBundle() throws {
        let bundle = store.appendingPathComponent("Games/X-1.app")
        let data = store.appendingPathComponent("Data/X-1")
        try Installer.place(partial: try partial("X-1"), bundle: bundle, data: data)
        let link = try fm.destinationOfSymbolicLink(atPath: bundle.appendingPathComponent("Contents/Resources/game").path)
        XCTAssertEqual(link, "../../../../Data/X-1/game")
        XCTAssertEqual(text(bundle.appendingPathComponent("Contents/MacOS/app0/eboot.bin")), "eboot", "MacOS/app0 reaches the game through the link")
        XCTAssertEqual(text(data.appendingPathComponent("game/libs/libc.prx")), "lib", "game/libs reaches the bundle's libraries")
        XCTAssertEqual(text(data.appendingPathComponent("game/app0/libs/libc.prx")), "lib", "app0/libs reaches the bundle's libraries")
        XCTAssertFalse(fm.fileExists(atPath: store.appendingPathComponent("Games/X-1.partial").path))
    }

    func testAnOldBundleKeepsItsSavesAndMovesOut() throws {
        let bundle = store.appendingPathComponent("Games/X-1.app")
        let old = try partial("old")
        try Data("save".utf8).write(to: old.appendingPathComponent("Contents/Resources/game/_sd").appendingPathExtension("bin"))
        try fm.moveItem(at: old, to: bundle)
        let data = store.appendingPathComponent("Data/X-1")
        try Installer.place(partial: try partial("X-1"), bundle: bundle, data: data)
        XCTAssertEqual(text(data.appendingPathComponent("game/_sd.bin")), "save")
        XCTAssertEqual(text(bundle.appendingPathComponent("Contents/Resources/game/_sd.bin")), "save")
    }

    func testUnlockingAgainKeepsSavesInTheDataFolder() throws {
        let bundle = store.appendingPathComponent("Games/X-1.app")
        let data = store.appendingPathComponent("Data/X-1")
        try Installer.place(partial: try partial("X-1"), bundle: bundle, data: data)
        try Data("save".utf8).write(to: data.appendingPathComponent("game/_sd.bin"))
        try Data("old game".utf8).write(to: data.appendingPathComponent("game/app0/eboot.bin"))
        try Installer.place(partial: try partial("X-1"), bundle: bundle, data: data)
        XCTAssertEqual(text(data.appendingPathComponent("game/_sd.bin")), "save", "saves stay")
        XCTAssertEqual(text(data.appendingPathComponent("game/app0/eboot.bin")), "eboot", "the game itself is the new one")
        XCTAssertEqual(text(data.appendingPathComponent("game/libs/libc.prx")), "lib")
    }
}
