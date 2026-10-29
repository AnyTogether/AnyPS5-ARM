import Foundation

/// A GitHub "new issue" page filled in from a report: its title and form fields, as a link that
/// stays under the length browsers and GitHub take.
public struct IssueDraft: Sendable {
    public struct Field: Sendable, Equatable {
        public let id: String
        public let label: String
        public let value: String
    }

    public static let repository = "AnyTogether/AnyPS5-ARM"
    /// The engine's own repository, for a bug in the engine rather than in the Mac port.
    public static let engineRepository = "boykopovar/AnyPS5"
    /// Where the launcher's own crashes and stalls go (.github/ISSUE_TEMPLATE/launcher_crash.yml).
    public static let launcherRepository = "AnyTogether/AnyPS5-ARM"
    public static let maximumLength = 7000
    /// One log line longer than this is cut, so it cannot crowd out the rest.
    static let lineLimit = 300

    public let title: String
    public let fields: [Field]
    public let url: URL

    /// What the link sends, as the user is shown it before it opens.
    public var preview: String {
        ([title] + fields.map { "\n\($0.label)\n\($0.value)" }).joined(separator: "\n")
    }

    static let attachHint = "Attach the report file the launcher saved (Export Report): drag %@ into this box."

    /// The Mac port's crash form (.github/ISSUE_TEMPLATE/crash.yml).
    public static func crash(_ report: SessionReport, logLines: Int = 60) -> IssueDraft {
        var reason = report.reason
        let crash = report.crashSummary(frames: 6)
        if !crash.isEmpty { reason += "\n" + crash.joined(separator: "\n") }
        let fixed = [
            Field(id: "game", label: "Game", value: "\(report.gameName) (\(report.titleID)), version \(report.gameVersion)"),
            Field(id: "reason", label: "What happened", value: reason),
            Field(id: "system", label: "Mac", value: report.system.line),
            Field(id: "versions", label: "Versions", value: report.versionsLine),
            Field(id: "settings", label: "Game settings", value: report.settings.reportSummary + "\nSession: " + report.sessionLine
                + (report.controllers.first.map { "\nController: " + $0 } ?? "")),
        ]
        let attach = Field(id: "report", label: "Report file", value: String(format: attachHint, report.fileName))
        return fit(repository: repository, template: "crash.yml", title: "Crash: \(report.gameName) (\(report.titleID))",
                   fixed: fixed, log: (id: "log", label: "Last log lines"), after: [attach], report: report, logLines: logLines)
    }

    /// The engine's bug form (boykopovar/AnyPS5, bug_report.yml), with the same facts.
    public static func engine(_ report: SessionReport, logLines: Int = 60) -> IssueDraft {
        let engine = report.unlockedWith ?? report.engineNow ?? "unknown"
        let crash = report.crashSummary(frames: 6)
        let fixed = [
            Field(id: "summary", label: "What happens", value: report.reason),
            Field(id: "commit", label: "AnyPS5 commit", value: "AnyPS5-ARM engine \(engine) (the macOS port, github.com/\(repository)), launcher \(report.launcherLine)"),
            Field(id: "system", label: "System", value: report.system.line),
            Field(id: "steps", label: "Steps to reproduce", value: "Started \(report.gameName) from the AnyPS5 macOS launcher.\nSettings: \(report.settings.reportSummary)\nSession: \(report.sessionLine)"),
        ]
        let notes = Field(id: "notes", label: "What was checked", value: (crash.isEmpty ? "" : crash.joined(separator: "\n") + "\n\n") + String(format: attachHint, report.fileName))
        // Their form's "title" field takes the issue title's parameter too: one value for both.
        return fit(repository: engineRepository, template: "bug_report.yml", title: "Crash: \(report.gameName) (\(report.titleID)) \(report.gameVersion)",
                   fixed: fixed, log: (id: "log", label: "Log"), after: [notes], report: report, logLines: logLines)
    }

