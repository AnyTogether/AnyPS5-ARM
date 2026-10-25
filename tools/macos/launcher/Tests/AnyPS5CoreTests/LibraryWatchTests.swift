import XCTest
@testable import AnyPS5Core

final class LibraryWatchTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func game(_ path: String, title: String) -> Game {
        Game(folder: URL(fileURLWithPath: "/games/" + path), titleID: title, name: title, version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
    }

    private func makeSystem(_ folder: URL, title: String) throws {
        let system = folder.appendingPathComponent("sce_sys")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        let json = #"{"titleId":"\#(title)","contentVersion":"01.000","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"Game \#(title)"}}}"#
        try Data(json.utf8).write(to: system.appendingPathComponent("param.json"))
    }

    private func makeEboot(_ folder: URL) throws {
        try Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0, 0]).write(to: folder.appendingPathComponent("eboot.bin"))
    }

    private func makeGame(_ relative: String, title: String) throws -> URL {
        let folder = root.appendingPathComponent(relative)
        try makeSystem(folder, title: title)
        try makeEboot(folder)
        return folder
    }

    // MARK: Which games are new

    func testTheFirstScanIsTheBaselineAndLaterOnesAnnounceWhatIsNew() {
        var tracker = LibraryTracker()
        let a = game("A", title: "PPSA00001"), b = game("B", title: "PPSA00002"), c = game("C", title: "PPSA00003")
        XCTAssertEqual(tracker.update([a, b]), [], "nothing is new on the first scan after launch or a new folder")
        XCTAssertEqual(tracker.update([a, b]), [])
        XCTAssertEqual(tracker.update([a, b, c]), [c])
        XCTAssertEqual(tracker.update([a, b, c]), [], "a game is announced once")
    }

    func testSeveralNewGamesComeTogether() {
        var tracker = LibraryTracker()
        let a = game("A", title: "PPSA00001")
        _ = tracker.update([a])
        let new = [game("B", title: "PPSA00002"), game("C", title: "PPSA00003"), game("D", title: "PPSA00004")]
        XCTAssertEqual(tracker.update([a] + new), new)
    }

    func testRemovedGamesGoQuietlyAndComingBackIsNotNew() {
        var tracker = LibraryTracker()
        let a = game("A", title: "PPSA00001"), b = game("B", title: "PPSA00002")
        _ = tracker.update([a, b])
        XCTAssertEqual(tracker.update([a]), [])
        XCTAssertEqual(tracker.update([]), [], "an unplugged drive empties the library without a word")
        XCTAssertEqual(tracker.update([a, b]), [], "plugged back in, its games are not new")
    }

    func testARenamedOrMovedFolderIsNotANewGame() {
        var tracker = LibraryTracker()
        _ = tracker.update([game("Old name", title: "PPSA00001"), game("B", title: "PPSA00002")])
        XCTAssertEqual(tracker.update([game("Folder/New name", title: "PPSA00001"), game("B", title: "PPSA00002")]), [])
        let copy = game("Second copy", title: "PPSA00002")
        XCTAssertEqual(tracker.update([game("Folder/New name", title: "PPSA00001"), game("B", title: "PPSA00002"), copy]), [copy],
                       "a second copy of a game still there is a new folder")
    }

    func testResetMakesTheNextScanABaselineAgain() {
        var tracker = LibraryTracker()
        _ = tracker.update([game("A", title: "PPSA00001")])
        tracker.reset()
        XCTAssertEqual(tracker.update([game("X", title: "PPSA00009")]), [])
    }

    // MARK: Half-copied dumps

    func testAnIncompleteDumpIsNoticedAndBecomesAGameWhenItsCopyFinishes() throws {
        _ = try makeGame("Have/One", title: "PPSA00001")
        var tracker = LibraryTracker()
        XCTAssertEqual(tracker.update(GameLibrary.survey(root).games), [])

        let folder = root.appendingPathComponent("Sub/Copying")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        var survey = GameLibrary.survey(root)
        XCTAssertEqual(survey.games.count, 1)
        XCTAssertEqual(survey.incomplete.map(\.standardizedFileURL), [folder.standardizedFileURL])
        XCTAssertEqual(tracker.update(survey.games), [])

        // param.json half written: still not a game.
        try Data(#"{"titleId":"PPSA0"#.utf8).write(to: folder.appendingPathComponent("sce_sys/param.json"))
        survey = GameLibrary.survey(root)
        XCTAssertEqual(survey.incomplete.count, 1)
        try makeSystem(folder, title: "PPSA00002")
        survey = GameLibrary.survey(root)
        XCTAssertEqual(survey.incomplete.count, 1, "no eboot.bin yet")
        XCTAssertEqual(tracker.update(survey.games), [])

        try makeEboot(folder)
        survey = GameLibrary.survey(root)
        XCTAssertEqual(survey.incomplete, [])
        let added = tracker.update(survey.games)
        XCTAssertEqual(added.map(\.titleID), ["PPSA00002"])
        XCTAssertEqual(added.first?.name, "Game PPSA00002")
    }

    func testTheSurveyFindsTheSameGamesAsTheScan() throws {
        _ = try makeGame("A", title: "PPSA00001")
        _ = try makeGame("Deep/Er/B", title: "PPSA00002")
        XCTAssertEqual(GameLibrary.survey(root).games, GameLibrary.scan(root))
        XCTAssertEqual(GameLibrary.scan(root).count, 2)
    }

    func testTheSameListingComparesWhatTheLibraryShows() throws {
        let a = game("A", title: "PPSA00001")
        let unreadable = Game(folder: a.folder, titleID: a.titleID, name: a.name, version: a.version, icon: nil, background: nil, music: nil, executable: .unreadable)
        XCTAssertTrue(GameLibrary.sameListing([a], [a]))
        XCTAssertFalse(GameLibrary.sameListing([a], [unreadable]), "a half-written eboot.bin that is now whole changes the game's state")
        XCTAssertFalse(GameLibrary.sameListing([a], []))
    }

    // MARK: Which changes matter

    func testTheLaunchersOwnStoreAndHiddenFilesDoNotCount() {
        let base = "/Volumes/Games/PS5"
        XCTAssertFalse(LibraryMonitor.matters("/Volumes/Games/PS5/.AnyPS5/Games/PPSA-1.app/Contents/MacOS/eboot", root: base))
        XCTAssertFalse(LibraryMonitor.matters("/Volumes/Games/PS5/.AnyPS5", root: base))
        XCTAssertFalse(LibraryMonitor.matters("/Volumes/Games/PS5/Some/.DS_Store", root: base))
        XCTAssertTrue(LibraryMonitor.matters("/Volumes/Games/PS5/Folder/Game/sce_sys/param.json", root: base))
        XCTAssertTrue(LibraryMonitor.matters("/Volumes/Games/PS5/Folder/Game/eboot.bin", root: base))
        XCTAssertTrue(LibraryMonitor.matters("/Volumes/Games/PS5", root: base), "the folder itself")
        XCTAssertTrue(LibraryMonitor.matters("/Volumes/Games", root: base), "above it: the folder moved or its drive went")
        XCTAssertTrue(LibraryMonitor.matters("/private/var/folders/x/PS5/Game/eboot.bin", root: "/var/folders/x/PS5"), "the same folder through /private")
        XCTAssertFalse(LibraryMonitor.matters("/private/var/folders/x/PS5/.AnyPS5/Work/a", root: "/var/folders/x/PS5"))
    }

    // MARK: The watcher

    func testTheWatcherNoticesANestedGameCopiedInSteps() throws {
        _ = try makeGame("Existing", title: "PPSA00001")
        let baseline = expectation(description: "baseline")
        let detected = expectation(description: "new game")
        let lock = NSLock()
        var updates: [LibraryMonitor.Update] = []
        let monitor = LibraryMonitor(root: root) { update in
            lock.lock()
            updates.append(update)
            let count = updates.count
            lock.unlock()
            if count == 1 { baseline.fulfill() }
            if update.added.contains(where: { $0.titleID == "PPSA00002" }) { detected.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        wait(for: [baseline], timeout: 5)
        lock.lock()
        XCTAssertEqual(updates.first?.games.count, 1)
        XCTAssertEqual(updates.first?.added, [], "the first scan announces nothing")
        lock.unlock()

        // Like a big copy: the folder, a while later its sce_sys, then the eboot.bin, two levels down.
        let folder = root.appendingPathComponent("New Games/Big Game")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Thread.sleep(forTimeInterval: 1.5)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try makeSystem(folder, title: "PPSA00002")
        Thread.sleep(forTimeInterval: 1.5)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Content/Paks"), withIntermediateDirectories: true)
        try Data(count: 4096).write(to: folder.appendingPathComponent("Content/Paks/a.pak"))
        try makeEboot(folder)
        wait(for: [detected], timeout: 8)
        lock.lock()
        XCTAssertEqual(updates.last?.games.count, 2)
        XCTAssertEqual(updates.filter { !$0.added.isEmpty }.count, 1, "announced once")
        lock.unlock()
    }

    func testTheWatcherCatchesADumpThatWasIncompleteWhenItsFolderAppeared() throws {
        // The folder lands whole but without its eboot.bin; the eboot comes later by itself.
        let first = expectation(description: "baseline")
        let detected = expectation(description: "completed")
        let lock = NSLock()
        var count = 0
        let monitor = LibraryMonitor(root: root) { update in
            lock.lock(); count += 1; let n = count; lock.unlock()
            if n == 1 { first.fulfill() }
            if update.added.contains(where: { $0.titleID == "PPSA00003" }) { detected.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        wait(for: [first], timeout: 5)
        let folder = root.appendingPathComponent("Late")
        try makeSystem(folder, title: "PPSA00003")
        Thread.sleep(forTimeInterval: 2.5)
        try makeEboot(folder)
        wait(for: [detected], timeout: 8)
    }

    func testTheWatcherIgnoresTheLaunchersStore() throws {
        _ = try makeGame("Existing", title: "PPSA00001")
        let first = expectation(description: "baseline")
        let scans = Counter()
        let monitor = LibraryMonitor(root: root) { _ in
            if scans.increment() == 1 { first.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        wait(for: [first], timeout: 5)
        // The game made just before the start may still come in as events: let them pass.
        Thread.sleep(forTimeInterval: 2.5)
        let before = scans.value
        let store = root.appendingPathComponent(".AnyPS5/Games/PPSA00001.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        for index in 0..<20 { try Data(count: 1024).write(to: store.appendingPathComponent("file\(index)")) }
        try Data(count: 10).write(to: root.appendingPathComponent("Existing/.DS_Store"))
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertEqual(scans.value, before, "unlocking a game writes only in the store, which never rescans")
    }

    func testAskedRescansAreCoalescedNotDropped() throws {
        _ = try makeGame("Existing", title: "PPSA00001")
        let first = expectation(description: "baseline")
        let second = expectation(description: "the asked rescan")
        let lock = NSLock()
        var updates: [LibraryMonitor.Update] = []
        let monitor = LibraryMonitor(root: root) { update in
            lock.lock(); updates.append(update); let n = updates.count; lock.unlock()
            if n == 1 { first.fulfill() }
            if n == 2 { second.fulfill() }
        }
        monitor.start()
        defer { monitor.stop() }
        wait(for: [first], timeout: 5)
        // Asked right after a scan, several times: one more scan, which sees the game made meanwhile.
        _ = try makeGame("Made meanwhile", title: "PPSA00004")
        for _ in 0..<5 { monitor.rescan() }
        wait(for: [second], timeout: 5)
        Thread.sleep(forTimeInterval: 2.5)
        lock.lock()
        XCTAssertLessThanOrEqual(updates.count, 3, "asked rescans and the folder's own events coalesce")
        XCTAssertEqual(updates[1].games.count, 2)
        XCTAssertEqual(updates.flatMap(\.added).map(\.titleID), ["PPSA00004"])
        lock.unlock()
    }
}

/// A count the monitor's queue bumps and the test reads.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
