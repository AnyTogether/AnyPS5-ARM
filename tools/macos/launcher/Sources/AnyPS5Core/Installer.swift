import Foundation

/// The launcher's copy of the tools the command line uses, in Contents/Resources/toolkit: the
/// relinker, the prx libraries, the Vulkan loader with MoltenVK (already patched, see
/// tools/macos/moltenvk_patches.py) and its driver manifest, and the per-title patches.
public struct Toolkit: Sendable {
    public let root: URL
    /// Changes whenever the relinker or the libraries change: an installed game made by another
    /// toolkit can be installed again. version.txt, or for a folder someone put together without
    /// one, "local-" and the fingerprint the build script would write.
    public let version: String

    public init(root: URL) {
        self.root = root
        if let text = try? String(contentsOf: root.appendingPathComponent("version.txt"), encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let fingerprint = Toolkit.fingerprint(of: root) {
            version = "local-" + fingerprint
        } else {
            version = "unknown"
        }
    }

    /// ANYPS5_TOOLKIT, else the app bundle's toolkit.
    public static func locate() -> Toolkit? {
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["ANYPS5_TOOLKIT"] { candidates.append(URL(fileURLWithPath: path)) }
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("toolkit")) }
        return candidates.map(Toolkit.init).first { FileManager.default.isExecutableFile(atPath: $0.relinker.path) }
    }

    public var relinker: URL { root.appendingPathComponent("relinker") }
    public var libraries: URL { root.appendingPathComponent("libs") }
    public var vulkan: URL { root.appendingPathComponent("vulkan") }
    public var patches: URL { root.appendingPathComponent("patches") }

}

/// What the launcher records in an installed bundle (Contents/Resources/anyps5-install.json).
public struct InstallRecord: Codable, Sendable {
    public let source: String
    public let titleID: String
    public let toolkit: String
    public let date: Date
    /// The version of the update the bundle was made with (GameUpdate), nil without one.
    public var update: String? = nil
}

public struct InstallError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A tool that ended with an error: its exit code and what it printed. The relinker ends a
/// failed conversion with `FAIL: <reason>` and, when one file caused it, `Input: <path>`.
public struct ToolFailed: LocalizedError {
    public let tool: String
    public let code: Int32
    /// Everything the tool printed (its last lines).
    public let lines: [String]
    /// Its working directory: an `Input:` path inside it is said relative to it, as the dump has
    /// the file (the work folder it names is gone once the unlock stops).
    public let directory: URL?

    /// What it says, made while the work folder is there to resolve the `Input:` path against.
    private let message: String

    public init(tool: String, code: Int32, lines: [String], directory: URL? = nil) {
        self.tool = tool
        self.code = code
        self.lines = lines
        self.directory = directory
        let fail = lines.lastIndex { $0.hasPrefix("FAIL:") }
        let tail = fail.map { Array(lines[$0...]) } ?? (lines.last.map { [$0] } ?? [])
        let shown = tail.map { line -> String in
            guard let directory, line.hasPrefix("Input:") else { return line }
            return "Input: " + ToolFailed.inside(line.dropFirst(6).trimmingCharacters(in: .whitespaces), directory)
        }
        message = "\(tool) failed (\(code))" + (shown.isEmpty ? "" : ": " + shown.joined(separator: "\n"))
    }

    private var failIndex: Int? { lines.lastIndex { $0.hasPrefix("FAIL:") } }

    /// The lines that say what went wrong: from the last `FAIL:` line on, else the last line.
    public var tail: [String] {
        if let failIndex { return Array(lines[failIndex...]) }
        return lines.last.map { [$0] } ?? []
    }

    /// The reason after `FAIL:`, nil when the tool printed none.
    public var reason: String? {
        failIndex.map { lines[$0].dropFirst(5).trimmingCharacters(in: .whitespaces) }
    }

    /// The file the relinker names after its `FAIL:` line, nil when it names none.
    public var input: String? {
        guard let failIndex else { return nil }
        return lines[(failIndex + 1)...].first { $0.hasPrefix("Input:") }.map { $0.dropFirst(6).trimmingCharacters(in: .whitespaces) }
    }

    /// `path` relative to `folder` with / separators when it is inside it (links resolved, so
    /// /var and /private/var are one), else as it is.
    static func inside(_ path: String, _ folder: URL) -> String {
        let file = URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
        for base in [folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().standardizedFileURL.path] {
            for candidate in [file.path, file.resolvingSymlinksInPath().path] where candidate.hasPrefix(base + "/") {
                return String(candidate.dropFirst(base.count + 1))
            }
        }
        return path
    }

    public var errorDescription: String? { message }
}

/// A module of the dump the unlock left out. The engine starts a game without a module it imports
/// nothing from, answers the game's own load of it with an error, and uses its own library of
/// that name where it has one (libSceNpCppWebApi); one the executable imports from and the engine
/// lacks stops the game at its start.
public struct LeftOutModule: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// Neither an ELF nor a SELF container that can be unwrapped: still encrypted in the dump.
        case encrypted
        /// The relinker could not convert it.
        case notRelinked
    }

    /// Relative to the dump.
    public let path: String
    public let reason: Reason
    /// The relinker's reason, or the unwrap's.
    public let detail: String?

    public init(_ path: String, _ reason: Reason, _ detail: String? = nil) {
        self.path = path
        self.reason = reason
        self.detail = detail
    }
}

