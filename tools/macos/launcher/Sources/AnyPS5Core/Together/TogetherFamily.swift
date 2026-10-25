import Foundation

/// What a child asks a parent for; parents answer on the website.
public enum FamilyAsk: Equatable, Sendable {
    /// More time today (5 to 240 minutes), while playing a game or not.
    case moreTime(minutes: Int, titleId: String? = nil, note: String? = nil)
    /// A game the age rating keeps closed.
    case playGame(titleId: String, name: String? = nil, note: String? = nil)
    /// Someone the friend rules do not let the child add.
    case addFriend(handle: String, note: String? = nil)

    var body: [String: Any] {
        var body: [String: Any]
        let note: String?
        switch self {
        case .moreTime(let minutes, let titleId, let text):
            body = ["kind": "more_time", "minutes": min(240, max(5, minutes))]
            if let titleId { body["titleId"] = titleId }
            note = text
        case .playGame(let titleId, let name, let text):
            body = ["kind": "play_game", "titleId": titleId]
            if let name { body["name"] = String(name.prefix(200)) }
            note = text
        case .addFriend(let handle, let text):
            body = ["kind": "add_friend", "handle": handle]
            note = text
        }
        if let note, !note.isEmpty { body["note"] = String(note.prefix(200)) }
        return body
    }
}

/// A feature a parent's settings can turn off, as a 403 "restricted_by_family" names it.
public enum FamilyFeature: String, Sendable {
    case friendRequests = "friend_requests"
    case messages
    case voiceChat = "voice_chat"
    case sharePlay = "share_play"
    case publicMatchmaking = "public_matchmaking"
    case profileVisibility = "profile_visibility"
    case discovery
    case communities
    case mediaSharing = "media_sharing"
    case ageRating = "age_rating"
    case family
}

extension TogetherProblem {
    /// What the family settings refused, with "restricted_by_family"; `.family` when it does not say.
    public var familyFeature: FamilyFeature? {
        guard code == "restricted_by_family" else { return nil }
        return feature.flatMap(FamilyFeature.init(rawValue:)) ?? .family
    }

    /// The other person's family limit refused it (a friend request to a restricted child), not
    /// the asker's own.
    public var byOthersFamily: Bool { code == "restricted_by_family" && side == "other" }
}

extension TogetherClient {
    /// The family status for the signed-in account, and the server's signed copy of it.
    public func familyStatus() async throws -> (status: FamilyStatus, signed: String) {
        struct Answer: Decodable { let signed: String }
        let data = try await authorized("GET", "me/family/restrictions", nil)
        return (try JSONDecoder.together.decode(FamilyStatus.self, from: data), try JSONDecoder.together.decode(Answer.self, from: data).signed)
    }

    /// The keys the server signs with.
    public func signingKeys() async throws -> [FamilyKey] {
        struct Keys: Decodable { let keys: [FamilyKey] }
        return try JSONDecoder.together.decode(Keys.self, from: try await send("GET", ".well-known/jwks.json", nil)).keys
    }

    /// True for a new ask; false when the same one already waits for a parent (the server
    /// answers it with 200 and the waiting request).
    @discardableResult
    public func askFamily(_ ask: FamilyAsk) async throws -> Bool {
        try await authorizedResponse("POST", "me/family/requests", ask.body).status == 201
    }

    /// Tells the parents the child reached today's limit; the server tells them once a day.
    public func familyLimitReached(titleId: String?) async throws {
        _ = try await authorized("POST", "me/family/limit-reached", titleId.map { ["titleId": $0] } ?? [String: String]())
    }
}

extension FamilyCache {
    /// The status from the server, checked against its keys and kept; what applies comes back.
    /// The signed copy decides, not the plain answer beside it.
    @discardableResult
    public func refresh(from client: TogetherClient, now: Date = Date()) async throws -> FamilyStanding {
        async let answer = client.familyStatus()
        async let keys = client.signingKeys()
        let (signed, known) = try await (answer.signed, keys)
        try accept(signed: signed, keys: known, server: client.base, now: now)
        return standing(now: now)
    }
}
