import Foundation

/// Finding people to play with beyond friends: the looking-for-group board ("Find players"),
/// parties and share plays their hosts list in public, "Live now", suggestions, players of a game
/// and a game's hub. Who sees whom follows blocks and each person's privacy on the server.

/// A game as the server names it, where a list shows one.
public struct TogetherGameNames: Codable, Equatable, Sendable {
    public let names: [String: String]
    public let iconUrl: String?

    public init(names: [String: String], iconUrl: String? = nil) {
        self.names = names
        self.iconUrl = iconUrl
    }

    public func name(in language: String) -> String? { TogetherNames.pick(names, language) }
}

/// What a post is for: co-op over share play, an online game, a party to talk in, trophy help.
public enum TogetherLfgPurpose: String, CaseIterable, Codable, Sendable {
    case coop, online, party, trophies

    /// Co-op goes over share play, where a viewer can hold pad 2, 3 or 4; everyone else ends up
    /// in the poster's party of eight.
    public var maxSlots: Int { self == .coop ? 3 : TogetherParty.maxSize - 1 }
}

/// How strangers get into a public party or share play: they ask, or walk in.
public enum TogetherPublicJoin: String, CaseIterable, Codable, Sendable {
    case request, open
}

/// Where an accepted player was invited: the poster's party or the share play they host.
public struct TogetherLfgInvite: Codable, Equatable, Sendable {
    public let kind: String
    public let id: String

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }

    public var isSharePlay: Bool { kind == "share_play" }
}

/// Someone's "I'm in" on the user's own post.
public struct TogetherLfgRequest: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { user.userId }
    public let user: TogetherPerson
    /// "pending", "accepted" or "declined".
    public let status: String
    public let invite: TogetherLfgInvite?
    public let createdAt: Date

    public init(user: TogetherPerson, status: String, invite: TogetherLfgInvite? = nil, createdAt: Date = Date()) {
        self.user = user
        self.status = status
        self.invite = invite
        self.createdAt = createdAt
    }

    public var pending: Bool { status == "pending" }
}

/// A post on the board.
public struct TogetherLfgPost: Decodable, Equatable, Sendable, Identifiable {
    public struct Mine: Decodable, Equatable, Sendable {
        public let status: String
        public let invite: TogetherLfgInvite?

        public init(status: String, invite: TogetherLfgInvite? = nil) {
            self.status = status
            self.invite = invite
        }
    }

    /// Where the user stands with someone else's post.
    public enum Standing: Equatable, Sendable {
        /// "I'm in" can be said.
        case canAsk
        case waiting
        case accepted(TogetherLfgInvite?)
        case declined
        /// Full, closed or out of time.
        case closed
        case own
    }

    /// When it starts.
    public enum When: Equatable, Sendable {
        case now
        case inMinutes(Int)
    }

    public let id: String
    public let author: TogetherPerson
    public let titleId: String
    public let game: TogetherGameNames?
    public let purpose: TogetherLfgPurpose
    public let startsAt: Date?
    public let languages: [String]
    public let region: String?
    public let slots: Int
    public let filled: Int
    public let note: String?
    public let expiresAt: Date
    /// "open", "full", "closed", "expired" or "removed".
    public let status: String
    public let createdAt: Date
    public let mine: Bool
    public let myRequest: Mine?
    /// Only on the user's own posts: who wants in.
    public let requests: [TogetherLfgRequest]?

    public init(id: String, author: TogetherPerson, titleId: String, game: TogetherGameNames? = nil, purpose: TogetherLfgPurpose, startsAt: Date? = nil, languages: [String],
                region: String? = nil, slots: Int, filled: Int = 0, note: String? = nil, expiresAt: Date, status: String = "open", createdAt: Date = Date(), mine: Bool = false,
                myRequest: Mine? = nil, requests: [TogetherLfgRequest]? = nil) {
        self.id = id
        self.author = author
        self.titleId = titleId
        self.game = game
        self.purpose = purpose
        self.startsAt = startsAt
        self.languages = languages
        self.region = region
        self.slots = slots
        self.filled = filled
        self.note = note
        self.expiresAt = expiresAt
        self.status = status
        self.createdAt = createdAt
        self.mine = mine
        self.myRequest = myRequest
        self.requests = requests
    }

