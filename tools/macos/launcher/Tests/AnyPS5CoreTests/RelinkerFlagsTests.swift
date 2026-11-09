import XCTest
@testable import AnyPS5Core

/// The relinker options a player can choose for a game: which ones ever reach the relinker, that
/// a rebuild picks a change up past the kept output, and that a saved option never costs the game
/// its unlock on an engine that lacks it or a relinker that refuses it.
final class RelinkerFlagsTests: XCTestCase {
    var scratch: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("flags-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: scratch) }

    /// A dump with an executable and a module, a games folder, and a toolkit whose relinker notes
    /// its arguments run by run. `supportsTraceImports` gives the toolkit the option's text in
    /// its relinker and libc.prx; `refusesWithTrace` makes the relinker stop as the real one does
    /// for a game without libc.prx; `failOn` stops it on a module as a conversion failure does.
    func fixture(supportsTraceImports: Bool = true, refusesWithTrace: Bool = false, failOn: String? = nil) throws -> (game: Game, toolkit: Toolkit, root: URL, runs: URL) {
        let dump = scratch.appendingPathComponent("dump")
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dump.appendingPathComponent("sce_module"), withIntermediateDirectories: true)
        try Data("\u{7F}ELF executable".utf8).write(to: dump.appendingPathComponent("eboot.bin"))
        try Data("\u{7F}ELF module".utf8).write(to: dump.appendingPathComponent("sce_module/libgame.prx"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkitFolder = try FakeToolkit.make(in: scratch)
        let runs = scratch.appendingPathComponent("runs.txt")
        var script = "#!/bin/sh\n"
        if supportsTraceImports { script += "# knows --trace-imports\n" }
        script += "echo \"$*\" >> \"\(runs.path)\"\n"
        if refusesWithTrace {
            script += "case \"$*\" in *--trace-imports*) echo 'FAIL: --trace-imports requires libc.prx among the libraries' >&2; echo \"Input: $PWD/eboot.bin\" >&2; exit 2;; esac\n"
        }
        if let failOn {
            script += "if [ -f \"\(failOn)\" ]; then echo 'FAIL: bad module' >&2; echo \"Input: $PWD/\(failOn)\" >&2; exit 2; fi\n"
        }
        script += """
        for argument; do last="$argument"; done
        mkdir -p "$(dirname "$last")"
        echo relinked > "$last"

        """
        try Data(script.utf8).write(to: toolkitFolder.appendingPathComponent("relinker"))
        if supportsTraceImports {
            try Data("exports TraceImport_nid_no_patch".utf8).write(to: toolkitFolder.appendingPathComponent("libs/libc.prx"))
        }
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        return (game, Toolkit(root: toolkitFolder), root, runs)
    }

    func runs(_ file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func unlock(_ game: Game, _ toolkit: Toolkit, _ root: URL, flags: [RelinkerFlag]) throws -> (bundle: URL, log: [String]) {
        let lines = Locked<[String]>([])
        let installer = Installer(game: game, toolkit: toolkit, progress: { _, _ in }, log: { line in lines.withLock { $0.append(line) } })
        installer.relinkerFlags = flags
        let bundle = try installer.run(root: root)
        return (bundle, lines.withLock { $0 })
    }

    // MARK: Settings

    func testOnlyOptionsTheLauncherKnowsAreChosen() {
        var settings = GameSettings()
        XCTAssertEqual(settings.chosenRelinkerFlags, [])
        settings.relinkerFlags = ["--windows", "--trace-imports", "--rpath", "/tmp/evil"]
        XCTAssertEqual(settings.chosenRelinkerFlags, [.traceImports])
        settings.setRelinkerFlag(.traceImports, false)
        XCTAssertNil(settings.relinkerFlags, "nothing chosen leaves nothing behind")
        settings.setRelinkerFlag(.traceImports, true)
        XCTAssertEqual(settings.relinkerFlags, ["--trace-imports"])
    }

    func testTheChoiceIsSavedAndAnOldFileHasNone() throws {
        var settings = GameSettings()
        settings.setRelinkerFlag(.traceImports, true)
        let restored = try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.relinkerFlags, ["--trace-imports"])
        let older = #"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"off"}"#
        XCTAssertNil(try JSONDecoder().decode(GameSettings.self, from: Data(older.utf8)).relinkerFlags)
        let odd = #"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"off","relinkerFlags":"--windows"}"#
        XCTAssertEqual(try JSONDecoder().decode(GameSettings.self, from: Data(odd.utf8)).chosenRelinkerFlags, [])
    }

    func testAnEngineSupportsAnOptionOnlyWithBothItsRelinkerAndItsLibc() throws {
        let (_, toolkit, _, _) = try fixture()
        XCTAssertTrue(toolkit.supports(.traceImports))
        let without = try FakeToolkit.make(in: scratch, name: "without")
        XCTAssertFalse(Toolkit(root: without).supports(.traceImports), "an engine whose relinker never heard of the option")
        let libcOnly = try FakeToolkit.make(in: scratch, name: "libcOnly")
        try Data("exports TraceImport_nid_no_patch".utf8).write(to: libcOnly.appendingPathComponent("libs/libc.prx"))
        XCTAssertFalse(Toolkit(root: libcOnly).supports(.traceImports))
        let relinkerOnly = try FakeToolkit.make(in: scratch, name: "relinkerOnly")
        try Data("#!/bin/sh\n# --trace-imports\n".utf8).write(to: relinkerOnly.appendingPathComponent("relinker"))
        try Data("old libc".utf8).write(to: relinkerOnly.appendingPathComponent("libs/libc.prx"))
        XCTAssertFalse(Toolkit(root: relinkerOnly).supports(.traceImports), "a game relinked with it would not load on this libc")
    }

    // MARK: A rebuild

    func testARebuildPicksUpAChangedOptionAndTheBundleRecordsIt() throws {
        let (game, toolkit, root, runs) = try fixture()
        let first = try unlock(game, toolkit, root, flags: [])
        XCTAssertFalse(self.runs(runs)[0].contains("--trace-imports"))
        XCTAssertNil(Installer.record(of: first.bundle)?.relinkerFlags)

        XCTAssertNil(Installer.plan(game: game, toolkit: toolkit, root: root, relinkerFlags: [.traceImports]).keptRelink, "what is kept was made without it")
        let second = try unlock(game, toolkit, root, flags: [.traceImports])
        XCTAssertEqual(self.runs(runs).count, 2, "the kept output is not reused for another option")
        XCTAssertTrue(self.runs(runs)[1].hasPrefix("--macos --to-rosetta --trace-imports "))
        XCTAssertEqual(Installer.record(of: second.bundle)?.relinkerFlags, ["--trace-imports"])

        let third = try unlock(game, toolkit, root, flags: [.traceImports])
        XCTAssertEqual(self.runs(runs).count, 2, "the same option reuses it")
        XCTAssertEqual(Installer.record(of: third.bundle)?.relinkerFlags, ["--trace-imports"])

        let fourth = try unlock(game, toolkit, root, flags: [])
        XCTAssertEqual(self.runs(runs).count, 3, "taken off, it is relinked without")
        XCTAssertNil(Installer.record(of: fourth.bundle)?.relinkerFlags)
    }

    func testAnEngineThatLacksTheOptionUnlocksWithoutItAndSaysSo() throws {
        let (game, toolkit, root, runs) = try fixture(supportsTraceImports: false)
        let result = try unlock(game, toolkit, root, flags: [.traceImports])
        XCTAssertFalse(self.runs(runs).contains { $0.contains("--trace-imports") })
        XCTAssertTrue(fm.fileExists(atPath: result.bundle.appendingPathComponent("Contents/MacOS/eboot").path))
        XCTAssertNil(Installer.record(of: result.bundle)?.relinkerFlags)
        XCTAssertTrue(result.log.contains { $0.contains("this engine does not support --trace-imports") })
    }

    func testARelinkerThatRefusesTheOptionRunsAgainWithoutItAndTheGameIsUnlocked() throws {
        let (game, toolkit, root, runs) = try fixture(refusesWithTrace: true)
        let result = try unlock(game, toolkit, root, flags: [.traceImports])
        XCTAssertEqual(self.runs(runs).map { $0.contains("--trace-imports") }, [true, false])
        XCTAssertTrue(fm.fileExists(atPath: result.bundle.appendingPathComponent("Contents/MacOS/eboot").path))
        XCTAssertNil(Installer.record(of: result.bundle)?.relinkerFlags, "what it was really made with")
        XCTAssertTrue(result.log.contains { $0.contains("the game is rebuilt without it") })
        // Filed under what it was made with: the same choice tries again, none reuses it.
        _ = try unlock(game, toolkit, root, flags: [])
        XCTAssertEqual(self.runs(runs).count, 2)
    }

    func testAModuleTheRelinkerCannotConvertKeepsTheOption() throws {
        let (game, toolkit, root, runs) = try fixture(failOn: "sce_module/libgame.prx")
        let result = try unlock(game, toolkit, root, flags: [.traceImports])
        XCTAssertEqual(self.runs(runs).count, 2)
        XCTAssertTrue(self.runs(runs).allSatisfy { $0.contains("--trace-imports") }, "the module left out, the option stays")
        XCTAssertEqual(Installer.record(of: result.bundle)?.relinkerFlags, ["--trace-imports"])
    }

    func testAFailureWithoutAnyOptionStillStopsTheUnlock() throws {
        let (game, toolkit, root, runs) = try fixture(failOn: "eboot.bin")
        XCTAssertThrowsError(try unlock(game, toolkit, root, flags: [])) { error in
            XCTAssertTrue(error.localizedDescription.contains("bad module"))
        }
        XCTAssertEqual(self.runs(runs).count, 1)
    }

    func testAnOptionTheRelinkerFailsOnEitherWayEndsWithTheRealFailure() throws {
        let (game, toolkit, root, runs) = try fixture(failOn: "eboot.bin")
        XCTAssertThrowsError(try unlock(game, toolkit, root, flags: [.traceImports])) { error in
            XCTAssertTrue(error.localizedDescription.contains("bad module"))
        }
        XCTAssertEqual(self.runs(runs).map { $0.contains("--trace-imports") }, [true, false])
    }

    // MARK: Reports and detailed logging

    func testDetailedLoggingAsksForTheCallTrace() {
        XCTAssertEqual(TraceMode.environment["APS5_TRACE_CALLS"], "all")
    }

    func testTheReportSaysWhatTheGameWasBuiltWithAndWhatIsSavedForTheNext() {
        var settings = GameSettings()
        XCTAssertFalse(settings.reportSummary.contains("Relinker flags"))
        settings.setRelinkerFlag(.traceImports, true)
        XCTAssertTrue(settings.reportSummary.contains("Relinker flags --trace-imports"))

        var report = SessionReport(gameName: "G", titleID: "PPSA00001", gameVersion: "1.0", settings: GameSettings(),
                                   system: SystemInfo(model: "m", chip: "c", memoryGB: 8, macOS: "15", displayHz: nil), launcherVersion: "0.2",
                                   session: "", privacy: ReportPrivacy(home: "/nowhere"))
        XCTAssertFalse(report.text().contains("Relinker flags the game was unlocked with"))
        report.relinkerFlags = ["--trace-imports"]
        XCTAssertTrue(report.text().contains("Relinker flags the game was unlocked with: --trace-imports\n"))
    }
}
