import XCTest
@testable import AnyPS5Core

/// A player's own relinker options and launch options: how the text splits into words, which
/// relinker options are refused and why, what a rebuild passes, and what a game starts with. The
/// same cases as AnyPS5 Desktop's custom_options_test.dart.
final class CustomOptionsTests: XCTestCase {
    var scratch: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        scratch = fm.temporaryDirectory.appendingPathComponent("custom-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: scratch) }

    func words(_ text: String) -> [String]? { try? OptionWords.split(text).get() }

    func problem<T>(_ result: Result<T, OptionsProblem>) -> OptionsProblem? {
        if case .failure(let problem) = result { return problem }
        return nil
    }

    // MARK: Words

    func testWordsSplitAsAShellWouldWithoutOne() {
        XCTAssertEqual(words(""), [])
        XCTAssertEqual(words("  \t\n "), [])
        XCTAssertEqual(words("--a  --b\t--c\n--d"), ["--a", "--b", "--c", "--d"])
        XCTAssertEqual(words("'a b' \"c d\""), ["a b", "c d"])
        XCTAssertEqual(words("--a=\"b c\"x"), ["--a=b cx"], "quoted parts join the word they touch")
        XCTAssertEqual(words(#"'it\s' "say \"hi\" \\ \n""#), [#"it\s"#, #"say "hi" \ \n"#], "single quotes keep everything, double quotes only \\\" and \\\\")
        XCTAssertEqual(words(#"a\ b \$HOME"#), ["a b", "$HOME"], "a backslash takes the next character as it is, and nothing is expanded")
        XCTAssertEqual(words(#"end\"#), [#"end\"#], "a backslash at the end stays")
        XCTAssertEqual(words("'' \"\""), ["", ""])
        XCTAssertEqual(words("$(rm -rf ~) `x` ; |"), ["$(rm", "-rf", "~)", "`x`", ";", "|"], "no shell ever runs it")
    }

    func testAnOpenQuoteIsAProblem() {
        XCTAssertEqual(problem(OptionWords.split("'abc")), .openQuote)
        XCTAssertEqual(problem(OptionWords.split("--a \"b")), .openQuote)
        XCTAssertEqual(problem(OptionWords.split(#""a\""#)), .openQuote)
    }

    // MARK: Relinker options

    func testTheOptionsLeftToThePlayerPass() {
        XCTAssertEqual(try CustomRelinkerOptions.check("").get(), [])
        let text = "--lazy-binding --skip-syscall-check unused-filter=1 --exclude-sce-module 'libfoo bar.prx' --macos-fixed-base 0x10000000 --registry"
        XCTAssertEqual(try CustomRelinkerOptions.check(text).get(),
                       ["--lazy-binding", "--skip-syscall-check", "unused-filter=1", "--exclude-sce-module", "libfoo bar.prx", "--macos-fixed-base", "0x10000000", "--registry"])
        for option in CustomRelinkerOptions.plain { XCTAssertNotNil(try? CustomRelinkerOptions.check(option).get(), option) }
        for filter in CustomRelinkerOptions.unusedFilters { XCTAssertNotNil(try? CustomRelinkerOptions.check(filter).get(), filter) }
    }

    func testWhatTheLauncherChoosesOrWhatBreaksTheGameIsRefused() {
        for option in ["--windows", "--windows-gui", "--macos", "--to-intel", "--to-rosetta", "--sce-module-path", "--module-dir", "--executable", "--rpath", "--patches", "--no-patches"] {
            XCTAssertEqual(problem(CustomRelinkerOptions.check("--lazy-binding \(option) x")), .launcherOption(option))
        }
        for option in ["--skip-sce-module", "--dry-run", "--autorun", "--verify-patches", "--verify-output", "--help", "--version"] {
            XCTAssertEqual(problem(CustomRelinkerOptions.check(option)), .breaksGame(option))
        }
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--trace-imports")), .hasSwitch("--trace-imports"))
    }

    func testUnknownOptionsMissingValuesAndFilesAreRefused() {
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--registry --made-up")), .unknown("--made-up"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("unused-filter=3")), .unknown("unused-filter=3"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("unused-filter")), .unknown("unused-filter"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--exclude-sce-module")), .needsValue("--exclude-sce-module"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--macos-fixed-base --registry")), .needsValue("--macos-fixed-base"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--exclude-sce-module ''")), .needsValue("--exclude-sce-module"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("other.elf")), .positional("other.elf"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--registry -- x")), .positional("--"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("-v")), .positional("-v"))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("''")), .positional("\"\""))
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--dry-run --windows")), .breaksGame("--dry-run"), "the first problem from the left")
        XCTAssertEqual(problem(CustomRelinkerOptions.check("--registry 'x")), .openQuote)
    }

    /// Every option the relinker's usage text lists is sorted into one of the lists, and the
    /// lists name nothing it no longer has: a new relinker option has to be placed here.
    func testEveryOptionOfTheRelinkerIsPlaced() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent("core/relinker/cli/src/CliArgs.cpp"), encoding: .utf8)
        let usage = try XCTUnwrap(source.range(of: "const char* Usage()").map { source[$0.lowerBound...] }?.prefix { $0 != "}" })
        let listed = Set(try NSRegularExpression(pattern: #""  (--[a-z][a-z0-9-]*)"#).matches(in: String(usage), range: NSRange(usage.startIndex..., in: usage))
            .map { String(usage[Range($0.range(at: 1), in: usage)!]) })
        XCTAssertTrue(listed.contains("--macos") && listed.contains("--trace-imports"), "the usage text was read: \(listed.sorted())")
        let placed = CustomRelinkerOptions.launcherOwned.union(CustomRelinkerOptions.breaking).union(CustomRelinkerOptions.switched)
            .union(CustomRelinkerOptions.withValue).union(CustomRelinkerOptions.plain)
        XCTAssertEqual(listed.subtracting(placed).sorted(), [], "relinker options no list holds")
        XCTAssertEqual(placed.subtracting(listed).sorted(), [], "listed options the relinker does not have")
        XCTAssertTrue(usage.contains("unused-filter=0") && usage.contains("unused-filter=2"))
    }

    // MARK: Launch options

    func testLaunchOptionsAreVariablesFirstThenArguments() throws {
        let options = try LaunchOptions.parse("APS5_REPORT=0 _X='a b' EMPTY= --aps5-report=off LATER=1 'two words'").get()
        XCTAssertEqual(options.variables.map(\.name), ["APS5_REPORT", "_X", "EMPTY"])
        XCTAssertEqual(options.variables.map(\.value), ["0", "a b", ""])
        XCTAssertEqual(options.arguments, ["--aps5-report=off", "LATER=1", "two words"], "a NAME=value after the first argument is an argument")
        XCTAssertEqual(try LaunchOptions.parse("1A=2 x").get().arguments, ["1A=2", "x"], "not a variable name")
        XCTAssertEqual(try LaunchOptions.parse("A=b=c").get().variables.map(\.value), ["b=c"])
        XCTAssertTrue(try LaunchOptions.parse("").get().isEmpty)
        XCTAssertEqual(problem(LaunchOptions.parse("A='b")), .openQuote)
    }

    func testTheLaunchersOwnValueWins() throws {
        let options = try LaunchOptions.parse("ANYPS5_FULLSCREEN=0 MINE=1 VK_DRIVER_FILES=/x").get()
        let launcher = ["ANYPS5_FULLSCREEN": "1", "ANYPS5_LANGUAGE": "1"]
        let environment = options.environment(under: launcher, reserved: Installer.launchScriptVariables)
        XCTAssertEqual(environment, ["ANYPS5_FULLSCREEN": "1", "ANYPS5_LANGUAGE": "1", "MINE": "1"])
        XCTAssertEqual(options.overridden(by: launcher, reserved: Installer.launchScriptVariables), ["ANYPS5_FULLSCREEN", "VK_DRIVER_FILES"])
        XCTAssertEqual(options.environment(under: launcher), ["ANYPS5_FULLSCREEN": "1", "ANYPS5_LANGUAGE": "1", "MINE": "1", "VK_DRIVER_FILES": "/x"])
    }

    func testTheLaunchScriptPassesTheArgumentsOn() {
        // The variables a launch option cannot change are the ones the script sets itself.
        let script = Installer.launchHead(identifier: "x") + Installer.asyncSubmits
        for name in Installer.launchScriptVariables { XCTAssertTrue(script.contains("export \(name)=\"${\(name):-"), name) }
    }

    // MARK: Settings

    func testOnlyACheckedTextIsSavedAndReadBack() throws {
        var settings = GameSettings()
        XCTAssertNil(settings.setCustomRelinkerOptions("--lazy-binding"))
        XCTAssertEqual(settings.customRelinkerOptions, "--lazy-binding")
        XCTAssertEqual(settings.setCustomRelinkerOptions("--macos"), .launcherOption("--macos"))
        XCTAssertEqual(settings.customRelinkerOptions, "--lazy-binding", "nothing saved")
        XCTAssertNil(settings.setLaunchOptions("A=1 --x"))
        XCTAssertEqual(settings.setLaunchOptions("A='1"), .openQuote)
        XCTAssertEqual(settings.launchOptions, "A=1 --x")
        XCTAssertEqual(settings.chosenRelinkerOptions, ["--lazy-binding"])
        XCTAssertEqual(settings.chosenLaunchOptions.arguments, ["--x"])

        let restored = try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
        let shared = try SharedSettings.read(SharedSettings(game: Game(folder: scratch, titleID: "PPSA00001", name: "G", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf), settings: settings).data())
        XCTAssertEqual(shared.settings.customRelinkerOptions, "--lazy-binding", "an exported file carries them")
        XCTAssertEqual(shared.settings.launchOptions, "A=1 --x")

        XCTAssertNil(settings.setCustomRelinkerOptions("  "))
        XCTAssertNil(settings.customRelinkerOptions, "blank is none")
        XCTAssertNil(settings.setLaunchOptions(""))
        XCTAssertNil(settings.launchOptions)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains("Options"))
    }

    func testAFileWithAnOptionThatDoesNotPassHasNone() throws {
        let json = #"{"overlay":"off","customRelinkerOptions":"--rpath /tmp/evil","launchOptions":"A='open"}"#
        let settings = try JSONDecoder().decode(GameSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.customRelinkerOptions)
        XCTAssertNil(settings.launchOptions)
        let odd = #"{"overlay":"off","customRelinkerOptions":["--registry"],"launchOptions":3}"#
        XCTAssertNil(try JSONDecoder().decode(GameSettings.self, from: Data(odd.utf8)).customRelinkerOptions)
    }

    // MARK: A rebuild

    /// A dump, a games folder and a toolkit whose relinker writes each run's arguments, one per
    /// line, ending the run with a blank line. `refuses` makes it stop on that word as the real
    /// one stops on an option it refuses.
    func fixture(refuses: String? = nil) throws -> (game: Game, toolkit: Toolkit, root: URL, runs: URL) {
        let dump = scratch.appendingPathComponent("dump")
        try fm.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data("\u{7F}ELF executable".utf8).write(to: dump.appendingPathComponent("eboot.bin"))
        let root = scratch.appendingPathComponent("games")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let toolkitFolder = try FakeToolkit.make(in: scratch)
        let runs = scratch.appendingPathComponent("runs.txt")
        var script = "#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"\(runs.path)\"\necho >> \"\(runs.path)\"\n"
        if let refuses {
            script += "for argument; do if [ \"$argument\" = \"\(refuses)\" ]; then echo 'FAIL: \(refuses) conflicts' >&2; exit 1; fi; done\n"
        }
        script += """
        for argument; do last="$argument"; done
        mkdir -p "$(dirname "$last")"
        echo relinked > "$last"

        """
        try Data(script.utf8).write(to: toolkitFolder.appendingPathComponent("relinker"))
        let game = Game(folder: dump, titleID: "PPSA00001", name: "Test", version: "1.0", icon: nil, background: nil, music: nil, executable: .elf)
        return (game, Toolkit(root: toolkitFolder), root, runs)
    }

    func runs(_ file: URL) -> [[String]] {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "\n\n").filter { !$0.isEmpty }.map { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
    }

    func unlock(_ game: Game, _ toolkit: Toolkit, _ root: URL, custom: [String]) throws -> (bundle: URL, log: [String]) {
        let lines = Locked<[String]>([])
        let installer = Installer(game: game, toolkit: toolkit, progress: { _, _ in }, log: { line in lines.withLock { $0.append(line) } })
        installer.customRelinkerOptions = custom
        let bundle = try installer.run(root: root)
        return (bundle, lines.withLock { $0 })
    }

    func testARebuildPassesThemAfterTheLaunchersOwnAndRecordsThem() throws {
        let (game, toolkit, root, runs) = try fixture()
        let custom = try CustomRelinkerOptions.check("--lazy-binding --exclude-sce-module 'lib a.prx'").get()
        let first = try unlock(game, toolkit, root, custom: custom)
        let arguments = try XCTUnwrap(self.runs(runs).first)
        XCTAssertEqual(Array(arguments.prefix(2)), ["--macos", "--to-rosetta"])
        XCTAssertEqual(Array(arguments.dropLast(2).suffix(3)), ["--lazy-binding", "--exclude-sce-module", "lib a.prx"], "after the launcher's options, a word with a space kept whole")
        XCTAssertEqual(arguments.suffix(2).first, "eboot.bin", "before the files")
        XCTAssertEqual(Installer.record(of: first.bundle)?.customRelinkerOptions, custom)

        XCTAssertNotNil(Installer.plan(game: game, toolkit: toolkit, root: root, customRelinkerOptions: custom).keptRelink, "the same options reuse the kept output")
        XCTAssertNil(Installer.plan(game: game, toolkit: toolkit, root: root).keptRelink, "other options relink")
        _ = try unlock(game, toolkit, root, custom: custom)
        XCTAssertEqual(self.runs(runs).count, 1)
        let without = try unlock(game, toolkit, root, custom: [])
        XCTAssertEqual(self.runs(runs).count, 2)
        XCTAssertNil(Installer.record(of: without.bundle)?.customRelinkerOptions)
    }

    func testARelinkerThatRefusesThemRunsAgainWithoutThemAndTheGameIsUnlocked() throws {
        let (game, toolkit, root, runs) = try fixture(refuses: "--lazy-binding")
        let result = try unlock(game, toolkit, root, custom: ["--lazy-binding"])
        XCTAssertEqual(self.runs(runs).map { $0.contains("--lazy-binding") }, [true, false])
        XCTAssertTrue(fm.fileExists(atPath: result.bundle.appendingPathComponent("Contents/MacOS/eboot").path))
        XCTAssertNil(Installer.record(of: result.bundle)?.customRelinkerOptions, "what it was really made with")
        XCTAssertTrue(result.log.contains { $0.contains("the relinker stopped with --lazy-binding") && $0.contains("the game is rebuilt without it") })
    }

    // MARK: Reports

    func testTheReportSaysThem() {
        var settings = GameSettings()
        XCTAssertFalse(settings.reportSummary.contains("Custom relinker options"))
        XCTAssertFalse(settings.reportSummary.contains("Launch options"))
        settings.setCustomRelinkerOptions("--lazy-binding")
        settings.setLaunchOptions("A=1 --x")
        XCTAssertTrue(settings.reportSummary.contains("Custom relinker options --lazy-binding"))
        XCTAssertTrue(settings.reportSummary.contains("Launch options A=1 --x"))

        var report = SessionReport(gameName: "G", titleID: "PPSA00001", gameVersion: "1.0", settings: settings,
                                   system: SystemInfo(model: "m", chip: "c", memoryGB: 8, macOS: "15", displayHz: nil), launcherVersion: "0.2",
                                   session: "", privacy: ReportPrivacy(home: "/nowhere"))
        XCTAssertFalse(report.text().contains("Custom relinker options the game was unlocked with"))
        report.customRelinkerOptions = ["--lazy-binding"]
        XCTAssertTrue(report.text().contains("Custom relinker options the game was unlocked with: --lazy-binding\n"))
    }
}