    public func name(in language: String) -> String { game?.name(in: language) ?? titleId }

    public func isOpen(at now: Date = Date()) -> Bool { status == "open" && expiresAt > now && filled < slots }

    public func standing(at now: Date = Date()) -> Standing {
        if mine { return .own }
        switch myRequest?.status {
        case "pending": return isOpen(at: now) ? .waiting : .closed
        case "accepted": return .accepted(myRequest?.invite)
        case "declined": return .declined
        default: return isOpen(at: now) ? .canAsk : .closed
        }
    }

    /// Now, or in so many minutes (a start a little in the past is now).
    public func when(at now: Date = Date()) -> When {
        guard let startsAt else { return .now }
        let minutes = Int((startsAt.timeIntervalSince(now) / 60).rounded())
        return minutes <= 1 ? .now : .inMinutes(minutes)
    }

    /// People still waiting for the poster's answer.
    public var pending: [TogetherLfgRequest] { (requests ?? []).filter(\.pending) }
}

/// The board's filters: one game or all, what for, a language, and only what starts soon.
public struct TogetherLfgFilter: Equatable, Sendable {
    public var titleId: String?
    public var purpose: TogetherLfgPurpose?
    public var language: String?
    public var now: Bool

    public init(titleId: String? = nil, purpose: TogetherLfgPurpose? = nil, language: String? = nil, now: Bool = false) {
        self.titleId = titleId
        self.purpose = purpose
        self.language = language
        self.now = now
    }

    /// The query string for GET /lfg; `before` is the last post of the page before.
    public func query(before: String? = nil, limit: Int? = nil) -> String {
        var items: [String] = []
        if let titleId { items.append("titleId=\(titleId)") }
        if let purpose { items.append("purpose=\(purpose.rawValue)") }
        if let language { items.append("language=\(language)") }
        if now { items.append("now=1") }
        if let before { items.append("before=\(before)") }
        if let limit { items.append("limit=\(limit)") }
        return items.isEmpty ? "" : "?" + items.joined(separator: "&")
    }

    /// The gateway topic that tells of changes to what this filter shows.
    public var topic: String { titleId.map { "lfg:\($0)" } ?? "lfg" }
}

/// A post being written in "Find players for <game>".
public struct TogetherLfgDraft: Equatable, Sendable {
    public static let maxNote = 140
    public static let maxLanguages = 3
    public static let maxHours = 24

    public var titleId: String
    public var purpose: TogetherLfgPurpose
    public var slots: Int
    public var languages: [String]
    public var note: String
    /// Minutes from now until it starts; 0 for now.
    public var startsIn: Int
    /// Hours after the start until the post goes.
    public var hours: Int

    public init(titleId: String, purpose: TogetherLfgPurpose = .coop, slots: Int = 1, languages: [String], note: String = "", startsIn: Int = 0, hours: Int = 3) {
        self.titleId = titleId
        self.purpose = purpose
        self.slots = slots
        self.languages = languages
        self.note = note
        self.startsIn = startsIn
        self.hours = hours
    }

    /// Slots a purpose allows.
    public var slotRange: ClosedRange<Int> { 1 ... purpose.maxSlots }

    /// Changes what it is for, keeping the slots within what the new purpose allows.
    public mutating func setPurpose(_ purpose: TogetherLfgPurpose) {
        self.purpose = purpose
        slots = min(max(1, slots), purpose.maxSlots)
    }

    /// Hours the post may stay after its start: until 24 hours from now.
    public var hourRange: ClosedRange<Int> { 1 ... max(1, Self.maxHours - Int((Double(startsIn) / 60).rounded(.up))) }

    /// What POST /lfg takes.
    public func body(now: Date = Date()) -> [String: Any] {
        let format = ISO8601DateFormatter()
        let start = now.addingTimeInterval(TimeInterval(max(0, startsIn) * 60))
        let latest = now.addingTimeInterval(TimeInterval(Self.maxHours * 3600))
        let expires = min(latest, start.addingTimeInterval(TimeInterval(min(max(1, hours), Self.maxHours) * 3600)))
        var body: [String: Any] = [
            "titleId": titleId,
            "purpose": purpose.rawValue,
            "slots": min(max(1, slots), purpose.maxSlots),
            "languages": Array(languages.prefix(Self.maxLanguages)),
            "expiresAt": format.string(from: expires),
        ]
        if startsIn > 0 { body["startsAt"] = format.string(from: start) }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { body["note"] = String(text.prefix(Self.maxNote)) }
        return body
    }
}

