@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// Game Settings › Delete game, as on Windows and Linux (game_delete_test.dart): the game itself
/// off the disk, not only what the launcher built. Asked first with Cancel in focus; the tile
/// leaves at once and comes back when the files could not go; the saves are kept. The Trash is
/// a folder of the test's own: the Mac's Trash is never asked.
@MainActor
final class DeleteGameModelTests: XCTestCase {
    private let fm = FileManager.default

    /// What the fake Trash was asked and how it answers, read from the deletion's own thread.
    private final class FakeTrash: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        private var reply: TrashResult?
        /// Held shut, a move waits until it is opened.
        let gate = DispatchSemaphore(value: 0)
        var waits = false
        let folder: URL

        init(folder: URL) { self.folder = folder }

        var asked: [String] { lock.withLock { names } }
        func answer(_ result: TrashResult?) { lock.withLock { reply = result } }

        func move(_ url: URL) -> TrashResult {
            lock.withLock { names.append(url.lastPathComponent) }
            if waits { gate.wait() }
            if let said = lock.withLock({ reply }) { return said }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
                return .trashed
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A launcher of three games, the first installed with a save, and a Trash of the test's own.
    private func launcher() throws -> (AppModel, Game, FakeTrash) {
        let model = try LauncherFixture.model(games: 3)
        let game = try XCTUnwrap(model.games.first)
        let root = try XCTUnwrap(model.root(of: game))
        let bundle = Installer.bundle(for: game, root: root)
        try write("eboot", to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        try write(#"{"source":"\#(game.folder.path)","titleID":"\#(game.titleID)","toolkit":"toolkit-1","date":"2026-11-10T00:00:00Z"}"#,
                  to: bundle.appendingPathComponent("Contents/Resources/anyps5-install.json"))
        try write("the game", to: Installer.dataFolder(for: game, root: root).appendingPathComponent("game/app0/data.bin"))
        try write("forty hours", to: Installer.dataFolder(for: game, root: root).appendingPathComponent("game/_sd/save.dat"))
        model.preview(games: model.games, root: root)
        let trash = FakeTrash(folder: root.deletingLastPathComponent().appendingPathComponent("Trash-\(UUID().uuidString)"))
        model.trashItem = { trash.move($0) }
        model.selected = 0
        let trashFolder = trash.folder
        addTeardownBlock {
            try? FileManager.default.removeItem(at: trashFolder)
            try? FileManager.default.removeItem(at: root)
        }
        return (model, game, trash)
    }

    /// The deletion of `game` over, on its thread and back on the main one.
    private func settled(_ model: AppModel, _ game: Game) async {
        _ = await model.deletions[game.id]?.value
    }

    // MARK: The action

    func testDeleteGameIsTheLastRowAfterUninstallAndDestructive() throws {
        let (model, game, _) = try launcher()
        guard case .installed = model.state(of: game) else { return XCTFail("the first game reads installed") }
        model.open(.gameSettings)
        let rows = try XCTUnwrap(model.panelCategories().first?.rows)
        XCTAssertEqual(rows.suffix(2).map(\.id), ["uninstall", "deleteGame"])
        XCTAssertEqual(rows.last?.title, T.text(.deleteGame))
        guard case .action(let destructive, _)? = rows.last?.kind else { return XCTFail("an action") }
        XCTAssertTrue(destructive)
        XCTAssertNotEqual(model.panelRow, rows.count - 1, "never where the focus starts")

        // A locked game has no Uninstall, and still Delete game.
        model.selected = 1
        let locked = try XCTUnwrap(model.panelCategories().first?.rows)
        XCTAssertFalse(locked.contains { $0.id == "uninstall" })
        XCTAssertEqual(locked.last?.id, "deleteGame")
    }

    func testWhileTheGameStartsOrIsUnlockedTheRowSaysWhyAndTheCardDoesNotOpen() throws {
        let (model, game, trash) = try launcher()
        model.previewStarting(game)
        model.open(.gameSettings)
        XCTAssertEqual(model.panelCategories().first?.rows.last?.detail, T.text(.closeGameFirst))
        model.askDeleteGame(game)
        XCTAssertNotEqual(model.overlay, .confirmDeleteGame)
        XCTAssertNil(model.deleteAsk)
        XCTAssertEqual(model.toast?.text, T.text(.closeGameFirst))

        let other = model.games[1]
        model.previewProgress(other, step: .relink, fraction: 0.4)
        XCTAssertEqual(model.deleteBlock(other), T.text(.gameBusyUpdating))
        model.askDeleteGame(other)
        XCTAssertNil(model.deleteAsk)
        XCTAssertEqual(trash.asked, [])
    }

    // MARK: The card

    func testTheCardNamesTheGameAndItsFolderAndCancelIsWhereTheFocusStarts() async throws {
        let (model, game, trash) = try launcher()
        model.open(.gameSettings)
        guard case .action(_, let run)? = model.panelCategories().first?.rows.last?.kind else { return XCTFail("an action") }
        run()
        XCTAssertEqual(model.overlay, .confirmDeleteGame)
        XCTAssertEqual(model.menuIndex, 0, "Return on the card as it opens deletes nothing")
        let ask = try XCTUnwrap(model.deleteAsk)
        XCTAssertEqual(ask.plan.folder, game.folder)
        XCTAssertFalse(ask.permanent)
        for _ in 0..<200 where model.deleteAsk?.size == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThan(try XCTUnwrap(model.deleteAsk?.size), 0, "what it takes on the disk, measured off the main thread")

        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertNil(model.deleteAsk)
        XCTAssertTrue(model.games.contains(game))
        XCTAssertEqual(trash.asked, [])
        XCTAssertTrue(fm.fileExists(atPath: game.folder.path))
    }

    func testBackCancelsEvenFromTheDestructiveAnswer() throws {
        let (model, game, trash) = try launcher()
        model.askDeleteGame(game)
        XCTAssertTrue(model.handle(.right))
        XCTAssertEqual(model.menuIndex, 1)
        XCTAssertTrue(model.handle(.back))
        XCTAssertNil(model.overlay)
        XCTAssertEqual(trash.asked, [])
        XCTAssertTrue(model.games.contains(game))
    }

    func testAGameThatStartedWhileTheCardWasUpIsNotDeleted() throws {
        let (model, game, trash) = try launcher()
        model.askDeleteGame(game)
        model.previewStarting(game)
        model.confirmDeleteGame()
        XCTAssertEqual(model.toast?.text, T.text(.closeGameFirst))
        XCTAssertEqual(trash.asked, [])
        XCTAssertTrue(model.games.contains(game))
        XCTAssertTrue(model.deletions.isEmpty)
    }

    // MARK: Deleting

    func testTheTileLeavesAtOnceTheFilesGoToTheTrashTheInstallationGoesAndTheSavesStay() async throws {
        let (model, game, trash) = try launcher()
        let root = try XCTUnwrap(model.root(of: game))
        let bundle = Installer.bundle(for: game, root: root)
        let archive = game.folder.deletingLastPathComponent().appendingPathComponent(game.folder.lastPathComponent + ".zip")
        try write("the zip it came in", to: archive)
        let others = model.games.filter { $0 != game }.map(\.id)
        trash.waits = true
        model.askDeleteGame(game)
        XCTAssertTrue(model.handle(.right))
        XCTAssertTrue(model.handle(.select))

        XCTAssertNil(model.overlay)
        XCTAssertEqual(model.games.map(\.id), others, "gone from the library when the answer is given")
        XCTAssertNotNil(model.selectedGame)
        XCTAssertTrue(fm.fileExists(atPath: game.folder.path), "its files go after, off the main thread")
        XCTAssertNotNil(model.deletions[game.id])

        trash.gate.signal()
        trash.gate.signal()
        await settled(model, game)
        XCTAssertEqual(trash.asked, [game.folder.lastPathComponent, archive.lastPathComponent])
        XCTAssertFalse(fm.fileExists(atPath: game.folder.path))
        XCTAssertTrue(fm.fileExists(atPath: trash.folder.appendingPathComponent(game.folder.lastPathComponent).appendingPathComponent("eboot.bin").path), "in the Trash, whole")
        XCTAssertTrue(fm.fileExists(atPath: trash.folder.appendingPathComponent(archive.lastPathComponent).path))
        XCTAssertFalse(fm.fileExists(atPath: bundle.path), "the installation went too")
        XCTAssertFalse(fm.fileExists(atPath: Installer.dataFolder(for: game, root: root).path))
        XCTAssertEqual(try String(contentsOf: Installer.keptSaves(for: game, root: root).appendingPathComponent("_sd/save.dat"), encoding: .utf8), "forty hours",
                       "the saves are kept in the store")
        XCTAssertEqual(model.toast?.text, T.format(.deleteGameDone, game.name, T.text(.trashMac)))
        XCTAssertEqual(model.games.map(\.id), others)
        XCTAssertTrue(model.deletions.isEmpty)
        XCTAssertNil(model.installedRecords[game.id])
    }

    func testTheFilesCouldNotGoTheTileComesBackSelectedWithTheReason() async throws {
        let (model, game, trash) = try launcher()
        let root = try XCTUnwrap(model.root(of: game))
        trash.answer(.failed("the folder is in use"))
        model.askDeleteGame(game)
        model.confirmDeleteGame()
        XCTAssertFalse(model.games.contains(game))
        await settled(model, game)
        XCTAssertTrue(model.games.contains(game))
        XCTAssertEqual(model.games.map(\.name), model.games.map(\.name).sorted(), "back where the library's order has it")
        XCTAssertEqual(model.selectedGame, game)
        guard case .installed = model.state(of: game) else { return XCTFail("nothing of the installation was touched") }
        XCTAssertTrue(fm.fileExists(atPath: Installer.bundle(for: game, root: root).path))
        XCTAssertTrue(fm.fileExists(atPath: game.folder.path))
        XCTAssertEqual(model.toast?.text, T.format(.deleteGameFailed, game.name, "the folder is in use"))
        XCTAssertNil(model.overlay)
    }

    func testNoTrashWhereTheGameIsAskedAgainCancelFirstBeforeAnythingIsDeletedForGood() async throws {
        let (model, game, trash) = try launcher()
        trash.answer(.noTrash)
        model.askDeleteGame(game)
        model.confirmDeleteGame()
        await settled(model, game)
        XCTAssertTrue(fm.fileExists(atPath: game.folder.path), "nothing was touched")
        XCTAssertTrue(model.games.contains(game))
        XCTAssertEqual(model.overlay, .confirmDeleteGame)
        XCTAssertEqual(model.deleteAsk?.permanent, true)
        XCTAssertEqual(model.menuIndex, 0)

        // Cancel: everything stays.
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertTrue(fm.fileExists(atPath: game.folder.path))

        // Asked and answered again: this time it is deleted for good, never through the Trash.
        model.askDeleteGame(game)
        model.confirmDeleteGame()
        await settled(model, game)
        XCTAssertEqual(model.deleteAsk?.permanent, true)
        let asked = trash.asked.count
        XCTAssertTrue(model.handle(.right))
        XCTAssertTrue(model.handle(.select))
        XCTAssertFalse(model.games.contains(game))
        await settled(model, game)
        XCTAssertEqual(trash.asked.count, asked, "the Trash is not asked again")
        XCTAssertFalse(fm.fileExists(atPath: game.folder.path))
        XCTAssertFalse(fm.fileExists(atPath: trash.folder.path))
        XCTAssertEqual(model.toast?.text, T.format(.deleteGameDoneForever, game.name))
        XCTAssertFalse(model.games.contains(game))
    }

    func testADumpKeptLooseInTheGamesFolderIsRefusedWithTheReason() throws {
        let (model, game, trash) = try launcher()
        let root = try XCTUnwrap(model.root(of: game))
        let loose = Game(folder: root, titleID: "PPSA09009", name: "Loose", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        model.askDeleteGame(loose)
        XCTAssertNotEqual(model.overlay, .confirmDeleteGame)
        XCTAssertEqual(model.toast?.text, T.text(.deleteGameRefusedFolder))
        XCTAssertEqual(trash.asked, [])
    }
}
