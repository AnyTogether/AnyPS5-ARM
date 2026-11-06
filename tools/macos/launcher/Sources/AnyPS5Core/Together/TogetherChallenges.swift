import Foundation

/// A challenge on AnyTogether: a time-boxed race on one game's leaderboard, between a start and
/// an end, for friends, a community or everyone (packages/shared/src/challenges.ts). Made on the
/// website; the launcher shows them where the leaderboards are, and joins and leaves them.
/// Read leniently: fields a later server adds are passed over, and a metric, audience or state
/// this launcher does not know reads as `.other`.
public struct TogetherChallenge: Decodable, Equatable, Sendable, Identifiable {
    /// What counts: trophy points, trophies earned, or seconds played, in the window.
    public enum Metric: String, Sendable { case points, trophies, time, other }
    public enum Audience: String, Sendable { case friends, community, `public`, other }
    /// upcoming, active (running), ended (final once `final`), cancelled (called off).
    public enum State: String, Sendable { case upcoming, active, ended, cancelled, other }

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

        enum CodingKeys: String, CodingKey { case titleId, names, iconUrl }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            titleId = try container.decode(String.self, forKey: .titleId)
            names = (try? container.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
            iconUrl = try? container.decodeIfPresent(String.self, forKey: .iconUrl)
        }
    }

    public struct Community: Decodable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let icon: String?
        public let iconUrl: String?

        public init(id: String, name: String, icon: String? = nil, iconUrl: String? = nil) {
            self.id = id
            self.name = name
            self.icon = icon
            self.iconUrl = iconUrl
        }
    }

    /// A place in the standings. `user` is nil for someone the reader may not see (a block
    /// either way): their place still counts. Ranks are shared on ties (1, 2, 2, 4).
    public struct Standing: Decodable, Equatable, Sendable {
        public let rank: Int
        public let user: TogetherPerson?
        /// Trophy points, trophies, or seconds played.
        public let value: Int
        /// The reader's own row.
        public let me: Bool

        public init(rank: Int, user: TogetherPerson?, value: Int, me: Bool = false) {
            self.rank = rank
            self.user = user
            self.value = value
            self.me = me
        }

        enum CodingKeys: String, CodingKey { case rank, user, value, me }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rank = try container.decode(Int.self, forKey: .rank)
            // A player card of a shape this launcher cannot read is shown as a hidden player.
            user = (try? container.decodeIfPresent(TogetherPerson.self, forKey: .user)) ?? nil
            value = (try? container.decodeIfPresent(Int.self, forKey: .value)) ?? 0
            me = (try? container.decodeIfPresent(Bool.self, forKey: .me)) ?? false
        }
    }

    /// The reader's place, when they joined and it started.
    public struct Place: Decodable, Equatable, Sendable {
        public let rank: Int
        public let value: Int

        public init(rank: Int, value: Int) {
            self.rank = rank
            self.value = value
        }
    }

    public let id: String
    public let title: String
    public let description: String?
    public let game: Game
    public let metricName: String
    public let audienceName: String
    public let community: Community?
    /// Nil once the maker's account is gone (or the reader may not see them).
    public let creator: TogetherPerson?
    public let startsAt: Date
    public let endsAt: Date
    public let stateName: String
    /// Ended and past the grace hour: the standings will not change.
    public let final: Bool
    public let entrants: Int
    public let joined: Bool
    /// The reader made it (and stays in it).
    public let mine: Bool
    public let canCancel: Bool
    /// First place while it runs, the winner once it ended; nil before it starts or with no one
    /// above zero.
    public let leader: Standing?
    public let myStanding: Place?
    public let createdAt: Date?

    public var metric: Metric { Metric(rawValue: metricName) ?? .other }
    public var audience: Audience { Audience(rawValue: audienceName) ?? .other }
    public var state: State { State(rawValue: stateName) ?? .other }

    public init(id: String, title: String, description: String? = nil, game: Game, metric: Metric, audience: Audience, community: Community? = nil, creator: TogetherPerson? = nil,
                startsAt: Date, endsAt: Date, state: State, final: Bool = false, entrants: Int = 0, joined: Bool = false, mine: Bool = false, canCancel: Bool = false,
                leader: Standing? = nil, myStanding: Place? = nil, createdAt: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.game = game
        self.metricName = metric.rawValue
        self.audienceName = audience.rawValue
        self.community = community
        self.creator = creator
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.stateName = state.rawValue
        self.final = final
        self.entrants = entrants
        self.joined = joined
        self.mine = mine
        self.canCancel = canCancel
        self.leader = leader
        self.myStanding = myStanding
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, game, community, creator, startsAt, endsAt, final, entrants, joined, mine, canCancel, leader, myStanding, createdAt
        case metricName = "metric", audienceName = "audience", stateName = "state"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // What a challenge is: without these it cannot be shown.
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        game = try container.decode(Game.self, forKey: .game)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        // The rest has a reading of its own when missing or of another shape.
        func soft<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? { (try? container.decodeIfPresent(type, forKey: key)) ?? nil }
        description = soft(String.self, .description)
        metricName = soft(String.self, .metricName) ?? Metric.other.rawValue
        audienceName = soft(String.self, .audienceName) ?? Audience.other.rawValue
        community = soft(Community.self, .community)
        creator = soft(TogetherPerson.self, .creator)
        stateName = soft(String.self, .stateName) ?? State.other.rawValue
        final = soft(Bool.self, .final) ?? false
        entrants = soft(Int.self, .entrants) ?? 0
        joined = soft(Bool.self, .joined) ?? false
        mine = soft(Bool.self, .mine) ?? false
        canCancel = soft(Bool.self, .canCancel) ?? false
        leader = soft(Standing.self, .leader)
        myStanding = soft(Place.self, .myStanding)
        createdAt = soft(Date.self, .createdAt)
    }

    // MARK: Time

    /// Where the challenge stands in time, read from its window (fresher than `state`, which is
    /// as the server answered).
    public enum Clock: Equatable, Sendable {
        case startsIn(TimeInterval)
        case endsIn(TimeInterval)
        /// Over, the results not final yet (late sessions and trophies have an hour).
        case finishing
        case ended
        case cancelled
    }

    public func clock(now: Date = Date()) -> Clock {
        if state == .cancelled { return .cancelled }
        if now < startsAt { return .startsIn(startsAt.timeIntervalSince(now)) }
        if now < endsAt { return .endsIn(endsAt.timeIntervalSince(now)) }
        return final ? .ended : .finishing
    }

    /// How much of the window has gone, 0 before the start to 1 at the end.
    public func progress(now: Date = Date()) -> Double {
        let length = endsAt.timeIntervalSince(startsAt)
        guard length > 0 else { return now < startsAt ? 0 : 1 }
        return min(1, max(0, now.timeIntervalSince(startsAt) / length))
    }

    /// A length of time as it reads in one unit: the largest that comes to two or more ("2 days",
    /// "36 hours", "90 minutes"), down to a minute.
    public struct Span: Equatable, Sendable {
        public enum Unit: Sendable { case days, hours, minutes }
        public let amount: Int
        public let unit: Unit

        public init(amount: Int, unit: Unit) {
            self.amount = amount
            self.unit = unit
        }

        public init(seconds: TimeInterval) {
            if seconds >= 2 * 86400 {
                self.init(amount: Int(seconds / 86400), unit: .days)
            } else if seconds >= 2 * 3600 {
                self.init(amount: Int(seconds / 3600), unit: .hours)
            } else {
                self.init(amount: max(1, Int(seconds / 60)), unit: .minutes)
            }
        }
    }
}

