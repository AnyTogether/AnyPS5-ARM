import Foundation
import XCTest

@testable import AnyPS5Core

/// Play Together: a LAN game session the host starts in the party, which the party joins with
/// the same game and version, and which ends with its host.
final class PlayTogetherClientTests: TogetherSignedInCase {
    static func lan(players: [[String: Any]] = [TogetherPartyTests.member("u1", "Utku")], rule: String = "exact") -> [String: Any] {
        TogetherGameSessionTests.session(players: players).merging(["kind": "lan", "partyId": "p1", "versionRule": rule, "titleId": "PPSA17221",
                                                                    "gameVersion": "01.044.000"]) { _, new in new }
    }

    func testStartingPlayTogetherOpensALanSessionInTheParty() async throws {
        FakeTogether.handler = { _, _ in (201, Self.lan()) }
        let session = try await client.startPlayTogether(titleId: "PPSA17221", gameVersion: "01.044.000", engineBuild: "0.2.21-4194", capacity: 8, versionRule: "major")
        XCTAssertEqual(last(), "POST /api/v1/game-sessions")
        XCTAssertEqual(body()?["kind"] as? String, "lan")
        XCTAssertEqual(body()?["versionRule"] as? String, "major")
        XCTAssertEqual(body()?["capacity"] as? Int, 8)
        XCTAssertEqual(session.kind, .lan)
        XCTAssertEqual(session.partyId, "p1")
        XCTAssertTrue(session.together)
    }

    func testAnOlderServersSessionReadsAsOnline() throws {
        let session = try JSONDecoder.together.decode(TogetherGameSession.self, from: JSONSerialization.data(withJSONObject: TogetherGameSessionTests.session()))
        XCTAssertEqual(session.kind, .online)
        XCTAssertNil(session.partyId)
        XCTAssertEqual(session.versionRule, "exact")
        XCTAssertFalse(session.together)
    }

    func testTheHostsGameExitingEndsItWithThatReason() async throws {
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.endGameSession("s1", reason: .gameExited)
        XCTAssertEqual(last(), "DELETE /api/v1/game-sessions/s1?reason=game_exited")
        try await client.endGameSession("s1")
        XCTAssertEqual(last(), "DELETE /api/v1/game-sessions/s1")
    }

