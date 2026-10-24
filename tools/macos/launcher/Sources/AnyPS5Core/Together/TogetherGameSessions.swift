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

    public let id: String
    public let host: TogetherPerson?
    public let titleId: String
    public let gameVersion: String
    public let engineBuild: String
    public let capacity: Int
    public let joinable: Bool
    public let players: [TogetherPerson]
    public let properties: [String: TogetherJSON]

    public init(id: String, host: TogetherPerson?, titleId: String, gameVersion: String, engineBuild: String, capacity: Int, joinable: Bool, players: [TogetherPerson], properties: [String: TogetherJSON] = [:]) {
        self.id = id
        self.host = host
        self.titleId = titleId
        self.gameVersion = gameVersion
        self.engineBuild = engineBuild
        self.capacity = capacity
        self.joinable = joinable
        self.players = players
        self.properties = properties
    }

    /// Why this Mac's copy cannot join, or nil when it can.
    public func mismatch(gameVersion: String, engineBuild: String) -> Mismatch? {
        if gameVersion != self.gameVersion { return .gameVersion }
        if engineBuild != self.engineBuild { return .engineBuild }
        return nil
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
    public func joinGameSession(_ id: String, gameVersion: String, engineBuild: String) async throws -> TogetherGameSession {
        try gameSession(try await authorized("POST", "game-sessions/\(id)/join", ["gameVersion": gameVersion, "engineBuild": engineBuild]))
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

    public func endGameSession(_ id: String) async throws {
        _ = try await authorized("DELETE", "game-sessions/\(id)", nil)
    }

    private func gameSession(_ data: Data) throws -> TogetherGameSession { try JSONDecoder.together.decode(TogetherGameSession.self, from: data) }
}
