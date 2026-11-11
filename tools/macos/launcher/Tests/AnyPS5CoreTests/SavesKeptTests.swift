import XCTest
@testable import AnyPS5Core

/// A game's saves and trophies live in the installation the launcher builds (its data folder),
/// so whatever removes or replaces an installation has to leave them, as on Windows and Linux
/// (saves_kept_test.dart): Remove installation keeps them in the store as Delete game does, every
/// rebuild carries them into the new one, and one that is interrupted or fails leaves them where
/// the next unlock finds them.
final class SavesKeptTests: XCTestCase {
    var scratch: URL!
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("saves-\(UUID().uuidString)")
        root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: scratch) }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

    /// A dump with an ELF executable in the games folder.
    private func makeGame(update: GameUpdate? = nil) throws -> Game {
        let dump = root.appendingPathComponent("astro")
        try write("\u{7F}ELF executable", to: dump.appendingPathComponent("eboot.bin"))
        try write("level data", to: dump.appendingPathComponent("data/level1.bin"))
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        var game = Game(folder: dump, titleID: "PPSA01234", name: "Astro", version: "01.000.000", icon: nil, background: nil, music: nil, executable: .elf)
        game.update = update
        return game
    }

    /// An engine whose relinker writes an executable, or fails as the real one does with `fails`.
    private func makeToolkit(_ name: String = "toolkit", version: String = "0.2.15-arm-0123456789ab", fails: Bool = false) throws -> Toolkit {
        let folder = try FakeToolkit.make(in: scratch, name: name, version: version)
        let script = """
        #!/bin/sh
        for argument; do last="$argument"; done
        if [ "\(fails ? "fail" : "ok")" = fail ]; then
          echo "FAIL: Unsupported relocation type 0x25 (offset 0x1234)" >&2
          echo "Input: $PWD/eboot.bin" >&2
          exit 2
        fi
        mkdir -p "$(dirname "$last")"
        echo "relinked $*" > "$last"
        """
        try Data(script.utf8).write(to: folder.appendingPathComponent("relinker"))
        return Toolkit(root: folder)
    }

    private func install(_ game: Game, _ toolkit: Toolkit, custom: [String] = []) throws -> URL {
        let installer = Installer(game: game, toolkit: toolkit, progress: { _, _ in }, log: { _ in })
        installer.customRelinkerOptions = custom
        return try installer.run(root: root)
    }

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

    private func play(_ folder: URL) throws {
        for (relative, text) in played { try write(text, to: folder.appendingPathComponent(relative)) }
    }

    private func assertPlayed(_ folder: URL, _ message: String = "is there", file: StaticString = #filePath, line: UInt = #line) {
        for (relative, expected) in played {
            XCTAssertEqual(text(folder.appendingPathComponent(relative)), expected, "\(relative) \(message)", file: file, line: line)
        }
    }

    private func gameFolder(_ game: Game) -> URL { Installer.dataFolder(for: game, root: root).appendingPathComponent("game") }

    private func record(_ game: Game) -> InstallRecord? { Installer.record(of: Installer.bundle(for: game, root: root)) }

    // MARK: Remove installation

    func testRemoveInstallationKeepsTheSavesInTheStoreAndTheNextUnlockTakesThemBack() throws {
        let game = try makeGame()
        let toolkit = try makeToolkit()
        let bundle = try install(game, toolkit)
        try play(gameFolder(game))
        try fm.createDirectory(at: gameFolder(game).appendingPathComponent("download1"), withIntermediateDirectories: true)

        Installer.remove(try Installer.uninstall(game, root: root))
        XCTAssertFalse(fm.fileExists(atPath: bundle.path), "the installation is gone")
        XCTAssertFalse(fm.fileExists(atPath: Installer.dataFolder(for: game, root: root).path))
        let kept = Installer.keptSaves(for: game, root: root)
        XCTAssertEqual(kept.path, root.appendingPathComponent(GameLibrary.storeName).appendingPathComponent("Saves").appendingPathComponent(bundle.deletingPathExtension().lastPathComponent).path)
        assertPlayed(kept, "is kept")
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: kept.path)), ["_sd", "_sd_mem", "_trophy", "_profiles", ".anyps5-profile", "download0"],
                       "only what is the player's own, and no empty folder")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: Installer.removingFolder(root: root).path), [])
        XCTAssertEqual(text(game.folder.appendingPathComponent("data/level1.bin")), "level data", "the dump stays")

        _ = try install(game, toolkit)
        assertPlayed(gameFolder(game), "is back")
        XCTAssertFalse(fm.fileExists(atPath: kept.path), "nothing left to keep")
    }

    func testSavesThatCannotBeKeptRemoveNothingAndTheGameStaysInstalled() throws {
        let game = try makeGame()
        _ = try install(game, try makeToolkit())
        try play(gameFolder(game))
        // Where the kept saves go is taken by a file.
        try write("in the way", to: root.appendingPathComponent(GameLibrary.storeName).appendingPathComponent("Saves"))
        XCTAssertThrowsError(try Installer.uninstall(game, root: root))
        assertPlayed(gameFolder(game), "stays in the game")
        XCTAssertNotNil(record(game), "still installed")
        XCTAssertFalse(fm.fileExists(atPath: Installer.removingFolder(root: root).path), "nothing was set aside")
    }

    func testAPartThatCannotBeMovedAfterOthersWerePutsThoseBack() throws {
        let game = try makeGame()
        _ = try install(game, try makeToolkit())
        try play(gameFolder(game))
        // The trophies cannot be read, so they cannot be told from an empty folder.
        let trophies = gameFolder(game).appendingPathComponent("_trophy")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trophies.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trophies.path) }
        XCTAssertThrowsError(try Installer.uninstall(game, root: root))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trophies.path)
        assertPlayed(gameFolder(game), "is back in the game")
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: Installer.keptSaves(for: game, root: root).path)) ?? [], [])
    }

    // MARK: A rebuild keeps the saves

    func testARebuildAfterAnEngineChangeKeepsTheSaves() throws {
        let game = try makeGame()
        let toolkit = try makeToolkit()
        _ = try install(game, toolkit)
        try play(gameFolder(game))
        try Data("0.2.99-arm-0123456789ab\n".utf8).write(to: toolkit.root.appendingPathComponent("version.txt"))
        _ = try install(game, Toolkit(root: toolkit.root))
        XCTAssertEqual(record(game)?.toolkit, "0.2.99-arm-0123456789ab")
        assertPlayed(gameFolder(game))
    }

    func testARebuildWithAnotherEngineAltogetherKeepsTheSaves() throws {
        let game = try makeGame()
        _ = try install(game, try makeToolkit())
        try play(gameFolder(game))
        // A game's own engine, or a checkout built again by Update from Git.
        _ = try install(game, try makeToolkit("other-engine", version: "0.2.40-arm-abcdefabcdef"))
        XCTAssertEqual(record(game)?.toolkit, "0.2.40-arm-abcdefabcdef")
        assertPlayed(gameFolder(game))
    }

    func testARebuildAfterTheRelinkerOptionsChangeKeepsTheSaves() throws {
        let game = try makeGame()
        let toolkit = try makeToolkit()
        _ = try install(game, toolkit)
        try play(gameFolder(game))
        _ = try install(game, toolkit, custom: ["--exclude-sce-module", "libx.sprx"])
        XCTAssertEqual(record(game)?.customRelinkerOptions, ["--exclude-sce-module", "libx.sprx"])
        assertPlayed(gameFolder(game))
    }

    func testARebuildAfterAnUpdateIsAddedKeepsTheSaves() throws {
        let game = try makeGame()
        let toolkit = try makeToolkit()
        _ = try install(game, toolkit)
        try play(gameFolder(game))
        let patch = root.appendingPathComponent("astro-UPDATE")
        try write("\u{7F}ELF executable, updated", to: patch.appendingPathComponent("eboot.bin"))
        let updated = try makeGame(update: GameUpdate(folder: patch, version: "01.005.000"))
        XCTAssertEqual(Installer.dataFolder(for: updated, root: root), Installer.dataFolder(for: game, root: root), "the same installation")
        _ = try install(updated, toolkit)
        XCTAssertEqual(record(game)?.update, "01.005.000")
        assertPlayed(gameFolder(game))
    }

    func testARebuildThatFailsLeavesTheGameAndItsSavesAsTheyWere() throws {
        let game = try makeGame()
        _ = try install(game, try makeToolkit())
        try play(gameFolder(game))
        XCTAssertThrowsError(try install(game, try makeToolkit("broken", version: "0.2.99-arm-0123456789ab", fails: true)))
        XCTAssertEqual(record(game)?.toolkit, "0.2.15-arm-0123456789ab")
        assertPlayed(gameFolder(game))
    }

    // MARK: A rebuild that does not finish

    /// A half-made bundle as the installer builds it, before it is put in place.
    private func partial(_ game: Game) throws -> URL {
        let partial = Installer.bundle(for: game, root: root).deletingPathExtension().appendingPathExtension("partial")
        try write("eboot", to: partial.appendingPathComponent("Contents/MacOS/eboot"))
        try write("the game", to: partial.appendingPathComponent("Contents/Resources/game/app0/eboot.bin"))
        return partial
    }

    func testTheGamesFilesWithoutTheirBundleStillGiveTheirSavesToTheNextUnlock() throws {
        let game = try makeGame()
        let toolkit = try makeToolkit()
        let bundle = try install(game, toolkit)
        try play(gameFolder(game))
        // The bundle removed by hand, or an unlock the launcher was quit over after the old
        // bundle went: the files and the saves are there, the game no longer reads installed.
        try fm.removeItem(at: bundle)
        XCTAssertNil(record(game))
        _ = try install(game, toolkit)
        XCTAssertNotNil(record(game))
        assertPlayed(gameFolder(game))
    }

    func testTheNewOneCannotTakeItsPlaceTheSavesWaitInTheStoreAndComeBack() throws {
        let game = try makeGame()
        let kept = Installer.keptSaves(for: game, root: root)
        try play(kept)
        let data = Installer.dataFolder(for: game, root: root)
        // Something that is no folder is where the game's files go.
        try write("in the way", to: data)
        XCTAssertThrowsError(try Installer.place(partial: try partial(game), bundle: Installer.bundle(for: game, root: root), data: data))
        assertPlayed(kept, "waits in the store, out of the half-made bundle")
        try fm.removeItem(at: data)
        try fm.removeItem(at: Installer.bundle(for: game, root: root).deletingPathExtension().appendingPathExtension("partial"))

        _ = try install(game, try makeToolkit())
        assertPlayed(gameFolder(game), "is back")
    }

    func testTheLauncherQuitWhileTheNewOneTookTheOldOnesPlaceTheNextUnlockHasTheSaves() throws {
        let game = try makeGame()
        let toolkit = try makeToolkit()
        _ = try install(game, toolkit)
        // As it is left when the launcher goes between the saves moving over and the swap.
        try play(try partial(game).appendingPathComponent("Contents/Resources/game"))
        try Data("0.2.99-arm-0123456789ab\n".utf8).write(to: toolkit.root.appendingPathComponent("version.txt"))
        _ = try install(game, Toolkit(root: toolkit.root))
        XCTAssertEqual(record(game)?.toolkit, "0.2.99-arm-0123456789ab")
        assertPlayed(gameFolder(game))
    }

    func testTheSameWithTheOldOneAlreadyGoneTheyWaitInTheStore() throws {
        let game = try makeGame()
        try play(try partial(game).appendingPathComponent("Contents/Resources/game"))
        _ = try install(game, try makeToolkit())
        assertPlayed(gameFolder(game))
        XCTAssertFalse(fm.fileExists(atPath: Installer.keptSaves(for: game, root: root).path))
    }

    func testRemoveLeftoversTakesTheSavesOutOfAHalfMadeBundleBeforeItRemovesIt() throws {
        let game = try makeGame()
        _ = try install(game, try makeToolkit())
        let half = try partial(game)
        try play(half.appendingPathComponent("Contents/Resources/game"))
        Installer.removeLeftovers(root: root)
        XCTAssertFalse(fm.fileExists(atPath: half.path))
        assertPlayed(gameFolder(game), "is back in the game that is still there")

        // With no game left to take them, they wait where the next unlock looks.
        Installer.remove(try Installer.uninstall(game, root: root))
        let kept = Installer.keptSaves(for: game, root: root)
        try fm.removeItem(at: kept)
        let again = try partial(game)
        try play(again.appendingPathComponent("Contents/Resources/game"))
        Installer.removeLeftovers(root: root)
        XCTAssertFalse(fm.fileExists(atPath: again.path))
        assertPlayed(kept)
    }
}