/// A game with open posts, for the board's game filter.
public struct TogetherLfgGame: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { titleId }
    public let titleId: String
    public let posts: Int
    public let names: [String: String]?
    public let iconUrl: String?

    public init(titleId: String, posts: Int, names: [String: String]? = nil, iconUrl: String? = nil) {
        self.titleId = titleId
        self.posts = posts
        self.names = names
        self.iconUrl = iconUrl
    }

    public func name(in language: String) -> String { TogetherNames.pick(names ?? [:], language) ?? titleId }
}

/// How a party is listed in public: who may get in, and the game and language it is about.
public struct TogetherPartyListing: Codable, Equatable, Sendable {
    public let join: TogetherPublicJoin
    public let titleId: String?
    public let language: String?

    public init(join: TogetherPublicJoin, titleId: String? = nil, language: String? = nil) {
        self.join = join
        self.titleId = titleId
        self.language = language
    }

    var body: [String: Any] {
        ["join": join.rawValue, "titleId": titleId ?? NSNull(), "language": language ?? NSNull()]
    }
}

/// How a share play is listed in public; `live` also lists it under "Live now", which needs an
/// open one.
public struct TogetherShareListing: Codable, Equatable, Sendable {
    public let join: TogetherPublicJoin
    public let language: String?
    public let live: Bool

    public init(join: TogetherPublicJoin, language: String? = nil, live: Bool = false) {
        self.join = join
        self.language = language
        // Only an open share play can be under Live now.
        self.live = live && join == .open
    }

    var body: [String: Any] {
        ["join": join.rawValue, "language": language ?? NSNull(), "live": live]
    }
}

/// A party in the public list.
public struct TogetherPublicParty: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let host: TogetherPerson?
    public let titleId: String?
    public let game: TogetherGameNames?
    public let language: String?
    public let join: TogetherPublicJoin
    public let size: Int
    public let max: Int
    /// The user asked to join and waits.
    public let requested: Bool

    public init(id: String, host: TogetherPerson?, titleId: String? = nil, game: TogetherGameNames? = nil, language: String? = nil, join: TogetherPublicJoin, size: Int, max: Int = TogetherParty.maxSize, requested: Bool = false) {
        self.id = id
        self.host = host
        self.titleId = titleId
        self.game = game
        self.language = language
        self.join = join
        self.size = size
        self.max = max
        self.requested = requested
    }

    public var full: Bool { size >= max }
}

/// A share play in the public list, or under Live now.
public struct TogetherPublicShare: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let host: TogetherPerson?
    public let titleId: String
    public let title: String?
    public let game: TogetherGameNames?
    public let language: String?
    public let join: TogetherPublicJoin
    public let live: Bool
    public let viewers: Int
    public let maxViewers: Int
    public let requested: Bool

    public init(id: String, host: TogetherPerson?, titleId: String, title: String? = nil, game: TogetherGameNames? = nil, language: String? = nil, join: TogetherPublicJoin, live: Bool,
                viewers: Int, maxViewers: Int, requested: Bool = false) {
        self.id = id
        self.host = host
        self.titleId = titleId
        self.title = title
        self.game = game
        self.language = language
        self.join = join
        self.live = live
        self.viewers = viewers
        self.maxViewers = maxViewers
        self.requested = requested
    }

    public func name(in language: String) -> String { title ?? game?.name(in: language) ?? titleId }
    public var full: Bool { viewers >= maxViewers }
}

/// "Show me in discovery": what the user chose, or following the library's privacy.
public struct TogetherDiscovery: Decodable, Equatable, Sendable {
    public enum Choice: Int, CaseIterable, Sendable {
        case followLibrary, on, off

        var json: Any {
            switch self {
            case .followLibrary: return NSNull()
            case .on: return true
            case .off: return false
            }
        }
    }

    public static let maxLanguages = 5

