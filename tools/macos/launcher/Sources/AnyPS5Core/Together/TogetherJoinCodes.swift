import Foundation

/// A join code: eight letters and digits a party's leader or a share play's host hands out (or
/// shows on Discord); whoever has it can ask to join, and the leader or host still says yes.
/// Opening its link never joins anybody.
public struct TogetherJoinCode: Codable, Equatable, Sendable {
    /// The letters a code is made of: no 0, O, 1 or I, so it reads aloud.
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let length = 8

    public let code: String
    /// The web page that shows what the code opens, with an "Ask to join" button.
    public let url: String
    public let expiresAt: Date

    public init(code: String, url: String, expiresAt: Date) {
        self.code = code
        self.url = url
        self.expiresAt = expiresAt
    }

    /// "K7QM-3XPA".
    public var display: String { TogetherJoinCode.display(code) }

    public func works(at now: Date = Date()) -> Bool { expiresAt > now }

    /// A code in two halves of four, the way people read it; anything else as it is.
    public static func display(_ code: String) -> String {
        let upper = code.uppercased()
        guard upper.count == length else { return code }
        return String(upper.prefix(4)) + "-" + String(upper.suffix(4))
    }

    /// The code in what was typed or pasted: any case, with or without the dash or spaces, or
    /// the whole link; nil when it cannot be one.
    public static func normalize(_ text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "/join/", options: [.caseInsensitive, .backwards]) {
            text = String(text[range.upperBound...])
            if let end = text.firstIndex(where: { $0 == "?" || $0 == "#" || $0 == "/" }) { text = String(text[..<end]) }
        }
        let code = text.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard code.count == length, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return code
    }
}

/// What a code opens, as anyone reading it sees it.
public struct TogetherJoinInfo: Decodable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case party
        case sharePlay = "share_play"
    }

    /// Where the reader stands with it (signed in only); "none" is not in it and not asked.
    public enum State: String, Codable, Sendable {
        case notIn = "none"
        case member, requested, invited
    }

    /// The leader or host; signed out there is no user ID.
    public struct Host: Decodable, Equatable, Sendable {
        public let userId: String?
        public let handle: String
        public let displayName: String
        public let avatar: String?

        public init(userId: String?, handle: String, displayName: String, avatar: String?) {
            self.userId = userId
            self.handle = handle
            self.displayName = displayName
            self.avatar = avatar
        }
    }

    public struct Game: Decodable, Equatable, Sendable {
        public let titleId: String
        public let title: String?
        public let names: [String: String]?
        public let iconUrl: String?

        public init(titleId: String, title: String?, names: [String: String]? = nil, iconUrl: String? = nil) {
            self.titleId = titleId
            self.title = title
            self.names = names
            self.iconUrl = iconUrl
        }

        public func name(in language: String) -> String { TogetherNames.pick(names ?? [:], language) ?? title ?? titleId }
    }

    public let code: String
    public let kind: Kind
    public let id: String
    public let host: Host?
    public let game: Game?
    public let size: Int
    public let max: Int
    public let expiresAt: Date?
    public let state: State?

    public init(code: String, kind: Kind, id: String, host: Host?, game: Game?, size: Int, max: Int, expiresAt: Date?, state: State?) {
        self.code = code
        self.kind = kind
        self.id = id
        self.host = host
        self.game = game
        self.size = size
        self.max = max
        self.expiresAt = expiresAt
        self.state = state
    }

    enum CodingKeys: String, CodingKey { case code, kind, id, host, game, size, max, expiresAt, state }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        host = try container.decodeIfPresent(Host.self, forKey: .host)
        game = try container.decodeIfPresent(Game.self, forKey: .game)
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        max = try container.decodeIfPresent(Int.self, forKey: .max) ?? 0
        expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        // A state a newer server adds reads as none said.
        state = (try? container.decodeIfPresent(String.self, forKey: .state)).flatMap { $0.flatMap(State.init(rawValue:)) }
    }

    public var full: Bool { max > 0 && size >= max }
}

