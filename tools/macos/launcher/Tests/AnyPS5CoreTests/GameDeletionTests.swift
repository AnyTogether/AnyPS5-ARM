import XCTest
@testable import AnyPS5Core

/// Delete game, away from the interface, as on Windows and Linux (game_deletion_test.dart): what
/// it may take, what it refuses, and how it ends when the Trash takes the files, has no room
/// for them, or fails. Everything in temporary folders, with a Trash that is one of them: the
/// Mac's own Trash is never asked.
final class GameDeletionTests: XCTestCase {
    var base: URL!
    var root: URL!
    var trashFolder: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        // Links resolved, so the temporary folder behind /var compares as itself.
        base = fm.temporaryDirectory.appendingPathComponent("deletion-\(UUID().uuidString)").resolvingSymlinksInPath()
        root = base.appendingPathComponent("Games")
        trashFolder = base.appendingPathComponent("Trash")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: base) }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @discardableResult
    private func makeDump(_ folder: URL, titleID: String, version: String = "01.000.000") throws -> URL {
        try write(#"{"titleId":"\#(titleID)","contentVersion":"\#(version)","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"\#(folder.lastPathComponent)"}}}"#,
                  to: folder.appendingPathComponent("sce_sys/param.json"))
        try Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0, 0]).write(to: folder.appendingPathComponent("eboot.bin"))
        return folder
    }

    private func scan(_ roots: [URL]? = nil) -> [Game] { GameLibrary.survey(roots: roots ?? [root]).games }

    private func game(_ titleID: String, in games: [Game]? = nil) throws -> Game {
        try XCTUnwrap((games ?? scan()).first { $0.titleID == titleID })
    }

    private func plan(_ game: Game, roots: [URL]? = nil, games: [Game]? = nil) throws -> DeletionPlan {
        try GameDeletion.plan(game, root: root, roots: roots ?? [root], games: games ?? scan(roots))
    }

    /// Paths with their links followed, so /var and /private/var are one.
    private func paths(_ urls: [URL]) -> [String] { urls.map { $0.resolvingSymlinksInPath().path } }

    /// A Trash in the test's folder: what is moved lands there (its name is noted), unless
    /// `answer` says otherwise for it.
    private func fakeTrash(answer: @escaping (URL) -> TrashResult? = { _ in nil }) -> (URL) -> TrashResult {
        let folder = trashFolder!, box = self.box
        return { url in
            if let said = answer(url) { return said }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            } catch {
                return .failed(error.localizedDescription)
            }
            box.moved.append(url.lastPathComponent)
            return .trashed
        }
    }

    private final class Box { var moved: [String] = [] }
    private let box = Box()

    // MARK: What goes

    func testOnlyTheGamesOwnFolderWhenNothingBelongsToIt() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        try makeDump(root.appendingPathComponent("stray"), titleID: "PPSA02002")
        XCTAssertEqual(paths(try plan(game("PPSA01001")).items), paths([astro]))
    }

    func testItsUpdateItsAddOnsAndTheArchivesTheyWereUnpackedFromGoWithIt() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        try makeDump(root.appendingPathComponent("astro-UPDATE"), titleID: "PPSA01001", version: "01.004.000")
        try write("dlc", to: root.appendingPathComponent("astro-DLC/SKINPACK00000001/data.bin"))
        try write("the zip it came in", to: root.appendingPathComponent("astro.zip"))
        try write("the update's file", to: root.appendingPathComponent("astro-UPDATE.ffpfsc"))
        try write("the player's own", to: root.appendingPathComponent("notes.txt"))
        try makeDump(root.appendingPathComponent("stray"), titleID: "PPSA02002")
        let found = try plan(game("PPSA01001"))
        XCTAssertEqual(paths([found.folder]), paths([astro]))
        XCTAssertEqual(Set(paths(found.extras)), Set(paths(["astro-UPDATE", "astro-DLC", "astro.zip", "astro-UPDATE.ffpfsc"].map { root.appendingPathComponent($0) })))
        XCTAssertGreaterThan(GameDeletion.size(of: found.items), 0)
    }

    func testAnUpdateTwoDumpsOfOneTitleShareStays() throws {
        try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        try makeDump(root.appendingPathComponent("astro-copy"), titleID: "PPSA01001")
        try makeDump(root.appendingPathComponent("PPSA01001-UPDATE"), titleID: "PPSA01001", version: "01.004.000")
        let games = scan()
        XCTAssertEqual(games.filter { $0.update != nil }.count, 2, "both dumps use the update")
        let first = try XCTUnwrap(games.first { $0.folder.lastPathComponent == "astro" })
        XCTAssertEqual(paths(try plan(first, games: games).items), paths([first.folder]))
    }

    func testAnUpdateThatIsALinkIsNeverTaken() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let elsewhere = try makeDump(base.appendingPathComponent("Elsewhere/update"), titleID: "PPSA01001", version: "01.004.000")
        try fm.createSymbolicLink(at: root.appendingPathComponent("astro-UPDATE"), withDestinationURL: elsewhere)
        let found = try plan(game("PPSA01001"))
        XCTAssertEqual(paths(found.items), paths([astro]))
    }

    // MARK: What is refused

    private func assertRefused(_ reason: DeletionRefusal, _ body: @autoclosure () throws -> DeletionPlan, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? DeletionRefusal, reason, file: file, line: line)
        }
    }

    func testADumpKeptLooseInAGamesFolderTheGamesFolderItselfNeverGoes() throws {
        try makeDump(root, titleID: "PPSA01001")
        try makeDump(root.appendingPathComponent("stray"), titleID: "PPSA02002")
        let games = scan()
        XCTAssertEqual(games.count, 1, "the scan stops at the games folder: it is the game")
        assertRefused(.libraryFolder, try plan(games[0], games: games))
    }

    func testAGameWhoseFolderHoldsAnotherGamesFolder() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let inner = astro.appendingPathComponent("More")
        try makeDump(inner.appendingPathComponent("stray"), titleID: "PPSA02002")
        assertRefused(.libraryFolder, try plan(game("PPSA01001"), roots: [root, inner]))
    }

    func testAGameThatIsALinkToAFolderOutsideTheGamesFolder() throws {
        let elsewhere = try makeDump(base.appendingPathComponent("Elsewhere/astro"), titleID: "PPSA01001")
        try fm.createSymbolicLink(at: root.appendingPathComponent("astro"), withDestinationURL: elsewhere)
        let linked = Game(folder: root.appendingPathComponent("astro"), titleID: "PPSA01001", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        assertRefused(.linkedElsewhere, try plan(linked, games: [linked]))
        XCTAssertTrue(fm.fileExists(atPath: elsewhere.appendingPathComponent("eboot.bin").path))
    }

    func testAGameReachedThroughALinkedFolderThatLeadsOutOfTheGamesFolder() throws {
        let outside = base.appendingPathComponent("Elsewhere/shelf")
        try makeDump(outside.appendingPathComponent("astro"), titleID: "PPSA01001")
        try fm.createSymbolicLink(at: root.appendingPathComponent("shelf"), withDestinationURL: outside)
        let reached = Game(folder: root.appendingPathComponent("shelf/astro"), titleID: "PPSA01001", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        assertRefused(.linkedElsewhere, try plan(reached, games: [reached]))
    }

    func testAGamesFolderThatIsItselfALinkIsStillTheLibrary() throws {
        let real = base.appendingPathComponent("Drive/Games")
        try makeDump(real.appendingPathComponent("astro"), titleID: "PPSA01001")
        let linked = base.appendingPathComponent("GamesLink")
        try fm.createSymbolicLink(at: linked, withDestinationURL: real)
        let found = Game(folder: linked.appendingPathComponent("astro"), titleID: "PPSA01001", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let plan = try GameDeletion.plan(found, root: linked, roots: [linked], games: [found])
        XCTAssertEqual(plan.items, [found.folder], "the game's folder as the library names it, through the link")
    }

    func testAFolderAnotherGameOfTheLibraryLivesIn() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let bonus = Game(folder: astro.appendingPathComponent("bonus"), titleID: "PPSA09009", name: "Bonus", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let first = try game("PPSA01001")
        assertRefused(.sharedFolder, try plan(first, games: [first, bonus]))
    }

    // MARK: How it ends

    func testEverythingInTheTrashTheGamesFolderFirstNothingElseTouched() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        try makeDump(root.appendingPathComponent("astro-UPDATE"), titleID: "PPSA01001", version: "01.004.000")
        try write("zip", to: root.appendingPathComponent("astro.zip"))
        let stray = try makeDump(root.appendingPathComponent("stray"), titleID: "PPSA02002")
        let trash = fakeTrash()
        let outcome = GameDeletion.run(try plan(game("PPSA01001")), trash: trash)
        XCTAssertEqual(outcome, .deleted(left: []))
        XCTAssertEqual(box.moved, ["astro", "astro-UPDATE", "astro.zip"], "the game's folder first")
        XCTAssertFalse(fm.fileExists(atPath: astro.path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("astro-UPDATE").path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("astro.zip").path))
        XCTAssertTrue(fm.fileExists(atPath: trashFolder.appendingPathComponent("astro/eboot.bin").path), "moved, not destroyed")
        XCTAssertTrue(fm.fileExists(atPath: stray.path))
        XCTAssertEqual(scan().map(\.titleID), ["PPSA02002"])
    }

    func testNoTrashWhereTheGameIsNothingIsTouchedAndItAsksBeforeDeletingForGood() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let update = try makeDump(root.appendingPathComponent("astro-UPDATE"), titleID: "PPSA01001", version: "01.004.000")
        let found = try plan(game("PPSA01001"))
        XCTAssertEqual(GameDeletion.run(found, trash: { _ in .noTrash }), .needsPermanent)
        XCTAssertTrue(fm.fileExists(atPath: astro.path))
        XCTAssertTrue(fm.fileExists(atPath: update.path))

        var asked: [String] = []
        let outcome = GameDeletion.run(found, permanent: true, trash: { _ in
            XCTFail("the Trash is not asked when deleting for good")
            return .noTrash
        }, remove: { url in
            asked.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        })
        XCTAssertEqual(outcome, .deleted(left: []))
        XCTAssertEqual(asked, ["astro", "astro-UPDATE"], "the game's folder first")
        XCTAssertFalse(fm.fileExists(atPath: astro.path))
        XCTAssertFalse(fm.fileExists(atPath: update.path))
    }

    func testTheTrashFailsOnTheGamesFolderNothingIsTouchedAndTheReasonIsGiven() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let update = try makeDump(root.appendingPathComponent("astro-UPDATE"), titleID: "PPSA01001", version: "01.004.000")
        let trash = fakeTrash { $0.lastPathComponent == "astro" ? .failed("in use") : nil }
        XCTAssertEqual(GameDeletion.run(try plan(game("PPSA01001")), trash: trash), .failed("in use"))
        XCTAssertEqual(box.moved, [], "the update is not taken without its game")
        XCTAssertTrue(fm.fileExists(atPath: astro.path))
        XCTAssertTrue(fm.fileExists(atPath: update.path))
    }

    func testSomethingThatBelongsToItCannotFollowTheGameIsDeletedAndWhatStayedIsNamed() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let update = try makeDump(root.appendingPathComponent("astro-UPDATE"), titleID: "PPSA01001", version: "01.004.000")
        let trash = fakeTrash { $0.lastPathComponent == "astro-UPDATE" ? .failed("in use") : nil }
        guard case .deleted(let left) = GameDeletion.run(try plan(game("PPSA01001")), trash: trash) else { return XCTFail("the game is deleted") }
        XCTAssertEqual(paths(left), paths([update]))
        XCTAssertFalse(fm.fileExists(atPath: astro.path))
        XCTAssertTrue(fm.fileExists(atPath: update.path))
    }

    func testAFolderThatBecameALinkAfterItWasPlannedIsNeverFollowed() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let found = try plan(game("PPSA01001"))
        let elsewhere = base.appendingPathComponent("Elsewhere/astro")
        try fm.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: astro, to: elsewhere)
        try fm.createSymbolicLink(at: astro, withDestinationURL: elsewhere)
        let trash = fakeTrash()
        guard case .failed = GameDeletion.run(found, trash: trash) else { return XCTFail("refused") }
        guard case .failed = GameDeletion.run(found, permanent: true, trash: trash) else { return XCTFail("refused for good too") }
        XCTAssertTrue(fm.fileExists(atPath: elsewhere.appendingPathComponent("eboot.bin").path))
        XCTAssertEqual(box.moved, [])
    }

    func testAFolderThatIsGoneSaysSo() throws {
        let astro = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let found = try plan(game("PPSA01001"))
        try fm.removeItem(at: astro)
        guard case .failed = GameDeletion.run(found, trash: { _ in .trashed }) else { return XCTFail("nothing to delete") }
    }

    // MARK: The saves

    func testSavesAreKeptInTheStoreWhenTheGameIsDeletedAndBackInTheGameUnlockedThereAgain() throws {
        let dump = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let game = Game(folder: dump, titleID: "PPSA01001", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let bundle = Installer.bundle(for: game, root: root)
        let data = Installer.dataFolder(for: game, root: root)
        try write("eboot", to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        try write("the game", to: data.appendingPathComponent("game/app0/data.bin"))
        try write("forty hours", to: data.appendingPathComponent("game/_sd/slot1/save.dat"))
        try write("[1,2]", to: data.appendingPathComponent("game/_trophy/earned.json"))
        try write("another player", to: data.appendingPathComponent("game/_profiles/second/_sd/save.dat"))
        try write("first", to: data.appendingPathComponent("game/.anyps5-profile"))

        try Installer.keepSaves(game, root: root)
        Installer.remove(Installer.setAside(game, root: root))
        XCTAssertFalse(fm.fileExists(atPath: bundle.path), "the installation is gone")
        XCTAssertFalse(fm.fileExists(atPath: data.path))
        let kept = Installer.keptSaves(for: game, root: root)
        XCTAssertTrue(kept.path.hasPrefix(root.appendingPathComponent(GameLibrary.storeName).path + "/"), "in the games folder's store")
        XCTAssertEqual(try String(contentsOf: kept.appendingPathComponent("_sd/slot1/save.dat"), encoding: .utf8), "forty hours")
        XCTAssertTrue(fm.fileExists(atPath: kept.appendingPathComponent("_trophy/earned.json").path))
        XCTAssertTrue(fm.fileExists(atPath: kept.appendingPathComponent("_profiles/second/_sd/save.dat").path))
        XCTAssertEqual(try String(contentsOf: kept.appendingPathComponent(".anyps5-profile"), encoding: .utf8), "first")
        XCTAssertFalse(fm.fileExists(atPath: kept.appendingPathComponent("app0").path), "only what is the player's own")

        // The game added again in the same folder and unlocked: the new installation takes them.
        let partial = bundle.deletingLastPathComponent().appendingPathComponent(bundle.lastPathComponent + ".partial")
        try write("eboot again", to: partial.appendingPathComponent("Contents/MacOS/eboot"))
        try write("the game again", to: partial.appendingPathComponent("Contents/Resources/game/app0/data.bin"))
        try Installer.place(partial: partial, bundle: bundle, data: data)
        let placed = data.appendingPathComponent("game")
        XCTAssertEqual(try String(contentsOf: placed.appendingPathComponent("_sd/slot1/save.dat"), encoding: .utf8), "forty hours")
        XCTAssertEqual(try String(contentsOf: placed.appendingPathComponent("_profiles/second/_sd/save.dat"), encoding: .utf8), "another player")
        XCTAssertEqual(try String(contentsOf: placed.appendingPathComponent(".anyps5-profile"), encoding: .utf8), "first")
        XCTAssertFalse(fm.fileExists(atPath: kept.path), "nothing left to keep")
    }

    func testSavesKeptTwiceAreBothThereTheOlderOnesAreNeverWrittenOver() throws {
        let dump = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let game = Game(folder: dump, titleID: "PPSA01001", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let save = Installer.dataFolder(for: game, root: root).appendingPathComponent("game/_sd/save.dat")
        try write("first run", to: save)
        try Installer.keepSaves(game, root: root)
        try write("second run", to: save)
        try Installer.keepSaves(game, root: root)
        let kept = Installer.keptSaves(for: game, root: root)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: kept.path).count, 2)
        XCTAssertEqual(try String(contentsOf: kept.appendingPathComponent("_sd/save.dat"), encoding: .utf8), "first run")
    }

    func testAGameNeverUnlockedHasNothingToKeep() throws {
        let dump = try makeDump(root.appendingPathComponent("astro"), titleID: "PPSA01001")
        let game = Game(folder: dump, titleID: "PPSA01001", name: "Astro", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        try Installer.keepSaves(game, root: root)
        XCTAssertFalse(fm.fileExists(atPath: Installer.keptSaves(for: game, root: root).path))
    }
}
