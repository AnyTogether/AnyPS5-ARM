import XCTest
@testable import AnyPS5Core

/// What a relink takes in: the dump's executable and modules, never a relinker's output left in
/// the dump by a relink by hand (which writes into app0's sce_module, the dump's own folder when
/// the dump is used as app0); a module that cannot be used is left out instead of stopping the
/// game; and a failure says the relinker's reason and the file it names.
final class RelinkInputsTests: XCTestCase {
    var scratch: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("inputs-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: scratch) }

    /// A dump with an ELF executable and an ELF module; a relinker that lists its input files run
    /// by run, writes an executable and a guest module, and fails as the real one fails a
    /// conversion (exit 2, FAIL: and Input:) while `failOn` is in its input.
    func fixture(failOn: String? = nil, folder: String = "dump") throws -> (game: Game, toolkit: Toolkit, root: URL, inputs: URL) {
        let dump = scratch.appendingPathComponent(folder)
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dump.appendingPathComponent("sce_module"), withIntermediateDirectories: true)
        try Data("\u{7F}ELF executable".utf8).write(to: dump.appendingPathComponent("eboot.bin"))
        try Data("\u{7F}ELF module".utf8).write(to: dump.appendingPathComponent("sce_module/libgame.prx"))
        try Data("data".utf8).write(to: dump.appendingPathComponent("data.pak"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkitFolder = try FakeToolkit.make(in: scratch)
        let inputs = scratch.appendingPathComponent("inputs.txt")
        let script = """
        #!/bin/sh
        for argument; do last="$argument"; done
        echo run >> "\(inputs.path)"
        find . -type f | sed 's|^\\./||' | sort >> "\(inputs.path)"
        fail_on="\(failOn ?? "")"
        if [ -n "$fail_on" ] && [ -f "$fail_on" ]; then
          echo "FAIL: Unsupported relocation type 0x25 (offset 0x1234)" >&2
          echo "Input: $PWD/$fail_on" >&2
          exit 2
        fi
        mkdir -p "$(dirname "$last")/app0/sce_module"
        echo relinked > "$last"
        echo relinked module > "$(dirname "$last")/app0/sce_module/libgame.prx.guest.prx"
        """
        try Data(script.utf8).write(to: toolkitFolder.appendingPathComponent("relinker"))
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        return (game, Toolkit(root: toolkitFolder), root, inputs)
    }

    func runs(_ file: URL) -> [[String]] {
        var runs: [[String]] = []
        for line in ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n") {
            if line == "run" { runs.append([]) } else { runs[runs.count - 1].append(String(line)) }
        }
        return runs
    }

    func installer(_ game: Game, _ toolkit: Toolkit, lines: Locked<[String]>? = nil) -> Installer {
        Installer(game: game, toolkit: toolkit, progress: { _, _ in }, log: { line in lines?.withLock { $0.append(line) } })
    }

    /// Outputs of a relink by hand in the dump; PE files, as the Windows relinker writes them.
    func pollute(_ dump: URL) throws {
        try Data("MZ\u{90}".utf8).write(to: dump.appendingPathComponent("sce_module/libgame.prx.guest.prx"))
        try Data("MZ\u{90}".utf8).write(to: dump.appendingPathComponent("sce_module/libSceFace.PRX.GUEST.PRX"))
    }

    func testARelinkerOutputInTheDumpIsNeverAnInput() throws {
        let (game, _, _, _) = try fixture()
        try pollute(game.folder)
        XCTAssertEqual(Installer.modules(in: game.folder).map(\.relativePath), ["sce_module/libgame.prx"])
        XCTAssertTrue(Installer.isRelinkerOutput("libSceFace.prx.guest.prx"))
        XCTAssertFalse(Installer.isRelinkerOutput("libSceFace.prx"))
    }

    func testADumpWithAnEarlierRelinksOutputsUnlocksWithOnlyThisRelinksOutputs() throws {
        let (game, toolkit, root, inputs) = try fixture()
        try pollute(game.folder)
        let bundle = try installer(game, toolkit).run(root: root)
        XCTAssertEqual(runs(inputs), [["eboot.bin", "sce_module/libgame.prx"]])
        let app0 = bundle.appendingPathComponent("Contents/Resources/game/app0").resolvingSymlinksInPath()
        XCTAssertEqual(try String(contentsOf: app0.appendingPathComponent("sce_module/libgame.prx.guest.prx"), encoding: .utf8), "relinked module\n")
        XCTAssertFalse(fm.fileExists(atPath: app0.appendingPathComponent("sce_module/libSceFace.PRX.GUEST.PRX").path))
        XCTAssertTrue(fm.fileExists(atPath: game.folder.appendingPathComponent("sce_module/libSceFace.PRX.GUEST.PRX").path), "the dump stays as it is")
    }

    func testARelinkAfterAnEngineUpdateOverAPollutedDumpHeals() throws {
        let (game, toolkit, root, inputs) = try fixture()
        _ = try installer(game, toolkit).run(root: root)
        try pollute(game.folder)
        let kept = Installer.keptRelink(for: game, root: root)
        if fm.fileExists(atPath: kept.path) {
            try Data("stale".utf8).write(to: kept.appendingPathComponent("out/app0/sce_module/stale.prx.guest.prx"))
        }
        try Data("0.2.99-arm-0123456789ab\n".utf8).write(to: toolkit.root.appendingPathComponent("version.txt"))
        let bundle = try installer(game, Toolkit(root: toolkit.root)).run(root: root)
        XCTAssertEqual(runs(inputs).count, 2)
        XCTAssertEqual(runs(inputs).last, ["eboot.bin", "sce_module/libgame.prx"])
        let app0 = bundle.appendingPathComponent("Contents/Resources/game/app0").resolvingSymlinksInPath()
        XCTAssertFalse(fm.fileExists(atPath: app0.appendingPathComponent("sce_module/stale.prx.guest.prx").path))
        XCTAssertFalse(fm.fileExists(atPath: app0.appendingPathComponent("sce_module/libSceFace.PRX.GUEST.PRX").path))
    }

    func testAnEncryptedModuleIsLeftOutByName() throws {
        let (game, toolkit, root, inputs) = try fixture()
        try Data([9, 9, 9, 9, 9, 9, 9, 9]).write(to: game.folder.appendingPathComponent("sce_module/libSceFace.prx"))
        let lines = Locked<[String]>([])
        let unlocking = installer(game, toolkit, lines: lines)
        _ = try unlocking.run(root: root)
        XCTAssertEqual(unlocking.leftOut, [LeftOutModule("sce_module/libSceFace.prx", .encrypted)])
        XCTAssertTrue(lines.withLock { $0 }.contains("sce_module/libSceFace.prx in the dump is encrypted (neither an ELF nor a decrypted SELF container): it is left out, and the game is unlocked without it"))
        XCTAssertEqual(runs(inputs), [["eboot.bin", "sce_module/libgame.prx"]])
    }

    func testAnEncryptedExecutableStopsInPlainWords() throws {
        let (game, toolkit, root, _) = try fixture()
        try Data([9, 9, 9, 9]).write(to: game.folder.appendingPathComponent("eboot.bin"))
        XCTAssertThrowsError(try installer(game, toolkit).run(root: root)) { error in
            XCTAssertEqual(error.localizedDescription, "eboot.bin in the dump is encrypted (neither an ELF nor a decrypted SELF container): dump the game again with a dumper that decrypts it")
        }
    }

    func testAModuleTheRelinkerCannotConvertIsLeftOutAndTheRelinkRunsAgain() throws {
        let (game, toolkit, root, inputs) = try fixture(failOn: "sce_module/libgame.prx", folder: "Oyunlar/PlayStation 5 Oyunları")
        let unlocking = installer(game, toolkit)
        let bundle = try unlocking.run(root: root)
        XCTAssertEqual(unlocking.leftOut, [LeftOutModule("sce_module/libgame.prx", .notRelinked, "Unsupported relocation type 0x25 (offset 0x1234)")])
        XCTAssertEqual(runs(inputs), [["eboot.bin", "sce_module/libgame.prx"], ["eboot.bin"]])
        XCTAssertTrue(fm.fileExists(atPath: bundle.appendingPathComponent("Contents/MacOS/eboot").path))
        // Reused, the kept relink says again what it left out.
        if Installer.keepsRelinks(root: root) {
            let again = installer(game, toolkit)
            _ = try again.run(root: root)
            XCTAssertEqual(again.leftOut, unlocking.leftOut)
            XCTAssertEqual(runs(inputs).count, 2)
        }
    }

    func testAFailedExecutableStopsWithTheRelinkersWholeReason() throws {
        let (game, toolkit, root, inputs) = try fixture(failOn: "eboot.bin")
        XCTAssertThrowsError(try installer(game, toolkit).run(root: root)) { error in
            XCTAssertEqual(error.localizedDescription, "relinker failed (2): FAIL: Unsupported relocation type 0x25 (offset 0x1234)\nInput: eboot.bin")
        }
        XCTAssertEqual(runs(inputs).count, 1)
    }

    func testTheErrorTextFromTheLastFailLineToTheEnd() {
        let failure = ToolFailed(tool: "relinker", code: 2, lines: ["Instruction scan | eboot.bin | 100%", "FAIL: bad", "Input: /work/source/sce_module/a.prx"],
                                 directory: URL(fileURLWithPath: "/work/source"))
        XCTAssertEqual(failure.localizedDescription, "relinker failed (2): FAIL: bad\nInput: sce_module/a.prx")
        XCTAssertEqual(failure.reason, "bad")
        XCTAssertEqual(failure.input, "/work/source/sce_module/a.prx")
        XCTAssertEqual(Installer.failedModule(failure, source: URL(fileURLWithPath: "/work/source"), modules: ["sce_module/a.prx"]), "sce_module/a.prx")
        XCTAssertNil(Installer.failedModule(failure, source: URL(fileURLWithPath: "/elsewhere"), modules: ["sce_module/a.prx"]))
        XCTAssertEqual(ToolFailed(tool: "relinker", code: 3, lines: ["a", "b"]).localizedDescription, "relinker failed (3): b")
    }
}