/// Unlocks a game: unwraps its executable and modules, relinks them for macOS and makes the
/// bundle the launcher starts, the same bundle tools/package_macos_app.py makes.
public final class Installer: @unchecked Sendable {
    public enum Step: Int, CaseIterable, Sendable {
        case unwrap
        case relink
        case copy
        case bundle
        case finish
    }

    public let game: Game
    public let toolkit: Toolkit
    let progress: @Sendable (Step, Double) -> Void
    let log: @Sendable (String) -> Void
    /// Guards `running`, `cancelled`, `paused` and `isBackground`; waited on while paused.
    private let lock = NSCondition()
    private var running: Process?
    private var cancelled = false
    private var paused = false
    private var isBackground = false
    private var leftOutModules: [LeftOutModule] = []
    /// The dump's modules the last run left out (encrypted, or the relinker could not convert
    /// them); the game was unlocked without them.
    public var leftOut: [LeftOutModule] { lock.withLock { leftOutModules } }
    private func leaveOut(_ module: LeftOutModule) { lock.withLock { leftOutModules.append(module) } }
    /// The free bytes on the games folder's drive (FreeSpace.available); replaceable in tests.
    public var freeSpace: @Sendable (URL) -> Int64? = { FreeSpace.available(at: $0) }

    /// A background unlock (a new game prepared on its own): the tools it runs go in the
    /// system's background band, as `taskpolicy -b` puts them, so a game or anything the user
    /// does comes first. Set to false while it runs (the user asked to play it), it goes on at
    /// full speed.
    public var background: Bool {
        get { lock.withLock { isBackground } }
        set {
            lock.lock()
            isBackground = newValue
            let process = running
            lock.unlock()
            if let process, process.isRunning, process.processIdentifier > 0 { Installer.setBackground(process.processIdentifier, newValue) }
        }
    }

    public init(game: Game, toolkit: Toolkit, progress: @escaping @Sendable (Step, Double) -> Void, log: @escaping @Sendable (String) -> Void) {
        self.game = game
        self.toolkit = toolkit
        self.progress = progress
        self.log = log
    }

    /// The installed bundle of a game folder, inside the games root's store.
    public static func bundle(for game: Game, root: URL) -> URL {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in game.folder.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        let name = game.titleID.filter { $0.isLetter || $0.isNumber } + "-" + String(hash & 0xFF_FFFF, radix: 16)
        return root.appendingPathComponent(GameLibrary.storeName).appendingPathComponent("Games").appendingPathComponent(name + ".app")
    }

    /// Where an installed game's files and saves live, outside its bundle.
    public static func dataFolder(for game: Game, root: URL) -> URL {
        root.appendingPathComponent(GameLibrary.storeName).appendingPathComponent("Data")
            .appendingPathComponent(bundle(for: game, root: root).deletingPathExtension().lastPathComponent)
    }

    /// Removes the marks macOS leaves on files that came from a download (quarantine) or were
    /// written by an app that did (provenance) from `url` and everything in it. With them, macOS
    /// verifies a game's whole bundle before its code first runs, a window that takes minutes
    /// for a game of several gigabytes.
    public static func clearMarks(_ url: URL) {
        let marks = ["com.apple.provenance", "com.apple.quarantine"]
        func clear(_ path: String) {
            for mark in marks { removexattr(path, mark, XATTR_NOFOLLOW) }
        }
        clear(url.path)
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let relative as String in enumerator { clear(url.appendingPathComponent(relative).path) }
    }

