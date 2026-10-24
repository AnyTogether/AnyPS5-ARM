import Foundation

/// The four reactions an activity item can get, one per person.
public enum TogetherReaction: String, CaseIterable, Codable, Sendable {
    case fire, clap, wow, heart

    public var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .clap: return "👏"
        case .wow: return "😮"
        case .heart: return "❤️"
        }
    }
}

/// One item of the activity feed as AnyTogether shows it to this user: trophies earned in a game,
/// a platinum, a first play, a long session, a new friend or a milestone.
public struct TogetherActivity: Decodable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case trophy, platinum, friendship, milestone
        case firstPlay = "first_play"
        case longSession = "long_session"
        /// A kind this launcher does not know yet.
        case other
    }

    public struct Game: Decodable, Equatable, Sendable {
        public let titleId: String
        public let names: [String: String]
        public let iconUrl: String?

        public init(titleId: String, names: [String: String], iconUrl: String? = nil) {
            self.titleId = titleId
            self.names = names
            self.iconUrl = iconUrl
        }

        public func name(in language: String) -> String { TogetherNames.pick(names, language) ?? titleId }
    }

    public struct Trophy: Decodable, Equatable, Sendable {
        public let trophyId: Int
        public let grade: String
        public let hidden: Bool
        /// nil for a hidden trophy this user has not earned.
        public let texts: [String: TogetherEarnedTrophy.Text]?
        public let rarity: Double?
        public let rarityLabel: String?

        public init(trophyId: Int, grade: String, hidden: Bool = false, texts: [String: TogetherEarnedTrophy.Text]?, rarity: Double? = nil, rarityLabel: String? = nil) {
            self.trophyId = trophyId
            self.grade = grade
            self.hidden = hidden
            self.texts = texts
            self.rarity = rarity
            self.rarityLabel = rarityLabel
        }

        public func name(in language: String) -> String? {
            texts.flatMap { TogetherNames.pick($0.mapValues(\.name), language) }
        }
    }

    public struct Milestone: Decodable, Equatable, Sendable {
        /// "trophies", "platinums", "games" or "hours".
        public let kind: String
        public let value: Int

        public init(kind: String, value: Int) {
            self.kind = kind
            self.value = value
        }
    }

    public struct Reactions: Decodable, Equatable, Sendable {
        public var counts: [TogetherReaction: Int]
        public var mine: TogetherReaction?

        public init(counts: [TogetherReaction: Int] = [:], mine: TogetherReaction? = nil) {
            self.counts = counts
            self.mine = mine
        }

        enum CodingKeys: String, CodingKey { case counts, mine }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
            counts = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in TogetherReaction(rawValue: key).map { ($0, value) } }.filter { $0.1 > 0 })
            mine = (try container.decodeIfPresent(String.self, forKey: .mine)).flatMap(TogetherReaction.init(rawValue:))
        }

        public var total: Int { counts.values.reduce(0, +) }

        /// As they will be once `reaction` is chosen: the same one again takes it back, another
        /// one takes the old one's place.
        public func choosing(_ reaction: TogetherReaction) -> Reactions {
            var next = self
            if let mine { next.counts[mine] = (next.counts[mine] ?? 1) - 1 }
            next.mine = mine == reaction ? nil : reaction
            if let chosen = next.mine { next.counts[chosen, default: 0] += 1 }
            next.counts = next.counts.filter { $0.value > 0 }
            return next
        }
    }

    public let id: String
    public let kindName: String
    public let createdAt: Date
    public let actor: TogetherPerson
    public let game: Game?
    /// "platinum", "rare" (a trophy held by at most 20 % of players) or nil.
    public let highlight: String?
    /// The best first, at most five.
    public let trophies: [Trophy]?
    public let trophyCount: Int?
    public let seconds: Int?
    public let friend: TogetherPerson?
    public let milestone: Milestone?
    public var reactions: Reactions

    public var kind: Kind { Kind(rawValue: kindName) ?? .other }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, actor, game, highlight, trophies, trophyCount, seconds, friend, milestone, reactions
        case kindName = "kind"
    }

    public init(id: String, kind: Kind, createdAt: Date, actor: TogetherPerson, game: Game? = nil, highlight: String? = nil, trophies: [Trophy]? = nil,
                trophyCount: Int? = nil, seconds: Int? = nil, friend: TogetherPerson? = nil, milestone: Milestone? = nil, reactions: Reactions = .init()) {
        self.id = id
        self.kindName = kind.rawValue
        self.createdAt = createdAt
        self.actor = actor
        self.game = game
        self.highlight = highlight
        self.trophies = trophies
        self.trophyCount = trophyCount
        self.seconds = seconds
        self.friend = friend
        self.milestone = milestone
        self.reactions = reactions
    }

    /// The item a `feed.item` event carries.
    public static func from(_ event: TogetherSocket.Event) -> TogetherActivity? {
        event.type == "feed.item" ? event.decode(TogetherActivity.self) : nil
    }
}

