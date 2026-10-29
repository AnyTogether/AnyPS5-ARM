import XCTest
@testable import AnyPS5Core

/// Several games folders (a drive each, say): the list kept in the settings, the library made of
/// all of them, and the watcher over them.
final class LibraryFoldersTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        // The real path: the scan lists the temporary folder through /private.
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-folders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        base = URL(fileURLWithPath: try XCTUnwrap(realpath(made.path, nil).map { String(cString: $0) }))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func folder(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeGame(in root: URL, _ relative: String, title: String, name: String? = nil) throws -> URL {
        let folder = root.appendingPathComponent(relative)
        let system = folder.appendingPathComponent("sce_sys")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        let json = #"{"titleId":"\#(title)","contentVersion":"01.000","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"\#(name ?? "Game " + title)"}}}"#
        try Data(json.utf8).write(to: system.appendingPathComponent("param.json"))
        try Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0, 0]).write(to: folder.appendingPathComponent("eboot.bin"))
        return folder
    }

    // MARK: The list in the settings

    func testAnOlderLaunchersSingleFolderBecomesAListOfOne() {
        XCTAssertEqual(LibraryFolders.list(nil, legacy: "/Games"), ["/Games"])
        XCTAssertEqual(LibraryFolders.list(nil, legacy: nil), [])
        XCTAssertEqual(LibraryFolders.list(["/Games", "/Volumes/Drive/PS5"], legacy: "/Games"), ["/Games", "/Volumes/Drive/PS5"])
        XCTAssertEqual(LibraryFolders.list(["/Games", "/Volumes/Drive/PS5"], legacy: "/Other"), ["/Other", "/Volumes/Drive/PS5"],
                       "an older launcher that changed its one folder since changes the first")
    }

    func testAddingKeepsTheOrderAndNeverAddsAFolderTwice() {
        var folders = LibraryFolders.adding("/Games", to: [])
        folders = LibraryFolders.adding("/Volumes/Drive/PS5", to: folders)
        XCTAssertEqual(folders, ["/Games", "/Volumes/Drive/PS5"])
        XCTAssertEqual(LibraryFolders.adding("/Games/", to: folders), folders, "the same folder written another way")
        XCTAssertEqual(LibraryFolders.adding("/Games/./", to: folders), folders)
    }

    func testRemovingAndChoosingTheFirstAgain() {
        let folders = ["/Games", "/Volumes/Drive/PS5", "/Volumes/Other"]
        XCTAssertEqual(LibraryFolders.removing("/Volumes/Drive/PS5", from: folders), ["/Games", "/Volumes/Other"])
        XCTAssertEqual(LibraryFolders.removing("/Games", from: ["/Games"]), [], "the last one out: no folders")
        XCTAssertEqual(LibraryFolders.replacingFirst(with: "/New", in: folders), ["/New", "/Volumes/Drive/PS5", "/Volumes/Other"])
        XCTAssertEqual(LibraryFolders.replacingFirst(with: "/Volumes/Other", in: folders), ["/Volumes/Other", "/Volumes/Drive/PS5"], "moved up, not shown twice")
        XCTAssertEqual(LibraryFolders.replacingFirst(with: "/Games", in: []), ["/Games"])
    }

    // MARK: The library

    func testTheLibraryIsEveryFoldersGamesWithEachGameOnceFromTheFirstFolderThatHasIt() throws {
        let first = try folder("Internal"), second = try folder("Drive")
        let shared = try makeGame(in: first, "Shared", title: "PPSA00001", name: "Alpha")
        try makeGame(in: second, "Shared copy", title: "PPSA00001", name: "Alpha")
        try makeGame(in: first, "Only here", title: "PPSA00002", name: "Charlie")
        let deep = try makeGame(in: second, "Sub/Only there", title: "PPSA00003", name: "Bravo")

        let library = GameLibrary.survey(roots: [first, second])
        XCTAssertEqual(library.games.map(\.name), ["Alpha", "Bravo", "Charlie"], "one list, by name")
        XCTAssertEqual(library.games.first { $0.titleID == "PPSA00001" }?.folder.path, shared.path, "the game from the folder earliest in the list")
        XCTAssertEqual(library.roots[shared.path], first)
        XCTAssertEqual(library.roots[deep.path], second, "each game knows the folder it came from")
        XCTAssertEqual(library.folders, [GameLibrary.FolderStatus(url: first, connected: true, games: 2), GameLibrary.FolderStatus(url: second, connected: true, games: 2)])

        let reversed = GameLibrary.survey(roots: [second, first])
        XCTAssertEqual(reversed.games.first { $0.titleID == "PPSA00001" }.map { reversed.roots[$0.id] }, second, "the order of the list decides")
    }

    func testTwoDumpsOfOneGameInTheSameFolderBothShowAsBefore() throws {
        let root = try folder("One")
        try makeGame(in: root, "A", title: "PPSA00001")
        try makeGame(in: root, "B", title: "PPSA00001")
        XCTAssertEqual(GameLibrary.survey(roots: [root]).games.count, 2)
        XCTAssertEqual(GameLibrary.survey(roots: [root]).games, GameLibrary.scan(root), "one folder finds what it always did")
    }

    func testAFolderThatIsNotThereIsKeptAndSaidNotConnected() throws {
        let here = try folder("Here")
        try makeGame(in: here, "Game", title: "PPSA00001")
        let unplugged = base.appendingPathComponent("Volumes/Unplugged/PS5")
        let library = GameLibrary.survey(roots: [unplugged, here])
        XCTAssertEqual(library.games.map(\.titleID), ["PPSA00001"], "its games are hidden, the others show")
        XCTAssertEqual(library.folders.map(\.connected), [false, true])
        XCTAssertEqual(library.folders.first?.games, 0)

        // Plugged back in: the next look finds it.
        try makeGame(in: unplugged, "Game", title: "PPSA00001")
        try makeGame(in: unplugged, "Other", title: "PPSA00009")
        let back = GameLibrary.survey(roots: [unplugged, here])
        XCTAssertEqual(back.folders.map(\.connected), [true, true])
        XCTAssertEqual(back.games.count, 2)
        XCTAssertEqual(back.games.first { $0.titleID == "PPSA00001" }.flatMap { back.roots[$0.id] }, unplugged, "first in the list again")
    }

    func testAFolderInsideAnotherShowsItsGamesOnce() throws {
        let outer = try folder("Outer")
        let inner = try folder("Outer/Inner")
        let game = try makeGame(in: inner, "Game", title: "PPSA00001")
        for roots in [[outer, inner], [inner, outer]] {
            let library = GameLibrary.survey(roots: roots)
            XCTAssertEqual(library.games.map(\.folder.path), [game.path])
            XCTAssertEqual(library.roots[game.path], roots[0])
        }
    }

    // MARK: Watching them

    func testOneFoldersStoreIsNotAnotherFoldersChange() {
        let roots = ["/Volumes/A/PS5", "/Volumes/B/PS5"]
        XCTAssertFalse(LibraryMonitor.matters("/Volumes/A/PS5/.AnyPS5/Games/x.app/Contents/MacOS/eboot", roots: roots), "an unlock on drive A")
        XCTAssertFalse(LibraryMonitor.matters("/Volumes/B/PS5/.AnyPS5/Work/a", roots: roots))
        XCTAssertTrue(LibraryMonitor.matters("/Volumes/B/PS5/Game/eboot.bin", roots: roots))
        XCTAssertTrue(LibraryMonitor.matters("/Volumes/A", roots: roots), "what holds a folder: its drive came or went")
        XCTAssertFalse(LibraryMonitor.matters("/Games/Inner/.AnyPS5/Games/x", roots: ["/Games", "/Games/Inner"]), "a folder inside another")
        XCTAssertTrue(LibraryMonitor.matters("/Games/Inner/Game/eboot.bin", roots: ["/Games", "/Games/Inner"]))
    }

    func testTheWatcherWatchesEveryFolder() throws {
        let first = try folder("First"), second = try folder("Second")
        try makeGame(in: first, "Existing", title: "PPSA00001")
        let missing = base.appendingPathComponent("Unplugged")
        let baseline = expectation(description: "baseline")
        let detected = expectation(description: "a game copied into the second folder")
        let lock = NSLock()
        var updates: [LibraryMonitor.Update] = []
        let monitor = LibraryMonitor(roots: [first, missing, second]) { update in
            lock.lock(); updates.append(update); let n = updates.count; lock.unlock()
            if n == 1 { baseline.fulfill() }
            if update.added.contains(where: { $0.titleID == "PPSA00002" }) { detected.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        wait(for: [baseline], timeout: 5)
        lock.lock()
        XCTAssertEqual(updates.first?.folders.map(\.connected), [true, false, true])
        XCTAssertEqual(updates.first?.games.count, 1)
        lock.unlock()

        try makeGame(in: second, "New", title: "PPSA00002")
        wait(for: [detected], timeout: 8)
        lock.lock()
        XCTAssertEqual(updates.last?.games.count, 2)
        XCTAssertEqual(updates.last.flatMap { update in update.games.first { $0.titleID == "PPSA00002" }.flatMap { update.roots[$0.id] } }, second)
        lock.unlock()
    }
}
