import Foundation

/// Why a game stopped, read from what its last start wrote to the log and from the crash report
/// macOS left for it.
public enum Diagnosis: Equatable, Sendable {
    /// dyld could not find a module the executable links.
    case missingModule(String)
    /// The game called a system function the engine does not implement yet.
    case unsupported(String)
    /// The GPU device was lost.
    case gpuLost
    /// The engine or the GPU ran out of memory.
    case outOfMemory
    /// Any other error the engine stopped on, with its message.
    case engineError(String)
    /// The process was killed by a signal or an exception, as the crash report names it.
    case crashed(String)
    /// The engine stopped the game with abort() ("[libc] abort() called from …").
    case aborted
    /// The game exited with a status other than 0, as detailed logging (APS5_TRACE_EXIT) shows.
    case exited(Int)

    /// The line the launcher writes to a game's log before it starts the game.
    public static let startMarker = "[anyps5-launcher] start"

    /// The log text of the last start: what follows the last start marker, or the end of the log
    /// when the game was started some other way.
    public static func lastSession(_ log: String) -> String {
        if let range = log.range(of: startMarker, options: .backwards) { return String(log[range.upperBound...]) }
        return String(log.suffix(64 * 1024))
    }

    /// The reason in `session` (the log of one start) and the crash report, nil for a game that
    /// ended without a sign of trouble.
    public static func read(session: String, crashReport: String? = nil) -> Diagnosis? {
        if let module = firstMatch(#"Library not loaded: (?:@rpath/)?(\S+)"#, in: session) {
            return .missingModule((module as NSString).lastPathComponent)
        }
        if let message = firstMatch(#"uncaught C\+\+ exception \S+ of type [^\n,]+, what\(\): ([^\n]+)"#, in: session)
            ?? firstMatch(#"terminating (?:due to|with) uncaught exception of type \S+?: ([^\n]+)"#, in: session) {
            return classify(message)
        }
        if session.contains("VK_ERROR_DEVICE_LOST") { return .gpuLost }
        if session.contains("VK_ERROR_OUT_OF_DEVICE_MEMORY") || session.contains("std::bad_alloc") { return .outOfMemory }
        if session.contains("[libc] abort() called") { return .aborted }
        if let crashReport, let exception = crashException(crashReport) { return .crashed(exception) }
        if let code = lastMatch(#"^\[libc\] (?:exit|_Exit)\((-?\d+)\) called"#, in: session).flatMap(Int.init), code != 0 { return .exited(code) }
        return nil
    }

    /// What happened, in English for a bug report (the launcher shows its own translation).
    public var report: String {
        switch self {
        case .missingModule(let name): return "Missing module: \(name)"
        case .unsupported(let function): return "Unsupported system function: \(function)"
        case .gpuLost: return "The GPU device was lost (VK_ERROR_DEVICE_LOST)"
        case .outOfMemory: return "Out of memory"
        case .engineError(let message): return "Engine error: \(message)"
        case .crashed(let exception): return "The game crashed: \(exception)"
        case .aborted: return "The engine stopped the game (abort)"
        case .exited(let code): return "The game exited with status \(code)"
        }
    }

    /// A log that ends on the GPU's shutdown summary: the engine went down in order.
    public static func cleanShutdown(_ session: String) -> Bool {
        session.suffix(16 * 1024).contains("host imports at shutdown")
    }

    /// The crashed thread of an .ips crash report, innermost first: "0  image  symbol + 12", or
    /// "0  image  + 0x1a2b" without a symbol.
    public static func crashFrames(_ report: String, limit: Int = 16) -> [String] {
        guard let body = crashBody(report), let threads = body["threads"] as? [[String: Any]] else { return [] }
        let index = body["faultingThread"] as? Int ?? 0
        guard threads.indices.contains(index), let frames = threads[index]["frames"] as? [[String: Any]] else { return [] }
        let images = (body["usedImages"] as? [[String: Any]]) ?? []
        return frames.prefix(limit).enumerated().map { number, frame in
            let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil } ?? "???"
            if let symbol = frame["symbol"] as? String {
                return "\(number)  \(image)  \(symbol) + \(frame["symbolLocation"] as? Int ?? 0)"
            }
            return "\(number)  \(image)  + 0x" + String(frame["imageOffset"] as? Int ?? 0, radix: 16)
        }
    }

    static func crashBody(_ report: String) -> [String: Any]? {
        guard let newline = report.firstIndex(of: "\n") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(report[report.index(after: newline)...].utf8)) as? [String: Any]
    }

    static func classify(_ message: String) -> Diagnosis {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        if let function = firstMatch(#"^(\S+) not implemented"#, in: trimmed) { return .unsupported(function) }
        if trimmed.contains("VK_ERROR_DEVICE_LOST") || trimmed.localizedCaseInsensitiveContains("device lost") { return .gpuLost }
        if trimmed.contains("VK_ERROR_OUT_OF_DEVICE_MEMORY") || trimmed.localizedCaseInsensitiveContains("out of memory") { return .outOfMemory }
        return .engineError(trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed)
    }

    /// "EXC_BAD_ACCESS (SIGSEGV)" from an .ips crash report: a JSON header line, then the report.
    public static func crashException(_ report: String) -> String? {
        guard let body = crashBody(report), let exception = body["exception"] as? [String: Any], let type = exception["type"] as? String else { return nil }
        if let signal = exception["signal"] as? String { return "\(type) (\(signal))" }
        return type
    }

    /// Where macOS writes the crash reports of the user's processes.
    public static var reportsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    /// The newest crash report macOS wrote for the game's executable since `start`; with `pid`,
    /// only the report of that process.
    public static func crashReport(since start: Date, bundleIdentifier: String, pid: Int32? = nil, folder: URL = reportsFolder, process: String = "eboot") -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let reports = files.compactMap { file -> (URL, Date)? in
            guard file.lastPathComponent.hasPrefix(process), file.pathExtension == "ips",
                  let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date >= start else { return nil }
            return (file, date)
        }
        for (file, _) in reports.sorted(by: { $0.1 > $1.1 }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            guard text.prefix(4096).contains(bundleIdentifier) else { continue }
            if let pid, firstMatch(#"^\s*"pid"\s*:\s*(\d+)"#, in: text).flatMap(Int32.init) != pid { continue }
            return text
        }
        return nil
    }

    static func lastMatch(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last, match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// A game's settings as a file to share: another player imports them onto their copy of the game.
public struct SharedSettings: Codable, Sendable {
    public static let format = "anyps5-settings"

    public var format = SharedSettings.format
    public var version = 1
    public let titleID: String
    public let game: String
    public let settings: GameSettings

    public init(game: Game, settings: GameSettings) {
        self.titleID = game.titleID
        self.game = game.name
        self.settings = settings
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func read(_ data: Data) throws -> SharedSettings {
        let shared = try JSONDecoder().decode(SharedSettings.self, from: data)
        guard shared.format == format else { throw InstallError("not an AnyPS5 settings file") }
        return shared
    }
}