public struct TogetherFeedPage: Decodable, Equatable, Sendable {
    public let items: [TogetherActivity]
    /// Pass as `before` for the next, older page; nil at the end.
    public let next: String?

    public init(items: [TogetherActivity], next: String?) {
        self.items = items
        self.next = next
    }
}

/// The feed as the launcher holds it: newest first (IDs are time-ordered UUIDv7s), one item per ID.
public struct TogetherFeed: Equatable, Sendable {
    public private(set) var items: [TogetherActivity] = []
    public private(set) var next: String?
    public private(set) var loaded = false

    public init() {}

    /// The first page, in place of whatever was read before.
    public mutating func load(_ page: TogetherFeedPage) {
        items = []
        loaded = true
        next = page.next
        page.items.forEach { upsert($0) }
    }

    /// An older page, after what is there.
    public mutating func loadOlder(_ page: TogetherFeedPage) {
        next = page.next
        page.items.forEach { upsert($0) }
    }

    /// A new or changed item: it replaces the one with its ID, or goes in at its place.
    public mutating func upsert(_ item: TogetherActivity) {
        if let index = index(of: item.id) {
            items[index] = item
        } else {
            items.insert(item, at: items.firstIndex { $0.id < item.id } ?? items.endIndex)
        }
    }

    public mutating func setReactions(_ reactions: TogetherActivity.Reactions, for id: String) {
        guard let index = index(of: id) else { return }
        items[index].reactions = reactions
    }

    public func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }
}

extension TogetherClient {
    /// Friends' activity, newest first; `before` an item's ID reads the page after it.
    public func feed(before: String? = nil, limit: Int? = nil) async throws -> TogetherFeedPage {
        try JSONDecoder.together.decode(TogetherFeedPage.self, from: try await authorized("GET", "me/feed" + Self.paging(before, limit), nil))
    }

    /// One person's recent activity, as their privacy lets this user see it.
    public func activity(of handle: String, before: String? = nil, limit: Int? = nil) async throws -> TogetherFeedPage {
        try JSONDecoder.together.decode(TogetherFeedPage.self, from: try await authorized("GET", "users/\(Self.path(handle))/activity" + Self.paging(before, limit), nil))
    }

    /// Reacts to an item, or takes the reaction back with nil; the item's reactions as they are now.
    @discardableResult
    public func react(to id: String, with reaction: TogetherReaction?) async throws -> TogetherActivity.Reactions {
        let path = "activities/\(Self.path(id))/reaction"
        let data = try await authorized(reaction == nil ? "DELETE" : "PUT", path, reaction.map { ["reaction": $0.rawValue] })
        return try JSONDecoder.together.decode(TogetherActivity.Reactions.self, from: data)
    }

    static func paging(_ before: String?, _ limit: Int?) -> String {
        let query = [before.map { "before=\($0)" }, limit.map { "limit=\($0)" }].compactMap { $0 }
        return query.isEmpty ? "" : "?" + query.joined(separator: "&")
    }
}
