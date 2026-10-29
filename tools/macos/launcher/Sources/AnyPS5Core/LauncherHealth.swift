import Darwin
import Foundation

/// What went wrong with the launcher itself (not a game) in an earlier run, offered as a report
/// at the next start. The same file as AnyPS5 Desktop's launcher_health.dart writes.
public struct LauncherProblem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The run ended without the launcher quitting: a crash, or Force Quit.
        case crash
        /// The interface did not answer for `stalledFor` (or until the run ended).
        case hang
    }

    public var kind: Kind
    /// When it happened: the stall's start, or the last moment the run was seen alive.
    public var at: Date
    public var version: String
    public var platform: String
    public var stalledMs: Int?
    /// The stall ended by itself (the launcher went on).
    public var recovered: Bool?
    /// The uncaught exception or the fatal signal of that run, with where it happened, and what
    /// macOS's crash report says.
    public var error: String?
    /// What the launcher was doing in its last seconds: a line a second.
    public var lines: [String]

    public init(kind: Kind, at: Date, version: String, platform: String, stalledMs: Int? = nil, recovered: Bool? = nil, error: String? = nil, lines: [String] = []) {
        self.kind = kind
        self.at = at
        self.version = version
        self.platform = platform
        self.stalledMs = stalledMs
        self.recovered = recovered
        self.error = error
        self.lines = lines
    }

    public var stalledFor: TimeInterval? { stalledMs.map { Double($0) / 1000 } }
}

extension JSONEncoder {
    static var health: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var health: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The launcher's own crashes and long stalls, kept so the next start can offer a report:
///
/// - `running-<pid>.json` while a run lasts: when it started and, every few seconds, what it was
///   doing. Taken away when the launcher quits; one left by a process that is gone is a run that
///   crashed or was ended.
/// - `fatal-<pid>.txt`: the uncaught exception or fatal signal of that run (CrashCatcher).
/// - `problem.json`: a stall the watchdog saw (written from its own thread, so even an interface
///   that never answers again leaves it), or a crash found at start.
///
/// Nothing leaves the Mac: the report is a GitHub issue the user opens and sends.
public final class LauncherHealth: @unchecked Sendable {
    public let folder: URL
    public let version: String
    public let platform = "macOS"
    public let pid: Int32
    private let alive: @Sendable (Int32) -> Bool
    /// macOS's own crash report of the launcher, found by its process (Diagnosis.crashReport).
    private let crashReport: @Sendable (_ since: Date, _ pid: Int32) -> String?

    /// A stall this long is a problem worth a report.
    public static let stall: TimeInterval = 5
    /// The lines of recent activity a marker and a report keep.
    public static let keptLines = 30

    public static var defaultFolder: URL { GameLog.folder.appendingPathComponent("Launcher") }

    public init(folder: URL = LauncherHealth.defaultFolder, version: String, pid: Int32 = getpid(), alive: @escaping @Sendable (Int32) -> Bool = LauncherHealth.processAlive,
                crashReport: @escaping @Sendable (Date, Int32) -> String? = { _, _ in nil }) {
        self.folder = folder
        self.version = version
        self.pid = pid
        self.alive = alive
        self.crashReport = crashReport
    }

    var marker: URL { folder.appendingPathComponent("running-\(pid).json") }
    public var fatalFile: URL { Self.fatalFile(in: folder, pid: pid) }
    public var problemFile: URL { folder.appendingPathComponent("problem.json") }

    static func fatalFile(in folder: URL, pid: Int32) -> URL { folder.appendingPathComponent("fatal-\(pid).txt") }

    struct Marker: Codable {
        var pid: Int32
        var started: Date
        var alive: Date
        var version: String
        var platform: String
        var error: String?
        var lines: [String]
    }

