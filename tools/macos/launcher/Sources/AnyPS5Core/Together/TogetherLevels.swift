import Foundation

/// A trophy level as a badge: the number, the metal it is drawn in and its frame.
public struct TogetherLevelBadge: Codable, Equatable, Sendable {
    /// bronze 1-99, silver 100-299, gold 300-599, platinum 600-999.
    public enum Tier: String, Codable, CaseIterable, Sendable {
        case bronze, silver, gold, platinum

        public init(level: Int) {
            switch level {
            case 600...: self = .platinum
            case 300...: self = .gold
            case 100...: self = .silver
            default: self = .bronze
            }
        }
    }

    public static let top = 999

    public let level: Int
    public let tier: Tier
    /// 1 for 1-99, 2 for 100-199 … 10 for 900-999: the frame grows every 100 levels.
    public let frame: Int

    public init(level: Int, tier: Tier? = nil, frame: Int? = nil) {
        self.level = max(1, min(Self.top, level))
        self.tier = tier ?? Tier(level: self.level)
        self.frame = max(1, min(10, frame ?? Self.frame(for: self.level)))
    }

    public static func frame(for level: Int) -> Int { min(10, max(1, level / 100 + 1)) }

    enum CodingKeys: String, CodingKey { case level, tier, frame }

    /// A tier or frame this launcher does not know, or left out, is worked out from the level.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let level = try container.decode(Int.self, forKey: .level)
        self.init(level: level, tier: container.lenient(String.self, .tier).flatMap(Tier.init(rawValue:)), frame: container.lenient(Int.self, .frame))
    }
}

/// The level with the way to the next one, as a profile shows it.
public struct TogetherTrophyLevel: Decodable, Equatable, Sendable {
    public let badge: TogetherLevelBadge
    /// All trophy points.
    public let points: Int
    /// Where this level started and where the next one starts (nil at the top).
    public let levelPoints: Int
    public let nextLevelPoints: Int?
    /// How far towards the next level, 0-99 (100 at the top).
    public let progress: Int

    public init(badge: TogetherLevelBadge, points: Int, levelPoints: Int, nextLevelPoints: Int?, progress: Int) {
        self.badge = badge
        self.points = points
        self.levelPoints = levelPoints
        self.nextLevelPoints = nextLevelPoints
        self.progress = max(0, min(100, progress))
    }

    enum CodingKeys: String, CodingKey { case points, levelPoints, nextLevelPoints, progress }

    public init(from decoder: Decoder) throws {
        let badge = try TogetherLevelBadge(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(badge: badge, points: container.lenient(Int.self, .points) ?? 0, levelPoints: container.lenient(Int.self, .levelPoints) ?? 0,
                  nextLevelPoints: container.lenient(Int.self, .nextLevelPoints), progress: container.lenient(Int.self, .progress) ?? 0)
    }

    public var level: Int { badge.level }
    public var tier: TogetherLevelBadge.Tier { badge.tier }
    public var frame: Int { badge.frame }
    public var isTop: Bool { nextLevelPoints == nil }
    /// Points still to earn for the next level; nil at the top.
    public var pointsToNext: Int? { nextLevelPoints.map { max(0, $0 - points) } }
    /// The progress bar's share, 0-1.
    public var fraction: Double { isTop ? 1 : Double(progress) / 100 }

    /// A new badge (a level up the gateway told of) before the points are read again: the way to
    /// the next level starts over.
    public func raised(to badge: TogetherLevelBadge) -> TogetherTrophyLevel {
        guard badge != self.badge else { return self }
        return TogetherTrophyLevel(badge: badge, points: points, levelPoints: points, nextLevelPoints: badge.level >= TogetherLevelBadge.top ? nil : nextLevelPoints.map { max($0, points) },
                                   progress: badge.level >= TogetherLevelBadge.top ? 100 : 0)
    }
}

/// `level.up` from the gateway: the user or a friend (who may see their trophies) went up.
public struct TogetherLevelUp: Equatable, Sendable {
    public let userId: String
    public let handle: String
    public let displayName: String
    public let badge: TogetherLevelBadge

    public init(userId: String, handle: String, displayName: String, badge: TogetherLevelBadge) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.badge = badge
    }

    public init?(_ event: TogetherSocket.Event) {
        struct Data: Decodable { let userId: String; let handle: String?; let displayName: String? }
        guard event.type == "level.up", let data = event.decode(Data.self), let badge = event.decode(TogetherLevelBadge.self) else { return nil }
        self.init(userId: data.userId, handle: data.handle ?? "", displayName: data.displayName ?? data.handle ?? "", badge: badge)
    }

