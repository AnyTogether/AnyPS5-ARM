import Foundation

/// Takes out of a report what names the user or lets someone act as them: the home folder and
/// other users' folders, the user's names, e-mail addresses, private network addresses, the
/// AnyTogether tokens and the identifiers macOS puts in a crash report.
public struct ReportPrivacy: Sendable {
    public var home: String
    /// The account name, the full name and the computer's name.
    public var names: [String]
    /// Values known to be secret (the AnyTogether tokens), taken out wherever they appear.
    public var secrets: [String]

    public init(home: String, names: [String] = [], secrets: [String] = []) {
        self.home = home
        self.names = names
        self.secrets = secrets
    }

    /// This Mac's user; `names` adds the computer's name, `secrets` the AnyTogether tokens.
    public static func current(names: [String] = [], secrets: [String] = []) -> ReportPrivacy {
        ReportPrivacy(home: NSHomeDirectory(), names: [NSUserName(), NSFullUserName()] + names, secrets: secrets)
    }

    private static let keys = "access_?token|refresh_?token|relay_?token|session_?token|id_?token|token|secret|password|passwd|api_?key"
        + "|crashReporterKey|sleepWakeUUID|deviceIdentifierForVendor|deviceIdentifierForAdvertising"
    private static let rules: [(NSRegularExpression, String)] = [
        (#"eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}"#, "<token>"),
        (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{6,}"#, "Bearer <token>"),
        (#"(?i)("?\b(?:\#(keys))\b"?\s*[:=]\s*"?)([^\s"',;&]{4,})"#, "$1<redacted>"),
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>"),
        (#"\b(?:192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}|10(?:\.\d{1,3}){3})\b"#, "<ip>"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    public func clean(_ text: String) -> String {
        var text = text
        for secret in secrets where secret.count >= 6 { text = text.replacingOccurrences(of: secret, with: "<redacted>") }
        for (expression, template) in Self.rules { text = Self.replace(expression, in: text, with: template) }
        if home.count > 1 {
            let pattern = NSRegularExpression.escapedPattern(for: home) + #"(?![^/\s"':,;)\]}>])"#
            text = Self.replace(try! NSRegularExpression(pattern: pattern), in: text, with: "~")
        }
        text = Self.replace(try! NSRegularExpression(pattern: #"/Users/(?!Shared\b)[^/\s"':,;)\]}>]+"#), in: text, with: "/Users/<user>")
        // The longest first, so "Ada Lovelace" goes before "Ada"; a word that only holds a name stays.
        let variants = Set(names.flatMap { name -> [String] in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return [trimmed, trimmed.replacingOccurrences(of: " ", with: "-"), trimmed.replacingOccurrences(of: " ", with: "_"), trimmed.replacingOccurrences(of: " ", with: "")]
        }.filter { $0.count >= 3 })
        for name in variants.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?i)(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: name) + "(?![A-Za-z0-9])"
            text = Self.replace(try! NSRegularExpression(pattern: pattern), in: text, with: "<user>")
        }
        return text
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

/// The Mac a report comes from.
public struct SystemInfo: Equatable, Sendable {
    public var model: String
    public var chip: String
    public var memoryGB: Int
    /// "15.6 (24G84)".
    public var macOS: String
    /// The display's highest refresh rate, when the launcher knows it.
    public var displayHz: Int?

    public init(model: String, chip: String, memoryGB: Int, macOS: String, displayHz: Int?) {
        self.model = model
        self.chip = chip
        self.memoryGB = memoryGB
        self.macOS = macOS
        self.displayHz = displayHz
    }

    public static func current(displayHz: Int?) -> SystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        return SystemInfo(model: sysctl("hw.model") ?? "unknown Mac", chip: sysctl("machdep.cpu.brand_string") ?? "unknown chip",
                          memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
                          macOS: number + (sysctl("kern.osversion").map { " (\($0))" } ?? ""), displayHz: displayHz)
    }

    /// "Mac15,7 · Apple M3 Pro · 18 GB · macOS 15.6 (24G84) · 120 Hz".
    public var line: String {
        ([model, chip, "\(memoryGB) GB", "macOS \(macOS)"] + (displayHz.map { ["\($0) Hz"] } ?? [])).joined(separator: " · ")
    }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

extension GameSettings {
    /// The settings in one line of English, for a bug report.
    public var reportSummary: String {
        var parts = ["Resolution " + (resolution ?? "default")]
        parts.append(fullscreen ? "Fullscreen" : "Windowed \(windowSize)%")
        parts.append("V-sync " + (vsync || frameGeneration == true ? "on" : "off"))
        parts.append("Frame generation " + (frameGeneration == true ? "on" : "off"))
        parts.append(upscaler == .fsr1 ? String(format: "Upscaling FSR 1 (sharpness %.1f)", sharpness) : "Upscaling bilinear")
        let corners: [Overlay: String] = [.topLeft: "top left", .topRight: "top right", .bottomLeft: "bottom left", .bottomRight: "bottom right"]
        parts.append(corners[overlay].map { "Overlay \($0) (\(style.rawValue))" } ?? "Overlay off")
        parts.append("Language " + (language.map { number in ConsoleLanguage.all.first { $0.number == number }.map { "\($0.name) (\(number))" } ?? "\(number)" } ?? "follows the launcher"))
        parts.append("Shader cache " + (shaderCache == false ? "off" : "on"))
        parts.append("Engine " + (engine ?? "default"))
        parts.append("Controls " + ((controls ?? [:]).isEmpty ? "default" : "\(controls!.count) changed"))
        if tuning != nil { parts.append("Stick and mouse tuning changed") }
        parts.append("Detailed logging " + (trace == true ? "on" : "off"))
        return parts.joined(separator: " · ")
    }
}

/// Everything known about one start of a game, for the report file and the issue: what the
/// launcher, the log and macOS say. Every text it gives out has been through `privacy`.
public struct SessionReport: Sendable {
    public var gameName: String
    public var titleID: String
    public var gameVersion: String
    public var settings: GameSettings
    public var system: SystemInfo
    public var launcherVersion: String
    /// The launcher's update channel ("stable", "nightly"), when it is known.
    public var updateChannel: String?
    /// The engine toolkit the game's bundle was made with, and the one chosen for it now.
    public var unlockedWith: String?
    public var engineNow: String?
    public var diagnosis: Diagnosis?
    public var startedWithoutWindow = false
    /// The session ran with detailed logging (TraceMode).
    public var traced = false
    public var started: Date?
    public var ended: Date?
    /// The log of the session.
    public var session: String
    /// The .ips crash report macOS wrote for the game's process.
    public var crashReport: String?
    /// What the last unlock of the game printed (unwrapping, relinking, patching).
    public var unlockLog: String?
    /// The controllers connected and the last connects and disconnects (PadLog.report).
    public var controllers: [String] = []
    public var created: Date
    public var privacy: ReportPrivacy

    /// The log lines the report text carries; the rest of the log goes into a file next to it.
    public static let tailLines = 200

    public init(gameName: String, titleID: String, gameVersion: String, settings: GameSettings, system: SystemInfo, launcherVersion: String,
                session: String, created: Date = Date(), privacy: ReportPrivacy) {
        self.gameName = gameName
        self.titleID = titleID
        self.gameVersion = gameVersion
        self.settings = settings
        self.system = system
        self.launcherVersion = launcherVersion
        self.session = session
        self.created = created
        self.privacy = privacy
    }

    /// The game stopped on an error, a crash, or before it ever showed its window.
    public var abnormal: Bool { diagnosis != nil || startedWithoutWindow }

    /// Why the game stopped, in English.
    public var reason: String {
        if let diagnosis { return diagnosis.report }
        if startedWithoutWindow { return "The game closed before its window appeared" }
        return "No error found: the game closed normally"
    }

    public static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// "AnyPS5-PPSA01234-20261024-214600".
    public var baseName: String { "AnyPS5-\(titleID)-\(Self.stamp(created))" }

    /// More than one file to give: the crash report, the unlock output or a log longer than the
    /// report's tail.
    public var archived: Bool {
        if crashReport != nil || unlockLog != nil { return true }
        // Counted only as far as the tail reaches: a session's log can be tens of MB.
        var newlines = 0
        for byte in session.utf8 where byte == 10 {
            newlines += 1
            if newlines > Self.tailLines { return true }
        }
        return false
    }

    public var fileName: String { baseName + (archived ? ".zip" : ".txt") }

    /// The last `count` lines of the session's log, cleaned.
    public func logTail(_ count: Int) -> [String] {
        Array(lines(of: privacy.clean(String(session.suffix(count * 600)))).suffix(count))
    }

    private func lines(of text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).reversed().drop { $0.isEmpty }.reversed()
    }

    /// The crash report's exception, its detail and the crashed thread's innermost frames.
    func crashSummary(frames: Int) -> [String] {
        guard let crashReport else { return [] }
        var lines: [String] = []
        if let exception = Diagnosis.crashException(crashReport) {
            let subtype = (Diagnosis.crashBody(crashReport)?["exception"] as? [String: Any])?["subtype"] as? String
            lines.append(exception + (subtype.map { ", " + $0 } ?? ""))
        }
        let stack = Diagnosis.crashFrames(crashReport, limit: frames)
        if !stack.isEmpty { lines += ["Crashed thread:"] + stack.map { "  " + $0 } }
        return lines
    }

    var versionsLine: String {
        var parts = ["Launcher \(launcherLine)"]
        if let unlockedWith { parts.append("unlocked with engine \(unlockedWith)") }
        if let engineNow, engineNow != unlockedWith { parts.append("engine chosen now \(engineNow)") }
        return parts.joined(separator: " · ")
    }

    /// The launcher's version and its update channel: "0.2.16-arm (stable channel)".
    var launcherLine: String {
        launcherVersion + (updateChannel.map { " (\($0) channel)" } ?? "")
    }

    var sessionLine: String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm:ss"
        var parts: [String] = []
        if let started { parts.append("started \(time.string(from: started))") }
        if let started, let ended {
            let seconds = max(0, Int(ended.timeIntervalSince(started)))
            parts.append("ran \(seconds / 60) min \(seconds % 60) s")
        }
        parts.append(startedWithoutWindow ? "no window shown" : "window shown")
        parts.append("detailed logging " + (traced ? "on" : "off"))
        return parts.joined(separator: ", ")
    }

    /// The report: the game, why it stopped, the Mac, the versions, the settings, the crash and
    /// the end of the log.
    public func text() -> String {
        let created = ISO8601DateFormatter.string(from: self.created, timeZone: .current, formatOptions: [.withInternetDateTime])
        var lines = [
            "AnyPS5 crash report, \(created)",
            "",
            "Game: \(gameName) (\(titleID)), version \(gameVersion)",
            "What happened: \(reason)",
            "Session: \(sessionLine)",
            "",
            "System: \(system.line)",
            "Launcher: \(launcherLine)",
            "Engine the game was unlocked with: \(unlockedWith ?? "unknown")",
            "Engine chosen for it now: \(engineNow ?? "unknown")",
            "",
            "Settings: \(settings.reportSummary)",
        ]
        if !controllers.isEmpty { lines += ["", "Controllers:"] + controllers.map { "  " + $0 } }
        let crash = crashSummary(frames: 24)
        if !crash.isEmpty { lines += ["", "macOS crash report (the whole report: crash-report.ips):"] + crash.map { "  " + $0 } }
        if unlockLog != nil { lines += ["", "The last unlock's output: unlock.log"] }
        let tail = logTail(Self.tailLines)
        lines += ["", archived ? "The last \(tail.count) log lines (the whole log: game.log):" : "The log:"] + tail
        return privacy.clean(lines.joined(separator: "\n")) + "\n"
    }

    /// Writes the report to `file`: the text alone, or, when `archived`, a zip holding a folder
    /// with the text, the whole log, the crash report, the unlock output and the settings.
    public func write(to file: URL) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: file)
        guard archived else { return try Data(text().utf8).write(to: file, options: .atomic) }
        let stage = manager.temporaryDirectory.appendingPathComponent("anyps5-report-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: stage) }
        let folder = stage.appendingPathComponent(baseName)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text().utf8).write(to: folder.appendingPathComponent(baseName + ".txt"))
        try Data(privacy.clean(session).utf8).write(to: folder.appendingPathComponent("game.log"))
        if let crashReport { try Data(privacy.clean(crashReport).utf8).write(to: folder.appendingPathComponent("crash-report.ips")) }
        if let unlockLog { try Data(privacy.clean(unlockLog).utf8).write(to: folder.appendingPathComponent("unlock.log")) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Data(privacy.clean(String(decoding: try encoder.encode(settings), as: UTF8.self)).utf8).write(to: folder.appendingPathComponent("settings.json"))
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, file.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw InstallError("ditto could not make the report's zip (\(ditto.terminationStatus))") }
    }
}
