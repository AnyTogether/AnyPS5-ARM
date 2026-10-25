import Foundation

/// AnyTogether's game sessions as the online router uses them: JSON in, JSON out, so the router
/// stays testable without a server. TogetherClient is the real one.
public protocol OnlineSessionService: Sendable {
    func call(_ method: String, _ path: String, _ body: Data?) async throws -> Data
}

extension TogetherClient: OnlineSessionService {
    public func call(_ method: String, _ path: String, _ body: Data?) async throws -> Data {
        let object = try body.flatMap { $0.isEmpty ? nil : try JSONSerialization.jsonObject(with: $0) }
        return try await authorized(method, path, object)
    }
}

/// A game session as AnyTogether shows it, as much as the launcher needs.
public struct OnlineSessionView: Decodable, Equatable, Sendable {
    public struct Member: Decodable, Equatable, Sendable {
        public let userId: String
        public let handle: String
    }

    /// What a player published in the session: the device (the AnyTogether session their
    /// launcher signs in with) is where signals for them go. Only players see it.
    public struct Published: Decodable, Equatable, Sendable {
        public let userId: String
        public let device: String?
    }

    public let id: String
    public let titleId: String
    public let gameVersion: String
    public let engineBuild: String
    public let players: [Member]
    public let members: [Published]?
    public let endedAt: String?

    public init(id: String, titleId: String, gameVersion: String, engineBuild: String, players: [Member], members: [Published]? = nil, endedAt: String? = nil) {
        self.id = id
        self.titleId = titleId
        self.gameVersion = gameVersion
        self.engineBuild = engineBuild
        self.players = players
        self.members = members
        self.endedAt = endedAt
    }

    /// The virtual address of each player (`OnlineIdentity.addresses`): the same on every
    /// launcher, and nobody's moves when someone leaves.
    public var addresses: [String: UInt32] { OnlineIdentity.addresses(for: players.map(\.userId)) }
}

/// Answers the engine's web API requests. The `anyps5` group maps onto AnyTogether's game
/// sessions and invitations for this game; `userProfile` is answered from AnyTogether friends
/// (`OnlineUserProfile`, unverified) and `communicationRestrictionStatus` with "not restricted"
/// while `platformGroups` is on; every other platform group is
/// answered "not offered" until its format is known from observation, and every such request is
/// counted so it shows up.
public final class OnlineWebRouter: @unchecked Sendable {
    public struct Game: Sendable {
        public var titleId: String
        public var gameVersion: String
        public var engineBuild: String
        public init(titleId: String, gameVersion: String, engineBuild: String) {
            self.titleId = titleId
            self.gameVersion = gameVersion
            self.engineBuild = engineBuild
        }
    }

    public static let group = "anyps5"

    private let service: OnlineSessionService
    private let profile: OnlineUserProfile?
    private let platformGroups: Bool
    private let lock = NSLock()
    private var game: Game
    private var unanswered: [String: Int] = [:]
    private let sessionChanged: @Sendable (OnlineSessionView?) -> Void

    /// `profile` answers `userProfile` (nil while signed out); `platformGroups` off answers every
    /// platform group "not offered", for a clean observation run.
    public init(service: OnlineSessionService, game: Game, profile: OnlineUserProfile? = nil, platformGroups: Bool = true,
                sessionChanged: @escaping @Sendable (OnlineSessionView?) -> Void = { _ in }) {
        self.service = service
        self.game = game
        self.profile = profile
        self.platformGroups = platformGroups
        self.sessionChanged = sessionChanged
    }

    /// Platform groups and paths the game asked for that nobody answers yet, with counts.
    public var notOffered: [String: Int] { lock.withLock { unanswered } }

    public func setEngineBuild(_ build: String) { lock.withLock { game.engineBuild = build } }