/// GET /challenges/:id: the challenge, its first hundred places and the reader's neighbours
/// past them.
public struct TogetherChallengeDetail: Decodable, Equatable, Sendable {
    public typealias Standing = TogetherChallenge.Standing

    public let challenge: TogetherChallenge
    public let standings: [Standing]
    public let around: [Standing]
    public let updatedAt: Date

    /// What the standings show, line by line.
    public enum Line: Equatable, Sendable {
        case standing(Standing)
        /// Places left out between the top and the reader's neighbours.
        case gap

        public var rank: Int? {
            if case .standing(let standing) = self { return standing.rank }
            return nil
        }
    }

    public init(challenge: TogetherChallenge, standings: [Standing], around: [Standing] = [], updatedAt: Date = Date()) {
        self.challenge = challenge
        self.standings = standings
        self.around = around
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case standings, around, updatedAt }

    public init(from decoder: Decoder) throws {
        challenge = try TogetherChallenge(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standings = (try? container.decodeIfPresent(Lenient<Standing>.self, forKey: .standings))?.items ?? []
        around = (try? container.decodeIfPresent(Lenient<Standing>.self, forKey: .around))?.items ?? []
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }

    /// The top; then, when the reader is further down, a gap and their neighbours (no one twice).
    public var lines: [Line] {
        var lines = standings.map(Line.standing)
        let rest = around.filter { !standings.contains($0) }
        if let first = rest.first {
            if let last = standings.last, first.rank > last.rank + 1 { lines.append(.gap) }
            lines += rest.map(Line.standing)
        }
        return lines
    }

    /// The same challenge after joining or leaving: its new count and place, the standings as
    /// they were until read again.
    public func with(_ challenge: TogetherChallenge) -> TogetherChallengeDetail {
        TogetherChallengeDetail(challenge: challenge, standings: standings, around: around, updatedAt: updatedAt)
    }
}

/// A list read item by item: one that cannot be read is left out, not the whole list.
struct Lenient<Item: Decodable>: Decodable {
    let items: [Item]

