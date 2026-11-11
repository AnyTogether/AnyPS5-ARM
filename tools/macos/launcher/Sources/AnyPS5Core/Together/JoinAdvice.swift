import Foundation

/// Joining someone's game, said whole: when a copy is rebuilt before it starts, what a different
/// engine build asks of whom, what each party member plays next to the user's own game, and
/// whose game to offer when the user starts a title someone they know already plays.

/// A copy of a game made by another engine than the one it starts with now.
public enum StaleCopy {
    /// `built`: the engine in the copy's install record (nil: not unlocked). `current`: the engine
    /// the game is unlocked with now, the one inside the app or the game's own (nil: none at hand).
    /// A copy made by another engine is rebuilt before it starts or joins a game.
    public static func needsRebuild(built: String?, current: String?) -> Bool {
        guard let built, let current else { return false }
        return built != current
    }
}

/// What gets a player past a host's different engine build.
public enum EngineAdvice: Equatable, Sendable {
    /// The copy was made by an older engine and the engine at hand is the host's: rebuild it, then join.
    case rebuild
    /// The host's release is newer than the engine at hand: this side updates.
    case updateYours
    /// The host plays on a nightly build ahead of this release: the same update channel on both.
    case hostNightly
    /// This side is newer: the host updates and starts the game again.
    case updateHost
    /// The same release built differently (an engine of one's own, another download), or builds
    /// that say no release: the same engine on both.
    case sameEngine

    /// `yours`: the engine this copy was made with. `host`: the session's. `rebuildGives`: the
    /// engine unlocking the copy again would give, when that differs. The releases are compared
    /// as releases come out (a nightly before its release), never by a build's fingerprint.
    public static func of(yours: String, host: String, rebuildGives: String? = nil) -> EngineAdvice {
        if let rebuildGives, rebuildGives == host, rebuildGives != yours { return .rebuild }
        let atHand = rebuildGives ?? yours
        guard let mine = Updates.Version(Toolkit.release(of: atHand)), let theirs = Updates.Version(Toolkit.release(of: host)), mine != theirs else { return .sameEngine }
        if mine < theirs { return theirs.isNightly && !mine.isNightly ? .hostNightly : .updateYours }
        return .updateHost
    }

    /// Whether this side is the one behind.
    public var youUpdate: Bool { self == .updateYours || self == .hostNightly }
}

/// What a party member plays, next to the user's own game.
public enum MemberGame: Equatable, Sendable {
    /// In the session the user is in.
    case yours
    /// In another session; `sameTitle` when it is the title the user plays in a session of their own.
    case other(sessionId: String, titleId: String, hostId: String, joinable: Bool, together: Bool, sameTitle: Bool)
    /// Known to play nothing others can join.
    case nothing

    /// `mine`: the session the user is in, with its players. `together`: the party's Play
    /// Together game. `presence`: the member's game as a friend's presence says it; `friend`
    /// whether they are a friend at all (nothing is known of a stranger outside the party's game:
    /// nil).
    public static func of(_ userId: String, mine: TogetherGameSession?, together: TogetherPartyTogether?, presence: TogetherFriend.Presence.Game?, friend: Bool) -> MemberGame? {
        if let mine {
            if mine.players.contains(where: { $0.userId == userId }) || mine.host?.userId == userId { return .yours }
            if together?.sessionId == mine.id, together?.players.contains(userId) == true { return .yours }
            if presence?.sessionId == mine.id { return .yours }
        }
        if let together, together.players.contains(userId) {
            return .other(sessionId: together.sessionId, titleId: together.titleId, hostId: together.hostId, joinable: together.players.count < together.capacity,
                          together: true, sameTitle: mine?.titleId == together.titleId)
        }
        if let presence {
            return .other(sessionId: presence.sessionId, titleId: presence.titleId, hostId: presence.hostId ?? userId, joinable: presence.joinable && presence.players < presence.capacity,
                          together: presence.together, sameTitle: mine?.titleId == presence.titleId)
        }
        return friend ? .nothing : nil
    }
}

/// A game someone the user knows already plays, offered when the user starts the same title:
/// join theirs, or start one of their own.
public struct JoinableGame: Equatable, Sendable {
    public var sessionId: String
    public var titleId: String
    /// Whose game it is to join: the host when they are known here, else the friend seen in it.
    public var personId: String
    /// The party's Play Together game (joined as one), not a friend's own session.
    public var together: Bool

    public init(sessionId: String, titleId: String, personId: String, together: Bool) {
        self.sessionId = sessionId
        self.titleId = titleId
        self.personId = personId
        self.together = together
    }

    /// The game to offer for `titleId`: the party's Play Together game first, then a party
    /// member's own session, then any friend's; only one with room that lets others in, never
    /// the session the user is in (`mine`) or hosts.
    public static func find(titleId: String, me: String, mine: String?, party: TogetherParty?, friends: [TogetherFriend]) -> JoinableGame? {
        if let together = party?.together, together.titleId == titleId, together.sessionId != mine, together.hostId != me, !together.players.contains(me),
           together.players.count < together.capacity {
            return JoinableGame(sessionId: together.sessionId, titleId: titleId, personId: together.hostId, together: true)
        }
        let inParty = Set(party?.members.map(\.userId) ?? [])
        let playing = friends.filter { friend in
            guard let game = friend.presence?.game else { return false }
            return game.titleId == titleId && game.joinable && game.players < game.capacity && game.sessionId != mine && game.hostId != me && friend.userId != me
        }
        guard let friend = playing.first(where: { inParty.contains($0.userId) }) ?? playing.first, let game = friend.presence?.game else { return nil }
        return JoinableGame(sessionId: game.sessionId, titleId: titleId, personId: friend.userId, together: game.together)
    }
}
