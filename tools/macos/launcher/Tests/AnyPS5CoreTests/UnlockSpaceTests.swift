import XCTest
@testable import AnyPS5Core

/// The free space an unlock asks for before it writes anything, and the refusal when the games
/// folder's drive does not have it.
final class UnlockSpaceTests: XCTestCase {
    let mib: Int64 = 1 << 20
    var scratch: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("space-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: scratch) }

    // MARK: The math

    /// The unwrapped binaries and the relinker's output can each be twice the dump's executables;
    /// a disk that clones takes nothing more for the bundle's copy of them.
    func testANewUnlockOnADiskThatClonesNeedsTheBinariesFourTimesAndTheMargin() {
        let space = UnlockSpace(executables: 100 * mib, clones: true)
        XCTAssertEqual(space.needed, 400 * mib + UnlockSpace.margin)
    }

    func testWithoutClonesTheBundlesCopyOfTheRelinkedFilesCountsToo() {
        let space = UnlockSpace(executables: 100 * mib, clones: false)
        XCTAssertEqual(space.needed, 600 * mib + UnlockSpace.margin)
    }

    func testCopiedLibrariesAndGameFilesAreAdded() {
        let space = UnlockSpace(executables: 10 * mib, libraries: 30 * mib, copied: 2_000 * mib, clones: true)
        XCTAssertEqual(space.needed, 40 * mib + 30 * mib + 2_000 * mib + UnlockSpace.margin)
        XCTAssertTrue(space.copies)
    }

    /// Unlocking again with nothing changed reuses the relinker's kept output: no unwrap, no relink.
    func testAKeptRelinkLeavesOnlyItsCopy() {
        XCTAssertEqual(UnlockSpace(executables: 100 * mib, clones: true, keptRelink: 250 * mib).needed, UnlockSpace.margin)
        XCTAssertEqual(UnlockSpace(executables: 100 * mib, clones: false, keptRelink: 250 * mib).needed, 250 * mib + UnlockSpace.margin)
    }

    // MARK: The refusal

    func testEnoughSpaceGoesAhead() {
        let space = UnlockSpace(executables: 100 * mib, clones: true)
        XCTAssertNil(space.shortage(free: space.needed, volume: "Games"))
        XCTAssertNil(space.shortage(free: 50_000 * mib, volume: "Games"))
    }

    func testTooLittleSpaceSaysHowMuchIsNeededAndFree() throws {
        let space = UnlockSpace(executables: 100 * mib, libraries: 0, copied: 0, clones: true)
        let shortage = try XCTUnwrap(space.shortage(free: space.needed - 1, volume: "Games"))
        XCTAssertEqual(shortage.needed, space.needed)
        XCTAssertEqual(shortage.free, space.needed - 1)
        XCTAssertEqual(shortage.missing, 1)
        XCTAssertEqual(shortage.volume, "Games")
        XCTAssertFalse(shortage.copying)
        XCTAssertTrue(shortage.localizedDescription.contains("Games"))
    }

    func testAShortageWhileCopyingSaysSo() throws {
        let space = UnlockSpace(executables: mib, copied: 5_000 * mib, clones: true)
        XCTAssertTrue(try XCTUnwrap(space.shortage(free: 100 * mib, volume: "USB")).copying)
    }

    /// A drive that does not say how much is free never stops an unlock: the unlock reports a
    /// full disk itself, as before.
    func testUnknownFreeSpaceNeverBlocks() {
        XCTAssertNil(UnlockSpace(executables: 100_000 * mib, clones: false).shortage(free: nil, volume: "NAS"))
    }

    func testTheMacsOwnDiskSaysHowMuchIsFree() throws {
        let free = try XCTUnwrap(FreeSpace.available(at: scratch))
        XCTAssertGreaterThan(free, 0)
        // A folder not made yet is measured where it would be.
        XCTAssertNotNil(FreeSpace.available(at: scratch.appendingPathComponent("not/yet/here")))
        XCTAssertFalse(FreeSpace.volumeName(at: scratch).isEmpty)
    }

    // MARK: The plan of a real folder

    func testThePlanCountsTheExecutableAndModulesOfTheDump() throws {
        let dump = scratch.appendingPathComponent("dump")
        try fm.createDirectory(at: dump.appendingPathComponent("sce_module"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data(count: 3000).write(to: dump.appendingPathComponent("eboot.bin"))
        try Data(count: 1000).write(to: dump.appendingPathComponent("sce_module/libgame.prx"))
        try Data(count: 99_999).write(to: dump.appendingPathComponent("data.pak"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkit = Toolkit(root: try FakeToolkit.make(in: scratch))
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let space = Installer.plan(game: game, toolkit: toolkit, root: root)
        XCTAssertEqual(space.executables, 4000)
        XCTAssertEqual(space.copied, 0, "the Mac clones or links the game's files, never copies them")
        XCTAssertTrue(space.clones, "the test's folders are on the Mac's own APFS disk")
        XCTAssertEqual(space.libraries, 0, "the toolkit is on the same disk, so its files are cloned")
        XCTAssertNil(space.keptRelink)
    }

    /// The pipeline asks before step 1: with too little space nothing is written, no work folder,
    /// no half-made bundle, no progress.
    func testAnUnlockWithTooLittleSpaceStopsBeforeWritingAnything() throws {
        let dump = scratch.appendingPathComponent("dump")
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data("\u{7F}ELF-not-really".utf8).write(to: dump.appendingPathComponent("eboot.bin"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkit = Toolkit(root: try FakeToolkit.make(in: scratch))
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let steps = Locked<[Installer.Step]>([])
        let installer = Installer(game: game, toolkit: toolkit, progress: { step, _ in steps.withLock { $0.append(step) } }, log: { _ in })
        installer.freeSpace = { _ in 1 << 20 }
        XCTAssertThrowsError(try installer.run(root: root)) { error in
            XCTAssertTrue(error is SpaceShortage, "\(error)")
        }
        XCTAssertEqual(steps.withLock { $0 }, [])
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(".AnyPS5/Work").path))
        let games = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(".AnyPS5/Games").path)) ?? []
        XCTAssertTrue(games.isEmpty, "\(games)")
    }

    func testAnUnknownFreeSpaceLetsTheUnlockGoOn() throws {
        let dump = scratch.appendingPathComponent("dump")
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data("not an executable".utf8).write(to: dump.appendingPathComponent("eboot.bin"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkit = Toolkit(root: try FakeToolkit.make(in: scratch))
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        let installer = Installer(game: game, toolkit: toolkit, progress: { _, _ in }, log: { _ in })
        installer.freeSpace = { _ in nil }
        XCTAssertThrowsError(try installer.run(root: root)) { error in
            // Past the space check: step 1 finds the made-up executable.
            XCTAssertTrue(error is InstallError, "\(error)")
        }
    }
}