    public func handle(_ request: OnlineWire.WebRequest) async -> OnlineWire.WebReply {
        if request.apiGroup == OnlineUserProfile.group, platformGroups, let profile { return await profile.handle(request) }
        if request.apiGroup == OnlineUserProfile.restrictionGroup, platformGroups, let profile { return profile.handleRestriction(request) }
        guard request.apiGroup == OnlineWebRouter.group else {
            let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
            lock.withLock { unanswered["\(request.apiGroup) \(request.method) \(path)", default: 0] += 1 }
            return .notOffered
        }
        let game = lock.withLock { self.game }
        let parts = request.path.split(separator: "?", maxSplits: 1).first.map { $0.split(separator: "/").map(String.init) } ?? []
        let method = request.method.uppercased()
        let id = parts.count >= 3 && parts[0] == "v1" && parts[1] == "sessions" ? parts[2] : nil
        if let id, id.isEmpty || id.count > 64 || !id.allSatisfy({ $0.isHexDigit || $0 == "-" }) {
            return problem(404, "not_found", "No such game session")
        }
        let action = parts.count == 4 ? parts[3] : nil
        do {
            switch (method, parts.count, id, action) {
            case ("POST", 2, _, _) where parts == ["v1", "sessions"]:
                var fields = try object(request.body)
                fields["titleId"] = game.titleId
                fields["gameVersion"] = game.gameVersion
                fields["engineBuild"] = game.engineBuild
                if fields["capacity"] == nil { fields["capacity"] = 2 }
                return try await session("POST", "game-sessions", fields, status: 201)
            case ("GET", 3, let id?, nil):
                return try await session("GET", "game-sessions/\(id)", nil, status: 200)
            case ("PATCH", 3, let id?, nil):
                return try await session("PATCH", "game-sessions/\(id)", try object(request.body), status: 200)
            case ("POST", 4, let id?, "join"):
                return try await session("POST", "game-sessions/\(id)/join", ["gameVersion": game.gameVersion, "engineBuild": game.engineBuild], status: 200)
            case ("POST", 4, let id?, "leave"):
                _ = try await service.call("POST", "game-sessions/\(id)/leave", Data("{}".utf8))
                sessionChanged(nil)
                return OnlineWire.WebReply(status: 204)
            case ("POST", 4, let id?, "invites"):
                return json(200, try await service.call("POST", "game-sessions/\(id)/invites", request.body))
            case ("GET", 3, _, _) where parts == ["v1", "me", "session"]:
                return json(200, try await service.call("GET", "me/game-session", nil))
            default:
                return problem(404, "not_found", "No such \(OnlineWebRouter.group) call")
            }
        } catch let problem as TogetherProblem {
            return self.problem(problem.status, problem.code, problem.title)
        } catch {
            return problem(502, "unavailable", "AnyTogether could not be reached")
        }
    }

    private func session(_ method: String, _ path: String, _ fields: [String: Any]?, status: UInt16) async throws -> OnlineWire.WebReply {
        let body = try fields.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await service.call(method, path, body)
        if let view = try? JSONDecoder.together.decode(OnlineSessionView.self, from: data) {
            sessionChanged(view.endedAt == nil ? view : nil)
        }
        return json(status, data)
    }

    private func object(_ body: Data) throws -> [String: Any] {
        guard !body.isEmpty else { return [:] }
        guard let fields = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw TogetherProblem(status: 400, code: "invalid_input", title: "The body must be a JSON object")
        }
        return fields
    }

    private func json(_ status: UInt16, _ data: Data) -> OnlineWire.WebReply {
        OnlineWire.WebReply(status: status, headers: [.init("Content-Type", "application/json")], body: data)
    }

    private func problem(_ status: Int, _ code: String, _ title: String) -> OnlineWire.WebReply {
        let body = (try? JSONSerialization.data(withJSONObject: ["status": status, "code": code, "title": title])) ?? Data()
        return OnlineWire.WebReply(status: UInt16(clamping: status), headers: [.init("Content-Type", "application/problem+json")], body: body)
    }
}