    /// Starts this run's marker and returns what an earlier run left to report, if anything: the
    /// stall the watchdog wrote, else a crash read from the marker of a run whose process is gone.
    public func start(now: Date = Date()) -> LauncherProblem? {
        var found: LauncherProblem?
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            found = read(problemFile)
            for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
                guard name.hasPrefix("running-"), name.hasSuffix(".json"), let other = Int32(name.dropFirst(8).dropLast(5)),
                      other != pid, !alive(other) else { continue }
                let file = folder.appendingPathComponent(name)
                let marker = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder.health.decode(Marker.self, from: $0) }
                let fatal = Self.fatalFile(in: folder, pid: other)
                let caught = (try? String(contentsOf: fatal, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: fatal)
                // A stall the watchdog wrote is the same run, told better.
                guard found == nil, let marker else { continue }
                var error = [marker.error, caught].compactMap { $0 }.filter { !$0.isEmpty }
                if let report = crashReport(marker.started, other) { error.append(Self.summary(ofCrashReport: report)) }
                found = LauncherProblem(kind: .crash, at: marker.alive, version: marker.version, platform: marker.platform,
                                        error: error.isEmpty ? nil : error.joined(separator: "\n\n"), lines: marker.lines)
                write(found, to: problemFile)
            }
            writeMarker(started: now, alive: now, lines: [], error: nil)
        } catch {
            // Reports are a help, never a reason not to start.
        }
        return found
    }

    /// The launcher is quitting as it should: no crash to find next time.
    public func closed() {
        try? FileManager.default.removeItem(at: marker)
        try? FileManager.default.removeItem(at: fatalFile)
    }

    /// The report was sent or put aside.
    public func forget() {
        try? FileManager.default.removeItem(at: problemFile)
    }

    public func writeMarker(started: Date, alive: Date, lines: [String], error: String?) {
        write(Marker(pid: pid, started: started, alive: alive, version: version, platform: platform, error: error, lines: lines), to: marker)
    }

    func writeStall(since: Date, length: TimeInterval, recovered: Bool, error: String?, lines: [String]) {
        write(LauncherProblem(kind: .hang, at: since, version: version, platform: platform, stalledMs: Int(length * 1000), recovered: recovered ? true : nil,
                              error: error, lines: lines), to: problemFile)
    }

    private func read(_ file: URL) -> LauncherProblem? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder.health.decode(LauncherProblem.self, from: $0) }
    }

    private func write<Value: Encodable>(_ value: Value?, to file: URL) {
        guard let value, let data = try? JSONEncoder.health.encode(value) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// The exception and the crashed thread's first frames of a macOS crash report (.ips).
    static func summary(ofCrashReport report: String) -> String {
        var lines = ["macOS crash report:"]
        if let exception = Diagnosis.crashException(report) { lines.append("  " + exception) }
        lines += Diagnosis.crashFrames(report, limit: 16).map { "  " + $0 }
        return lines.joined(separator: "\n")
    }

    /// Whether a process with `pid` runs.
    public static let processAlive: @Sendable (Int32) -> Bool = { pid in
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// Under a debugger a breakpoint is no stall, and the debugger has the signals.
    public static var debuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}

/// The watchdog's reckoning, apart from its thread (tests drive it with made-up times, in seconds
/// of uptime): the interface pings it a few times a second; no ping for `limit` is a stall. When
/// the watchdog's own ticks stop too, the Mac slept or the process was stopped: that gap is no
/// stall. While the launcher is behind a game (`watching` off) nothing counts.
public struct StallDetector: Sendable {
    public let limit: TimeInterval
    /// A gap between the watchdog's own ticks this long means the whole process was stopped.
    public let asleep: TimeInterval
    public var watching = true
    private var lastPing: TimeInterval?
    private var lastTick: TimeInterval?
    /// When the stall being reported began; nil while the interface answers.
    public private(set) var stalledSince: TimeInterval?

    public init(limit: TimeInterval = LauncherHealth.stall, asleep: TimeInterval = 3) {
        self.limit = limit
        self.asleep = asleep
    }

    /// The interface answered: the length of the stall that ended, when one was reported.
    public mutating func ping(_ now: TimeInterval) -> TimeInterval? {
        let since = stalledSince
        lastPing = now
        stalledSince = nil
        return since.map { now - $0 }
    }

    /// The watchdog's own tick: true when a stall has just become long enough to report.
    public mutating func tick(_ now: TimeInterval) -> Bool {
        let last = lastTick
        lastTick = now
        if !watching || (last.map { now - $0 >= asleep } ?? false) {
            if stalledSince == nil { lastPing = now }
            return false
        }
        guard let ping = lastPing, stalledSince == nil, now - ping >= limit else { return false }
        stalledSince = ping
        return true
    }
}

/// LauncherHealth's watchdog on a thread of its own, which keeps running while the main thread is
/// stuck: it writes the stall to problem.json as soon as it is long, again with its length when it
/// ends, and the run's marker every few seconds with what `ping` told it.
public final class StallWatch: @unchecked Sendable {
    private let health: LauncherHealth
    private let started: Date
    private let queue = DispatchQueue(label: "org.anyps5.launcher.stall-watch", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var detector: StallDetector
    private var lines: [String] = []
    private var error: String?
    private var ticks = 0
    private var closed = false
    private let interval: TimeInterval
    /// Wall-clock time of the last ping, for the report's "at".
    private var lastPingDate = Date()

    public init(health: LauncherHealth, started: Date, limit: TimeInterval = LauncherHealth.stall, interval: TimeInterval = 0.5) {
        self.health = health
        self.started = started
        self.interval = interval
        detector = StallDetector(limit: limit, asleep: max(3, interval * 6))
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        queue.async { _ = self.detector.ping(ProcessInfo.processInfo.systemUptime) }
    }

    /// The interface is alive (and in front when `watching`); `lines` (its last seconds) and
    /// `error` go into the marker when given.
    public func ping(watching: Bool, lines: [String]?, error: String?) {
        let now = ProcessInfo.processInfo.systemUptime, date = Date()
        queue.async {
            guard !self.closed else { return }
            if let lines { self.lines = Array(lines.suffix(LauncherHealth.keptLines)) }
            if let error, self.error == nil { self.error = error }
            self.detector.watching = watching
            let since = self.detector.stalledSince
            if let length = self.detector.ping(now), since != nil {
                self.health.writeStall(since: date.addingTimeInterval(-length), length: length, recovered: true, error: self.error, lines: self.lines)
            }
            self.lastPingDate = date
        }
    }

    /// The launcher is quitting: the watchdog writes nothing more (no marker after it went).
    public func closing() {
        queue.sync {
            closed = true
            timer?.cancel()
            timer = nil
        }
    }

    private func tick() {
        guard !closed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if detector.tick(now), let since = detector.stalledSince {
            health.writeStall(since: lastPingDate, length: now - since, recovered: false, error: error, lines: lines)
        }
        // The marker every five seconds: what a crash report says the launcher was doing.
        ticks += 1
        if ticks % max(1, Int(5 / interval)) == 0 {
            health.writeMarker(started: started, alive: Date(), lines: lines, error: error)
        }
    }
}

/// Writes the launcher's uncaught Objective-C exception or fatal signal (with the stack) to
/// LauncherHealth's `fatal-<pid>.txt`, then lets macOS end the process and write its own crash
/// report as before. The signal handler only writes to a file opened beforehand.
public enum CrashCatcher {
    nonisolated(unsafe) private static var descriptor: Int32 = -1
    nonisolated(unsafe) private static var messages = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 32)
    /// The signal handler's stack frames: nothing is allocated there.
    nonisolated(unsafe) private static var frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 64)
    public static let signals: [(Int32, String)] = [
        (SIGSEGV, "SIGSEGV (a bad memory access)"), (SIGBUS, "SIGBUS (a bad memory access)"), (SIGILL, "SIGILL (an illegal instruction)"),
        (SIGFPE, "SIGFPE (an arithmetic error)"), (SIGTRAP, "SIGTRAP (a Swift runtime check: a nil unwrapped, an index out of range, a fatalError)"),
        (SIGABRT, "SIGABRT (abort)"),
    ]

    /// The tests' crashing child ends here rather than in macOS's crash reporter.
    nonisolated(unsafe) static var exitInstead = false

    public static func install(health: LauncherHealth) {
        guard descriptor < 0 else { return }
        descriptor = open(health.fatalFile.path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o644)
        guard descriptor >= 0 else { return }
        messages.initialize(repeating: nil, count: 32)
        for (number, name) in signals { messages[Int(number)] = strdup("Fatal signal \(name)\n") }
        NSSetUncaughtExceptionHandler { exception in
            let text = "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.prefix(30).joined(separator: "\n") + "\n"
            text.withCString { _ = Darwin.write(CrashCatcher.descriptor, $0, strlen($0)) }
        }
        for (number, _) in signals {
            signal(number) { number in
                if CrashCatcher.descriptor >= 0 {
                    if number >= 0, number < 32, let message = CrashCatcher.messages[Int(number)] { _ = Darwin.write(CrashCatcher.descriptor, message, strlen(message)) }
                    let count = backtrace(CrashCatcher.frames, 64)
                    backtrace_symbols_fd(CrashCatcher.frames, count, CrashCatcher.descriptor)
                }
                if CrashCatcher.exitInstead { _exit(70) }
                signal(number, SIG_DFL)
                raise(number)
            }
        }
    }
}
