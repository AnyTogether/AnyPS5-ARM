import Foundation

/// A party: up to eight friends together, with a leader and, while one runs, a voice call.
public struct TogetherParty: Decodable, Equatable, Sendable, Identifiable {
    public struct Call: Decodable, Equatable, Sendable {
        public let id: String
        /// Who is in the voice call now, by user ID.
        public let `in`: [String]

        public init(id: String, in members: [String]) {
            self.id = id
            self.in = members
        }
    }

    public static let maxSize = 8

    public let id: String
    public let leaderId: String
    /// "invite": only people a member invited may join; "friends": the leader's friends too.
    public let privacy: String
    public let members: [TogetherPerson]
    public let invited: [TogetherPerson]
    public let call: Call?

    public init(id: String, leaderId: String, privacy: String, members: [TogetherPerson], invited: [TogetherPerson], call: Call?) {
        self.id = id
        self.leaderId = leaderId
        self.privacy = privacy
        self.members = members
        self.invited = invited
        self.call = call
    }

    public var open: Bool { privacy == "friends" }
    public func isLeader(_ userId: String) -> Bool { leaderId == userId }

    /// Whether `me` may remove `member` or hand them the lead: the leader, about someone else in the party.
    public func canManage(_ member: String, me: String) -> Bool {
        isLeader(me) && member != me && members.contains { $0.userId == member }
    }
}

/// An invite waiting for the user.
public struct TogetherPartyInvite: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { partyId }
    public let partyId: String
    public let from: TogetherPerson?
    public let size: Int

    public init(partyId: String, from: TogetherPerson?, size: Int) {
        self.partyId = partyId
        self.from = from
        self.size = size
    }
}

extension TogetherClient {
    public func myParty() async throws -> (party: TogetherParty?, invites: [TogetherPartyInvite]) {
        struct Mine: Decodable { let party: TogetherParty?; let invites: [TogetherPartyInvite] }
        let mine = try JSONDecoder.together.decode(Mine.self, from: try await authorized("GET", "me/party", nil))
        return (mine.party, mine.invites)
    }

    /// A new party with the user as its leader (leaving the one they were in); `open` lets
    /// friends join without an invite.
    public func startParty(open: Bool = false) async throws -> TogetherParty {
        try party(try await authorized("POST", "parties", ["privacy": open ? "friends" : "invite"]))
    }

    public func setParty(_ partyId: String, open: Bool) async throws -> TogetherParty {
        try party(try await authorized("PATCH", "parties/\(partyId)", ["privacy": open ? "friends" : "invite"]))
    }

    public func invite(_ userIds: [String], to partyId: String) async throws -> TogetherParty {
        try party(try await authorized("POST", "parties/\(partyId)/invites", ["userIds": userIds]))
    }

    /// An invite accepted, or a friend's open party walked into.
    public func joinParty(_ partyId: String) async throws -> TogetherParty {
        try party(try await authorized("POST", "parties/\(partyId)/join", [:]))
    }

    public func declineParty(_ partyId: String) async throws {
        _ = try await authorized("POST", "parties/\(partyId)/decline", [:])
    }

    public func leaveParty(_ partyId: String) async throws {
        _ = try await authorized("POST", "parties/\(partyId)/leave", [:])
    }

    /// The leader removes someone from the party.
    public func kick(_ userId: String, from partyId: String) async throws {
        _ = try await authorized("POST", "parties/\(partyId)/kick", ["userId": userId])
    }

    /// The leader hands the lead to another member.
    public func makeLeader(_ userId: String, of partyId: String) async throws -> TogetherParty {
        try party(try await authorized("POST", "parties/\(partyId)/leader", ["userId": userId]))
    }

    private func party(_ data: Data) throws -> TogetherParty { try JSONDecoder.together.decode(TogetherParty.self, from: data) }
}
