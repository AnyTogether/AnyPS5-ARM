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
    /// conversion (exit 2, FAIL: and Input:) while `failOn` is in its input. Like the real one it
    /// stops when two modules in its working directory share a file name, naming the later of the
    /// two by path, and its last run's arguments are in arguments.txt, one on a line.
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
        printf '%s\\n' "$@" > "\(scratch.appendingPathComponent("arguments.txt").path)"
        echo run >> "\(inputs.path)"
        find . -type f | sed 's|^\\./||' | sort >> "\(inputs.path)"
        conflict=$(find . -type f ! -name eboot.bin | sed 's|^\\./||' | LC_ALL=C sort | awk -F/ '{ if ($NF in seen) { print; exit } seen[$NF] = 1 }')
        if [ -n "$conflict" ]; then
          echo "FAIL: Conflicting guest output filename: ${conflict##*/}.guest.prx" >&2
          echo "Input: $PWD/$conflict" >&2
          exit 2
        fi
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

    /// The folders the last relink was given with --module-dir, in their order.
    func moduleDirectories() -> [String] {
        let arguments = ((try? String(contentsOf: scratch.appendingPathComponent("arguments.txt"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        return arguments.indices.filter { arguments[$0] == "--module-dir" && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
    }

    /// Adds ELF modules to the dump, each at its path.
    func add(_ modules: [String], to dump: URL) throws {
        for module in modules {
            let file = dump.appendingPathComponent(module)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("\u{7F}ELF module".utf8).write(to: file)
        }
    }

    func duplicates(_ modules: [String]) -> [String: String] {
        Installer.duplicateModules(modules.map { URL(fileURLWithPath: $0) })
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

    /// Gran Turismo 7's dump (a report from another launcher's user): sce_module/pdiWheel_0.prx
    /// is neither an ELF nor a SELF container. The game unlocks with that one module left out.
    func testAWheelModuleThatIsNeitherAnElfNorASelfIsLeftOutAndTheGameUnlocks() throws {
        let (game, toolkit, root, inputs) = try fixture()
        var generator = SystemRandomNumberGenerator()
        var bytes = (0..<4096).map { _ in UInt8.random(in: 0...255, using: &generator) }
        bytes[0] = 0x8C  // never an ELF's or a SELF's first byte
        try Data(bytes).write(to: game.folder.appendingPathComponent("sce_module/pdiWheel_0.prx"))
        let lines = Locked<[String]>([])
        let unlocking = installer(game, toolkit, lines: lines)
        let unlocked = try unlocking.run(root: root)
        XCTAssertTrue(fm.fileExists(atPath: unlocked.path))
        XCTAssertEqual(unlocking.leftOut, [LeftOutModule("sce_module/pdiWheel_0.prx", .encrypted)])
        XCTAssertTrue(lines.withLock { $0 }.contains("sce_module/pdiWheel_0.prx in the dump is encrypted (neither an ELF nor a decrypted SELF container): it is left out, and the game is unlocked without it"))
        XCTAssertEqual(runs(inputs), [["eboot.bin", "sce_module/libgame.prx"]], "the relinker never sees it")
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

    /// Slick Daddy's Lost in Play (Desktop #144): the dump holds libc.prx and
    /// libSceNpCppWebApi.prx in sce_module and again in decrypted/sce_module. The relinker
    /// stopped twice with "Conflicting guest output filename", each time naming sce_module's
    /// copy, which was left out, and the game was unlocked with the copies from
    /// decrypted/sce_module.
    func testLostInPlayOfTheCopiesInDecryptedAndSceModuleSceModulesAreRelinked() throws {
        let (game, toolkit, root, inputs) = try fixture()
        let media = [
            "Media/Modules/Il2cppUserAssemblies.prx", "Media/Modules/PS5Util.prx", "Media/Plugins/CommonDialog.prx", "Media/Plugins/PSN.prx",
            "Media/Plugins/SaveData.prx", "Media/Plugins/Share.prx", "Media/Plugins/lib_burst_generated.prx", "Media/Plugins/libfmod.prx",
            "Media/Plugins/libfmodstudio.prx", "Media/Plugins/libresonanceaudio.prx",
        ]
        let standard = ["sce_module/libSceNpCppWebApi.prx", "sce_module/libc.prx"]
        try add(media + standard + ["decrypted/sce_module/libSceNpCppWebApi.prx", "decrypted/sce_module/libc.prx"], to: game.folder)
        let lines = Locked<[String]>([])
        let unlocking = installer(game, toolkit, lines: lines)
        let bundle = try unlocking.run(root: root)
        // One run, without a conflict: nothing is left out, and nothing came from decrypted.
        XCTAssertEqual(runs(inputs).map { $0.sorted() }, [(media + standard + ["eboot.bin", "sce_module/libgame.prx"]).sorted()])
        XCTAssertEqual(unlocking.leftOut, [])
        // What upstream's guide passes for a Unity game, and the folder of eboot.bin as ever.
        XCTAssertEqual(moduleDirectories(), [".", "Media/Modules", "Media/Plugins"])
        let logged = lines.withLock { $0 }
        XCTAssertFalse(logged.contains { $0.contains("Conflicting") })
        XCTAssertTrue(logged.contains("decrypted/sce_module/libSceNpCppWebApi.prx: the dump has this module as sce_module/libSceNpCppWebApi.prx too, the game is unlocked with that one"))
        XCTAssertTrue(logged.contains("decrypted/sce_module/libc.prx: the dump has this module as sce_module/libc.prx too, the game is unlocked with that one"))
        // The game's files are all there, the copies too.
        let app0 = bundle.appendingPathComponent("Contents/Resources/game/app0").resolvingSymlinksInPath()
        XCTAssertTrue(fm.fileExists(atPath: app0.appendingPathComponent("decrypted/sce_module/libc.prx").path))
        XCTAssertTrue(fm.fileExists(atPath: game.folder.appendingPathComponent("decrypted/sce_module/libc.prx").path), "the dump stays as it is")
    }

    /// Lenny4250gh's report (Desktop #145): Minecraft and other dumps with modules next to
    /// eboot.bin that sce_module holds too.
    func testModulesNextToTheExecutableAndAgainInSceModuleSceModulesAreRelinked() throws {
        let (game, toolkit, root, inputs) = try fixture()
        try add(["libSceFace.prx", "libc.prx", "libcohtml.Prospero.prx", "sce_module/libSceFace.prx", "sce_module/libc.prx"], to: game.folder)
        let lines = Locked<[String]>([])
        let unlocking = installer(game, toolkit, lines: lines)
        _ = try unlocking.run(root: root)
        // The one next to eboot.bin alone is still relinked where it is.
        XCTAssertEqual(runs(inputs).map { $0.sorted() }, [["eboot.bin", "libcohtml.Prospero.prx", "sce_module/libSceFace.prx", "sce_module/libc.prx", "sce_module/libgame.prx"]])
        XCTAssertEqual(unlocking.leftOut, [])
        XCTAssertEqual(moduleDirectories(), ["."])
        XCTAssertTrue(lines.withLock { $0 }.contains("libc.prx: the dump has this module as sce_module/libc.prx too, the game is unlocked with that one"))
    }

    func testAUnityGameOnePluginSceModuleHoldsTooCostsTheFolderNoneOfItsOthers() throws {
        let (game, toolkit, root, inputs) = try fixture()
        try add(["Media/Modules/PS5Util.prx", "Media/Plugins/PSN.prx", "Media/Plugins/libfmod.prx", "sce_module/libfmod.prx"], to: game.folder)
        let unlocking = installer(game, toolkit)
        _ = try unlocking.run(root: root)
        XCTAssertEqual(runs(inputs).map { $0.sorted() }, [["Media/Modules/PS5Util.prx", "Media/Plugins/PSN.prx", "eboot.bin", "sce_module/libfmod.prx", "sce_module/libgame.prx"]])
        XCTAssertEqual(moduleDirectories(), [".", "Media/Modules", "Media/Plugins"])
        XCTAssertEqual(unlocking.leftOut, [])
    }

    func testADumpWithoutAModuleInTwoPlacesIsRelinkedAsBeforeEachModuleWhereItIs() throws {
        let (game, toolkit, root, inputs) = try fixture()
        try add(["Media/Modules/Il2cppUserAssemblies.prx", "Media/Plugins/PSN.prx", "decrypted/extra.prx", "top.prx"], to: game.folder)
        XCTAssertEqual(Installer.modules(of: game).map(\.relativePath), Installer.modules(in: game.folder).map(\.relativePath))
        let lines = Locked<[String]>([])
        _ = try installer(game, toolkit, lines: lines).run(root: root)
        XCTAssertEqual(runs(inputs).map { $0.sorted() }, [["Media/Modules/Il2cppUserAssemblies.prx", "Media/Plugins/PSN.prx", "decrypted/extra.prx", "eboot.bin", "sce_module/libgame.prx", "top.prx"]])
        XCTAssertEqual(moduleDirectories(), [".", "Media/Modules", "Media/Plugins", "decrypted"])
        XCTAssertFalse(lines.withLock { $0 }.contains { $0.contains("the dump has this module") })
    }

    func testAModuleInSeveralFoldersTheStandardFoldersCopyElseTheOneNextToTheExecutableElseTheNearest() {
        // A dumper's folder beside sce_module, a backup folder, a copy next to eboot.bin.
        XCTAssertEqual(duplicates(["backup/libc.prx", "decrypted/sce_module/libc.prx", "libc.prx", "sce_module/libc.prx", "sce_module/libSceFios2.sprx"]),
                       ["backup/libc.prx": "sce_module/libc.prx", "decrypted/sce_module/libc.prx": "sce_module/libc.prx", "libc.prx": "sce_module/libc.prx"])
        // sce_module before prx, any standard folder before the rest.
        XCTAssertEqual(duplicates(["Media/Plugins/a.prx", "prx/a.prx", "sce_module/a.prx"]), ["Media/Plugins/a.prx": "sce_module/a.prx", "prx/a.prx": "sce_module/a.prx"])
        XCTAssertEqual(duplicates(["Media/Plugins/a.prx", "prx/a.prx"]), ["Media/Plugins/a.prx": "prx/a.prx"])
        // In no standard folder: next to eboot.bin, then the nearest folder, then the first by name.
        XCTAssertEqual(duplicates(["Media/Plugins/a.prx", "a.prx", "old/a.prx"]), ["Media/Plugins/a.prx": "a.prx", "old/a.prx": "a.prx"])
        XCTAssertEqual(duplicates(["Media/Plugins/a.prx", "old/a.prx"]), ["Media/Plugins/a.prx": "old/a.prx"])
        XCTAssertEqual(duplicates(["Media/Modules/a.prx", "Media/Plugins/a.prx", "Media/Plugins/b.prx"]), ["Media/Plugins/a.prx": "Media/Modules/a.prx"])
        // A module in one place alone stays, wherever it is, and a name is a whole file name.
        XCTAssertEqual(duplicates(["Media/Modules/x.prx", "Media/Plugins/y.prx", "decrypted/sce_module/only.prx", "sce_module/x.sprx", "top.prx"]), [:])
        // Folders the relinker never reads are no one's copy: fakelib, one below sce_module, one
        // with no .prx in it.
        XCTAssertEqual(duplicates(["Media/Other/libc.sprx", "fakelib/libc.prx", "sce_module/libc.prx", "sce_module/old/libc.prx"]), [:])
        // The relinker for the Mac tells names apart with their case.
        XCTAssertEqual(duplicates(["Media/Plugins/LibFmod.prx", "sce_module/libfmod.prx"]), [:])
        // The folders that go to the relinker are those of what is left.
        XCTAssertEqual(Installer.moduleDirectories([URL(fileURLWithPath: "Media/Plugins/a.prx"), URL(fileURLWithPath: "sce_module/libc.prx")]), [".", "Media/Plugins"])
        XCTAssertEqual(Installer.moduleDirectories([URL(fileURLWithPath: "sce_module/libc.prx")]), ["."])
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