/// What asking with a code did: asked and waiting, or let in at once (an invite to take).
public struct TogetherJoinAnswer: Decodable, Equatable, Sendable {
    public let kind: TogetherJoinInfo.Kind
    public let id: String
    public let state: TogetherJoinInfo.State
}

/// Someone asking to join the party or watch the share play: from the public list, or with the code.
public struct TogetherJoinRequest: Decodable, Equatable, Sendable {
    public let partyId: String?
    public let sharePlayId: String?
    public let from: TogetherPerson
    /// "list" or "code"; older servers do not say.
    public let via: String?

    public var withCode: Bool { via == "code" }
}

/// The party's Discord server or channel, as the server takes it: https on discord.gg or
/// discord.com (www, ptb, canary), an invite or a channel; query and fragment dropped.
public enum TogetherPartyDiscord {
    static let hosts: Set<String> = ["discord.gg", "discord.com", "www.discord.com", "ptb.discord.com", "canary.discord.com"]

    /// The link to send, or nil when the server would refuse it.
    public static func clean(_ text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text), components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), hosts.contains(host), components.port == nil, components.user == nil else { return nil }
        let path = components.path.split(separator: "/").map(String.init)
        let valid: Bool
        if host == "discord.gg" {
            valid = path.count == 1
        } else {
            valid = (path.count == 2 && path[0] == "invite") || (path.first == "channels" && (2 ... 3).contains(path.count))
        }
        guard valid, path.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }) else { return nil }
        return "https://\(host)/" + path.joined(separator: "/")
    }
}

extension TogetherClient {
    // MARK: Join codes

    /// A new code for the party (the leader only), replacing any earlier one; `hours` 1-72, the
    /// server's default (24) when nil.
    public func makeJoinCode(party partyId: String, hours: Int? = nil) async throws -> TogetherJoinCode {
        try joinCode(try await authorized("POST", "parties/\(partyId)/code", hours.map { ["hours": $0] } ?? [String: Any]()))
    }

    public func stopJoinCode(party partyId: String) async throws {
        _ = try await authorized("DELETE", "parties/\(partyId)/code", nil)
    }

    /// The same for the share play the user hosts.
    public func makeJoinCode(sharePlay id: String, hours: Int? = nil) async throws -> TogetherJoinCode {
        try joinCode(try await authorized("POST", "share-plays/\(id)/code", hours.map { ["hours": $0] } ?? [String: Any]()))
    }

    public func stopJoinCode(sharePlay id: String) async throws {
        _ = try await authorized("DELETE", "share-plays/\(id)/code", nil)
    }

    /// What a code opens; signed in, with where the user stands. "not_found" when it does not work.
    public func joinCodeInfo(_ code: String) async throws -> TogetherJoinInfo {
        let path = "join/" + (try Self.joinPath(code))
        let data = user == nil ? try await send("GET", path, nil) : try await authorized("GET", path, nil)
        return try JSONDecoder.together.decode(TogetherJoinInfo.self, from: data)
    }

    /// Asks to join with a code: the leader or host answers (or the user is invited at once).
    public func redeemJoinCode(_ code: String) async throws -> TogetherJoinAnswer {
        try JSONDecoder.together.decode(TogetherJoinAnswer.self, from: try await authorized("POST", "join/" + (try Self.joinPath(code)), [:]))
    }

    /// The party's Discord link, or none (nil); the leader only.
    public func setPartyDiscord(_ partyId: String, _ link: String?) async throws -> TogetherParty {
        try JSONDecoder.together.decode(TogetherParty.self, from: try await authorized("PATCH", "parties/\(partyId)", ["discord": link.map { $0 as Any } ?? NSNull()]))
    }

    private func joinCode(_ data: Data) throws -> TogetherJoinCode { try JSONDecoder.together.decode(TogetherJoinCode.self, from: data) }

    /// A code that cannot be one is refused here, as the server would.
    private static func joinPath(_ code: String) throws -> String {
        guard let clean = TogetherJoinCode.normalize(code) else { throw TogetherProblem(status: 404, code: "not_found", title: "No such code") }
        return clean
    }
}
