import Foundation

/// A notification from AnyTogether: a friend request or answer, messages while no device was
/// connected, an invite, a missed call, or a moderator's warning.
public struct TogetherNotification: Decodable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case message, warning
        case friendRequest = "friend_request"
        case friendAccepted = "friend_accepted"
        case partyInvite = "party_invite"
        case gameInvite = "game_invite"
        case missedCall = "missed_call"
        /// Someone said "I'm in" on the user's looking-for-group post, or the poster let the user in.
        case lfgRequest = "lfg_request"
        case lfgAccepted = "lfg_accepted"
        /// The user reached a new trophy level (the actor is the user).
        case levelUp = "level_up"
        /// A kind this launcher does not know yet.
        case other

        public static let allKnown: [Kind] = [.friendRequest, .friendAccepted, .message, .partyInvite, .gameInvite, .missedCall, .lfgRequest, .lfgAccepted, .levelUp, .warning, .other]

        /// Whether a new one deserves a toast of its own: requests, invites and missed calls are
        /// announced by their own events already.
        public var toastsOnItsOwn: Bool {
            switch self {
            case .friendRequest, .friendAccepted, .partyInvite, .gameInvite, .missedCall, .lfgRequest, .lfgAccepted, .levelUp: return false
            case .message, .warning, .other: return true
            }
        }
    }

    /// What a kind carries: message {conversationId, title, group, count, text}, party_invite
    /// {partyId, size}, game_invite {sessionId, titleId}, missed_call {callId}, warning {reason},
    /// lfg_request {postId, titleId, gameNames, purpose, count}, lfg_accepted {postId, titleId,
    /// gameNames, purpose, invite}.
    public struct Details: Decodable, Equatable, Sendable {
        public var conversationId: String?
        public var title: String?
        public var group: Bool?
        public var count: Int?
        public var text: String?
        public var partyId: String?
        public var size: Int?
        public var sessionId: String?
        public var titleId: String?
        public var callId: String?
        public var reason: String?
        public var postId: String?
        public var gameNames: [String: String]?
        public var purpose: String?
        public var invite: TogetherLfgInvite?
        /// Families: family_request {requestId, kind, minutes, titleId, gameName, person},
        /// family_answer {requestId, kind, approved, minutes}, family_alert {event, …},
        /// family_invite {familyName, role}.
        public var kind: String?
        public var approved: Bool?
        public var minutes: Int?
        public var gameName: String?
        public var familyName: String?
        public var role: String?
        public var event: String?
        /// level_up {level, tier, frame}.
        public var level: Int?
        public var tier: String?
        public var frame: Int?

        public init() {}

        /// The level a level_up notification is about.
        public var levelBadge: TogetherLevelBadge? {
            level.map { TogetherLevelBadge(level: $0, tier: tier.flatMap(TogetherLevelBadge.Tier.init(rawValue:)), frame: frame) }
        }
    }

    public let id: String
    public let kindName: String
    /// Who did it; nil for a warning.
    public let actor: TogetherPerson?
    public let subjectId: String?
    public let data: Details
    public var read: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public var kind: Kind { Kind(rawValue: kindName) ?? .other }

    enum CodingKeys: String, CodingKey {
        case id, actor, subjectId, data, read, createdAt, updatedAt
        case kindName = "kind"
    }

    public init(id: String, kind: Kind, actor: TogetherPerson?, subjectId: String? = nil, data: Details = .init(), read: Bool = false, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id
        self.kindName = kind.rawValue
        self.actor = actor
        self.subjectId = subjectId
        self.data = data
        self.read = read
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kindName = try container.decode(String.self, forKey: .kindName)
        actor = try container.decodeIfPresent(TogetherPerson.self, forKey: .actor)
        subjectId = try container.decodeIfPresent(String.self, forKey: .subjectId)
        // Fields of a shape this launcher does not expect are left out, not a failure.
        data = (try? container.decodeIfPresent(Details.self, forKey: .data)) ?? Details()
        read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct TogetherNotificationPage: Decodable, Equatable, Sendable {
    public let notifications: [TogetherNotification]
    public let unread: Int
    /// Older ones remain.
    public let more: Bool

    public init(notifications: [TogetherNotification], unread: Int, more: Bool) {
        self.notifications = notifications
        self.unread = unread
        self.more = more
    }
}

/// What the gateway says about notifications.
public enum TogetherNotificationEvent: Equatable, Sendable {
    /// New, or one that gathered another message; `unread` is the badge count now.
    case new(TogetherNotification, unread: Int)
    /// Read on some device: these, or all (nil).
    case read(ids: [String]?, unread: Int)

    public init?(_ event: TogetherSocket.Event) {
        switch event.type {
        case "notification":
            struct New: Decodable { let notification: TogetherNotification; let unread: Int }
            guard let new = event.decode(New.self) else { return nil }
            self = .new(new.notification, unread: new.unread)
        case "notification.read":
            struct Read: Decodable { let ids: [String]?; let unread: Int }
            guard let read = event.decode(Read.self) else { return nil }
            self = .read(ids: read.ids, unread: read.unread)
        default:
            return nil
        }
    }
}

/// The notification center as the launcher holds it: newest first, one per ID, and the badge.
public struct TogetherNotifications: Equatable, Sendable {
    public private(set) var items: [TogetherNotification] = []
    public private(set) var unread = 0
    public private(set) var more = false
    public private(set) var loaded = false

    public init() {}

    public mutating func load(_ page: TogetherNotificationPage) {
        items = []
        loaded = true
        absorb(page)
    }

    public mutating func loadOlder(_ page: TogetherNotificationPage) { absorb(page) }

    /// The badge alone, read before the list.
    public mutating func setUnread(_ count: Int) { unread = count }

    public mutating func apply(_ event: TogetherNotificationEvent) {
        switch event {
        case .new(let note, let count):
            upsert(note)
            unread = count
        case .read(let ids, let count):
            for index in items.indices where ids?.contains(items[index].id) ?? true { items[index].read = true }
            unread = count
        }
    }

    /// Read here, before the server answers; the badge drops once.
    public mutating func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].read else { return }
        items[index].read = true
        unread = max(0, unread - 1)
    }

    public mutating func markAllRead() {
        for index in items.indices { items[index].read = true }
        unread = 0
    }

    private mutating func absorb(_ page: TogetherNotificationPage) {
        page.notifications.forEach { upsert($0) }
        unread = page.unread
        more = page.more
    }

    private mutating func upsert(_ note: TogetherNotification) {
        if let index = items.firstIndex(where: { $0.id == note.id }) {
            items[index] = note
        } else {
            items.insert(note, at: items.firstIndex { $0.id < note.id } ?? items.endIndex)
        }
    }
}

extension TogetherClient {
    /// Newest first; `before` the last ID of the page before.
    public func notifications(before: String? = nil, limit: Int? = nil) async throws -> TogetherNotificationPage {
        try JSONDecoder.together.decode(TogetherNotificationPage.self, from: try await authorized("GET", "me/notifications" + Self.paging(before, limit), nil))
    }

    public func unreadNotifications() async throws -> Int {
        try Self.unread(try await authorized("GET", "me/notifications/unread", nil))
    }

    /// Marks one read; how many stay unread.
    @discardableResult
    public func readNotification(_ id: String) async throws -> Int {
        try Self.unread(try await authorized("POST", "me/notifications/\(Self.path(id))/read", nil))
    }

    @discardableResult
    public func readAllNotifications() async throws -> Int {
        try Self.unread(try await authorized("POST", "me/notifications/read-all", nil))
    }

    private static func unread(_ data: Data) throws -> Int {
        struct Count: Decodable { let unread: Int }
        return try JSONDecoder.together.decode(Count.self, from: data).unread
    }
}
