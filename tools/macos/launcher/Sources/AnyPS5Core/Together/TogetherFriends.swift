import Foundation

/// A friend as AnyTogether shows them: who, and what they are doing now.
public struct TogetherFriend: Decodable, Equatable, Sendable, Identifiable {
    public struct Presence: Decodable, Equatable, Sendable {
        public let state: String
        public let titleId: String?
        public let since: String?

        public init(state: String, titleId: String?, since: String?) {
            self.state = state
            self.titleId = titleId
            self.since = since
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

    public init(userId: String, handle: String, displayName: String, avatar: String?, presence: Presence?) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
        self.presence = presence
    }
}

/// Someone who asked to be friends, or whom this user asked.
public struct TogetherPerson: Decodable, Equatable, Sendable, Identifiable {
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
