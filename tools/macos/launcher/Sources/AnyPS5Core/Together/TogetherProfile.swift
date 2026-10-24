import Foundation

/// Someone's profile as AnyTogether shows it to this user.
public struct TogetherProfile: Decodable, Equatable, Sendable {
    public let userId: String
    public let handle: String
    public let displayName: String
    public let avatar: String?
    public let bio: String?
    public let country: String?
    /// "me", "friends", "none", "pending_out" (this user asked) or "pending_in" (they asked).
    public let friendship: String

    public init(userId: String, handle: String, displayName: String, avatar: String?, bio: String?, country: String?, friendship: String) {
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
        self.bio = bio
        self.country = country
        self.friendship = friendship
    }

    public var isMe: Bool { friendship == "me" }
}

/// A game in someone's library: its names, play time and trophy progress.
public struct TogetherPlayedGame: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { titleId }
    public let titleId: String
    public let names: [String: String]
    public let iconUrl: String?
    public let lastPlayedAt: Date?
    public let secondsPlayed: Int
    public let trophiesEarned: Int
    public let trophiesTotal: Int?
    /// 0-100, nil when the game's trophy set is unknown.
    public let progress: Int?
    public let points: Int

    public init(titleId: String, names: [String: String], iconUrl: String?, lastPlayedAt: Date?, secondsPlayed: Int, trophiesEarned: Int, trophiesTotal: Int?, progress: Int?, points: Int) {
        self.titleId = titleId
        self.names = names
        self.iconUrl = iconUrl
        self.lastPlayedAt = lastPlayedAt
        self.secondsPlayed = secondsPlayed
        self.trophiesEarned = trophiesEarned
        self.trophiesTotal = trophiesTotal
        self.progress = progress
        self.points = points
    }

    public func name(in language: String) -> String { TogetherNames.pick(names, language) ?? titleId }
}

/// A trophy someone earned, with how rare it is among AnyTogether's players of the game.
public struct TogetherEarnedTrophy: Decodable, Equatable, Sendable, Identifiable {
    public struct Text: Decodable, Equatable, Sendable {
        public let name: String
        public let detail: String?

        public init(name: String, detail: String? = nil) {
            self.name = name
            self.detail = detail
        }
    }

    public var id: String { "\(titleId)/\(trophyId)" }
    public let titleId: String
    public let gameNames: [String: String]
    public let trophyId: Int
    public let grade: String
    public let hidden: Bool
    /// nil for a hidden trophy this user has not earned.
    public let texts: [String: Text]?
    public let earnedAt: Date
    /// The share of the game's players who have it, 0-1.
    public let rarity: Double?
    /// "common", "uncommon", "rare", "very_rare" or "ultra_rare".
    public let rarityLabel: String?

    public init(titleId: String, gameNames: [String: String], trophyId: Int, grade: String, hidden: Bool, texts: [String: Text]?, earnedAt: Date, rarity: Double?, rarityLabel: String?) {
        self.titleId = titleId
        self.gameNames = gameNames
        self.trophyId = trophyId
        self.grade = grade
        self.hidden = hidden
        self.texts = texts
        self.earnedAt = earnedAt
        self.rarity = rarity
        self.rarityLabel = rarityLabel
    }

    public func name(in language: String) -> String? {
        texts.flatMap { texts in TogetherNames.pick(texts.mapValues(\.name), language) }
    }

    public func gameName(in language: String) -> String { TogetherNames.pick(gameNames, language) ?? titleId }
}

enum TogetherNames {
    /// The user's language, then English, then any.
    static func pick(_ names: [String: String], _ language: String) -> String? {
        names[language] ?? names["en"] ?? names.keys.sorted().first.flatMap { names[$0] }
    }
}

/// A section of a profile: shown, kept private by its owner (or to friends), or not read.
public enum TogetherSection<Value: Equatable & Sendable>: Equatable, Sendable {
    case shown(Value)
    case `private`
    case failed

    public var value: Value? {
        if case .shown(let value) = self { return value }
        return nil
    }
}

/// Everything a profile view shows, read together.
public struct TogetherProfilePage: Equatable, Sendable {
    public struct Totals: Equatable, Sendable {
        public let games: Int
        public let seconds: Int
        public let trophies: Int
        public let points: Int