    func testARefusedJoinSaysWhyAndWhoShouldUpdate() async throws {
        FakeTogether.handler = { _, _ in
            (409, ["code": "version_mismatch", "status": 409, "title": "This game needs version 01.044.000", "reason": "game_version",
                   "expected": "01.044.000", "actual": "01.008.000", "update": "you"])
        }
        do {
            _ = try await client.joinGameSession("s1", gameVersion: "01.008.000", engineBuild: "0.2.21-4194")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.joinRefusal, TogetherJoinRefusal(reason: .gameVersion, expected: "01.044.000", actual: "01.008.000", youUpdate: true))
        }
        FakeTogether.handler = { _, _ in
            (409, ["code": "version_mismatch", "status": 409, "title": "x", "reason": "engine", "expected": "0.2.20-1", "actual": "0.2.21-4194", "update": "host"])
        }
        do {
            _ = try await client.joinGameSession("s1", gameVersion: "01.044.000", engineBuild: "0.2.21-4194")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.joinRefusal?.reason, .engine)
            XCTAssertEqual(problem.joinRefusal?.youUpdate, false)
        }
    }

    func testThePartyCarriesItsPlayTogetherGame() throws {
        var json = TogetherPartyTests.party(members: [TogetherPartyTests.member("u1", "Utku"), TogetherPartyTests.member("f1", "Ayse")])
        json["together"] = ["sessionId": "s1", "hostId": "u1", "titleId": "PPSA17221", "gameVersion": "01.044.000", "engineBuild": "0.2.21-4194",
                            "versionRule": "exact", "players": ["u1"], "capacity": 8, "startedAt": "2026-10-26T00:00:00.000Z"]
        let party = try JSONDecoder.together.decode(TogetherParty.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(party.together?.sessionId, "s1")
        XCTAssertEqual(party.together?.players, ["u1"])
        XCTAssertEqual(party.together?.capacity, 8)
        // An older server says nothing about it.
        let older = try JSONDecoder.together.decode(TogetherParty.self, from: JSONSerialization.data(withJSONObject: TogetherPartyTests.party()))
        XCTAssertNil(older.together)
    }

    func testAFriendPlayingTogetherInPresence() throws {
        let json: [String: Any] = ["state": "in_game", "titleId": "PPSA17221",
                                   "game": ["sessionId": "s1", "titleId": "PPSA17221", "kind": "lan", "hostId": "u1", "joinable": false, "players": 2, "capacity": 8]]
        let presence = try JSONDecoder.together.decode(TogetherFriend.Presence.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(presence.game?.together, true)
        XCTAssertEqual(presence.game?.hostId, "u1")
        let old: [String: Any] = ["state": "in_game", "game": ["sessionId": "s1", "titleId": "PPSA01234", "joinable": true, "players": 1, "capacity": 4]]
        XCTAssertEqual(try JSONDecoder.together.decode(TogetherFriend.Presence.self, from: JSONSerialization.data(withJSONObject: old)).game?.together, false)
    }

    func testTheHostHandsOutAJoinCodeForTheGame() async throws {
        FakeTogether.handler = { _, _ in (201, ["code": "K7QM3XPA", "url": "https://anytogether.test/join/K7QM3XPA", "expiresAt": "2026-10-27T00:00:00.000Z"]) }
        let code = try await client.gameSessionCode("s1")
        XCTAssertEqual(last(), "POST /api/v1/game-sessions/s1/code")
        XCTAssertEqual(code.code, "K7QM3XPA")
    }
}

final class PlayTogetherCheckTests: XCTestCase {
    let offer = PlayTogetherOffer(sessionId: "s1", hostId: "u1", hostName: "Mira", titleId: "PPSA17221", gameVersion: "01.044.000", engineBuild: "0.2.21-4194",
                                  versionRule: "exact", players: 1, capacity: 8)

    func copy(_ id: String = "g1", version: String = "01.044.000", engine: String = "0.2.21-4194", unlocked: Bool = true, nextEngine: String? = nil) -> PlayTogetherCheck.Copy {
        PlayTogetherCheck.Copy(id: id, titleId: "PPSA17221", gameVersion: version, engineBuild: engine, unlocked: unlocked, nextEngineBuild: nextEngine)
    }

    func testTheSameGameVersionAndEngineJoins() {
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy()], running: nil), .join("g1"))
    }

    func testEachBlockerNamesWhatIsMissing() {
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: false, copies: [copy()], running: nil), .signIn)
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [], running: nil), .missing(titleId: "PPSA17221"))
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy(version: "01.008.000")], running: nil),
                       .gameVersion(have: "01.008.000", need: "01.044.000", youUpdate: true))
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy(version: "01.050.000")], running: nil),
                       .gameVersion(have: "01.050.000", need: "01.044.000", youUpdate: false))
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy(engine: "0.2.22-1")], running: nil),
                       .engine(have: "0.2.22-1", need: "0.2.21-4194", youUpdate: false))
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy()], running: "Stray"), .closeFirst(running: "Stray"))
        var full = offer
        full.players = 8
        XCTAssertEqual(PlayTogetherCheck.verdict(full, signedIn: true, copies: [copy()], running: nil), .full)
    }

    func testAnotherCopyWithTheRightVersionIsPicked() {
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy("old", version: "01.008.000"), copy("new")], running: nil), .join("new"))
    }

    func testALockedCopyIsUnlockedFirstAndAnOlderEngineUpdatedFirst() {
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy(unlocked: false)], running: nil), .unlockAndPlay("g1"))
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy(engine: "0.2.20-1", nextEngine: "0.2.21-4194")], running: nil),
                       .updateAndPlay("g1"))
        // An older engine that updating would not bring to the host's.
        XCTAssertEqual(PlayTogetherCheck.verdict(offer, signedIn: true, copies: [copy(engine: "0.2.20-1")], running: nil),
                       .engine(have: "0.2.20-1", need: "0.2.21-4194", youUpdate: true))
    }

    func testTheHostsVersionRule() {
        var major = offer
        major.versionRule = "major"
        XCTAssertEqual(PlayTogetherCheck.verdict(major, signedIn: true, copies: [copy(version: "01.050.000")], running: nil), .join("g1"))
        XCTAssertTrue(TogetherGameSession.versionFits("major", host: "01.044.000", joiner: "01.050.000"))
        XCTAssertFalse(TogetherGameSession.versionFits("major", host: "01.044.000", joiner: "02.000.000"))
        XCTAssertTrue(TogetherGameSession.versionFits("any", host: "01.044.000", joiner: "09.000.000"))
        XCTAssertFalse(TogetherGameSession.versionFits("exact", host: "01.044.000", joiner: "01.044.001"))
    }

    func testTheOfferFromASession() throws {
        let session = try JSONDecoder.together.decode(TogetherGameSession.self, from: JSONSerialization.data(withJSONObject: PlayTogetherClientTests.lan()))
        let made = PlayTogetherOffer(session: session)
        XCTAssertEqual(made.sessionId, "s1")
        XCTAssertEqual(made.hostName, "Utku")
        XCTAssertEqual(made.gameVersion, "01.044.000")
        XCTAssertEqual(made.players, 1)
    }
}