    /// The work folders and half-made bundles an interrupted unlock left in the store.
    public static func removeLeftovers(root: URL) {
        let store = root.appendingPathComponent(GameLibrary.storeName)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: store.appendingPathComponent("Work"))
        let games = store.appendingPathComponent("Games")
        for item in (try? fileManager.contentsOfDirectory(at: games, includingPropertiesForKeys: nil)) ?? [] where item.pathExtension == "partial" {
            try? fileManager.removeItem(at: item)
        }
    }

    public static func record(of bundle: URL) -> InstallRecord? {
        let file = bundle.appendingPathComponent("Contents/Resources/anyps5-install.json")
        guard FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/MacOS/eboot").path),
              let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InstallRecord.self, from: data)
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let process = running
        lock.broadcast()
        lock.unlock()
        process?.terminate()
        // A stopped process only gets the termination when it goes on.
        if let process, process.processIdentifier > 0 { kill(process.processIdentifier, SIGCONT) }
    }

    /// Stops the unlock where it is (a game started): the tool running is stopped (SIGSTOP), the
    /// launcher's own steps wait at their next file.
    public func pause() {
        lock.lock()
        paused = true
        let process = running
        lock.unlock()
        if let process, process.isRunning, process.processIdentifier > 0 { kill(process.processIdentifier, SIGSTOP) }
    }

    public func resume() {
        lock.lock()
        paused = false
        let process = running
        lock.broadcast()
        lock.unlock()
        if let process, process.processIdentifier > 0 { kill(process.processIdentifier, SIGCONT) }
    }

    /// Throws when cancelled; while paused, waits for the resume (or the cancel).
    private func checkCancelled() throws {
        lock.lock()
        defer { lock.unlock() }
        while paused && !cancelled { lock.wait() }
        if cancelled { throw CancellationError() }
    }

    /// Puts a process in the system's background band (`taskpolicy -b`: low CPU priority,
    /// throttled disk), or takes it out.
    static func setBackground(_ pid: pid_t, _ on: Bool) {
        _ = setpriority(Installer.darwinProcess, id_t(pid), on ? Installer.darwinBackground : 0)
    }

    /// Whether another process (the launcher) put a process in the background band; what it
    /// inherited from a parent in that band does not count.
    public static func isBackground(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return false }
        return info.pbi_flags & UInt32(PROC_FLAG_EXT_DARWINBG) != 0
    }

    // sys/resource.h: PRIO_DARWIN_PROCESS, PRIO_DARWIN_BG.
    static let darwinProcess: Int32 = 4
    static let darwinBackground: Int32 = 0x1000

    // MARK: Room and kept work

    /// Where the relinker's output of a game is kept for the next unlock, in the store.
    public static func keptRelink(for game: Game, root: URL) -> URL {
        root.appendingPathComponent(GameLibrary.storeName).appendingPathComponent("Relinked")
            .appendingPathComponent(bundle(for: game, root: root).deletingPathExtension().lastPathComponent)
    }

    /// What the relinker's output depends on: the toolkit, how it is called, and the dump's
    /// executable and modules (path, size and change date of each). Unlocking again with the
    /// same key reuses the kept output.
    static func relinkKey(game: Game, toolkit: Toolkit, modules: [URL]) -> String {
        var lines = ["toolkit \(toolkit.version)", "arguments --macos --to-rosetta " + moduleDirectories(modules).joined(separator: " ")]
        for relative in [URL(fileURLWithPath: "eboot.bin")] + modules {
            let file = Installer.source(relative, of: game)
            var info = stat()
            guard stat(file.path, &info) == 0 else { return "" }
            lines.append("\(relative.relativePath) \(info.st_size) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)")
            let backup = file.appendingPathExtension("esbak")
            if stat(backup.path, &info) == 0 { lines.append("\(relative.relativePath).esbak \(info.st_size) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)") }
        }
        if let update = game.update { lines.append("update \(update.folder.path) \(update.version)") }
        return lines.joined(separator: "\n")
    }

    /// Where the file at `relative` in the game comes from: the update's copy when the game has
    /// an update that has it, else the game's.
    static func source(_ relative: URL, of game: Game) -> URL {
        if let update = game.update {
            let updated = update.folder.appendingPathComponent(relative.relativePath)
            if FileManager.default.fileExists(atPath: updated.path) { return updated }
        }
        return game.folder.appendingPathComponent(relative.relativePath)
    }

    /// The game's modules and its update's, each once: the relinker converts the update's copy
    /// of one both have (source), and the engine loads the relinked ones from app0.
    static func modules(of game: Game) -> [URL] {
        var found = modules(in: game.folder)
        if let update = game.update {
            for module in modules(in: update.folder) where !found.contains(where: { $0.relativePath == module.relativePath }) { found.append(module) }
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }

    /// The kept relinker output of `game` when its key is `key`, nil when there is none or it was
    /// made from something else.
    static func reusableRelink(for game: Game, root: URL, key: String) -> URL? {
        let kept = keptRelink(for: game, root: root)
        guard !key.isEmpty, (try? String(contentsOf: kept.appendingPathComponent("key.txt"), encoding: .utf8)) == key,
              FileManager.default.fileExists(atPath: kept.appendingPathComponent("out/eboot").path) else { return nil }
        return kept.appendingPathComponent("out")
    }

    /// Whether the store keeps relinker output: only on a drive that clones, where the bundle's
    /// copy of it takes no room.
    static func keepsRelinks(root: URL) -> Bool {
        (try? root.resourceValues(forKeys: [.volumeSupportsFileCloningKey]))?.volumeSupportsFileCloning == true
    }

    /// What unlocking `game` into the games folder `root` will write (see UnlockSpace).
    public static func plan(game: Game, toolkit: Toolkit, root: URL) -> UnlockSpace {
        let fileManager = FileManager.default
        func size(_ url: URL) -> Int64 { ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0 }
        let modules = Installer.modules(of: game)
        let executables = ([URL(fileURLWithPath: "eboot.bin")] + modules).reduce(Int64(0)) { $0 + size(Installer.source($1, of: game)) }
        let clones = keepsRelinks(root: root)
        // The toolkit's files go in as clones from the same APFS drive, else as copies.
        var libraries: Int64 = 0
        if !Installer.clones(from: toolkit.root, to: root) {
            let names = ((try? fileManager.contentsOfDirectory(atPath: toolkit.libraries.path)) ?? []).filter { $0.hasSuffix(".prx") }
            libraries = names.reduce(Int64(0)) { $0 + size(toolkit.libraries.appendingPathComponent($1)) }
            for name in ["libvulkan.1.dylib", "libMoltenVK.dylib", "MoltenVK_icd.json"] { libraries += size(toolkit.vulkan.appendingPathComponent(name)) }
        }
        var kept: Int64?
        if clones, let reusable = reusableRelink(for: game, root: root, key: relinkKey(game: game, toolkit: toolkit, modules: modules)) {
            kept = GameLibrary.size(of: reusable)
        }
        // The game's own files are cloned, or linked where they cannot be: never copied.
        return UnlockSpace(executables: executables, libraries: libraries, copied: 0, clones: clones, keptRelink: kept)
    }

    public func run(root: URL) throws -> URL {
        let fileManager = FileManager.default
        let bundle = Installer.bundle(for: game, root: root)
        let store = root.appendingPathComponent(GameLibrary.storeName)
        let work = store.appendingPathComponent("Work").appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: work) }
        let partial = bundle.deletingPathExtension().appendingPathExtension("partial")
        defer { try? fileManager.removeItem(at: partial) }

        // 0. The room it takes, before anything is written.
        try checkCancelled()
        let space = Installer.plan(game: game, toolkit: toolkit, root: root)
        if let shortage = space.shortage(free: freeSpace(root), volume: FreeSpace.volumeName(at: root)) { throw shortage }

        lock.withLock { leftOutModules = [] }
        let modules = Installer.modules(of: game)
        let key = Installer.relinkKey(game: game, toolkit: toolkit, modules: modules)
        let keeps = Installer.keepsRelinks(root: root)
        let relinked: URL
        if keeps, let reusable = Installer.reusableRelink(for: game, root: root, key: key) {
            // Nothing the relinker depends on changed since the last unlock: its output is reused.
            log("\(game.titleID): the executable and modules are unchanged, the relinked ones are reused")
            relinked = reusable
            for module in Installer.keptLeftOut(reusable) { leaveOut(module) }
            progress(.unwrap, 1)
            progress(.relink, 1)
        } else {
            // 1. The executable and every guest module as plain ELF files, in the dump's layout.
            progress(.unwrap, 0)
            let source = work.appendingPathComponent("source")
            try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
            // Only what the dump holds goes in: a fresh folder each time, the output beside it.
            let inputs = [URL(fileURLWithPath: "eboot.bin")] + modules
            var placed: [String] = []
            for (index, relative) in inputs.enumerated() {
                try checkCancelled()
                let original = Installer.source(relative, of: game)
                let target = source.appendingPathComponent(relative.relativePath)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if try unwrap(original, to: target, relative: relative.relativePath), index > 0 { placed.append(relative.relativePath) }
                progress(.unwrap, Double(index + 1) / Double(inputs.count))
            }

            // 2. The relinker turns them into a Mach-O executable and guest modules.
            progress(.relink, 0)
            let output = work.appendingPathComponent("out")
            let estimate = RelinkProgress()
            let moduleDirectories = Installer.moduleDirectories(modules).flatMap { ["--module-dir", $0] }
            // A module the relinker cannot convert is left out and the relink runs again: the
            // game starts without it, as without an encrypted one. A failure in the executable stops.
            while true {
                do {
                    try runTool(toolkit.relinker, ["--macos", "--to-rosetta"] + moduleDirectories + ["eboot.bin", output.appendingPathComponent("eboot").path], in: source) { segment in
                        if let fraction = estimate.read(segment) { self.progress(.relink, fraction) }
                    }
                    break
                } catch let failure as ToolFailed {
                    guard let module = Installer.failedModule(failure, source: source, modules: placed) else { throw failure }
                    placed.removeAll { $0 == module }
                    try? fileManager.removeItem(at: source.appendingPathComponent(module))
                    try? fileManager.removeItem(at: output)
                    leaveOut(LeftOutModule(module, .notRelinked, failure.reason))
                    log("\(module): the relinker could not convert it (\(failure.reason ?? "")); it is left out and the relink runs again without it")
                }
            }
            guard fileManager.fileExists(atPath: output.appendingPathComponent("eboot").path) else { throw InstallError("relinker wrote no executable") }
            relinked = keeps ? Installer.keep(output, key: key, leftOut: leftOut, for: game, root: root) : output
            progress(.relink, 1)
        }

        // 3. The game files, cloned (no extra space on APFS) or linked where the disk cannot clone,
        // with the relinked modules copied over them.
        try checkCancelled()
        try? fileManager.removeItem(at: partial)
        let contents = partial.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        let app0 = resources.appendingPathComponent("game/app0")
        try fileManager.createDirectory(at: macOS.appendingPathComponent("libs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: app0, withIntermediateDirectories: true)
        // A relinker's output left in the dump is from another relink: only this one's goes in.
        try cloneTree(game.folder, into: app0, linkWithoutClone: true, skip: Installer.isRelinkerOutput) { fraction in self.progress(.copy, fraction) }
        let guestModules = relinked.appendingPathComponent("app0")
        if fileManager.fileExists(atPath: guestModules.path) { try cloneTree(guestModules, into: app0) { _ in } }
        try linkGuestModuleLibraries(in: app0)

        // 4. The executable with its patches, the libraries, MoltenVK and the launch script.
        try checkCancelled()
        progress(.bundle, 0)
        let eboot = macOS.appendingPathComponent("eboot")
        try fileManager.copyItem(at: relinked.appendingPathComponent("eboot"), to: eboot)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: eboot.path)
        let patches = GamePatches.load(titleID: game.titleID, from: toolkit.patches)
        if let patches {
            for (name, state) in try patches.apply(to: eboot) { log("\(game.titleID) patch \(name): \(state)") }
        }
        try fileManager.createSymbolicLink(atPath: macOS.appendingPathComponent("app0").path, withDestinationPath: "../Resources/game/app0")
        for library in try fileManager.contentsOfDirectory(at: toolkit.libraries, includingPropertiesForKeys: nil) where library.pathExtension == "prx" {
            try fileManager.copyItem(at: library, to: macOS.appendingPathComponent("libs").appendingPathComponent(library.lastPathComponent))
        }
        for name in ["libvulkan.1.dylib", "libMoltenVK.dylib"] {
            try fileManager.copyItem(at: toolkit.vulkan.appendingPathComponent(name), to: macOS.appendingPathComponent("libs").appendingPathComponent(name))
        }
        let icd = resources.appendingPathComponent("vulkan/icd.d")
        try fileManager.createDirectory(at: icd, withIntermediateDirectories: true)
        try fileManager.copyItem(at: toolkit.vulkan.appendingPathComponent("MoltenVK_icd.json"), to: icd.appendingPathComponent("MoltenVK_icd.json"))
        var script = Installer.launchHead(identifier: game.bundleIdentifier) + Installer.asyncSubmits
        if let patches, let resolution = patches.resolution, let offsets = patches.resolutionOffsets(in: eboot) {
            try GamePatches.write(resolution: resolution.default, offsets: offsets, to: eboot)
            let choices = "resolution_default=\(resolution.default)\nresolution_choices='\(resolution.choices.joined(separator: " "))'\nresolution_width=\(offsets.width)\nresolution_height=\(offsets.height)\n"
            try choices.write(to: resources.appendingPathComponent("resolution.txt"), atomically: true, encoding: .utf8)
            script += Installer.resolutionChoice
        }
        script += "exec \"$here/eboot\" \"$@\" >> \"$HOME/Library/Logs/AnyPS5/\(game.titleID).log\" 2>&1\n"
        let launcher = macOS.appendingPathComponent("launch")
        try script.write(to: launcher, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        progress(.bundle, 0.6)
        let hasIcon = makeIcon(from: app0.appendingPathComponent("sce_sys/icon0.png"), into: resources)
        var info: [String: Any] = [
            "CFBundleName": game.name,
            "CFBundleDisplayName": game.name,
            "CFBundleIdentifier": game.bundleIdentifier,
            "CFBundleExecutable": "launch",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": game.update?.version ?? game.version,
            "CFBundleVersion": game.update?.version ?? game.version,
            "LSMinimumSystemVersion": "11.0",
            "LSApplicationCategoryType": "public.app-category.games",
            "NSHighResolutionCapable": true,
        ]
        if hasIcon { info["CFBundleIconFile"] = "AppIcon" }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(InstallRecord(source: game.folder.path, titleID: game.titleID, toolkit: toolkit.version, date: Date(), update: game.update?.version)).write(to: resources.appendingPathComponent("anyps5-install.json"))

        // 5. Nothing in the bundle keeps a download's marks, then it takes the old one's place.
        progress(.finish, 0)
        Installer.clearMarks(partial)
        try Installer.place(partial: partial, bundle: bundle, data: Installer.dataFolder(for: game, root: root))
        progress(.finish, 1)
        return bundle
    }

    /// Moves the relinker's output into the store for the next unlock (a rename on the same
    /// drive) and returns where it is now; where that fails, it stays in the work folder.
    /// Beside the kept output: the modules its relink left out, said again when it is reused.
    static let leftOutName = "left-out.json"

    static func keptLeftOut(_ out: URL) -> [LeftOutModule] {
        guard let data = try? Data(contentsOf: out.deletingLastPathComponent().appendingPathComponent(leftOutName)) else { return [] }
        return (try? JSONDecoder().decode([LeftOutModule].self, from: data)) ?? []
    }

    /// The module of the source tree `source` the relinker named in `failure`, relative to it;
    /// nil when it named none, or the executable.
    static func failedModule(_ failure: ToolFailed, source: URL, modules: [String]) -> String? {
        guard let input = failure.input else { return nil }
        let relative = ToolFailed.inside(input, source)
        return modules.first { $0 == relative }
    }

    static func keep(_ output: URL, key: String, leftOut: [LeftOutModule] = [], for game: Game, root: URL) -> URL {
        let fileManager = FileManager.default
        let kept = keptRelink(for: game, root: root)
        try? fileManager.removeItem(at: kept)
        do {
            try fileManager.createDirectory(at: kept, withIntermediateDirectories: true)
            try fileManager.moveItem(at: output, to: kept.appendingPathComponent("out"))
            if !leftOut.isEmpty, let json = try? JSONEncoder().encode(leftOut) { try? json.write(to: kept.appendingPathComponent(leftOutName)) }
            try key.write(to: kept.appendingPathComponent("key.txt"), atomically: true, encoding: .utf8)
            return kept.appendingPathComponent("out")
        } catch {
            let moved = kept.appendingPathComponent("out")
            if fileManager.fileExists(atPath: moved.path) && !fileManager.fileExists(atPath: output.path) { try? fileManager.moveItem(at: moved, to: output) }
            try? fileManager.removeItem(at: kept)
            return output
        }
    }

    /// What the game wrote beside app0 in the old bundle (saves in _sd, trophies in _trophy, its
    /// data and download folders) moves into the new one, so unlocking again keeps the progress.
    /// Puts a finished bundle in place with its game outside it, in `data`/game, linked back as
    /// Contents/Resources/game. macOS assesses an unsigned bundle each time it changed before
    /// its code runs; with the gigabytes and the saves outside, that is a few seconds once
    /// instead of minutes at every start. What the game wrote beside app0 in the old bundle (or
    /// in the old data folder) moves into the new one.
    static func place(partial: URL, bundle: URL, data: URL) throws {
        let fileManager = FileManager.default
        let staged = partial.appendingPathComponent("Contents/Resources/game")
        let previous = bundle.appendingPathComponent("Contents/Resources/game")
        if fileManager.fileExists(atPath: previous.path) { try carryOver(from: previous.resolvingSymlinksInPath(), to: staged) }
        if fileManager.fileExists(atPath: bundle.path) { try fileManager.removeItem(at: bundle) }
        let game = data.appendingPathComponent("game")
        if fileManager.fileExists(atPath: game.path) { try fileManager.removeItem(at: game) }
        try fileManager.createDirectory(at: data, withIntermediateDirectories: true)
        try fileManager.moveItem(at: staged, to: game)
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try fileManager.createSymbolicLink(atPath: staged.path, withDestinationPath: relativePath(from: resources, to: game))
        let libraries = bundle.appendingPathComponent("Contents/MacOS/libs")
        for folder in [game, game.appendingPathComponent("app0")] {
            let link = folder.appendingPathComponent("libs")
            guard (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true else { continue }
            try fileManager.removeItem(at: link)
            try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: relativePath(from: folder, to: libraries))
        }
        try fileManager.moveItem(at: partial, to: bundle)
    }

    /// `target` as a path relative to the folder `base`.
    static func relativePath(from base: URL, to target: URL) -> String {
        let from = canonical(base)
        let to = canonical(target)
        var shared = 0
        while shared < min(from.count, to.count), from[shared] == to[shared] { shared += 1 }
        return (Array(repeating: "..", count: from.count - shared) + to[shared...]).joined(separator: "/")
    }

    /// The path's components with its existing part's symlinks resolved, so /tmp and
    /// /private/tmp compare equal; a part not made yet (a bundle before its move) is kept as is.
    static func canonical(_ url: URL) -> [String] {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while existing.path != "/", realpath(existing.path, nil) == nil {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.path
        if let real = realpath(existing.path, nil) {
            resolved = String(cString: real)
            free(real)
        }
        return URL(fileURLWithPath: resolved).pathComponents + rest
    }

    /// The game folder's items the game wrote (saves, trophies, data) move from `source` into
    /// `target` unless the new game has them.
    static func carryOver(from source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: source.path) else { return }
        for name in entries where !fileManager.fileExists(atPath: target.appendingPathComponent(name).path) {
            let item = source.appendingPathComponent(name)
            // A link (game/libs) belongs to the bundle that made it.
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { continue }
            try fileManager.moveItem(at: item, to: target.appendingPathComponent(name))
        }
    }

    /// The suffix the relinker gives the modules it converts (libX.prx becomes libX.prx.guest.prx).
    static let guestSuffix = ".guest.prx"

    /// Whether the file `name` is a module the relinker wrote, never one of its inputs.
    static func isRelinkerOutput(_ name: String) -> Bool {
        (name as NSString).lastPathComponent.lowercased().hasSuffix(guestSuffix)
    }

    /// Every .prx and .sprx of the dump outside sce_sys, relative to its folder; a relinker's
    /// output (isRelinkerOutput) is left out.
    static func modules(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        let base = folder.standardizedFileURL.path
        for case let file as URL in enumerator {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            if relative.hasPrefix("sce_sys/") { enumerator.skipDescendants(); continue }
            let depth = relative.split(separator: "/").count
            if depth > 3 { continue }
            // Nothing below the third level counts: a game's thousands of data files are not walked.
            if depth == 3, (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { enumerator.skipDescendants(); continue }
            let name = file.lastPathComponent.lowercased()
            // A relinker's output left in the dump (a relink by hand writes them into app0's
            // sce_module, the dump's own folder) is no module of the game.
            guard name.hasSuffix(".prx") || name.hasSuffix(".sprx"), !Installer.isRelinkerOutput(name) else { continue }
            found.append(URL(fileURLWithPath: relative))
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }

    /// The folders besides sce_module whose modules the relinker converts too (Unity's
    /// Media/Modules and Media/Plugins, prx next to eboot.bin). fakelib holds a dump tool's
    /// stand-ins for system libraries, which AnyPS5 implements itself.
    static func moduleDirectories(_ modules: [URL]) -> [String] {
        var directories = ["."]
        for module in modules where module.pathExtension.lowercased() == "prx" {
            let directory = module.deletingLastPathComponent().relativePath
            let first = directory.split(separator: "/").first.map(String.init) ?? "."
            guard !["sce_module", "sce_modules", "prx", "fakelib"].contains(first.lowercased()), !directories.contains(directory) else { continue }
            directories.append(directory)
        }
        return directories
    }

    /// A guest module outside sce_module finds the prx libraries through
    /// @loader_path/<up to app0's parent>/libs. Loaded through Contents/MacOS/app0 that is
    /// MacOS/libs already; loaded through the real Resources/game/app0 it needs these two links.
    func linkGuestModuleLibraries(in app0: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: app0, includingPropertiesForKeys: nil) else { return }
        let base = app0.standardizedFileURL.path
        var outside = false
        for case let file as URL in enumerator where file.lastPathComponent.hasSuffix(".guest.prx") {
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count + 1))
            if !relative.hasPrefix("sce_module/") && relative.contains("/") { outside = true; break }
        }
        guard outside else { return }
        for (folder, target) in [(app0, "../../../MacOS/libs"), (app0.deletingLastPathComponent(), "../../MacOS/libs")] {
            let link = folder.appendingPathComponent("libs")
            guard (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == nil, !fileManager.fileExists(atPath: link.path) else { continue }
            try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        }
    }

    /// An ELF as it is, a re-signed one from its .esbak, a SELF container unwrapped. A module
    /// (`relative` other than eboot.bin) still encrypted in the dump is left out (leftOut) and
    /// false returned: the engine starts a game without one of its modules (the game gets an
    /// error when it loads it), while it cannot start one without its executable.
    @discardableResult
    func unwrap(_ original: URL, to target: URL, relative: String = "eboot.bin") throws -> Bool {
        let executable = relative == "eboot.bin"
        var refused: String?
        if Elf.isElf(original) {
            try FileManager.default.copyItem(at: original, to: target)
            return true
        } else if Elf.isElf(original.appendingPathExtension("esbak")) {
            try FileManager.default.copyItem(at: original.appendingPathExtension("esbak"), to: target)
            log(original.lastPathComponent + ": from .esbak")
            return true
        } else if SelfUnwrap.isContainer(original) {
            do {
                let size = try SelfUnwrap.unwrap(original, to: target)
                log(original.lastPathComponent + ": unwrapped, \(size) bytes")
                return true
            } catch {
                if executable { throw InstallError(original.lastPathComponent + ": " + error.localizedDescription) }
                refused = error.localizedDescription
                try? FileManager.default.removeItem(at: target)
            }
        }
        if executable {
            throw InstallError("eboot.bin in the dump is encrypted (neither an ELF nor a decrypted SELF container): dump the game again with a dumper that decrypts it")
        }
        leaveOut(LeftOutModule(relative, .encrypted, refused))
        log("\(relative) in the dump is encrypted (\(refused ?? "neither an ELF nor a decrypted SELF container")): it is left out, and the game is unlocked without it")
        return false
    }

    /// Copies a tree with clonefile where the volume allows it, reporting the share of bytes done.
    func cloneTree(_ source: URL, into target: URL, linkWithoutClone: Bool = false, skip: ((String) -> Bool)? = nil, progress: (Double) -> Void) throws {
        let link = linkWithoutClone && !Installer.clones(from: source, to: target)
        if link { log("\(game.titleID): the games folder cannot clone, so the game links to its dump instead of copying it") }
        try Installer.copyTree(source, into: target, link: link, skip: skip, cancelled: checkCancelled, progress: progress)
    }

    /// Whether files from `source` can be cloned into `target`: on one volume that clones (APFS),
    /// where a clone takes no space.
    static func clones(from source: URL, to target: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey, .volumeSupportsFileCloningKey]
        guard let from = try? source.resourceValues(forKeys: keys), let to = try? target.resourceValues(forKeys: keys),
              let fromVolume = from.volumeIdentifier as? NSObject, let toVolume = to.volumeIdentifier as? NSObject else { return false }
        return fromVolume.isEqual(toVolume) && to.volumeSupportsFileCloning == true
    }

    /// The files of `source` in `target`, folder by folder: each cloned (a real copy where cloning
    /// is not possible), or with `link`, a link to the source file, so nothing takes space twice
    /// on a disk that cannot clone. The game only reads its files, as /app0 is read-only on the
    /// console, so a link serves as well as a copy; the dump has to stay where it is.
    static func copyTree(_ source: URL, into target: URL, link: Bool, skip: ((String) -> Bool)? = nil, cancelled: () throws -> Void, progress: (Double) -> Void) throws {
        let fileManager = FileManager.default
        let base = source.resolvingSymlinksInPath().standardizedFileURL.path
        var files: [(URL, String, Int64)] = []
        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else { return }
        for case let item as URL in enumerator {
            let path = item.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            if relative == GameLibrary.storeName || relative.hasPrefix(GameLibrary.storeName + "/") { enumerator.skipDescendants(); continue }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target.appendingPathComponent(relative), withIntermediateDirectories: true)
            } else {
                // A file `skip` names is left out (a relinker's output left in the dump).
                if skip?(relative) == true { continue }
                let size = Int64(values.fileSize ?? 0)
                files.append((item, relative, size))
                total += size
            }
        }
        func place(_ item: URL, _ relative: String) throws {
            let destination = target.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: destination.path) || (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                try fileManager.removeItem(at: destination)
            }
            if link {
                try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: item.resolvingSymlinksInPath().path)
            } else if copyfile(item.path, destination.path, nil, copyfile_flags_t(COPYFILE_CLONE)) != 0 {
                throw InstallError("copy \(relative): \(String(cString: strerror(errno)))")
            }
        }
        // A clone or a link is a few metadata writes: several at once get through a game of tens
        // of thousands of files sooner. The folders are all made above, so the workers only add
        // files.
        let lock = NSLock()
        var done: Int64 = 0
        var failure: Error?
        let workers = files.count < 64 ? 1 : min(8, max(1, ProcessInfo.processInfo.activeProcessorCount))
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            var index = worker
            while index < files.count {
                if lock.withLock({ failure != nil }) { return }
                let (item, relative, size) = files[index]
                do {
                    try cancelled()
                    try place(item, relative)
                } catch {
                    lock.withLock { if failure == nil { failure = error } }
                    return
                }
                lock.withLock {
                    done += size
                    progress(total == 0 ? 1 : Double(done) / Double(total))
                }
                index += workers
            }
        }
        if let failure { throw failure }
        if files.isEmpty { progress(1) }
    }

    func makeIcon(from png: URL, into resources: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: png.path) else { return false }
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
        defer { try? FileManager.default.removeItem(at: iconset) }
        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for size in [16, 32, 128, 256, 512] {
                for scale in [1, 2] {
                    let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
                    try runTool(URL(fileURLWithPath: "/usr/bin/sips"), ["-z", "\(size * scale)", "\(size * scale)", png.path, "--out", iconset.appendingPathComponent(name).path], quiet: true)
                }
            }
            try runTool(URL(fileURLWithPath: "/usr/bin/iconutil"), ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path], quiet: true)
            return true
        } catch {
            log("icon: " + error.localizedDescription)
            return false
        }
    }

    func runTool(_ tool: URL, _ arguments: [String], in directory: URL? = nil, quiet: Bool = false, status: (@Sendable (String) -> Void)? = nil) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collected = OutputCollector(quiet: quiet, log: log, status: status)
        pipe.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData) }
        lock.lock()
        while paused && !cancelled { lock.wait() }
        if cancelled { lock.unlock(); throw CancellationError() }
        running = process
        let background = isBackground
        lock.unlock()
        try process.run()
        if background { Installer.setBackground(process.processIdentifier, true) }
        // Paused while it was starting.
        if lock.withLock({ paused }) { kill(process.processIdentifier, SIGSTOP) }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
        collected.flush()
        lock.lock()
        running = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            if quiet { for line in collected.lines { log(line) } }
            throw ToolFailed(tool: tool.lastPathComponent, code: process.terminationStatus, lines: collected.lines, directory: directory)
        }
    }

    static func launchHead(identifier: String) -> String {
        """
        #!/bin/sh
        # Starts the title from its game folder: AnyPS5 maps /app0 under the working directory.
        here="$(cd "$(dirname "$0")" && pwd)"
        export VK_DRIVER_FILES="${VK_DRIVER_FILES:-$here/../Resources/vulkan/icd.d/MoltenVK_icd.json}"
        export ANYPS5_SHADER_CACHE_DIR="${ANYPS5_SHADER_CACHE_DIR:-$HOME/Library/Caches/\(identifier)/shader_cache}"
        mkdir -p "$ANYPS5_SHADER_CACHE_DIR" "$HOME/Library/Logs/AnyPS5"
        cd "$here/../Resources/game" || exit 1

        """
    }

    static let asyncSubmits = "export MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=\"${MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS:-0}\"\n"

    // The launcher passes APS5_RESOLUTION; started from Finder the bundle asks (as package_macos_app.py's does).
    static let resolutionChoice = #"""
    resolution_file="$here/../Resources/resolution.txt"
    if [ -f "$resolution_file" ]; then
        . "$resolution_file"
        choice="${APS5_RESOLUTION:-$resolution_default}"
        case " $resolution_choices " in *" $choice "*) ;; *) choice="$resolution_default" ;; esac
        width="${choice%%x*}"
        height="${choice#*x}"
        case "$width$height" in *[!0-9]*|"") echo "AnyPS5: not a WIDTHxHEIGHT resolution: $choice" >&2; exit 1 ;; esac
        write_u32() {
            printf "$(printf '\\%03o\\%03o\\%03o\\%03o' $(($2 & 255)) $(($2 >> 8 & 255)) $(($2 >> 16 & 255)) $(($2 >> 24 & 255)))" | dd of="$here/eboot" bs=1 seek="$1" count=4 conv=notrunc 2>/dev/null
        }
        write_u32 "$resolution_width" "$width"
        write_u32 "$resolution_height" "$height"
    fi

    """#
}

/// Splits a tool's output into lines for the log as it arrives.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    /// The current state of a line a progress display keeps rewriting.
    private var rewritten: String?
    private(set) var lines: [String] = []
    let quiet: Bool
    let log: @Sendable (String) -> Void

    let status: (@Sendable (String) -> Void)?

    init(quiet: Bool, log: @escaping @Sendable (String) -> Void, status: (@Sendable (String) -> Void)? = nil) {
        self.quiet = quiet
        self.log = log
        self.status = status
    }

    /// A progress display rewrites its line with carriage returns: every rewrite goes to `status`,
    /// only the line's last state to the log.
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        pending.append(data)
        var complete: [String] = []
        var segments: [String] = []
        while let end = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let text = String(decoding: pending[pending.startIndex..<end], as: UTF8.self)
            let newline = pending[end] == 0x0A
            pending.removeSubrange(pending.startIndex...end)
            if !text.isEmpty {
                segments.append(text)
                rewritten = text
            }
            if newline {
                if let line = rewritten { complete.append(line) }
                rewritten = nil
            }
        }
        lines.append(contentsOf: complete)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        lock.unlock()
        if let status { segments.forEach(status) }
        if !quiet { complete.forEach(log) }
    }

    func flush() {
        lock.lock()
        let rest = pending.isEmpty ? rewritten : String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        rewritten = nil
        if let rest { lines.append(rest) }
        lock.unlock()
        if let rest, !quiet { log(rest) }
    }
}

/// Turns the relinker's progress display ("Instruction scan | eboot.bin | 42%") into one rising
/// fraction of the relink step.
final class RelinkProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var reached = 0.0

    func read(_ segment: String) -> Double? {
        let fields = segment.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 3 else { return nil }
        let phase = fields[0]
        let file = fields[1]
        let value = fields[2]
        guard let percentText = value.split(separator: "%").first, let percent = Double(percentText.trimmingCharacters(in: .whitespaces)) else { return nil }
        let done = min(1, max(0, percent / 100))
        let estimate: Double
        switch phase {
        case "Instruction scan" where file == "eboot.bin": estimate = 0.2 * done
        case "Instruction conversion" where file == "eboot.bin": estimate = 0.2 + 0.25 * done
        case "Syscall scan" where file == "eboot.bin": estimate = 0.45 + 0.1 * done
        case "PRX conversion":
            // "100% (3/7)": modules converted of all.
            if let open = value.firstIndex(of: "("), let slash = value.firstIndex(of: "/"), let close = value.firstIndex(of: ")"),
               let converted = Double(value[value.index(after: open)..<slash]), let total = Double(value[value.index(after: slash)..<close]), total > 0 {
                estimate = 0.55 + 0.3 * converted / total
            } else {
                estimate = 0.55
            }
        case "Output image": estimate = 0.85 + 0.1 * done
        case "Write output": estimate = 0.95 + 0.05 * done
        default: return nil
        }
        lock.lock()
        defer { lock.unlock() }
        guard estimate > reached else { return nil }
        reached = estimate
        return estimate
    }
}
