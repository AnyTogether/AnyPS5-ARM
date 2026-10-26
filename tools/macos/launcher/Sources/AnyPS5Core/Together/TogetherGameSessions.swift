import Foundation

/// Any JSON value: a game session's properties, which only the launchers give a meaning.
public enum TogetherJSON: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([TogetherJSON])
    case object([String: TogetherJSON])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([TogetherJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: TogetherJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// A game someone runs that friends can join: the same game version on the same engine build.
public struct TogetherGameSession: Codable, Equatable, Sendable, Identifiable {
    public enum Mismatch: Equatable, Sendable { case gameVersion, engineBuild }

    /// online: the game's own online play (as before); lan: Play Together, the party's LAN game
    /// that ends with its host; local: one screen, nobody joins over the network.
    public enum Kind: String, Codable, Sendable {
        case online, lan, local

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .online
        }
    }

    public let id: String
    public let kind: Kind
    /// The party a Play Together session belongs to.
    public let partyId: String?
    public let host: TogetherPerson?
    public let titleId: String
    public let gameVersion: String
    public let engineBuild: String
    /// exact, major or any: how far a joiner's game version may be from the host's.
    public let versionRule: String
    public let capacity: Int
    public let joinable: Bool
    public let players: [TogetherPerson]
    public let properties: [String: TogetherJSON]

    public init(id: String, kind: Kind = .online, partyId: String? = nil, host: TogetherPerson?, titleId: String, gameVersion: String, engineBuild: String,
                versionRule: String = "exact", capacity: Int, joinable: Bool, players: [TogetherPerson], properties: [String: TogetherJSON] = [:]) {
        self.id = id
        self.kind = kind
        self.partyId = partyId
        self.host = host
        self.titleId = titleId
        self.gameVersion = gameVersion
        self.engineBuild = engineBuild
        self.versionRule = versionRule
        self.capacity = capacity
        self.joinable = joinable
        self.players = players
        self.properties = properties
    }

    enum CodingKeys: String, CodingKey { case id, kind, partyId, host, titleId, gameVersion, engineBuild, versionRule, capacity, joinable, players, properties }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), kind: (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .online,
                  partyId: try c.decodeIfPresent(String.self, forKey: .partyId), host: try c.decodeIfPresent(TogetherPerson.self, forKey: .host),
                  titleId: try c.decode(String.self, forKey: .titleId), gameVersion: try c.decode(String.self, forKey: .gameVersion),
                  engineBuild: try c.decode(String.self, forKey: .engineBuild), versionRule: try c.decodeIfPresent(String.self, forKey: .versionRule) ?? "exact",
                  capacity: try c.decode(Int.self, forKey: .capacity), joinable: try c.decode(Bool.self, forKey: .joinable),
                  players: try c.decode([TogetherPerson].self, forKey: .players), properties: try c.decodeIfPresent([String: TogetherJSON].self, forKey: .properties) ?? [:])
    }

    /// A Play Together game (the party's LAN game).
    public var together: Bool { kind == .lan }

    /// Why this Mac's copy cannot join, or nil when it can.
    public func mismatch(gameVersion: String, engineBuild: String) -> Mismatch? {
        if !TogetherGameSession.versionFits(versionRule, host: self.gameVersion, joiner: gameVersion) { return .gameVersion }
        if engineBuild != self.engineBuild { return .engineBuild }
        return nil
    }

    /// Whether a joiner's game version fits the host's under the host's rule: the same (exact),
    /// the same first dot-separated part (major) or any.
    public static func versionFits(_ rule: String, host: String, joiner: String) -> Bool {
        switch rule {
        case "any": return true
        case "major": return Int(host.split(separator: ".").first ?? "") == Int(joiner.split(separator: ".").first ?? "")
        default: return host == joiner
        }
    }

    /// Versions compared by their numbers: 01.010 > 01.9, 0.2.21-4194 > 0.2.20-5000.
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        let parts = { (text: String) in text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) } }
        let left = parts(a), right = parts(b)
        for index in 0..<max(left.count, right.count) {
            let x = index < left.count ? left[index] : 0, y = index < right.count ? right[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// An engine build as the server takes it: letters, digits and . _ + -, at most 64.
    public static func engineBuild(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")
        let cleaned = String(String.UnicodeScalarView(raw.trimmingCharacters(in: .whitespaces).unicodeScalars.map { allowed.contains($0) ? $0 : "-" }).prefix(64))
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    /// A game version as the server takes it (at most 32 of the same characters).
    public static func gameVersion(_ raw: String) -> String { String(engineBuild(raw).prefix(32)) }

    /// The session for the engine's online bridge (ANYPS5_TOGETHER_SESSION points at the file):
    /// the session, the user's ID and whether they host it. nil removes the file.
    public static func write(_ session: TogetherGameSession?, me: String, to file: URL) throws {
        guard let session else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        struct Bridge: Encodable { let role: String; let userId: String; let session: TogetherGameSession }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(Bridge(role: session.host?.userId == me ? "host" : "guest", userId: me, session: session)).write(to: file, options: .atomic)
    }

    public static var bridgeFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Together/game-session.json")
    }
}

/// An invitation to a friend's game.
public struct TogetherGameInvite: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { sessionId }
    public let sessionId: String
    public let from: TogetherPerson?
    public let titleId: String
    public let gameVersion: String
    public let engineBuild: String

    public init(sessionId: String, from: TogetherPerson?, titleId: String, gameVersion: String, engineBuild: String) {
        self.sessionId = sessionId
        self.from = from
        self.titleId = titleId
        self.gameVersion = gameVersion
        self.engineBuild = engineBuild
    }
}

