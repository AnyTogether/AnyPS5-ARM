import Foundation

/// A git checkout of AnyPS5-ARM chosen as the engine folder, built in place with CMake and Ninja
/// (docs/dev/MACOS_PORT.md):
///
///     <checkout>/
///         CMakeLists.txt, core/relinker/, core/libs/, tools/macos/patches/, .git
///         build-mac/                  the configured build folder (CMakeCache.txt)
///             core/relinker/relinker
///             core/libs/libs/*.prx
///
/// The launcher's engine is a toolkit folder (Toolkit): the build's relinker and libraries, the
/// checkout's patches, and the Vulkan loader with MoltenVK (patched) taken from a toolkit the
/// launcher already has. AnyLauncher Port's engine_checkout.dart, on the Mac.
public struct EngineCheckout: Sendable {
    public let root: URL
    /// The configured build folder, nil before CMake set one up.
    public let buildFolder: URL?

    /// The checkout at `root`, nil when the folder is not AnyPS5-ARM's source tree.
    public static func at(_ root: URL) -> EngineCheckout? {
        let fileManager = FileManager.default
        for part in ["CMakeLists.txt", "core/relinker", "core/libs", "tools/macos/patches"] where !fileManager.fileExists(atPath: root.appendingPathComponent(part).path) {
            return nil
        }
        return EngineCheckout(root: root, buildFolder: findBuild(root))
    }

    /// The configured build folder of `root` that builds the libraries: build-mac/ (as the Mac
    /// guide sets it up), else build/, else another folder at the top (build-*, cmake-build-*)
    /// with a CMakeCache.txt, one with the relinker built first. A relinker-only build has no
    /// libraries to build, so it is passed over. Nil when none was configured yet.
    public static func findBuild(_ root: URL) -> URL? {
        let fileManager = FileManager.default
        func usable(_ folder: URL) -> Bool {
            guard let cache = try? String(contentsOf: folder.appendingPathComponent("CMakeCache.txt"), encoding: .utf8) else { return false }
            return !cache.contains("ANYPS5_RELINKER_ONLY:BOOL=ON")
        }
        func built(_ folder: URL) -> Bool { fileManager.isExecutableFile(atPath: folder.appendingPathComponent("core/relinker/relinker").path) }
        for name in ["build-mac", "build"] where usable(root.appendingPathComponent(name)) { return root.appendingPathComponent(name) }
        let others = ((try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { folder in
                let name = folder.lastPathComponent.lowercased()
                return name.hasPrefix("build") || name.hasPrefix("cmake-build")
            }
            .filter(usable)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return others.first(where: built) ?? others.first
    }

    /// The build folder the relinker and the libraries come from (build-mac/ before one is configured).
    public var build: URL { buildFolder ?? root.appendingPathComponent("build-mac") }

    /// `cmake -S . -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64`:
    /// the setup the Mac guide (docs/dev/MACOS_PORT.md) runs once, which Update from Git runs for a
    /// checkout without a build folder.
    public static let configureArguments = ["-S", ".", "-B", "build-mac", "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_ARCHITECTURES=x86_64"]
    public var relinker: URL { build.appendingPathComponent("core/relinker/relinker") }
    public var libraries: URL { build.appendingPathComponent("core/libs/libs") }
    public var patches: URL { root.appendingPathComponent("tools/macos/patches") }

    /// Whether the folder is a git checkout (.git is a folder, or a file in a worktree).
    public var isGit: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) }

    /// Whether the build has a relinker and libraries to make an engine from.
    public var isBuilt: Bool {
        FileManager.default.isExecutableFile(atPath: relinker.path)
            && ((try? FileManager.default.contentsOfDirectory(atPath: libraries.path)) ?? []).contains { $0.hasSuffix(".prx") }
    }

    /// The build folder's CMakeCache.txt entries (NAME:TYPE=value).
    public var cache: [String: String] {
        guard let folder = buildFolder, let text = try? String(contentsOf: folder.appendingPathComponent("CMakeCache.txt"), encoding: .utf8) else { return [:] }
        var entries: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("//") {
            guard let colon = line.firstIndex(of: ":"), let equals = line.firstIndex(of: "="), colon < equals, colon != line.startIndex else { continue }
            entries[String(line[..<colon])] = String(line[line.index(after: equals)...])
        }
        return entries
    }
}

