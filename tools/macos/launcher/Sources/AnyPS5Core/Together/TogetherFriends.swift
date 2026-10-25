import Foundation

/// A friend as AnyTogether shows them: who, and what they are doing now.
public struct TogetherFriend: Decodable, Equatable, Sendable, Identifiable {
    public struct Presence: Decodable, Equatable, Sendable {
        /// The party they are in: its size, and whether friends may walk in.
        public struct Party: Decodable, Equatable, Sendable {
            public let id: String
            public let size: Int
            public let max: Int
            public let open: Bool

            public init(id: String, size: Int, max: Int, open: Bool) {
                self.id = id
                self.size = size
                self.max = max
                self.open = open
            }
        }

        /// The game session they host: open to friends and not full when joinable.
        public struct Game: Decodable, Equatable, Sendable {
            public let sessionId: String
            public let titleId: String
            public let joinable: Bool
            public let players: Int
            public let capacity: Int

            public init(sessionId: String, titleId: String, joinable: Bool, players: Int, capacity: Int) {
                self.sessionId = sessionId
                self.titleId = titleId
                self.joinable = joinable
                self.players = players
                self.capacity = capacity
            }
        }

        public let state: String
        public let titleId: String?
        public let since: String?
        public let party: Party?
        public let game: Game?
        /// The game they share for friends to watch.
        public let share: TogetherSharePresence?

        public init(state: String, titleId: String?, since: String?, party: Party? = nil, game: Game? = nil, share: TogetherSharePresence? = nil) {
            self.state = state
            self.titleId = titleId
            self.since = since
            self.party = party
            self.game = game
            self.share = share
        }

        public var playing: Bool { state == "in_game" }
        public var online: Bool { state != "offline" }
    }

    public var id: String { userId }
    public let userId: String
    public let handle: String
    public let displayName: String
    public let avatar: String?
    public let presence: Presence?
    /// Their trophy level; nil when their trophies are private to this user (or an older server).
    public var level: TogetherLevelBadge?

    public init(userId: String, handle: String, displayName: String, avatar: String?, presence: Presence?, level: TogetherLevelBadge? = nil) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
        self.presence = presence
        self.level = level
    }

    enum CodingKeys: String, CodingKey { case userId, handle, displayName, avatar, presence, level }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(userId: try container.decode(String.self, forKey: .userId), handle: try container.decode(String.self, forKey: .handle),
                  displayName: try container.decode(String.self, forKey: .displayName), avatar: try container.decodeIfPresent(String.self, forKey: .avatar),
                  presence: try container.decodeIfPresent(Presence.self, forKey: .presence), level: container.lenient(TogetherLevelBadge.self, .level))
    }
}

/// Someone who asked to be friends, or whom this user asked.
public struct TogetherPerson: Codable, Equatable, Sendable, Identifiable {
    public var id: String { userId }
    public let userId: String
    public let handle: String
    public let displayName: String
    public let avatar: String?

    public init(userId: String, handle: String, displayName: String, avatar: String?) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
    }
}

public struct TogetherRequests: Decodable, Equatable, Sendable {
    public let incoming: [TogetherPerson]
    public let outgoing: [TogetherPerson]

    public init(incoming: [TogetherPerson], outgoing: [TogetherPerson]) {
        self.incoming = incoming
        self.outgoing = outgoing
    }
}

extension TogetherClient {
    public func friends() async throws -> [TogetherFriend] {
        struct List: Decodable { let friends: [TogetherFriend] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "me/friends", nil)).friends
    }

    public func friendRequests() async throws -> TogetherRequests {
        try JSONDecoder.together.decode(TogetherRequests.self, from: try await authorized("GET", "me/friends/requests", nil))
    }

    /// Asks `handle` to be friends; "accepted" when they had already asked.
    @discardableResult
    public func askFriend(_ handle: String) async throws -> String {
        struct State: Decodable { let state: String }
        let cleaned = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return try JSONDecoder.together.decode(State.self, from: try await authorized("POST", "me/friends/requests", ["handle": cleaned])).state
    }

    public func answerFriend(_ userId: String, accept: Bool) async throws {
        _ = try await authorized("POST", "me/friends/requests/\(userId)/\(accept ? "accept" : "decline")", [:])
    }

    public func removeFriend(_ userId: String) async throws {
        _ = try await authorized("DELETE", "me/friends/\(userId)", nil)
    }

    public func searchPeople(_ query: String) async throws -> [TogetherPerson] {
        struct Found: Decodable { let users: [TogetherPerson] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try JSONDecoder.together.decode(Found.self, from: try await authorized("GET", "users/search?q=\(encoded)", nil)).users
    }
}