    public func isMine(_ userId: String?) -> Bool { userId != nil && userId == self.userId }
}

extension Array where Element == TogetherFriend {
    /// The friend's new level in the list; false when they are not in it.
    @discardableResult
    public mutating func apply(_ up: TogetherLevelUp) -> Bool {
        guard let index = firstIndex(where: { $0.userId == up.userId }) else { return false }
        self[index].level = up.badge
        return true
    }
}

extension TogetherOwnProfile {
    /// The user's own level up, until the profile is read again.
    public mutating func apply(_ up: TogetherLevelUp) {
        trophyLevel = trophyLevel?.raised(to: up.badge) ?? TogetherTrophyLevel(badge: up.badge, points: 0, levelPoints: 0, nextLevelPoints: nil, progress: 0)
    }
}

// MARK: Showcase

/// A game pinned on a profile.
public struct TogetherShowcaseGame: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { titleId }
    public let titleId: String
    public let names: [String: String]
    public let iconUrl: String?
    public let secondsPlayed: Int
    /// nil when the trophies are private to the reader.
    public let trophiesEarned: Int?
    public let trophiesTotal: Int?
    public let progress: Int?

    public init(titleId: String, names: [String: String], iconUrl: String?, secondsPlayed: Int, trophiesEarned: Int?, trophiesTotal: Int?, progress: Int?) {
        self.titleId = titleId
        self.names = names
        self.iconUrl = iconUrl
        self.secondsPlayed = secondsPlayed
        self.trophiesEarned = trophiesEarned
        self.trophiesTotal = trophiesTotal
        self.progress = progress
    }

    public func name(in language: String) -> String { TogetherNames.pick(names, language) ?? titleId }
}

/// What someone pinned: up to six earned trophies and four games. A part the reader may not see is nil.
public struct TogetherShowcase: Decodable, Equatable, Sendable {
    public let trophies: [TogetherEarnedTrophy]?
    public let games: [TogetherShowcaseGame]?

    public init(trophies: [TogetherEarnedTrophy]?, games: [TogetherShowcaseGame]?) {
        self.trophies = trophies
        self.games = games
    }

    /// Both parts private to the reader.
    public var isPrivate: Bool { trophies == nil && games == nil }
    /// Nothing to show (pinned or private).
    public var isEmpty: Bool { (trophies ?? []).isEmpty && (games ?? []).isEmpty }
}

// MARK: Compare

/// One side of a game compared: trophies earned, of how many, and the points.
public struct TogetherCompareSide: Decodable, Equatable, Sendable {
    public let earned: Int
    public let total: Int?
    public let progress: Int?
    public let points: Int

    public init(earned: Int, total: Int?, progress: Int?, points: Int) {
        self.earned = earned
        self.total = total
        self.progress = progress
        self.points = points
    }
}

/// A game either of the two has trophies in.
public struct TogetherCompareGame: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { titleId }
    public let titleId: String
    public let names: [String: String]
    public let iconUrl: String?
    public let mine: TogetherCompareSide?
    public let theirs: TogetherCompareSide?

    public init(titleId: String, names: [String: String], iconUrl: String?, mine: TogetherCompareSide?, theirs: TogetherCompareSide?) {
        self.titleId = titleId
        self.names = names
        self.iconUrl = iconUrl
        self.mine = mine
        self.theirs = theirs
    }

    /// Both play it.
    public var both: Bool { mine != nil && theirs != nil }
    public func name(in language: String) -> String { TogetherNames.pick(names, language) ?? titleId }
}

/// One game's trophies side by side: who earned which, and when.
public struct TogetherCompareView: Decodable, Equatable, Sendable {
    public struct Person: Decodable, Equatable, Sendable {
        public let userId: String
        public let handle: String
        public let displayName: String
        public let avatar: String?
        public let level: TogetherLevelBadge?

        public init(userId: String, handle: String, displayName: String, avatar: String?, level: TogetherLevelBadge?) {
            self.userId = userId
            self.handle = handle
            self.displayName = displayName
            self.avatar = avatar
            self.level = level
        }