/// The developer tools an update from git needs, found without starting anything that would ask
/// to install them (/usr/bin/git without the Command Line Tools opens Apple's installer).
public struct DevTools: Equatable, Sendable {
    /// The developer folder `xcode-select -p` names (the Command Line Tools or Xcode), nil when
    /// there is none.
    public var developer: URL?
    public var git: URL?
    public var cmake: URL?
    public var ninja: URL?

    public init(developer: URL? = nil, git: URL? = nil, cmake: URL? = nil, ninja: URL? = nil) {
        self.developer = developer
        self.git = git
        self.cmake = cmake
        self.ninja = ninja
    }

    /// What is missing, by the names people install them by.
    public var missing: [String] {
        var names: [String] = []
        if developer == nil { names.append("Xcode Command Line Tools") }
        if git == nil { names.append("Git") }
        if cmake == nil { names.append("CMake") }
        if ninja == nil { names.append("Ninja") }
        return names
    }

    /// Where Homebrew and the CMake app put their tools: an app opened from the Finder has a short
    /// PATH without them.
    public static let extraFolders = ["/opt/homebrew/bin", "/usr/local/bin", "/Applications/CMake.app/Contents/bin"]

    /// The tools on this Mac: the ones the build's CMakeCache.txt names first, then PATH and the
    /// usual folders.
    public static func find(cache: [String: String] = [:], environment: [String: String] = ProcessInfo.processInfo.environment,
                            developer: URL? = DevTools.developerFolder()) -> DevTools {
        let fileManager = FileManager.default
        let folders = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + extraFolders
        func search(_ name: String, hint: String? = nil, skipping skipped: Set<String> = []) -> URL? {
            if let hint, !hint.isEmpty, fileManager.isExecutableFile(atPath: hint) { return URL(fileURLWithPath: hint) }
            for folder in folders where !skipped.contains(folder) {
                let candidate = URL(fileURLWithPath: folder).appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
            }
            return nil
        }
        // The git in /usr/bin is a stub that asks for the Command Line Tools: only with them.
        let developerGit = developer.map { $0.appendingPathComponent("usr/bin/git") }.flatMap { fileManager.isExecutableFile(atPath: $0.path) ? $0 : nil }
        let git = developerGit ?? search("git", skipping: ["/usr/bin"])
        return DevTools(developer: developer, git: git, cmake: search("cmake", hint: cache["CMAKE_COMMAND"]), ninja: search("ninja", hint: cache["CMAKE_MAKE_PROGRAM"]))
    }