    /// Anything at all, to step past an item: it reads nothing.
    private struct Skip: Decodable {
        init(from decoder: Decoder) {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Item] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Item.self) {
                items.append(item)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.items = items
    }
}

extension TogetherClient {
    private struct ChallengeList: Decodable {
        let challenges: Lenient<TogetherChallenge>
    }

    /// The running and coming challenges the reader may see on a game (soonest first), or on every
    /// game with nil; the ended ones instead with `ended`.
    public func challenges(titleId: String?, ended: Bool = false) async throws -> [TogetherChallenge] {
        let query = [titleId.map { "titleId=\(Self.path($0))" }, ended ? "state=ended" : nil].compactMap { $0 }.joined(separator: "&")
        let path = "challenges" + (query.isEmpty ? "" : "?\(query)")
        return try JSONDecoder.together.decode(ChallengeList.self, from: try await authorized("GET", path, nil)).challenges.items
    }

    /// The reader's own, joined or made: running and coming first, then ended in the last 30 days.
    public func myChallenges() async throws -> [TogetherChallenge] {
        try JSONDecoder.together.decode(ChallengeList.self, from: try await authorized("GET", "me/challenges", nil)).challenges.items
    }

    public func challenge(_ id: String) async throws -> TogetherChallengeDetail {
        try JSONDecoder.together.decode(TogetherChallengeDetail.self, from: try await authorized("GET", "challenges/\(Self.path(id))", nil))
    }

    /// 409 "conflict" when it is over, 409 "full", 403 "restricted_by_family".
    public func joinChallenge(_ id: String) async throws -> TogetherChallenge {
        try JSONDecoder.together.decode(TogetherChallenge.self, from: try await authorized("POST", "challenges/\(Self.path(id))/join", [String: Any]()))
    }

    /// 409 "conflict" when it is over or the reader made it.
    public func leaveChallenge(_ id: String) async throws -> TogetherChallenge {
        try JSONDecoder.together.decode(TogetherChallenge.self, from: try await authorized("POST", "challenges/\(Self.path(id))/leave", [String: Any]()))
    }

    /// What the leaderboard shows above a board: a game's challenges, or the reader's own on the
    /// overall board. A server from before challenges answers 404: then there are none, quietly.
    public func challengeStrip(titleId: String?) async throws -> [TogetherChallenge] {
        do {
            if let titleId { return try await challenges(titleId: titleId) }
            return try await myChallenges()
        } catch let problem as TogetherProblem where problem.status == 404 {
            return []
        }
    }
}