    /// The launcher's own crash or stall (LauncherHealth), on launcher_crash.yml: every field
    /// cleaned by `privacy`, the oldest lines going first until the link is short enough.
    public static func launcherProblem(_ problem: LauncherProblem, system: SystemInfo, privacy: ReportPrivacy) -> IssueDraft {
        let formatter = ISO8601DateFormatter()
        let at = String(formatter.string(from: problem.at).prefix(19)).replacingOccurrences(of: "T", with: " ")
        let seconds = Int(problem.stalledFor ?? 0)
        let title: String, what: String
        switch problem.kind {
        case .crash:
            title = "Launcher crash"
            what = "The launcher closed without being quit (a crash, or Force Quit). Last seen alive \(at) UTC."
        case .hang where problem.recovered == true:
            title = "Launcher stopped responding (\(seconds)s)"
            what = "The interface did not answer for \(seconds) s from \(at) UTC, then went on."
        case .hang:
            title = "Launcher stopped responding"
            what = "The interface stopped answering at \(at) UTC and did not answer again (\(seconds)s or more) before it was closed."
        }
        func cut(_ line: String) -> String { line.count > lineLimit ? String(line.prefix(lineLimit)) + "…" : line }
        var error = problem.error.map { privacy.clean($0).components(separatedBy: "\n").prefix(40).map(cut).joined(separator: "\n") } ?? "None caught."
        var lines = problem.lines.map { cut(privacy.clean($0)) }
        while true {
            let fields = [
                Field(id: "what", label: "What happened", value: what + "\nWhat I was doing: "),
                Field(id: "system", label: "System", value: privacy.clean(system.line)),
                Field(id: "versions", label: "Version", value: privacy.clean("Launcher \(problem.version) (\(problem.platform))")),
                Field(id: "error", label: "Uncaught error", value: error),
                Field(id: "log", label: "Last seconds", value: lines.isEmpty ? "(none kept)" : lines.joined(separator: "\n")),
            ]
            let url = link(repository: launcherRepository, template: "launcher_crash.yml", title: title, fields: fields)
            if url.absoluteString.count <= maximumLength { return IssueDraft(title: title, fields: fields, url: url) }
            if !lines.isEmpty {
                lines.removeFirst()
            } else {
                error = String(error.prefix(error.count * 3 / 4)) + "…"
            }
        }
    }

    /// The newest log lines that fit: the oldest go first until the link is short enough.
    static func fit(repository: String, template: String, title: String, fixed: [Field], log: (id: String, label: String), after: [Field],
                    report: SessionReport, logLines: Int) -> IssueDraft {
        let clean = { (field: Field) in Field(id: field.id, label: field.label, value: report.privacy.clean(field.value)) }
        let title = report.privacy.clean(title)
        var fields = fixed.map(clean)
        var tail = report.logTail(logLines).map { $0.count > lineLimit ? String($0.prefix(lineLimit)) + "…" : $0 }
        var trailing = after.map(clean)
        while true {
            let all = fields + [Field(id: log.id, label: log.label, value: tail.joined(separator: "\n"))] + trailing
            let url = link(repository: repository, template: template, title: title, fields: all)
            if url.absoluteString.count <= maximumLength { return IssueDraft(title: title, fields: all, url: url) }
            if !tail.isEmpty {
                tail.removeFirst()
            } else if let longest = (fields + trailing).indices.max(by: { (fields + trailing)[$0].value.count < (fields + trailing)[$1].value.count }) {
                // Only a form of very long settings gets here: its longest field is shortened.
                var every = fields + trailing
                let field = every[longest]
                every[longest] = Field(id: field.id, label: field.label, value: String(field.value.prefix(field.value.count * 3 / 4)) + "…")
                fields = Array(every.prefix(fields.count))
                trailing = Array(every.suffix(trailing.count))
            }
        }
    }

    static func link(repository: String, template: String, title: String, fields: [Field]) -> URL {
        // RFC 3986's unreserved characters; a "+" left as it is would read as a space.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        var parameters = [("template", template), ("title", title)]
        // A form field with the id "title" is filled from the title parameter already.
        parameters += fields.filter { $0.id != "title" }.map { ($0.id, $0.value) }
        let query = parameters.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "https://github.com/\(repository)/issues/new?\(query)")!
    }
}