        enum CodingKeys: String, CodingKey { case userId, handle, displayName, avatar, level }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(userId: try container.decode(String.self, forKey: .userId), handle: try container.decode(String.self, forKey: .handle),
                      displayName: try container.decode(String.self, forKey: .displayName), avatar: container.lenient(String.self, .avatar),
                      level: container.lenient(TogetherLevelBadge.self, .level))
        }
    }

    public struct Game: Decodable, Equatable, Sendable {
        public let names: [String: String]
        public let iconUrl: String?

        public init(names: [String: String], iconUrl: String?) {
            self.names = names
            self.iconUrl = iconUrl
        }

        public func name(in language: String) -> String? { TogetherNames.pick(names, language) }
    }

    public struct Trophy: Decodable, Equatable, Sendable, Identifiable {
        public let id: Int
        public let grade: String
        public let hidden: Bool
        /// nil for a hidden trophy the user has not earned.
        public let texts: [String: TogetherEarnedTrophy.Text]?
        public let rarity: Double?
        public let rarityLabel: String?
        /// When each side earned it; nil when not yet.
        public let mine: Date?
        public let theirs: Date?

        public init(id: Int, grade: String, hidden: Bool, texts: [String: TogetherEarnedTrophy.Text]?, rarity: Double?, rarityLabel: String?, mine: Date?, theirs: Date?) {
            self.id = id
            self.grade = grade
            self.hidden = hidden
            self.texts = texts
            self.rarity = rarity
            self.rarityLabel = rarityLabel
            self.mine = mine
            self.theirs = theirs
        }

        public func name(in language: String) -> String? { texts.flatMap { TogetherNames.pick($0.mapValues(\.name), language) } }
        public func detail(in language: String) -> String? {
            texts.flatMap { texts in TogetherNames.pick(texts.compactMapValues(\.detail), language) }
        }
    }

    public struct Totals: Decodable, Equatable, Sendable {
        public let mine: Int
        public let theirs: Int
        public let both: Int
        public let total: Int

        public init(mine: Int, theirs: Int, both: Int, total: Int) {
            self.mine = mine
            self.theirs = theirs
            self.both = both
            self.total = total
        }
    }

    public let titleId: String
    public let game: Game?
    public let me: Person
    public let them: Person
    public let trophies: [Trophy]
    public let totals: Totals

    public init(titleId: String, game: Game?, me: Person, them: Person, trophies: [Trophy], totals: Totals) {
        self.titleId = titleId
        self.game = game
        self.me = me
        self.them = them
        self.trophies = trophies
        self.totals = totals
    }
}

// MARK: Appear offline

/// `presence.mode` from the gateway: appearing offline was turned on or off on another device.
public struct TogetherPresenceMode: Equatable, Sendable {
    public let appearOffline: Bool

    public init(appearOffline: Bool) { self.appearOffline = appearOffline }

    public init?(_ event: TogetherSocket.Event) {
        struct Mode: Decodable { let appearOffline: Bool }
        guard event.type == "presence.mode", let mode = event.decode(Mode.self) else { return nil }
        self.init(appearOffline: mode.appearOffline)
    }
}

extension TogetherProblem {
    /// Kept private from the user (a 403 for a private section).
    public var isPrivate: Bool { TogetherClient.isPrivate(self) }
}

extension TogetherClient {
    /// GET /users/{handle}/showcase.
    public func showcase(of handle: String) async throws -> TogetherShowcase {
        try JSONDecoder.together.decode(TogetherShowcase.self, from: try await authorized("GET", "users/\(Self.path(handle))/showcase", nil))
    }

    /// The games either has trophies in, the ones both play first. A 403 when their trophies are
    /// private to the user.
    public func compareGames(with handle: String) async throws -> [TogetherCompareGame] {
        struct List: Decodable { let games: [TogetherCompareGame] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "users/\(Self.path(handle))/trophies/compare", nil)).games
    }

    public func compareTrophies(with handle: String, titleId: String) async throws -> TogetherCompareView {
        let title = titleId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? titleId
        return try JSONDecoder.together.decode(TogetherCompareView.self, from: try await authorized("GET", "users/\(Self.path(handle))/trophies/compare?titleId=\(title)", nil))
    }

    /// PATCH /me/presence: friends see the user offline while it is on. What the server keeps.
    public func setAppearOffline(_ on: Bool) async throws -> Bool {
        struct Mode: Decodable { let appearOffline: Bool }
        return try JSONDecoder.together.decode(Mode.self, from: try await authorized("PATCH", "me/presence", ["appearOffline": on])).appearOffline
    }
}

extension KeyedDecodingContainer {
    /// The value, or nil when it is missing, null or of a shape this launcher does not expect.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