    /// Whether the user shows in discovery now.
    public let discoverable: Bool
    /// What they chose; nil while it follows the library.
    public let chosen: Bool?
    public let languages: [String]

    public init(discoverable: Bool, chosen: Bool?, languages: [String]) {
        self.discoverable = discoverable
        self.chosen = chosen
        self.languages = languages
    }

    public var choice: Choice { chosen.map { $0 ? .on : .off } ?? .followLibrary }

    /// The languages with `language` turned on or off; nil when it would go past five.
    public func toggling(_ language: String) -> [String]? {
        if languages.contains(language) { return languages.filter { $0 != language } }
        return languages.count >= Self.maxLanguages ? nil : languages + [language]
    }
}

/// Someone found in discovery: their card, where the user stands with them, and why.
public struct TogetherDiscoveredPerson: Decodable, Equatable, Sendable, Identifiable {
    public enum Reason: Decodable, Equatable, Sendable {
        case game(titleId: String, names: [String: String])
        case friends(count: Int)
        case language(String)
        case other

        enum CodingKeys: String, CodingKey { case kind, titleId, names, count, language }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "game": self = .game(titleId: try container.decode(String.self, forKey: .titleId), names: try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:])
            case "friends": self = .friends(count: try container.decode(Int.self, forKey: .count))
            case "language": self = .language(try container.decode(String.self, forKey: .language))
            default: self = .other
            }
        }
    }

    public struct Presence: Decodable, Equatable, Sendable {
        public let state: String
        public let titleId: String?

        public init(state: String, titleId: String? = nil) {
            self.state = state
            self.titleId = titleId
        }
    }

    public var id: String { user.userId }
    public let user: TogetherPerson
    /// "none", "friends", "pending_out" or "pending_in".
    public let friendship: String
    public let presence: Presence?
    public let lastPlayedAt: Date?
    public let reasons: [Reason]

    public init(user: TogetherPerson, friendship: String = "none", presence: Presence? = nil, lastPlayedAt: Date? = nil, reasons: [Reason] = []) {
        self.user = user
        self.friendship = friendship
        self.presence = presence
        self.lastPlayedAt = lastPlayedAt
        self.reasons = reasons
    }

    enum CodingKeys: String, CodingKey { case user, friendship, presence, lastPlayedAt, reasons }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(TogetherPerson.self, forKey: .user)
        friendship = try container.decodeIfPresent(String.self, forKey: .friendship) ?? "none"
        presence = try container.decodeIfPresent(Presence.self, forKey: .presence)
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        reasons = try container.decodeIfPresent([Reason].self, forKey: .reasons) ?? []
    }

    /// A friend request can go to them.
    public var canAsk: Bool { friendship == "none" }
}

/// One game's hub: who plays it now, open posts, public parties and share plays, its players.
public struct TogetherGameHub: Decodable, Equatable, Sendable {
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

    public struct Playing: Decodable, Equatable, Sendable {
        public struct Player: Decodable, Equatable, Sendable, Identifiable {
            public var id: String { user.userId }
            public let user: TogetherPerson
            public let since: Date?

            public init(user: TogetherPerson, since: Date?) {
                self.user = user
                self.since = since
            }
        }

        public let total: Int
        public let people: [Player]

        public init(total: Int, people: [Player]) {
            self.total = total
            self.people = people
        }
    }

    public let game: Game
    /// Accounts with the game in their library.
    public let players: Int
    public let playing: Playing
    public let lfg: [TogetherLfgPost]
    public let parties: [TogetherPublicParty]
    public let sharePlays: [TogetherPublicShare]
    public let recentPlayers: [TogetherDiscoveredPerson]

    public init(game: Game, players: Int, playing: Playing, lfg: [TogetherLfgPost] = [], parties: [TogetherPublicParty] = [], sharePlays: [TogetherPublicShare] = [],
                recentPlayers: [TogetherDiscoveredPerson] = []) {
        self.game = game
        self.players = players
        self.playing = playing
        self.lfg = lfg
        self.parties = parties
        self.sharePlays = sharePlays
        self.recentPlayers = recentPlayers
    }
}

