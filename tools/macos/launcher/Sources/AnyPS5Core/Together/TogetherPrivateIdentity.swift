import Foundation

/// A person card that may carry the friends-only name and picture (docs/private-identity.md).
public protocol TogetherIdentityCard {
    var userId: String { get }
    var handle: String { get }
    var displayName: String { get }
    var avatar: String? { get }
    var privateName: String? { get }
    var privateAvatar: String? { get }
}

extension TogetherFriend: TogetherIdentityCard {}
extension TogetherPerson: TogetherIdentityCard {}
extension TogetherProfile: TogetherIdentityCard {}

/// The friends' private names and pictures as the last friends list (over HTTP) said, by user
/// ID: realtime events never carry them, so a card from an event takes them from here. A friend
/// gone from the list, or one who cleared them, is forgotten with the next list.
public struct TogetherIdentityBook: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let name: String?
        public let avatar: String?
    }

    public private(set) var entries: [String: Entry] = [:]
    public private(set) var learnedAt: Date?

    public init() {}

    public mutating func learn(friends: [TogetherFriend], at date: Date = Date()) {
        var next: [String: Entry] = [:]
        for friend in friends {
            let name = TogetherIdentity.clean(friend.privateName)
            let avatar = TogetherIdentity.clean(friend.privateAvatar)
            if name != nil || avatar != nil { next[friend.userId] = Entry(name: name, avatar: avatar) }
        }
        entries = next
        learnedAt = date
    }

    /// Signed picture links last 6 to 12 hours: a list older than this is read again.
    public func stale(at date: Date = Date()) -> Bool {
        learnedAt.map { date.timeIntervalSince($0) > 5 * 3600 } ?? true
    }

    public subscript(userId: String) -> Entry? { entries[userId] }
}

/// What to show for someone: the private name and picture when there, else the public ones,
/// and the handle always beside a private name.
public struct TogetherIdentity: Equatable, Sendable {
    public let name: String
    public let avatar: String?
    public let handle: String
    public let publicName: String
    /// The name shown is the friends-only one.
    public let isPrivate: Bool

    public static func shown(_ card: TogetherIdentityCard, book: TogetherIdentityBook) -> TogetherIdentity {
        shown(userId: card.userId, handle: card.handle, displayName: card.displayName, avatar: card.avatar,
              privateName: card.privateName, privateAvatar: card.privateAvatar, book: book)
    }

    public static func shown(userId: String, handle: String, displayName: String, avatar: String?, privateName: String? = nil, privateAvatar: String? = nil,
                             book: TogetherIdentityBook) -> TogetherIdentity {
        let entry = book[userId]
        let name = clean(privateName) ?? entry?.name
        let picture = clean(privateAvatar) ?? entry?.avatar
        return TogetherIdentity(name: name ?? displayName, avatar: picture ?? avatar, handle: handle, publicName: displayName, isPrivate: name != nil)
    }

    static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension TogetherClient {
    /// The friends-only name (PATCH /me/profile); blank clears it.
    public func setPrivateName(_ name: String) async throws -> TogetherOwnProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any = trimmed.isEmpty ? NSNull() : trimmed
        return try JSONDecoder.together.decode(TogetherOwnProfile.self, from: try await authorized("PATCH", "me/profile", ["privateName": value]))
    }

    /// The friends-only picture (PUT /me/avatar/private): a PNG or JPEG, at most 5 MB; the public
    /// picture stays. Returns the signed link, which runs out.
    public func uploadPrivateAvatar(_ picture: Data) async throws -> String {
        struct Answer: Decodable { let privateAvatar: String }
        let body = TogetherRawBody(data: picture, contentType: ProfilePicture.contentType(picture))
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("PUT", "me/avatar/private", body)).privateAvatar
    }

    public func removePrivateAvatar() async throws {
        _ = try await authorized("DELETE", "me/avatar/private", nil)
    }

    /// A friend's private name or picture reported to the moderators.
    public func reportPrivateProfile(_ userId: String, reason: String) async throws {
        _ = try await authorized("POST", "reports", ["targetKind": "private_profile", "targetId": userId, "reason": reason])
    }
}