    /// `xcode-select -p`'s folder when it is there, without asking to install anything.
    public static func developerFolder() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, isDeveloperFolder(URL(fileURLWithPath: path)) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Whether `folder` has a compiler: the Command Line Tools keep clang in usr/bin, Xcode in its
    /// default toolchain.
    public static func isDeveloperFolder(_ folder: URL) -> Bool {
        ["usr/bin/clang", "Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"].contains {
            FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// PATH for the build: the tools' folders first (Ninja runs CMake again when the build files
    /// changed, and the compilers come from the developer folder).
    public func path(_ environment: [String: String]) -> String {
        var folders: [String] = []
        let found = [cmake, ninja, git].compactMap { $0?.deletingLastPathComponent().path } + [developer.map { $0.path + "/usr/bin" }].compactMap { $0 }
        for folder in found where !folders.contains(folder) { folders.append(folder) }
        folders += (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init).filter { !folders.contains($0) }
        return folders.joined(separator: ":")
    }
}

/// Runs a program away from the interface and hands each line it prints (stdout and stderr);
/// replaceable in tests.
public protocol CommandRunner: Sendable {
    /// Runs `executable` in `directory` and returns its exit code. Throws when it cannot start;
    /// `cancel` stops it and its children.
    func run(_ executable: URL, _ arguments: [String], in directory: URL, environment: [String: String], cancel: UnpackCancel?, onLine: @escaping (String) -> Void) throws -> Int32
}

/// Foundation's processes, stopped with their children (Ninja leaves the compilers to their own).
public struct SystemCommands: CommandRunner {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String], in directory: URL, environment: [String: String], cancel: UnpackCancel?, onLine: @escaping (String) -> Void) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let reader = pipe.fileHandleForReading
        let watch = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        watch.schedule(deadline: .now() + 0.3, repeating: 0.3)
        watch.setEventHandler {
            guard cancel?.cancelled == true, process.isRunning else { return }
            let children = Process()
            children.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            children.arguments = ["-TERM", "-P", "\(process.processIdentifier)"]
            try? children.run()
            children.waitUntilExit()
            process.terminate()
        }
        watch.resume()
        defer { watch.cancel() }
        var pending = Data()
        while true {
            let data = reader.availableData
            if data.isEmpty { break }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                onLine(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// The steps of an update from git.
public enum GitStep: Equatable, Sendable { case checking, pulling, submodules, configuring, building, assembling }

/// Why an update from git stopped.
public enum GitFailureKind: Equatable, Sendable {
    /// A tool it needs is not on this Mac (DevTools.missing).
    case missingTools([String])
    /// The folder is not a git checkout.
    case notGit
    /// The tree has changes not committed: nothing was pulled.
    case dirty
    /// CMake never configured a build folder (no longer said: the update sets one up).
    case noBuild
    /// CMake could not set up the build folder (a library or tool it looks for is missing).
    case configure
    /// git pull --ff-only failed (the branch went another way, no upstream, offline).
    case pull
    /// git submodule update failed.
    case submodules
    /// The build failed.
    case build
    /// The build's files could not be made into an engine (no toolkit to take MoltenVK from).
    case toolkit
    /// Stopped by the user.
    case cancelled
}

public struct GitUpdateFailure: Error, Equatable {
    public let kind: GitFailureKind
    /// The last lines the failing command printed.
    public let tail: [String]

    public init(_ kind: GitFailureKind, _ tail: [String] = []) {
        self.kind = kind
        self.tail = tail
    }

    /// Whether nothing was changed: the tree and the build are as they were.
    public var untouched: Bool { kind != .submodules && kind != .build && kind != .toolkit }

    /// Whether the build guide says how to put it right (a tool to install, CMake's setup).
    public var guideHelps: Bool {
        switch kind {
        case .missingTools, .configure: return true
        default: return false
        }
    }
}

/// What an update from git did: the commit before and after, and the engine it made.
public struct GitUpdateResult: Sendable {
    public let before: String
    public let after: String
    public let toolkit: Toolkit
    public var pulled: Bool { before != after }
}

/// Pulls an engine checkout, builds its relinker and libraries and makes an engine of them:
/// `git pull --ff-only`, `git submodule update --init --recursive`, `ninja -C <build> relinker
/// libs`. Refuses a tree with changes not committed. A checkout without a build folder gets one
/// first, as the Mac guide sets it up (EngineCheckout.configureArguments), as on Windows and Linux.
public final class EngineGit: @unchecked Sendable {
    public let checkout: EngineCheckout
    public let tools: DevTools
    private let runner: CommandRunner
    private let environment: [String: String]

    /// The most lines kept of what the commands printed, and the lines a failure keeps.
    public static let keptLines = 400
    public static let tailLines = 40

    /// What the commands printed, the last `keptLines`.
    public private(set) var output: [String] = []

    public init(_ checkout: EngineCheckout, tools: DevTools, runner: CommandRunner = SystemCommands(), environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.checkout = checkout
        self.tools = tools
        self.runner = runner
        self.environment = environment
    }

    /// git asks nothing on a terminal the launcher does not have: a remote that wants a password
    /// fails instead of waiting forever.
    var commandEnvironment: [String: String] {
        var values = environment
        values["PATH"] = tools.path(environment)
        values["GIT_TERMINAL_PROMPT"] = "0"
        if environment["GIT_SSH_COMMAND"] == nil, environment["GIT_SSH"] == nil { values["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes" }
        return values
    }

    private func keep(_ line: String) {
        output.append(line)
        if output.count > EngineGit.keptLines { output.removeFirst(output.count - EngineGit.keptLines) }
    }

    private static func tail(_ lines: [String]) -> [String] { Array(lines.suffix(tailLines)) }

    /// One command; its exit code and lines.
    private func run(_ tool: URL?, _ arguments: [String], quiet: Bool = false, cancel: UnpackCancel?, onLine: ((String) -> Void)? = nil) throws -> (Int32, [String]) {
        if cancel?.cancelled == true { throw GitUpdateFailure(.cancelled) }
        guard let tool else { throw GitUpdateFailure(.missingTools(tools.missing)) }
        if !quiet { keep("$ \(tool.lastPathComponent) \(arguments.joined(separator: " "))") }
        var lines: [String] = []
        let code: Int32
        do {
            code = try runner.run(tool, arguments, in: checkout.root, environment: commandEnvironment, cancel: cancel) { line in
                lines.append(line)
                guard !quiet else { return }
                self.keep(line)
                onLine?(line)
            }
        } catch let failure as GitUpdateFailure {
            throw failure
        } catch {
            throw GitUpdateFailure(.missingTools(tools.missing.isEmpty ? [tool.lastPathComponent] : tools.missing), [error.localizedDescription])
        }
        if cancel?.cancelled == true { throw GitUpdateFailure(.cancelled, EngineGit.tail(lines)) }
        return (code, lines)
    }

    private func head(_ cancel: UnpackCancel?) throws -> String {
        let (code, lines) = try run(tools.git, ["rev-parse", "HEAD"], quiet: true, cancel: cancel)
        guard code == 0 else { throw GitUpdateFailure(.notGit, EngineGit.tail(lines)) }
        return lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// `git describe --tags --always` without its v: the release version build_launcher_app.sh
    /// gives a toolkit (0.2.29-arm, or a longer form between releases).
    public func describe(_ cancel: UnpackCancel? = nil) -> String {
        guard let result = try? run(tools.git, ["describe", "--tags", "--always"], quiet: true, cancel: cancel), result.0 == 0,
              let first = result.1.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return "git" }
        return first.hasPrefix("v") ? String(first.dropFirst()) : first
    }

    /// Whether the remote has commits the checkout lacks (`git fetch`, then `HEAD..@{u}`), or the
    /// checkout is not at `built` (pulled by hand since the launcher last built it). nil when it
    /// cannot tell (offline, no upstream branch, no git) or `timeout` seconds passed. As AnyPS5
    /// Desktop's needsUpdate, for Update from Git Before Playing.
    public func needsUpdate(built: String?, timeout: TimeInterval = 20) -> Bool? {
        let cancel = UnpackCancel()
        let timer = DispatchWorkItem { cancel.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
        defer { timer.cancel() }
        do {
            let (fetchCode, _) = try run(tools.git, ["fetch", "--quiet"], quiet: true, cancel: cancel)
            guard fetchCode == 0 else { return nil }
            let (countCode, count) = try run(tools.git, ["rev-list", "--count", "HEAD..@{u}"], quiet: true, cancel: cancel)
            guard countCode == 0,
                  let behind = count.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }).flatMap({ Int($0) }) else { return nil }
            if behind > 0 { return true }
            guard let built else { return false }
            let now = try head(cancel)
            return !now.isEmpty && now != built
        } catch {
            return nil
        }
    }

    /// Pulls, builds and makes the engine in `folder` (its Vulkan folder copied from `vulkanFrom`, a
    /// toolkit the launcher has); `onStep` and `onLine` say how far it is. Throws GitUpdateFailure.
    public func update(in folder: URL, vulkanFrom: Toolkit?, cancel: UnpackCancel? = nil, onStep: ((GitStep) -> Void)? = nil, onLine: ((String) -> Void)? = nil) throws -> GitUpdateResult {
        output.removeAll()
        onStep?(.checking)
        if !tools.missing.isEmpty { throw GitUpdateFailure(.missingTools(tools.missing)) }
        guard checkout.isGit else { throw GitUpdateFailure(.notGit) }
        let (statusCode, changes) = try run(tools.git, ["status", "--porcelain", "--untracked-files=no"], quiet: true, cancel: cancel)
        guard statusCode == 0 else { throw GitUpdateFailure(.notGit, EngineGit.tail(changes)) }
        let changed = changes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !changed.isEmpty { throw GitUpdateFailure(.dirty, EngineGit.tail(changed)) }
        let before = try head(cancel)

        onStep?(.pulling)
        let (pullCode, pullLines) = try run(tools.git, ["pull", "--ff-only"], cancel: cancel, onLine: onLine)
        guard pullCode == 0 else { throw GitUpdateFailure(.pull, EngineGit.tail(pullLines)) }

        onStep?(.submodules)
        let (subCode, subLines) = try run(tools.git, ["submodule", "update", "--init", "--recursive"], cancel: cancel, onLine: onLine)
        guard subCode == 0 else { throw GitUpdateFailure(.submodules, EngineGit.tail(subLines)) }

        var configured = checkout
        if checkout.buildFolder == nil {
            onStep?(.configuring)
            let made = checkout.build
            let existed = FileManager.default.fileExists(atPath: made.path)
            do {
                let (configureCode, configureLines) = try run(tools.cmake, EngineCheckout.configureArguments, cancel: cancel, onLine: onLine)
                guard configureCode == 0 else { throw GitUpdateFailure(.configure, EngineGit.tail(configureLines)) }
            } catch {
                // A setup that stopped half way leaves no cache behind to be taken for a build folder.
                if existed {
                    try? FileManager.default.removeItem(at: made.appendingPathComponent("CMakeCache.txt"))
                } else {
                    try? FileManager.default.removeItem(at: made)
                }
                throw error
            }
            configured = EngineCheckout.at(checkout.root) ?? checkout
        }

        onStep?(.building)
        let (buildCode, buildLines) = try run(tools.ninja, ["-C", configured.build.path, "relinker", "libs"], cancel: cancel, onLine: onLine)
        guard buildCode == 0 else { throw GitUpdateFailure(.build, EngineGit.tail(buildLines)) }

        onStep?(.assembling)
        let after = try head(cancel)
        let toolkit: Toolkit
        do {
            toolkit = try EngineGit.makeToolkit(from: configured, vulkanFrom: vulkanFrom, in: folder, release: describe(cancel))
        } catch {
            keep(error.localizedDescription)
            throw GitUpdateFailure(.toolkit, [error.localizedDescription])
        }
        return GitUpdateResult(before: before, after: after, toolkit: toolkit)
    }

    /// The engine (a toolkit folder, as tools/macos/toolkit_layout.sh lays one out) made from the
    /// checkout's build in a folder of its own in `folder`, named by its version: the build's
    /// relinker and libraries, the checkout's patches, and the Vulkan folder of `vulkanFrom`.
    /// version.txt is "<release>-<fingerprint>" as the build script writes it, so games made with
    /// an earlier build offer to be unlocked again. An engine made before stays where it is (a game
    /// being unlocked with it keeps its files) until `removeOld` clears it.
    public static func makeToolkit(from checkout: EngineCheckout, vulkanFrom: Toolkit?, in folder: URL, release: String) throws -> Toolkit {
        let fileManager = FileManager.default
        guard checkout.isBuilt else { throw InstallError("the build has no relinker and libraries yet") }
        guard let vulkanFrom, fileManager.fileExists(atPath: vulkanFrom.vulkan.appendingPathComponent("libMoltenVK.dylib").path) else {
            throw InstallError("no engine to take the Vulkan loader and MoltenVK from")
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let fresh = folder.appendingPathComponent(".new-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: fresh.appendingPathComponent("libs"), withIntermediateDirectories: true)
            try fileManager.copyItem(at: checkout.relinker, to: fresh.appendingPathComponent("relinker"))
            for name in try fileManager.contentsOfDirectory(atPath: checkout.libraries.path).sorted() where name.hasSuffix(".prx") {
                try fileManager.copyItem(at: checkout.libraries.appendingPathComponent(name), to: fresh.appendingPathComponent("libs/" + name))
            }
            try fileManager.copyItem(at: vulkanFrom.vulkan, to: fresh.appendingPathComponent("vulkan"))
            try fileManager.createDirectory(at: fresh.appendingPathComponent("patches"), withIntermediateDirectories: true)
            for name in try fileManager.contentsOfDirectory(atPath: checkout.patches.path).sorted() where name.hasSuffix(".json") {
                try fileManager.copyItem(at: checkout.patches.appendingPathComponent(name), to: fresh.appendingPathComponent("patches/" + name))
            }
            guard let fingerprint = Toolkit.fingerprint(of: fresh) else { throw InstallError("the engine's files cannot be read") }
            let version = "\(release)-\(fingerprint)"
            try Data((version + "\n").utf8).write(to: fresh.appendingPathComponent("version.txt"))
            if let problem = Toolkit.layoutProblem(at: fresh) { throw InstallError(problem) }
            let name = String(version.map { $0.isLetter || $0.isNumber || "-._+".contains($0) ? $0 : "-" })
            let final = folder.appendingPathComponent(name)
            if fileManager.fileExists(atPath: final.path), Toolkit.layoutProblem(at: final) == nil {
                // The same files as an engine made before: that one is used.
                try? fileManager.removeItem(at: fresh)
            } else {
                try? fileManager.removeItem(at: final)
                try fileManager.moveItem(at: fresh, to: final)
            }
            return Toolkit(root: final)
        } catch {
            try? fileManager.removeItem(at: fresh)
            throw error
        }
    }

    /// The engines `makeToolkit` made in `folder` before, all but `keeping`, and what a stopped one
    /// left half made.
    public static func removeOld(in folder: URL, keeping: URL?) {
        let fileManager = FileManager.default
        let kept = keeping?.standardizedFileURL.path
        for entry in (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where entry.standardizedFileURL.path != kept {
            try? fileManager.removeItem(at: entry)
        }
    }
}
