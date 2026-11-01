import XCTest
@testable import AnyPS5Core

/// The commands an update from git runs, answered from a script instead of git and Ninja.
final class FakeCommands: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        let tool: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private(set) var calls: [Call] = []
    var environments: [[String: String]] = []
    /// The answer to a command, by its tool and first argument ("git pull"): exit code and lines.
    var answers: [String: (Int32, [String])] = [:]
    /// Called when a command runs, before it answers (to build the files Ninja would).
    var onRun: ((Call) -> Void)?

    func run(_ executable: URL, _ arguments: [String], in directory: URL, environment: [String: String], cancel: UnpackCancel?, onLine: @escaping (String) -> Void) throws -> Int32 {
        let call = Call(tool: executable.lastPathComponent, arguments: arguments)
        lock.lock()
        calls.append(call)
        environments.append(environment)
        lock.unlock()
        onRun?(call)
        let key = call.tool + " " + (arguments.first ?? "")
        let (code, lines) = answers[key] ?? (0, [])
        lines.forEach(onLine)
        return code
    }
}

final class EngineCheckoutTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-checkout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relative: String, _ text: String = "x", executable: Bool = false) throws {
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path) }
    }

    /// A checkout with a configured build-mac folder; `built` puts a relinker and a library in it.
    private func makeCheckout(built: Bool = true) throws -> EngineCheckout {
        try write("engine/CMakeLists.txt")
        try write("engine/core/relinker/main.cpp")
        try write("engine/core/libs/libc.cpp")
        try write("engine/tools/macos/patches/PPSA01234.json", "{}")
        try write("engine/.git/HEAD", "ref: refs/heads/main")
        try write("engine/build-mac/CMakeCache.txt", "# cache\nCMAKE_COMMAND:INTERNAL=/nowhere/cmake\nCMAKE_MAKE_PROGRAM:FILEPATH=/nowhere/ninja\n")
        if built { try buildFiles("one") }
        return try XCTUnwrap(EngineCheckout.at(root.appendingPathComponent("engine")))
    }

    private func buildFiles(_ contents: String) throws {
        try write("engine/build-mac/core/relinker/relinker", contents, executable: true)
        try write("engine/build-mac/core/libs/libs/libc.prx", contents)
    }

    /// A toolkit the launcher already has, for its Vulkan folder.
    private func makeToolkit() throws -> Toolkit {
        try write("kit/relinker", "r", executable: true)
        try write("kit/libs/libc.prx", "p")
        for name in ["libvulkan.1.dylib", "libMoltenVK.dylib", "MoltenVK_icd.json"] { try write("kit/vulkan/" + name, name) }
        try write("kit/patches/x.json", "{}")
        return Toolkit(root: root.appendingPathComponent("kit"))
    }

    private let tools = DevTools(developer: URL(fileURLWithPath: "/dev"), git: URL(fileURLWithPath: "/tools/git"),
                                 cmake: URL(fileURLWithPath: "/tools/cmake"), ninja: URL(fileURLWithPath: "/tools/ninja"))

    func testACheckoutIsTheEngineSourceAndItsBuildFolderIsFound() throws {
        XCTAssertNil(EngineCheckout.at(root), "an empty folder")
        let checkout = try makeCheckout(built: false)
        XCTAssertEqual(checkout.buildFolder?.lastPathComponent, "build-mac")
        XCTAssertTrue(checkout.isGit)
        XCTAssertFalse(checkout.isBuilt)
        XCTAssertEqual(checkout.cache["CMAKE_MAKE_PROGRAM"], "/nowhere/ninja")
        try buildFiles("one")
        XCTAssertTrue(checkout.isBuilt)
    }

    func testARelinkerOnlyBuildIsPassedOverForOneThatBuildsTheLibraries() throws {
        try write("engine/CMakeLists.txt")
        try write("engine/core/relinker/main.cpp")
        try write("engine/core/libs/libc.cpp")
        try write("engine/tools/macos/patches/a.json", "{}")
        try write("engine/build-relinker/CMakeCache.txt", "ANYPS5_RELINKER_ONLY:BOOL=ON\n")
        XCTAssertNil(EngineCheckout.findBuild(root.appendingPathComponent("engine")))
        try write("engine/build-x86/CMakeCache.txt", "ANYPS5_RELINKER_ONLY:BOOL=OFF\n")
        try write("engine/build-arm/CMakeCache.txt", "ANYPS5_RELINKER_ONLY:BOOL=OFF\n")
        try write("engine/build-x86/core/relinker/relinker", "r", executable: true)
        XCTAssertEqual(EngineCheckout.findBuild(root.appendingPathComponent("engine"))?.lastPathComponent, "build-x86", "the one with a relinker built")
    }

    func testToolsComeFromTheCacheThenPathAndWhatIsMissingIsNamed() throws {
        try write("bin/cmake", "#!/bin/sh", executable: true)
        try write("bin/git", "#!/bin/sh", executable: true)
        try write("other/ninja", "#!/bin/sh", executable: true)
        let found = DevTools.find(cache: ["CMAKE_MAKE_PROGRAM": root.appendingPathComponent("other/ninja").path],
                                  environment: ["PATH": root.appendingPathComponent("bin").path], developer: nil)
        XCTAssertEqual(found.cmake?.lastPathComponent, "cmake")
        XCTAssertEqual(found.ninja?.path, root.appendingPathComponent("other/ninja").path)
        XCTAssertEqual(found.git?.path, root.appendingPathComponent("bin/git").path)
        XCTAssertEqual(found.missing, ["Xcode Command Line Tools"])
        // /usr/bin/git without the Command Line Tools would ask to install them: never used.
        let bare = DevTools.find(environment: ["PATH": "/usr/bin"], developer: nil)
        XCTAssertNil(bare.git)
        XCTAssertEqual(DevTools().missing, ["Xcode Command Line Tools", "Git", "CMake", "Ninja"])
        XCTAssertTrue(tools.path(["PATH": "/usr/bin:/bin"]).hasPrefix("/tools:/dev/usr/bin:/usr/bin"))
        // The Command Line Tools keep clang in usr/bin, Xcode in its default toolchain.
        try write("clt/usr/bin/clang", "#!/bin/sh", executable: true)
        try write("Xcode/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang", "#!/bin/sh", executable: true)
        XCTAssertTrue(DevTools.isDeveloperFolder(root.appendingPathComponent("clt")))
        XCTAssertTrue(DevTools.isDeveloperFolder(root.appendingPathComponent("Xcode")))
        XCTAssertFalse(DevTools.isDeveloperFolder(root.appendingPathComponent("bin")))
    }

    func testAnUpdatePullsBuildsAndMakesAnEngineGamesCanBeUnlockedWith() throws {
        let checkout = try makeCheckout()
        let commands = FakeCommands()
        var heads = ["aaaaaaa1111", "bbbbbbb2222"]
        commands.onRun = { call in
            if call.arguments.first == "rev-parse" { commands.answers["git rev-parse"] = (0, [heads.count > 1 ? heads.removeFirst() : heads[0]]) }
            if call.tool == "ninja" { try? self.buildFiles("two") }
        }
        commands.answers["git describe"] = (0, ["v0.2.29-arm-3-gabcdef1"])
        let git = EngineGit(checkout, tools: tools, runner: commands, environment: ["PATH": "/usr/bin"])
        var steps: [GitStep] = []
        let engines = root.appendingPathComponent("engines")
        let result = try git.update(in: engines, vulkanFrom: try makeToolkit(), onStep: { steps.append($0) })
        XCTAssertEqual(steps, [.checking, .pulling, .submodules, .building, .assembling])
        XCTAssertEqual(commands.calls.map { ([$0.tool] + $0.arguments).joined(separator: " ") }, [
            "git status --porcelain --untracked-files=no", "git rev-parse HEAD", "git pull --ff-only", "git submodule update --init --recursive",
            "ninja -C \(checkout.build.path) relinker libs", "git rev-parse HEAD", "git describe --tags --always",
        ])
        XCTAssertEqual(commands.environments.first?["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(commands.environments.first?["GIT_SSH_COMMAND"], "ssh -o BatchMode=yes")
        XCTAssertTrue(result.pulled)
        XCTAssertNil(Toolkit.layoutProblem(at: result.toolkit.root))
        XCTAssertTrue(result.toolkit.version.hasPrefix("0.2.29-arm-3-gabcdef1-"), result.toolkit.version)
        XCTAssertEqual(try String(contentsOf: result.toolkit.relinker, encoding: .utf8), "two", "the new build's relinker")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.toolkit.patches.appendingPathComponent("PPSA01234.json").path))
        XCTAssertTrue(git.output.contains("$ git pull --ff-only"))
    }

    func testTheSameBuildMakesTheSameEngineAndOldOnesAreCleared() throws {
        let checkout = try makeCheckout()
        let kit = try makeToolkit()
        let engines = root.appendingPathComponent("engines")
        let first = try EngineGit.makeToolkit(from: checkout, vulkanFrom: kit, in: engines, release: "0.2.29-arm")
        let again = try EngineGit.makeToolkit(from: checkout, vulkanFrom: kit, in: engines, release: "0.2.29-arm")
        XCTAssertEqual(first.root.path, again.root.path)
        try buildFiles("changed")
        let next = try EngineGit.makeToolkit(from: checkout, vulkanFrom: kit, in: engines, release: "0.2.29-arm")
        XCTAssertNotEqual(next.version, first.version, "another fingerprint: games made before offer to be unlocked again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.root.path), "kept until cleared: an unlock may use it")
        EngineGit.removeOld(in: engines, keeping: next.root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: next.root.path))
        XCTAssertThrowsError(try EngineGit.makeToolkit(from: checkout, vulkanFrom: nil, in: engines, release: "x"), "no MoltenVK to take")
    }

    func testATreeWithChangesIsNotPulled() throws {
        let commands = FakeCommands()
        commands.answers["git status"] = (0, [" M core/relinker/main.cpp"])
        let git = EngineGit(try makeCheckout(), tools: tools, runner: commands)
        XCTAssertThrowsError(try git.update(in: root.appendingPathComponent("engines"), vulkanFrom: try makeToolkit())) { error in
            XCTAssertEqual((error as? GitUpdateFailure)?.kind, .dirty)
            XCTAssertEqual((error as? GitUpdateFailure)?.untouched, true)
        }
        XCTAssertFalse(commands.calls.contains { $0.arguments.first == "pull" })
    }

    func testFailuresSayWhereTheyStopped() throws {
        let checkout = try makeCheckout()
        let pull = FakeCommands()
        pull.answers["git pull"] = (1, ["fatal: Not possible to fast-forward, aborting."])
        XCTAssertThrowsError(try EngineGit(checkout, tools: tools, runner: pull).update(in: root.appendingPathComponent("e"), vulkanFrom: try makeToolkit())) { error in
            XCTAssertEqual((error as? GitUpdateFailure)?.kind, .pull)
            XCTAssertEqual((error as? GitUpdateFailure)?.tail, ["fatal: Not possible to fast-forward, aborting."])
        }
        let build = FakeCommands()
        build.answers["ninja -C"] = (1, ["FAILED: core/relinker/relinker"])
        XCTAssertThrowsError(try EngineGit(checkout, tools: tools, runner: build).update(in: root.appendingPathComponent("e"), vulkanFrom: try makeToolkit())) { error in
            XCTAssertEqual((error as? GitUpdateFailure)?.kind, .build)
            XCTAssertEqual((error as? GitUpdateFailure)?.untouched, false)
        }
        XCTAssertThrowsError(try EngineGit(checkout, tools: DevTools(git: tools.git), runner: FakeCommands()).update(in: root, vulkanFrom: nil)) { error in
            XCTAssertEqual((error as? GitUpdateFailure)?.kind, .missingTools(["Xcode Command Line Tools", "CMake", "Ninja"]))
        }
        let cancel = UnpackCancel()
        cancel.cancel()
        XCTAssertThrowsError(try EngineGit(checkout, tools: tools, runner: FakeCommands()).update(in: root, vulkanFrom: nil, cancel: cancel)) { error in
            XCTAssertEqual((error as? GitUpdateFailure)?.kind, .cancelled)
        }
    }

    /// An engine made from a real checkout's build, read only:
    /// `ANYPS5_LIVE_CHECKOUT=<AnyPS5-ARM checkout> ANYPS5_LIVE_TOOLKIT=<a toolkit> swift test --filter EngineCheckoutTests`.
    func testAnEngineFromARealCheckoutsBuild() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["ANYPS5_LIVE_CHECKOUT"], let kit = environment["ANYPS5_LIVE_TOOLKIT"] else { throw XCTSkip("no live checkout given") }
        let checkout = try XCTUnwrap(EngineCheckout.at(URL(fileURLWithPath: path)))
        XCTAssertTrue(checkout.isBuilt, "\(checkout.build.path)")
        let tools = DevTools.find(cache: checkout.cache)
        XCTAssertEqual(tools.missing, [])
        let release = EngineGit(checkout, tools: tools).describe()
        let made = try EngineGit.makeToolkit(from: checkout, vulkanFrom: Toolkit(root: URL(fileURLWithPath: kit)), in: root.appendingPathComponent("engines"), release: release)
        XCTAssertNil(Toolkit.layoutProblem(at: made.root))
        XCTAssertTrue(made.version.hasPrefix(release + "-"), made.version)
        print("live engine: \(checkout.build.lastPathComponent) \(made.version) \(Toolkit.shortVersion(made.version))")
    }

    func testTheRealRunnerHandsEveryLineAndTheExitCode() throws {
        var lines: [String] = []
        let code = try SystemCommands().run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo one; echo two >&2; exit 3"], in: root, environment: [:], cancel: nil) { lines.append($0) }
        XCTAssertEqual(code, 3)
        XCTAssertEqual(Set(lines), ["one", "two"])
    }
}
