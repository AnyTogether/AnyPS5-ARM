import Foundation

/// Who a leaderboard ranks: this user and their friends, or everyone whose trophies (and, for a
/// game, library) are public.
public enum TogetherBoardScope: String, CaseIterable, Codable, Sendable {
    case friends, global
}

/// What a game's leaderboard ranks by.
public enum TogetherGameBoard: String, CaseIterable, Sendable {
    case points, time, completion
}

/// A leaderboard as AnyTogether answers it: the top, this user's place, and the people around them.
public struct TogetherLeaderboard: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Sendable, Identifiable {
        public var id: String { user.userId }
        public let rank: Int
        public let user: TogetherPerson
        /// Points, seconds played, or completion percent.
        public let value: Int

        public init(rank: Int, user: TogetherPerson, value: Int) {
            self.rank = rank
            self.user = user
            self.value = value
        }
    }

    public struct Me: Decodable, Equatable, Sendable {
        /// nil with nothing to rank.
        public let rank: Int?
        public let value: Int
        /// False when this user is not on the board (private, or nothing yet); `rank` then says
        /// where they would be.
        public let listed: Bool

        public init(rank: Int?, value: Int, listed: Bool) {
            self.rank = rank
            self.value = value
            self.listed = listed
        }
    }

    /// What the board shows, line by line.
    public enum Line: Equatable, Sendable {
        case entry(Entry, me: Bool)
        /// Places left out between the top and the people around this user.
        case gap
        /// This user, not on the board.
        case unlisted(rank: Int?, value: Int)

        public var rank: Int? {
            switch self {
            case .entry(let entry, _): return entry.rank
            case .gap: return nil
            case .unlisted(let rank, _): return rank
            }
        }
    }

    /// "points", "time" or "completion".
    public let board: String
    public let scope: TogetherBoardScope
    public let game: TogetherActivity.Game?
    public let entries: [Entry]
    public let me: Me
    public let around: [Entry]
    public let total: Int
    public let updatedAt: Date

    public init(board: String, scope: TogetherBoardScope, game: TogetherActivity.Game?, entries: [Entry], me: Me, around: [Entry] = [], total: Int, updatedAt: Date = Date()) {
        self.board = board
        self.scope = scope
        self.game = game
        self.entries = entries
        self.me = me
        self.around = around
        self.total = total
        self.updatedAt = updatedAt
    }

    /// The top; then, when this user is further down, a gap and the people around them; or a line
    /// for this user when they are not on the board.
    public func lines(me userId: String) -> [Line] {
        var lines = entries.map { Line.entry($0, me: $0.user.userId == userId) }
        let shown = Set(entries.map(\.user.userId))
        let rest = around.filter { !shown.contains($0.user.userId) }
        if let first = rest.first {
            if let last = entries.last, first.rank > last.rank + 1 { lines.append(.gap) }
            lines += rest.map { Line.entry($0, me: $0.user.userId == userId) }
        }
        if !me.listed { lines.append(.unlisted(rank: me.rank, value: me.value)) }
        return lines
    }
}

/// A game with a leaderboard: this user's own first, then the most played.
public struct TogetherBoardGame: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { titleId }
    public let titleId: String
    public let names: [String: String]
    public let iconUrl: String?
    public let players: Int
    public let mine: Bool

    public func name(in language: String) -> String { TogetherNames.pick(names, language) ?? titleId }
}

extension TogetherClient {
    /// Overall trophy points.
    public func pointsLeaderboard(scope: TogetherBoardScope, limit: Int? = nil) async throws -> TogetherLeaderboard {
        let query = ["scope=\(scope.rawValue)", limit.map { "limit=\($0)" }].compactMap { $0 }.joined(separator: "&")
        return try JSONDecoder.together.decode(TogetherLeaderboard.self, from: try await authorized("GET", "leaderboards/points?\(query)", nil))
    }

    /// One game's board; a game no one has played on AnyTogether answers 404.
    public func gameLeaderboard(_ titleId: String, by board: TogetherGameBoard, scope: TogetherBoardScope, limit: Int? = nil) async throws -> TogetherLeaderboard {
        let query = ["by=\(board.rawValue)", "scope=\(scope.rawValue)", limit.map { "limit=\($0)" }].compactMap { $0 }.joined(separator: "&")
        return try JSONDecoder.together.decode(TogetherLeaderboard.self, from: try await authorized("GET", "games/\(Self.path(titleId))/leaderboard?\(query)", nil))
    }

    public func leaderboardGames() async throws -> [TogetherBoardGame] {
        struct List: Decodable { let games: [TogetherBoardGame] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "leaderboards/games", nil)).games
    }
}
