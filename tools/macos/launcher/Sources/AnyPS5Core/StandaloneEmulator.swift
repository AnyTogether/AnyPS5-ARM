import Darwin
import Foundation

/// An emulator the user installed (DuckStation, PCSX2, RPCS3), started on a disc of the library:
/// what its application runs, what it is handed, and its process. The launcher bundles,
/// downloads and links none of them, and starts the one chosen directly, without a shell.
public enum StandaloneEmulator {
    /// The program a chosen application or file starts: an application bundle's own executable
    /// (its Info.plist's CFBundleExecutable in Contents/MacOS), a file as it is. nil when the
    /// path is not absolute, is not there, or is a folder that is no application.
    public static func executable(of chosen: URL) -> URL? {
        var directory: ObjCBool = false
        guard chosen.isFileURL, chosen.path.hasPrefix("/"), FileManager.default.fileExists(atPath: chosen.path, isDirectory: &directory) else { return nil }
        guard directory.boolValue else { return chosen }
        guard let program = Bundle(url: chosen)?.executableURL, GameLibrary.isFile(program.path) else { return nil }
        return program
    }

    /// What the emulator boots for `disc` of the game in `folder`: the disc file, or an
    /// extracted PS3 disc's PS3_GAME/USRDIR/EBOOT.BIN.
    public static func bootFile(_ disc: RetroDisc, folder: URL) -> URL {
        disc.platform == .ps3 ? PS3Disc.bootFile(folder) : disc.path
    }

    /// Whether the disc is still where the scan found it, and what the emulator boots with it.
    public static func discThere(_ disc: RetroDisc, folder: URL) -> Bool {
        GameLibrary.isFile(disc.path.path) && GameLibrary.isFile(bootFile(disc, folder: folder).path)
    }

    /// The emulator's arguments to start `boot` at once, without its own window of games, and to
    /// end when the game does. The same on macOS as on Windows and Linux, as the three parse
    /// them on every system: DuckStation and PCSX2 take `-nogui` (no main window, quit when the
    /// game stops) and `--` before the file name, RPCS3 takes `--no-gui` and the path, never a
    /// `--`, which it would hand to the game with what follows.
    public static func arguments(_ platform: RetroPlatform, boot: URL) -> [String] {
        platform == .ps3 ? ["--no-gui", boot.path] : ["-nogui", "--", boot.path]
    }
}

/// An emulator the launcher started: asked to end, ended, and waited for.
public protocol EmulatorRun: AnyObject, Sendable {
    var processIdentifier: Int32 { get }
    var started: Date { get }
    /// Asks it to end (SIGTERM), so it can save; false when it could not be asked.
    func stop() -> Bool
    /// Ends it now (SIGKILL).
    func kill()
    /// Its exit code once it has ended; the signal's number below zero when a signal ended it.
    func exitCode() async -> Int32
}

/// The emulator's own process, its output in the game's log.
public final class EmulatorProcess: EmulatorRun, @unchecked Sendable {
    public let started = Date()
    private let process = Process()
    private let lock = NSLock()
    private var code: Int32?
    private var waiting: [CheckedContinuation<Int32, Never>] = []

    /// Starts `executable` with `arguments` in its own folder, what it prints going to `log`
    /// (begun again at each start). Throws when the program cannot be started.
    public static func start(executable: URL, arguments: [String], log: URL) throws -> EmulatorProcess {
        let run = EmulatorProcess()
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: Data("\(executable.path) \(arguments.joined(separator: " "))\n".utf8))
        let output = try FileHandle(forWritingTo: log)
        try output.seekToEnd()
        run.process.executableURL = executable
        run.process.arguments = arguments
        run.process.currentDirectoryURL = executable.deletingLastPathComponent()
        run.process.standardInput = FileHandle.nullDevice
        run.process.standardOutput = output
        run.process.standardError = output
        // The run is kept until its process ends, whoever still holds it then.
        run.process.terminationHandler = { process in
            try? output.close()
            run.ended(process.terminationReason == .exit ? process.terminationStatus : -process.terminationStatus)
            process.terminationHandler = nil
        }
        do {
            try run.process.run()
        } catch {
            try? output.close()
            throw error
        }
        return run
    }

    public var processIdentifier: Int32 { process.processIdentifier }

    /// Its process while it runs; a signal never goes to process 0, which is the launcher's group.
    private var live: Int32? {
        let pid = process.processIdentifier
        lock.lock()
        defer { lock.unlock() }
        return pid > 0 && code == nil ? pid : nil
    }

    public func stop() -> Bool {
        guard let pid = live else { return false }
        return Darwin.kill(pid, SIGTERM) == 0
    }

    public func kill() {
        guard let pid = live else { return }
        _ = Darwin.kill(pid, SIGKILL)
    }

    public func exitCode() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let code {
                lock.unlock()
                continuation.resume(returning: code)
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    private func ended(_ status: Int32) {
        lock.lock()
        code = status
        let told = waiting
        waiting = []
        lock.unlock()
        for continuation in told { continuation.resume(returning: status) }
    }
}
