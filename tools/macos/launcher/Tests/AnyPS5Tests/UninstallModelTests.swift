@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// Uninstall answers at once, as on Windows and Linux: the game is uninstalled when the press is
/// taken, its files go after off the main thread, and pressing again meanwhile starts nothing.
/// A big game removed in one piece on the main thread kept the launcher from answering until it
/// was gone (AnyPS5-Desktop issue 55).
@MainActor
final class UninstallModelTests: XCTestCase {
    private let fm = FileManager.default

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testUninstallIsDoneAtOnceTheFilesGoAfterAndASecondOneStartsNothing() async throws {
        let model = try LauncherFixture.model(games: 1)
        let game = try XCTUnwrap(model.games.first)
        let root = try XCTUnwrap(model.root(of: game))
        let bundle = Installer.bundle(for: game, root: root)
        let data = Installer.dataFolder(for: game, root: root)
        try write("eboot", to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        try write(#"{"source":"\#(game.folder.path)","titleID":"\#(game.titleID)","toolkit":"toolkit-1","date":"2026-11-10T00:00:00Z"}"#,
                  to: bundle.appendingPathComponent("Contents/Resources/anyps5-install.json"))
        for index in 0..<300 {
            try write("file \(index)", to: data.appendingPathComponent("game/app0/data\(index % 10)/file\(index).bin"))
        }
        model.preview(games: model.games, root: root)
        guard case .installed = model.state(of: game) else { return XCTFail("the game reads installed first") }

        model.uninstall(game)
        XCTAssertEqual(model.state(of: game), .locked)
        XCTAssertFalse(fm.fileExists(atPath: bundle.path), "uninstalled when the press is taken")
        XCTAssertFalse(fm.fileExists(atPath: data.path))
        let removal = try XCTUnwrap(model.removals[game.id], "the files go after, in a task of their own")
        model.uninstall(game)
        XCTAssertEqual(model.removals[game.id], removal, "a second Uninstall starts nothing")

        await removal.value
        for _ in 0..<200 where model.removals[game.id] != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(model.removals[game.id])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: Installer.removingFolder(root: root).path), [])
        XCTAssertTrue(fm.fileExists(atPath: game.folder.appendingPathComponent("eboot.bin").path), "the dump stays")
        XCTAssertEqual(model.state(of: game), .locked)
    }
}