extension TogetherClient {
    /// A session for the game this launcher runs (ending any other the user is in).
    public func openGameSession(titleId: String, gameVersion: String, engineBuild: String, capacity: Int, joinable: Bool = true) async throws -> TogetherGameSession {
        try gameSession(try await authorized("POST", "game-sessions", ["titleId": titleId, "gameVersion": gameVersion, "engineBuild": engineBuild, "capacity": capacity, "joinable": joinable]))
    }

    public func myGameSession() async throws -> (session: TogetherGameSession?, invites: [TogetherGameInvite]) {
        struct Mine: Decodable { let session: TogetherGameSession?; let invites: [TogetherGameInvite] }
        let mine = try JSONDecoder.together.decode(Mine.self, from: try await authorized("GET", "me/game-session", nil))
        return (mine.session, mine.invites)
    }

    public func gameSession(_ id: String) async throws -> TogetherGameSession {
        try gameSession(try await authorized("GET", "game-sessions/\(id)", nil))
    }

    public func updateGameSession(_ id: String, joinable: Bool) async throws -> TogetherGameSession {
        try gameSession(try await authorized("PATCH", "game-sessions/\(id)", ["joinable": joinable]))
    }

    /// Refused with "version_mismatch" (409) unless both match the host's, "full" when it is.
    /// `overrideVersion`: Try anyway after a game version refusal (the engine is still checked).
    public func joinGameSession(_ id: String, gameVersion: String, engineBuild: String, overrideVersion: Bool = false) async throws -> TogetherGameSession {
        var body: [String: Any] = ["gameVersion": gameVersion, "engineBuild": engineBuild]
        if overrideVersion { body["overrideVersion"] = true }
        return try gameSession(try await authorized("POST", "game-sessions/\(id)/join", body))
    }

    public func inviteToGame(_ userIds: [String], session id: String) async throws {
        _ = try await authorized("POST", "game-sessions/\(id)/invites", ["userIds": userIds])
    }

    public func declineGame(_ id: String) async throws {
        _ = try await authorized("POST", "game-sessions/\(id)/decline", [:])
    }

    public func leaveGameSession(_ id: String) async throws {
        _ = try await authorized("POST", "game-sessions/\(id)/leave", [:])
    }

    /// Why the host ends it: they ended it, or their game exited.
    public enum EndReason: String, Sendable { case ended, gameExited = "game_exited" }

    public func endGameSession(_ id: String, reason: EndReason = .ended) async throws {
        _ = try await authorized("DELETE", reason == .ended ? "game-sessions/\(id)" : "game-sessions/\(id)?reason=\(reason.rawValue)", nil)
    }

    /// Play Together: a LAN game in the user's party (the party hears it start); it ends with
    /// the host. One per party: a 409 "conflict" when the party already plays together.
    public func startPlayTogether(titleId: String, gameVersion: String, engineBuild: String, capacity: Int, versionRule: String = "exact") async throws -> TogetherGameSession {
        try gameSession(try await authorized("POST", "game-sessions", ["kind": "lan", "titleId": titleId, "gameVersion": gameVersion, "engineBuild": engineBuild,
                                                                      "capacity": capacity, "versionRule": versionRule]))
    }

    /// The host hands out a join code: whoever holds it may join the game.
    public func gameSessionCode(_ id: String) async throws -> TogetherJoinCode {
        try JSONDecoder.together.decode(TogetherJoinCode.self, from: try await authorized("POST", "game-sessions/\(id)/code", [:]))
    }

    private func gameSession(_ data: Data) throws -> TogetherGameSession { try JSONDecoder.together.decode(TogetherGameSession.self, from: data) }
}