        public init(games: Int, seconds: Int, trophies: Int, points: Int) {
            self.games = games
            self.seconds = seconds
            self.trophies = trophies
            self.points = points
        }
    }

    public let profile: TogetherProfile
    /// The profile's details (bio, country) are private: the card the launcher knew stands in.
    public let detailsPrivate: Bool
    public let library: TogetherSection<[TogetherPlayedGame]>
    public let trophies: TogetherSection<[TogetherEarnedTrophy]>

    public init(profile: TogetherProfile, detailsPrivate: Bool = false, library: TogetherSection<[TogetherPlayedGame]>, trophies: TogetherSection<[TogetherEarnedTrophy]>) {
        self.profile = profile
        self.detailsPrivate = detailsPrivate
        self.library = library
        self.trophies = trophies
    }

    /// Games, play time, trophies and points, from the library; nil when it is not shown.
    public var totals: Totals? {
        library.value.map { games in
            Totals(games: games.count, seconds: games.reduce(0) { $0 + $1.secondsPlayed },
                   trophies: games.reduce(0) { $0 + $1.trophiesEarned }, points: games.reduce(0) { $0 + $1.points })
        }
    }
}

extension TogetherClient {
    public func profile(_ handle: String) async throws -> TogetherProfile {
        try JSONDecoder.together.decode(TogetherProfile.self, from: try await authorized("GET", "users/\(Self.path(handle))", nil))
    }

    public func library(of handle: String) async throws -> TogetherSection<[TogetherPlayedGame]> {
        struct List: Decodable { let games: [TogetherPlayedGame]?; let `private`: Bool? }
        return try await section {
            let list = try JSONDecoder.together.decode(List.self, from: try await self.authorized("GET", "users/\(Self.path(handle))/library", nil))
            return list.private == true ? nil : list.games ?? []
        }
    }

    public func earnedTrophies(of handle: String) async throws -> TogetherSection<[TogetherEarnedTrophy]> {
        struct List: Decodable { let trophies: [TogetherEarnedTrophy]?; let `private`: Bool? }
        return try await section {
            let list = try JSONDecoder.together.decode(List.self, from: try await self.authorized("GET", "users/\(Self.path(handle))/trophies", nil))
            return list.private == true ? nil : list.trophies ?? []
        }
    }

    /// The profile, its library and its recent trophies at once. A section the server keeps
    /// private (403, or `private: true`) comes back private; profile details kept private fall
    /// back to `card`, the person as the friends list knows them.
    public func profilePage(_ handle: String, card: TogetherPerson? = nil) async throws -> TogetherProfilePage {
        async let library = library(of: handle)
        async let trophies = earnedTrophies(of: handle)
        var detailsPrivate = false
        let profile: TogetherProfile
        do {
            profile = try await self.profile(handle)
        } catch let problem as TogetherProblem where Self.isPrivate(problem) {
            guard let card else { throw problem }
            detailsPrivate = true
            profile = TogetherProfile(userId: card.userId, handle: card.handle, displayName: card.displayName, avatar: card.avatar, bio: nil, country: nil, friendship: "none")
        }
        return TogetherProfilePage(profile: profile, detailsPrivate: detailsPrivate, library: try await library, trophies: try await trophies)
    }

    /// A section read: nil from `read` or a refusal is private, anything else that fails is failed.
    /// Signing out on the way (a refused refresh) still throws.
    private func section<Value: Equatable & Sendable>(_ read: @escaping @Sendable () async throws -> Value?) async throws -> TogetherSection<Value> {
        do {
            return try await read().map { .shown($0) } ?? .private
        } catch let problem as TogetherProblem where Self.isPrivate(problem) {
            return .private
        } catch let problem as TogetherProblem where problem.status == 401 {
            throw problem
        } catch {
            return .failed
        }
    }

    static func isPrivate(_ problem: TogetherProblem) -> Bool {
        problem.status == 403 || problem.code == "private" || problem.code == "forbidden"
    }

    /// A handle as a path component: without the @, escaped.
    static func path(_ handle: String) -> String {
        let cleaned = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return cleaned.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? cleaned
    }
}