final class OnlinePeerLinkTests: XCTestCase {
    func testADirectRouteWithItsRoundTrip() {
        let stats: [OnlineStatsEntry] = [
            .init(id: "T1", type: "transport", values: ["selectedCandidatePairId": "CP1"]),
            .init(id: "CP1", type: "candidate-pair", values: ["state": "succeeded", "nominated": "1", "currentRoundTripTime": "0.023", "localCandidateId": "L1", "remoteCandidateId": "R1"]),
            .init(id: "L1", type: "local-candidate", values: ["candidateType": "srflx"]),
            .init(id: "R1", type: "remote-candidate", values: ["candidateType": "host"]),
        ]
        XCTAssertEqual(OnlinePeerLinkInfo.route(stats), .init(route: .direct, rttMs: 23))
    }

    func testARelayedRouteWithoutATransportEntry() {
        let stats: [OnlineStatsEntry] = [
            .init(id: "CP0", type: "candidate-pair", values: ["state": "failed", "nominated": "0", "localCandidateId": "L0", "remoteCandidateId": "R0"]),
            .init(id: "CP1", type: "candidate-pair", values: ["state": "succeeded", "nominated": "true", "currentRoundTripTime": "0.0814", "localCandidateId": "L1", "remoteCandidateId": "R1"]),
            .init(id: "L1", type: "local-candidate", values: ["candidateType": "relay"]),
            .init(id: "R1", type: "remote-candidate", values: ["candidateType": "srflx"]),
        ]
        XCTAssertEqual(OnlinePeerLinkInfo.route(stats), .init(route: .relay, rttMs: 81))
    }

    func testNoPairYetIsStillConnecting() {
        XCTAssertEqual(OnlinePeerLinkInfo.route([]), .init(route: .connecting, rttMs: nil))
    }
}

final class OnlinePlayTogetherHostTests: XCTestCase {
    func testPlayTogetherTurnsOnlinePlayOnForItsSessionOnly() {
        let before = UserDefaults.standard.object(forKey: OnlinePlayHost.enabledKey)
        defer { UserDefaults.standard.set(before, forKey: OnlinePlayHost.enabledKey) }
        OnlinePlayHost.enabled = false
        XCTAssertFalse(OnlinePlayHost.isOn)
        OnlinePlayHost.playTogether(sessionId: "s1")
        XCTAssertTrue(OnlinePlayHost.isOn)
        XCTAssertEqual(OnlinePlayHost.togetherSession, "s1")
        XCTAssertFalse(OnlinePlayHost.enabled, "the user's own setting stays as it was")
        OnlinePlayHost.stop()
        XCTAssertFalse(OnlinePlayHost.isOn)
        XCTAssertNil(OnlinePlayHost.togetherSession)
        OnlinePlayHost.enabled = true
        XCTAssertTrue(OnlinePlayHost.isOn)
    }
}