/// The public topics a gateway socket listens to: the board and the public lists, all of them or
/// one game's. They only say "something changed"; the list is read again.
public enum TogetherTopics {
    public static let max = 8
    /// "lfg" or "discover", alone or with ":" and a title ID like PPSA01234.
    static func valid(_ topic: String) -> Bool {
        let parts = topic.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let kind = parts.first, kind == "lfg" || kind == "discover" else { return false }
        guard parts.count == 2 else { return true }
        let title = Array(parts[1].unicodeScalars)
        return title.count == 9 && title.prefix(4).allSatisfy { ("A"..."Z").contains($0) } && title.suffix(5).allSatisfy { ("0"..."9").contains($0) }
    }

    /// Valid topics, each once, at most eight.
    public static func clean(_ topics: [String]) -> [String] {
        var seen = Set<String>()
        return Array(topics.filter { valid($0) && seen.insert($0).inserted }.prefix(max))
    }

    /// What a screen listens to: the board (all or one game's) and the public lists.
    public static func discovery(titleId: String?) -> [String] {
        clean(titleId.map { ["lfg:\($0)", "discover:\($0)"] } ?? ["lfg", "discover"])
    }

    public static func frame(_ topics: [String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["op": "watch", "topics": clean(topics)])) ?? Data()
    }
}

/// Languages offered for posts, listings and discovery: ISO 639-1 codes.
public enum TogetherLanguages {
    public static let common = ["en", "tr", "de", "fr", "es", "pt", "it", "ru", "pl", "nl", "ar", "ja", "ko", "zh"]

