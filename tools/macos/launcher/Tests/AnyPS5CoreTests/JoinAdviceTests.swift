import XCTest
@testable import AnyPS5Core

/// Two Macs on the same release could not play Greenhollow together: one copy had been made by
/// the nightly engine before the launcher was updated and was started as it was, the message read
/// "arm-ni … arm-f7, update" although both launchers were current, and Play from the library
/// while in a party opened a second session instead of joining the friend's.
final class JoinAdviceTests: XCTestCase {
    let nightly = "0.2.36-arm-nightly.20261110.1-a6fff1ba742d"
    let stable = "0.2.36-arm-f75c475400e3"

    func testACopyMadeByAnotherEngineThanTheOneAtHandIsRebuilt() {
        XCTAssertTrue(StaleCopy.needsRebuild(built: nightly, current: stable), "the launcher was updated since the copy was made")
        XCTAssertFalse(StaleCopy.needsRebuild(built: stable, current: stable))
        XCTAssertTrue(StaleCopy.needsRebuild(built: stable, current: "0.2.35-arm-0123456789ab"), "a game's own older engine counts as well")
        XCTAssertFalse(StaleCopy.needsRebuild(built: nil, current: stable), "not unlocked: nothing to rebuild")
        XCTAssertFalse(StaleCopy.needsRebuild(built: nightly, current: nil), "no engine at hand")
    }

    func testAStaleCopyAgainstTheEngineAtHandIsRebuiltNeverUpdated() {
        XCTAssertEqual(EngineAdvice.of(yours: nightly, host: stable, rebuildGives: stable), .rebuild)
        XCTAssertFalse(EngineAdvice.of(yours: nightly, host: stable, rebuildGives: stable).youUpdate)
    }

    func testWhoIsBehindIsReadFromTheReleasesNotTheFingerprints() {
        // The joiner on the release, the host's copy still the nightly's: the host is behind.
        XCTAssertEqual(EngineAdvice.of(yours: stable, host: nightly), .updateHost)
        // Comparing every number in the two builds called the release older ("update").
        XCTAssertLessThan(TogetherGameSession.compareVersions(stable, nightly), 0)
        XCTAssertEqual(EngineAdvice.of(yours: nightly, host: stable), .updateYours)
        XCTAssertEqual(EngineAdvice.of(yours: "0.2.35-arm-0123456789ab", host: stable), .updateYours)
        XCTAssertEqual(EngineAdvice.of(yours: stable, host: "0.2.37-arm-nightly.20261112.1-0123456789ab"), .hostNightly)
        XCTAssertEqual(EngineAdvice.of(yours: stable, host: "0.2.36-arm-0123456789ab"), .sameEngine, "one release, two builds: nobody updates")
        XCTAssertEqual(EngineAdvice.of(yours: "local-0123456789ab", host: stable), .sameEngine)
        // A stale copy whose rebuild still would not reach the host's: the engine at hand is what counts.
        XCTAssertEqual(EngineAdvice.of(yours: nightly, host: "0.2.37-arm-0123456789ab", rebuildGives: stable), .updateYours)
        XCTAssertEqual(EngineAdvice.of(yours: nightly, host: "0.2.35-arm-0123456789ab", rebuildGives: stable), .updateHost)
    }

