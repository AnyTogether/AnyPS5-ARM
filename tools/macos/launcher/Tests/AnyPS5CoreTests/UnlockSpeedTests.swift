import XCTest
@testable import AnyPS5Core

/// Unlocking faster where it is cheap: the relinker's output kept and reused while nothing it
/// depends on changed, a toolkit checked once per change instead of at every unlock, the game's
/// files cloned in parallel; and a background unlock that can stop for a game and go on after.
final class UnlockSpeedTests: XCTestCase {
    var scratch: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("speed-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: scratch) }

    /// A dump with a plain ELF executable, a toolkit whose relinker writes an executable and
    /// counts its runs, and the games folder.
    func fixture(relinker: String? = nil) throws -> (game: Game, toolkit: Toolkit, root: URL, runs: URL) {
        let dump = scratch.appendingPathComponent("dump")
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data("\u{7F}ELF executable".utf8).write(to: dump.appendingPathComponent("eboot.bin"))
        try Data("data".utf8).write(to: dump.appendingPathComponent("data.pak"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkitFolder = try FakeToolkit.make(in: scratch)
        let runs = scratch.appendingPathComponent("runs.txt")
        let script = relinker ?? """
        #!/bin/sh
        for argument; do last="$argument"; done
        mkdir -p "$(dirname "$last")"
        echo relinked > "$last"
        echo run >> "\(runs.path)"
        """
        try Data(script.utf8).write(to: toolkitFolder.appendingPathComponent("relinker"))
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        return (game, Toolkit(root: toolkitFolder), root, runs)
    }

    func runs(_ file: URL) -> Int {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    func installer(_ game: Game, _ toolkit: Toolkit, steps: Locked<[Installer.Step]>? = nil) -> Installer {
        Installer(game: game, toolkit: toolkit, progress: { step, _ in steps?.withLock { $0.append(step) } }, log: { _ in })
    }

    // MARK: Kept relinks

    func testUnlockingAgainWithNothingChangedSkipsTheRelinker() throws {
        let (game, toolkit, root, runs) = try fixture()
        let bundle = try installer(game, toolkit).run(root: root)
        XCTAssertEqual(self.runs(runs), 1)
        XCTAssertEqual(try String(contentsOf: bundle.appendingPathComponent("Contents/MacOS/eboot"), encoding: .utf8), "relinked\n")
        XCTAssertTrue(fm.fileExists(atPath: Installer.keptRelink(for: game, root: root).appendingPathComponent("out/eboot").path))

        let again = try installer(game, toolkit).run(root: root)
        XCTAssertEqual(self.runs(runs), 1, "the kept output was reused")
        XCTAssertEqual(try String(contentsOf: again.appendingPathComponent("Contents/MacOS/eboot"), encoding: .utf8), "relinked\n")
        XCTAssertEqual(Installer.plan(game: game, toolkit: toolkit, root: root).keptRelink.map { $0 > 0 }, true)
    }

    func testAChangedExecutableIsRelinkedAgain() throws {
        let (game, toolkit, root, runs) = try fixture()
        _ = try installer(game, toolkit).run(root: root)
        try Data("\u{7F}ELF executable, updated".utf8).write(to: game.folder.appendingPathComponent("eboot.bin"))
        _ = try installer(game, toolkit).run(root: root)
        XCTAssertEqual(self.runs(runs), 2)
    }

    func testAnotherToolkitRelinksAgain() throws {
        let (game, toolkit, root, runs) = try fixture()
        _ = try installer(game, toolkit).run(root: root)
        try Data("0.2.99-arm-0123456789ab\n".utf8).write(to: toolkit.root.appendingPathComponent("version.txt"))
        _ = try installer(game, Toolkit(root: toolkit.root)).run(root: root)
        XCTAssertEqual(self.runs(runs), 2)
    }

    /// Patches change the bundle's executable, never the kept one.
    func testTheKeptOutputStaysAsTheRelinkerWroteIt() throws {
        let (game, toolkit, root, _) = try fixture()
        let bundle = try installer(game, toolkit).run(root: root)
        try Data("patched".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        XCTAssertEqual(try String(contentsOf: Installer.keptRelink(for: game, root: root).appendingPathComponent("out/eboot"), encoding: .utf8), "relinked\n")
    }

    // MARK: Pause, priority, cancel

    func testAPausedUnlockWaitsAndGoesOnWhenResumed() throws {
        let (game, toolkit, root, runs) = try fixture()
        let steps = Locked<[Installer.Step]>([])
        let unlock = installer(game, toolkit, steps: steps)
        unlock.pause()
        let done = expectation(description: "unlocked")
        let result = Locked<Result<URL, Error>?>(nil)
        DispatchQueue.global().async {
            let outcome = Result { try unlock.run(root: root) }
            result.withLock { $0 = outcome }
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(steps.withLock { $0 }.contains(.relink), "nothing past the first step while paused")
        XCTAssertEqual(self.runs(runs), 0)
        unlock.resume()
        wait(for: [done], timeout: 10)
        if case .failure(let error) = result.value { XCTFail("\(error)") }
        XCTAssertEqual(self.runs(runs), 1)
    }

    func testCancelWhilePausedStopsAtOnce() throws {
        let (game, toolkit, root, _) = try fixture()
        let unlock = installer(game, toolkit)
        unlock.pause()
        let done = expectation(description: "stopped")
        let result = Locked<Result<URL, Error>?>(nil)
        DispatchQueue.global().async {
            let outcome = Result { try unlock.run(root: root) }
            result.withLock { $0 = outcome }
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.2)
        unlock.cancel()
        wait(for: [done], timeout: 5)
        guard case .failure(let error) = result.value else { return XCTFail("not stopped") }
        XCTAssertTrue(error is CancellationError, "\(error)")
    }

    /// A relinker stopped for a game (SIGSTOP) goes on where it was after the resume, and a
    /// background one runs in the system's background band.
    func testTheRelinkerItselfIsStoppedAndResumed() throws {
        let marker = scratch.appendingPathComponent("relinker-pid")
        let (game, toolkit, root, runs) = try fixture(relinker: """
        #!/bin/sh
        echo $$ > "\(scratch.path)/relinker-pid.tmp" && mv "\(scratch.path)/relinker-pid.tmp" "\(marker.path)"
        sleep 1
        for argument; do last="$argument"; done
        mkdir -p "$(dirname "$last")"
        echo relinked > "$last"
        echo run >> "\(scratch.path)/runs.txt"
        """)
        let unlock = installer(game, toolkit)
        unlock.background = true
        let done = expectation(description: "unlocked")
        let result = Locked<Result<URL, Error>?>(nil)
        DispatchQueue.global().async {
            let outcome = Result { try unlock.run(root: root) }
            result.withLock { $0 = outcome }
            done.fulfill()
        }
        var pid: pid_t = 0
        for _ in 0..<100 where pid == 0 {
            Thread.sleep(forTimeInterval: 0.05)
            pid = (try? String(contentsOf: marker, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        }
        XCTAssertGreaterThan(pid, 0)
        XCTAssertTrue(Installer.isBackground(pid), "a background unlock's relinker runs in the background band")
        unlock.pause()
        Thread.sleep(forTimeInterval: 1.6)
        XCTAssertEqual(self.runs(runs), 0, "stopped: its sleep could not finish")
        unlock.background = false
        XCTAssertFalse(Installer.isBackground(pid), "promoted: full speed")
        unlock.resume()
        wait(for: [done], timeout: 10)
        if case .failure(let error) = result.value { XCTFail("\(error)") }
        XCTAssertEqual(self.runs(runs), 1)
    }

    // MARK: Parallel cloning

    func testManyFilesAreAllPlacedWithTheProgressEndingAtOne() throws {
        let source = scratch.appendingPathComponent("many")
        for folder in 0..<8 {
            let sub = source.appendingPathComponent("f\(folder)")
            try fm.createDirectory(at: sub, withIntermediateDirectories: true)
            for file in 0..<60 { try Data("\(folder)-\(file)".utf8).write(to: sub.appendingPathComponent("\(file).bin")) }
        }
        for link in [false, true] {
            let target = scratch.appendingPathComponent("target-\(link)")
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let reported = Locked<[Double]>([])
            try Installer.copyTree(source, into: target, link: link, cancelled: {}) { value in reported.withLock { $0.append(value) } }
            for folder in 0..<8 {
                for file in 0..<60 {
                    XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("f\(folder)/\(file).bin"), encoding: .utf8), "\(folder)-\(file)")
                }
            }
            let values = reported.withLock { $0 }
            XCTAssertEqual(values.last, 1)
            XCTAssertEqual(values, values.sorted(), "the progress only rises")
        }
    }

    func testACancelledCopyStops() throws {
        let source = scratch.appendingPathComponent("many")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        for file in 0..<300 { try Data("\(file)".utf8).write(to: source.appendingPathComponent("\(file).bin")) }
        let target = scratch.appendingPathComponent("target")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Installer.copyTree(source, into: target, link: false, cancelled: { throw CancellationError() }) { _ in }) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    // MARK: The toolkit checked once per change

    func testAnUnchangedToolkitIsNotHashedAgain() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let folder = try FakeToolkit.make(in: store.folder, name: "0.2.16-arm-0123456789ab", version: "0.2.16-arm-0123456789ab")
        _ = folder
        let before = ToolkitVerifier.fullChecks
        _ = try store.verifiedToolkit(version: "0.2.16-arm-0123456789ab")
        XCTAssertEqual(ToolkitVerifier.fullChecks, before + 1)
        _ = try store.verifiedToolkit(version: "0.2.16-arm-0123456789ab")
        XCTAssertEqual(ToolkitVerifier.fullChecks, before + 1, "the second unlock trusts the first check")
        XCTAssertEqual(store.installed().map(\.version), ["0.2.16-arm-0123456789ab"], "the check's note is not a toolkit")
    }

    func testAToolkitChangedAfterItsCheckIsHashedAgainAndRefused() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let folder = try FakeToolkit.make(in: store.folder, name: "0.2.16-arm-0123456789ab", version: "0.2.16-arm-0123456789ab")
        _ = try store.verifiedToolkit(version: "0.2.16-arm-0123456789ab")
        // The same size, so only the file's change time gives it away.
        try Data("libSceAgX".utf8).write(to: folder.appendingPathComponent("libs/libSceAgc.prx"))
        XCTAssertThrowsError(try store.verifiedToolkit(version: "0.2.16-arm-0123456789ab"))
    }
}
