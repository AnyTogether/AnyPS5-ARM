import Foundation

/// How far a game gets on AnyPS5, worst to best.
public enum TogetherCompatStatus: String, CaseIterable, Codable, Sendable {
    case nothing, boots, menus, ingame, playable
}

/// The community's verdict for a game on one platform: what the newest launcher version tested reached.
public struct TogetherCompatSummary: Decodable, Equatable, Sendable {
    public let statusName: String
    public let version: String
    public let testedAt: Date
    public let reports: Int

    public var status: TogetherCompatStatus? { TogetherCompatStatus(rawValue: statusName) }

    enum CodingKeys: String, CodingKey {
        case version, testedAt, reports
        case statusName = "status"
    }

    public init(status: TogetherCompatStatus, version: String, testedAt: Date = Date(), reports: Int) {
        self.statusName = status.rawValue
        self.version = version
        self.testedAt = testedAt
        self.reports = reports
    }
}

/// A game on the compatibility list, with each platform's verdict.
public struct TogetherCompatGame: Decodable, Equatable, Sendable {
    public let titleId: String
    public let name: String?
    public let platforms: [String: TogetherCompatSummary]

    public var mac: TogetherCompatSummary? { platforms["macos"] }
}

/// A report on how a game ran, sent after a session when the player says.
public struct TogetherCompatReport: Equatable, Sendable {
    public var titleId: String
    public var name: String?
    public var status: TogetherCompatStatus
    public var launcherVersion: String
    public var engineVersion: String?
    public var machine: String?
    public var os: String?
    public var fpsAvg: Double?
    public var gameVersion: String?
    public var note: String?

    public init(titleId: String, name: String? = nil, status: TogetherCompatStatus, launcherVersion: String, engineVersion: String? = nil, machine: String? = nil,
                os: String? = nil, fpsAvg: Double? = nil, gameVersion: String? = nil, note: String? = nil) {
        self.titleId = titleId
        self.name = name
        self.status = status
        self.launcherVersion = launcherVersion
        self.engineVersion = engineVersion
        self.machine = machine
        self.os = os
        self.fpsAvg = fpsAvg
        self.gameVersion = gameVersion
        self.note = note
    }

    /// A version as the server takes it: letters, digits and . _ + - only, at most 40.
    public static func version(_ text: String?) -> String? {
        guard let text else { return nil }
        let kept = String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._+-".unicodeScalars.contains($0) }.prefix(40))
        return kept.isEmpty ? nil : kept
    }

    /// The JSON body: only what is known, cut to the server's lengths.
    public var body: [String: Any] {
        var body: [String: Any] = ["titleId": titleId, "platform": "macos", "status": status.rawValue, "launcherVersion": Self.version(launcherVersion) ?? "dev"]
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { body["name"] = String(name.prefix(200)) }
        if let engine = Self.version(engineVersion) { body["engineVersion"] = engine }
        if let machine, !machine.isEmpty { body["machine"] = String(machine.prefix(120)) }
        if let os, !os.isEmpty { body["os"] = String(os.prefix(60)) }
        if let fpsAvg, fpsAvg >= 0, fpsAvg <= 1000 { body["fpsAvg"] = fpsAvg }
        if let gameVersion, !gameVersion.isEmpty { body["gameVersion"] = String(gameVersion.prefix(20)) }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { body["note"] = String(note.prefix(500)) }
        return body
    }
}

/// When the launcher asks "How did it run?" after a session: once per game and launcher
/// version, after a session long enough to tell.
public enum TogetherCompatPrompt {
    public static let minimumSeconds: TimeInterval = 60

    /// `asked`: title ID → the launcher version last asked about it.
    public static func shouldAsk(titleId: String, played seconds: TimeInterval, launcherVersion: String, asked: [String: String]) -> Bool {
        seconds >= minimumSeconds && asked[titleId] != launcherVersion
    }
}

extension TogetherClient {
    /// Sends a report; the game's verdict on the Mac as it is now.
    @discardableResult
    public func reportCompat(_ report: TogetherCompatReport) async throws -> TogetherCompatSummary? {
        struct Answer: Decodable { let summary: TogetherCompatSummary? }
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("POST", "compat/reports", report.body)).summary
    }

    /// The game's verdicts; nil when no one reported it (or the server does not know it).
    public func compat(_ titleId: String) async throws -> TogetherCompatGame? {
        do {
            return try JSONDecoder.together.decode(TogetherCompatGame.self, from: try await authorized("GET", "compat/\(Self.path(titleId))", nil))
        } catch let problem as TogetherProblem where problem.status == 404 {
            return nil
        }
    }
}
