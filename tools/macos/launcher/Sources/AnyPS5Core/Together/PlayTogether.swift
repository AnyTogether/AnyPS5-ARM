import Foundation

/// Play Together: in a party, the host picks a game and presses Play Together; the launcher opens
/// a LAN game session (kind `lan`) and starts the game with online play on for that session. The
/// rest of the party hears "<host> started <game>", and Join checks they have the same game and
/// version, then starts it here in the same session, so the WebRTC mesh joins the players'
/// virtual LAN and the host's game sees the others as LAN peers. It ends with its host.

/// The party's Play Together game while one runs, as the party view carries it.
public struct TogetherPartyTogether: Decodable, Equatable, Sendable {
    public let sessionId: String
    public let hostId: String
    public let titleId: String
    public let gameVersion: String
    public let engineBuild: String
    public let versionRule: String
    /// Who plays, the host first, by user ID.
    public let players: [String]
    public let capacity: Int

    public init(sessionId: String, hostId: String, titleId: String, gameVersion: String, engineBuild: String, versionRule: String = "exact", players: [String], capacity: Int) {
        self.sessionId = sessionId
        self.hostId = hostId
        self.titleId = titleId
        self.gameVersion = gameVersion
        self.engineBuild = engineBuild
        self.versionRule = versionRule
        self.players = players
        self.capacity = capacity
    }
}

/// Why the server refused a join: a different game version or engine build, the host's and this
/// copy's, and whether this side is the one behind.
public struct TogetherJoinRefusal: Equatable, Sendable {
    public enum Reason: String, Sendable { case gameVersion = "game_version", engine }
    public let reason: Reason
    public let expected: String
    public let actual: String
    public let youUpdate: Bool

    public init(reason: Reason, expected: String, actual: String, youUpdate: Bool) {
        self.reason = reason
        self.expected = expected
        self.actual = actual
        self.youUpdate = youUpdate
    }
}

/// What a party member is offered: the host's game, its version and engine, and room left.
public struct PlayTogetherOffer: Equatable, Sendable, Identifiable {
    public var id: String { sessionId }
    public var sessionId: String
    public var hostId: String
    public var hostName: String
    public var titleId: String
    public var gameVersion: String
    public var engineBuild: String
    public var versionRule: String
    public var players: Int
    public var capacity: Int

    public init(sessionId: String, hostId: String, hostName: String, titleId: String, gameVersion: String, engineBuild: String, versionRule: String, players: Int, capacity: Int) {
        self.sessionId = sessionId
        self.hostId = hostId
        self.hostName = hostName
        self.titleId = titleId
        self.gameVersion = gameVersion
        self.engineBuild = engineBuild
        self.versionRule = versionRule
        self.players = players
        self.capacity = capacity
    }

    public init(session: TogetherGameSession) {
        self.init(sessionId: session.id, hostId: session.host?.userId ?? "", hostName: session.host?.displayName ?? "", titleId: session.titleId,
                  gameVersion: session.gameVersion, engineBuild: session.engineBuild, versionRule: session.versionRule, players: session.players.count,
                  capacity: session.capacity)
    }
}

/// What Join can do for an offer, checked here before asking the server, in a fixed order; each
/// answer that is not a way in names what is missing.
public enum PlayTogetherVerdict: Equatable, Sendable {
    /// Join with this copy (a game ID).
    case join(String)
    /// The copy is not unlocked yet: unlock it, then join.
    case unlockAndPlay(String)
    /// The copy was unlocked with an older engine and unlocking it again brings it to the host's.
    case updateAndPlay(String)
    case signIn
    case missing(titleId: String)
    /// No copy has a version that fits the host's; `youUpdate` when this side is behind.
    case gameVersion(have: String, need: String, youUpdate: Bool)
    case engine(have: String, need: String, youUpdate: Bool)
    case closeFirst(running: String)
    case full
}

public enum PlayTogetherCheck {
    /// A copy of a game in this Mac's library.
    public struct Copy: Equatable, Sendable {
        public var id: String
        public var titleId: String
        public var gameVersion: String
        /// The engine build it was unlocked with (or would be, while locked).
        public var engineBuild: String
        public var unlocked: Bool
        /// The engine build unlocking it again would give, when that differs.
        public var nextEngineBuild: String?

        public init(id: String, titleId: String, gameVersion: String, engineBuild: String, unlocked: Bool, nextEngineBuild: String? = nil) {
            self.id = id
            self.titleId = titleId
            self.gameVersion = gameVersion
            self.engineBuild = engineBuild
            self.unlocked = unlocked
            self.nextEngineBuild = nextEngineBuild
        }
    }

    /// Signed in, owned, version, engine, not busy, room, unlocked: the first that does not hold.
    public static func verdict(_ offer: PlayTogetherOffer, signedIn: Bool, copies: [Copy], running: String?) -> PlayTogetherVerdict {
        guard signedIn else { return .signIn }
        let owned = copies.filter { $0.titleId == offer.titleId }
        guard let first = owned.first else { return .missing(titleId: offer.titleId) }
        let fitting = owned.filter { TogetherGameSession.versionFits(offer.versionRule, host: offer.gameVersion, joiner: $0.gameVersion) }
        guard !fitting.isEmpty else {
            return .gameVersion(have: first.gameVersion, need: offer.gameVersion, youUpdate: TogetherGameSession.compareVersions(first.gameVersion, offer.gameVersion) < 0)
        }
        // The copy whose engine is the host's, else one that unlocking again brings there.
        let exact = fitting.first { $0.engineBuild == offer.engineBuild }
        let updatable = fitting.first { $0.unlocked && $0.nextEngineBuild == offer.engineBuild }
        guard let copy = exact ?? updatable else {
            let have = fitting[0].engineBuild
            return .engine(have: have, need: offer.engineBuild, youUpdate: TogetherGameSession.compareVersions(have, offer.engineBuild) < 0)
        }
        if let running { return .closeFirst(running: running) }
        guard offer.players < offer.capacity else { return .full }
        if !copy.unlocked { return .unlockAndPlay(copy.id) }
        if copy.engineBuild != offer.engineBuild { return .updateAndPlay(copy.id) }
        return .join(copy.id)
    }
}