    func testTheCheckNoLongerTellsTheNewerSideToUpdate() {
        let offer = PlayTogetherOffer(sessionId: "s1", hostId: "u1", hostName: "Mira", titleId: "FAKE18847", gameVersion: "01.000", engineBuild: nightly,
                                      versionRule: "exact", players: 1, capacity: 4)
        let mine = PlayTogetherCheck.Copy(id: "g1", titleId: "FAKE18847", gameVersion: "01.000", engineBuild: stable, unlocked: true)
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [mine], running: nil), .engine(have: stable, need: nightly, youUpdate: false))
        // The other way round, the stale copy is rebuilt and joins in one press.
        var current = offer
        current.engineBuild = stable
        let stale = PlayTogetherCheck.Copy(id: "g1", titleId: "FAKE18847", gameVersion: "01.000", engineBuild: nightly, unlocked: true, nextEngineBuild: stable)
        XCTAssertEqual(PlayTogetherCheck.verdict(current, signedIn: true, copies: [stale], running: nil), .updateAndPlay("g1"))
    }

    // MARK: Who is in whose game

    let me = TogetherPerson(userId: "me", handle: "robin", displayName: "Robin", avatar: nil)
    let mira = TogetherPerson(userId: "u1", handle: "mira", displayName: "Mira", avatar: nil)

    func session(_ id: String, host: TogetherPerson, players: [TogetherPerson], title: String = "FAKE18847") -> TogetherGameSession {
        TogetherGameSession(id: id, host: host, titleId: title, gameVersion: "01.000", engineBuild: stable, capacity: 4, joinable: true, players: players)
    }

    func testAMemberIsInYourGameInAnotherOneOrInNone() {
        let mine = session("s1", host: me, players: [me])
        let theirs = TogetherFriend.Presence.Game(sessionId: "s2", titleId: "FAKE18847", joinable: true, players: 1, capacity: 4, kind: "online", hostId: "u1")
        // Both in the party, each hosting their own session of the same title: the case that went unsaid.
        XCTAssertEqual(MemberGame.of("u1", mine: mine, together: nil, presence: theirs, friend: true),
                       .other(sessionId: "s2", titleId: "FAKE18847", hostId: "u1", joinable: true, together: false, sameTitle: true))
        XCTAssertEqual(MemberGame.of("u1", mine: session("s1", host: me, players: [me, mira]), together: nil, presence: nil, friend: true), .yours)
        XCTAssertEqual(MemberGame.of("u1", mine: nil, together: nil, presence: theirs, friend: true),
                       .other(sessionId: "s2", titleId: "FAKE18847", hostId: "u1", joinable: true, together: false, sameTitle: false))
        XCTAssertEqual(MemberGame.of("u1", mine: mine, together: nil, presence: nil, friend: true), .nothing)
        XCTAssertNil(MemberGame.of("u1", mine: mine, together: nil, presence: nil, friend: false), "nothing is known of someone who is no friend")
        let together = TogetherPartyTogether(sessionId: "s3", hostId: "u1", titleId: "PPSA17221", gameVersion: "01.000", engineBuild: stable, players: ["u1"], capacity: 2)
        XCTAssertEqual(MemberGame.of("u1", mine: mine, together: together, presence: nil, friend: false),
                       .other(sessionId: "s3", titleId: "PPSA17221", hostId: "u1", joinable: true, together: true, sameTitle: false))
        let full = TogetherFriend.Presence.Game(sessionId: "s2", titleId: "FAKE18847", joinable: true, players: 4, capacity: 4)
        XCTAssertEqual(MemberGame.of("u1", mine: nil, together: nil, presence: full, friend: true),
                       .other(sessionId: "s2", titleId: "FAKE18847", hostId: "u1", joinable: false, together: false, sameTitle: false))
    }

    // MARK: Join theirs, or start your own

    func friend(_ id: String, game: TogetherFriend.Presence.Game?) -> TogetherFriend {
        TogetherFriend(userId: id, handle: id, displayName: id, avatar: nil, presence: .init(state: game == nil ? "online" : "playing", titleId: game?.titleId, since: nil, game: game))
    }

    func party(_ members: [TogetherPerson], together: TogetherPartyTogether? = nil) -> TogetherParty {
        TogetherParty(id: "p1", leaderId: "me", privacy: "invite", members: members, invited: [], call: nil, together: together)
    }

    func testPlayOnAGameAFriendHostsOffersTheirs() {
        let hosting = TogetherFriend.Presence.Game(sessionId: "s2", titleId: "FAKE18847", joinable: true, players: 1, capacity: 4, kind: "online", hostId: "u1")
        let found = JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: party([me, mira]), friends: [friend("u1", game: hosting)])
        XCTAssertEqual(found, JoinableGame(sessionId: "s2", titleId: "FAKE18847", personId: "u1", together: false))
        XCTAssertNil(JoinableGame.find(titleId: "PPSA17221", me: "me", mine: nil, party: nil, friends: [friend("u1", game: hosting)]), "another title")
        XCTAssertNil(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: "s2", party: nil, friends: [friend("u1", game: hosting)]), "already in it")
    }

    func testOnlyAGameWithRoomThatLetsOthersInIsOffered() {
        let closed = TogetherFriend.Presence.Game(sessionId: "s2", titleId: "FAKE18847", joinable: false, players: 1, capacity: 4)
        let full = TogetherFriend.Presence.Game(sessionId: "s3", titleId: "FAKE18847", joinable: true, players: 4, capacity: 4)
        XCTAssertNil(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: nil, friends: [friend("u1", game: closed), friend("u2", game: full)]))
        XCTAssertNil(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: nil, friends: [friend("u1", game: nil)]))
    }

    func testThePartysPlayTogetherGameComesFirstThenAPartyMembersThenAnyFriends() {
        let together = TogetherPartyTogether(sessionId: "s9", hostId: "u1", titleId: "FAKE18847", gameVersion: "01.000", engineBuild: stable, players: ["u1"], capacity: 8)
        let online = TogetherFriend.Presence.Game(sessionId: "s2", titleId: "FAKE18847", joinable: true, players: 1, capacity: 4)
        let other = TogetherFriend.Presence.Game(sessionId: "s4", titleId: "FAKE18847", joinable: true, players: 1, capacity: 4)
        let friends = [friend("u7", game: other), friend("u1", game: online)]
        XCTAssertEqual(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: party([me, mira], together: together), friends: friends),
                       JoinableGame(sessionId: "s9", titleId: "FAKE18847", personId: "u1", together: true))
        XCTAssertEqual(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: party([me, mira]), friends: friends)?.sessionId, "s2", "the party member before another friend")
        XCTAssertEqual(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: nil, friends: friends)?.sessionId, "s4")
        // The user's own Play Together game is never offered back to them.
        let mine = TogetherPartyTogether(sessionId: "s9", hostId: "me", titleId: "FAKE18847", gameVersion: "01.000", engineBuild: stable, players: ["me"], capacity: 8)
        XCTAssertNil(JoinableGame.find(titleId: "FAKE18847", me: "me", mine: nil, party: party([me, mira], together: mine), friends: []))
    }
}