    /// A code's name in the language the launcher shows ("Türkçe", "German").
    public static func name(_ code: String, in language: String) -> String {
        let name = Locale(identifier: language).localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

extension TogetherClient {
    // MARK: The board

    public func lfgBoard(_ filter: TogetherLfgFilter = .init(), before: String? = nil) async throws -> (posts: [TogetherLfgPost], more: Bool) {
        struct Page: Decodable { let posts: [TogetherLfgPost]; let more: Bool }
        let page = try JSONDecoder.together.decode(Page.self, from: try await authorized("GET", "lfg" + filter.query(before: before), nil))
        return (page.posts, page.more)
    }

    /// Games with open posts, the busiest first.
    public func lfgGames() async throws -> [TogetherLfgGame] {
        struct List: Decodable { let games: [TogetherLfgGame] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "lfg/games", nil)).games
    }

    /// The user's posts of the last two days with who asked, and the posts they said "I'm in" to.
    public func myLfg() async throws -> (posts: [TogetherLfgPost], asked: [TogetherLfgPost]) {
        struct Mine: Decodable { let posts: [TogetherLfgPost]; let asked: [TogetherLfgPost] }
        let mine = try JSONDecoder.together.decode(Mine.self, from: try await authorized("GET", "me/lfg", nil))
        return (mine.posts, mine.asked)
    }

    public func postLfg(_ draft: TogetherLfgDraft, now: Date = Date()) async throws -> TogetherLfgPost {
        try JSONDecoder.together.decode(TogetherLfgPost.self, from: try await authorized("POST", "lfg", draft.body(now: now)))
    }

    public func lfgPost(_ id: String) async throws -> TogetherLfgPost {
        try JSONDecoder.together.decode(TogetherLfgPost.self, from: try await authorized("GET", "lfg/\(id)", nil))
    }

    /// The poster takes it off the board.
    public func closeLfg(_ id: String) async throws {
        _ = try await authorized("DELETE", "lfg/\(id)", nil)
    }

    /// "I'm in".
    public func joinLfg(_ id: String) async throws -> TogetherLfgPost {
        try JSONDecoder.together.decode(TogetherLfgPost.self, from: try await authorized("POST", "lfg/\(id)/requests", [:]))
    }

    public func cancelLfgRequest(_ id: String) async throws {
        _ = try await authorized("DELETE", "lfg/\(id)/requests/me", nil)
    }

    /// The poster's answer; yes invites the player to their party or share play on the server.
    public func answerLfg(_ postId: String, user userId: String, accept: Bool) async throws -> TogetherLfgPost {
        try JSONDecoder.together.decode(TogetherLfgPost.self, from: try await authorized("POST", "lfg/\(postId)/requests/\(userId)/\(accept ? "accept" : "decline")", [:]))
    }

    // MARK: Public parties and share plays

    public func publicParties(titleId: String? = nil, language: String? = nil) async throws -> [TogetherPublicParty] {
        struct List: Decodable { let parties: [TogetherPublicParty] }
        let query = [titleId.map { "titleId=\($0)" }, language.map { "language=\($0)" }].compactMap { $0 }.joined(separator: "&")
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "parties/public" + (query.isEmpty ? "" : "?" + query), nil)).parties
    }

    /// Lists the party in public, or takes it off the list (nil); the leader only.
    public func setPartyListing(_ partyId: String, _ listing: TogetherPartyListing?) async throws -> TogetherParty {
        try JSONDecoder.together.decode(TogetherParty.self, from: try await authorized("PATCH", "parties/\(partyId)", ["public": listing.map { $0.body as Any } ?? NSNull()]))
    }

    /// Asks to join a public party; the leader's yes is an invite.
    public func askToJoinParty(_ partyId: String) async throws {
        _ = try await authorized("POST", "parties/\(partyId)/requests", [:])
    }

    public func cancelPartyRequest(_ partyId: String) async throws {
        _ = try await authorized("DELETE", "parties/\(partyId)/requests/me", nil)
    }

    public func answerPartyRequest(_ partyId: String, user userId: String, accept: Bool) async throws -> TogetherParty {
        try JSONDecoder.together.decode(TogetherParty.self, from: try await authorized("POST", "parties/\(partyId)/requests/\(userId)/\(accept ? "accept" : "decline")", [:]))
    }

    /// Public share plays; `live` only those under Live now.
    public func publicSharePlays(live: Bool = false, titleId: String? = nil) async throws -> [TogetherPublicShare] {
        struct List: Decodable { let sharePlays: [TogetherPublicShare] }
        let query = [live ? "live=1" : nil, titleId.map { "titleId=\($0)" }].compactMap { $0 }.joined(separator: "&")
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "share-plays/public" + (query.isEmpty ? "" : "?" + query), nil)).sharePlays
    }

    /// Lists the share play the user hosts in public, or takes it off (nil).
    public func setShareListing(_ id: String, _ listing: TogetherShareListing?) async throws -> TogetherSharePlay {
        try JSONDecoder.together.decode(TogetherSharePlay.self, from: try await authorized("PATCH", "share-plays/\(id)", ["public": listing.map { $0.body as Any } ?? NSNull()]))
    }

    public func askToWatch(_ id: String) async throws {
        _ = try await authorized("POST", "share-plays/\(id)/requests", [:])
    }

    public func answerShareRequest(_ id: String, user userId: String, accept: Bool) async throws -> TogetherSharePlay {
        try JSONDecoder.together.decode(TogetherSharePlay.self, from: try await authorized("POST", "share-plays/\(id)/requests/\(userId)/\(accept ? "accept" : "decline")", [:]))
    }

    // MARK: Discovery

    public func discovery() async throws -> TogetherDiscovery {
        try JSONDecoder.together.decode(TogetherDiscovery.self, from: try await authorized("GET", "me/discovery", nil))
    }

    public func setDiscovery(_ choice: TogetherDiscovery.Choice? = nil, languages: [String]? = nil) async throws -> TogetherDiscovery {
        var body: [String: Any] = [:]
        if let choice { body["discoverable"] = choice.json }
        if let languages { body["languages"] = Array(languages.prefix(TogetherDiscovery.maxLanguages)) }
        return try JSONDecoder.together.decode(TogetherDiscovery.self, from: try await authorized("PATCH", "me/discovery", body))
    }

    public func suggestions() async throws -> [TogetherDiscoveredPerson] {
        struct List: Decodable { let suggestions: [TogetherDiscoveredPerson] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "discover/suggestions", nil)).suggestions
    }

    public func playersOf(_ titleId: String) async throws -> [TogetherDiscoveredPerson] {
        struct List: Decodable { let players: [TogetherDiscoveredPerson] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "discover/players?titleId=\(titleId)", nil)).players
    }

    public func gameHub(_ titleId: String) async throws -> TogetherGameHub {
        try JSONDecoder.together.decode(TogetherGameHub.self, from: try await authorized("GET", "games/\(titleId)/hub", nil))
    }
}
