@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// The saves and trophies of an installed game through what the launcher does to its
/// installation, as on Windows and Linux (saves_survive_test.dart): Remove installation says
/// they are kept, keeps them in the store, and the next unlock takes them back; a copy rebuilt
/// before it starts, or unlocked again from Game Settings, has them in the new one. Every other
/// rebuild (Update from Git, a game's own engine, the relinker options, an update added) goes
/// through the same unlock; the installer's side of each is in SavesKeptTests.
@MainActor
final class SavesSurviveModelTests: XCTestCase {
    private let fm = FileManager.default
    private let built = "0.2.36-arm-nightly.20261110.1-a6fff1ba742d"
    private let current = "0.2.36-arm-f75c475400e3"

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

    /// What a player has in an installed game: saves, save memory, trophies, another profile's
    /// parked saves, whose are in place, and the game's download data.
    private let played = [
        "_sd/slot1/save.dat": "forty hours",
        "_sd_mem/u1/slot0.bin": "memory",
        "_trophy/268435456_0.txt": "12 1",
        "_profiles/second/_sd/save.dat": "another player",
        ".anyps5-profile": "first",
        "download0/settings.bin": "downloaded",
    ]

    private func assertPlayed(_ folder: URL, _ message: String = "is there", file: StaticString = #filePath, line: UInt = #line) {
        for (relative, expected) in played {
            XCTAssertEqual(text(folder.appendingPathComponent(relative)), expected, "\(relative) \(message)", file: file, line: line)
        }
    }

    /// An engine folder of the user's own, whole enough to unlock with: its relinker writes an
    /// executable.
    private func engine(version: String) throws -> Toolkit {
        let folder = fm.temporaryDirectory.appendingPathComponent("AnyPS5-tests-engine-\(UUID().uuidString)")
        try write("#!/bin/sh\nfor argument; do last=\"$argument\"; done\nmkdir -p \"$(dirname \"$last\")\"\necho relinked > \"$last\"\n", to: folder.appendingPathComponent("relinker"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent("relinker").path)
        try write("libSceAgc", to: folder.appendingPathComponent("libs/libSceAgc.prx"))
        try write("loader", to: folder.appendingPathComponent("vulkan/libvulkan.1.dylib"))
        try write("moltenvk", to: folder.appendingPathComponent("vulkan/libMoltenVK.dylib"))
        try write("{}", to: folder.appendingPathComponent("vulkan/MoltenVK_icd.json"))
        try fm.createDirectory(at: folder.appendingPathComponent("patches"), withIntermediateDirectories: true)
        try write(version + "\n", to: folder.appendingPathComponent("version.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return Toolkit(root: folder)
    }

    /// A launcher whose one game was unlocked by `built` and played, with an engine of the
    /// user's own at `version` in use. Gives the game and the folder its saves are in.
    private func launcher(engine version: String) throws -> (AppModel, Game, URL) {
        let model = try LauncherFixture.model(games: 1) { $0.engine = "custom" }
        let game = try XCTUnwrap(model.games.first)
        let root = try XCTUnwrap(model.root(of: game))
        let bundle = Installer.bundle(for: game, root: root)
        let folder = Installer.dataFolder(for: game, root: root).appendingPathComponent("game")
        try write("eboot", to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        try write(#"{"source":"\#(game.folder.path)","titleID":"\#(game.titleID)","toolkit":"\#(built)","date":"2026-11-10T00:00:00Z"}"#,
                  to: bundle.appendingPathComponent("Contents/Resources/anyps5-install.json"))
        try write("the game", to: folder.appendingPathComponent("app0/data.bin"))
        try fm.createSymbolicLink(atPath: bundle.appendingPathComponent("Contents/Resources/game").path, withDestinationPath: folder.path)
        for (relative, text) in played { try write(text, to: folder.appendingPathComponent(relative)) }
        model.preview(games: model.games, root: root)
        model.previewEngines(installed: [], catalogue: [], checked: nil, custom: try engine(version: version))
        model.selected = 0
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (model, game, folder)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<1500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    // MARK: Remove installation

    func testRemoveInstallationSaysTheSavesAreKeptKeepsThemAndUnlockBringsThemBack() async throws {
        let (model, game, folder) = try launcher(engine: built)
        let root = try XCTUnwrap(model.root(of: game))
        XCTAssertEqual(model.state(of: game), .installed(outdated: false))
        XCTAssertEqual(AppModel.uninstallAsks,
                       "Remove the installation? Your game files stay; the game shows as locked again. Your saves and trophies are kept and come back when you unlock the game again.")
        model.open(.confirmUninstall)
        let confirm = try XCTUnwrap(model.panelCategories().first?.rows.first { $0.id == "confirm" })
        guard case .action(let destructive, let run) = confirm.kind else { return XCTFail("an action") }
        XCTAssertTrue(destructive)
        run()
        XCTAssertEqual(model.state(of: game), .locked)
        XCTAssertEqual(model.toast?.text, T.text(.uninstallDone))
        XCTAssertFalse(fm.fileExists(atPath: folder.path), "the installation is gone")
        let kept = Installer.keptSaves(for: game, root: root)
        assertPlayed(kept, "is kept in the store")
        await model.removals[game.id]?.value

        model.unlock(game)
        try await until { model.state(of: game) == .installed(outdated: false) }
        assertPlayed(folder, "is back")
        XCTAssertFalse(fm.fileExists(atPath: kept.path), "nothing left to keep")
    }

    func testSavesThatCannotBeKeptRemoveInstallationSaysSoAndRemovesNothing() throws {
        let (model, game, folder) = try launcher(engine: built)
        let root = try XCTUnwrap(model.root(of: game))
        // Where the kept saves go is taken by a file.
        try write("in the way", to: root.appendingPathComponent(GameLibrary.storeName).appendingPathComponent("Saves"))
        model.uninstall(game)
        XCTAssertEqual(model.toast?.text.hasPrefix("The installation could not be removed: "), true)
        XCTAssertEqual(model.state(of: game), .installed(outdated: false))
        XCTAssertNil(model.removals[game.id])
        assertPlayed(folder, "stays in the game")
    }

    // MARK: Rebuilds

    func testACopyMadeByAnotherEngineIsRebuiltBeforeItStartsWithTheSavesInTheNewOne() async throws {
        let (model, game, folder) = try launcher(engine: current)
        XCTAssertEqual(model.state(of: game), .installed(outdated: true))
        XCTAssertTrue(model.needsRebuild(game))
        model.primaryAction(game)
        XCTAssertEqual(model.afterRebuild?.id, game.id, "the stale copy is rebuilt on its own")
        // The start that waits on the rebuild is not this test's.
        var rebuilt = false
        model.afterRebuild = (game.id, { rebuilt = true })
        try await until { rebuilt }
        XCTAssertEqual(model.installedRecords[game.id]?.toolkit, current)
        XCTAssertFalse(model.needsRebuild(game))
        assertPlayed(folder)
    }

    func testUnlockAgainFromGameSettingsHasTheSavesInTheNewOne() async throws {
        let (model, game, folder) = try launcher(engine: built)
        model.open(.gameSettings)
        let row = try XCTUnwrap(model.panelCategories().first?.rows.first { $0.id == "reinstall" })
        guard case .action(_, let run) = row.kind else { return XCTFail("an action") }
        let before = try XCTUnwrap(model.installedRecords[game.id]?.date)
        run()
        try await until { (model.installedRecords[game.id]?.date ?? before) > before }
        try await until { model.state(of: game) == .installed(outdated: false) }
        assertPlayed(folder)
    }
}
