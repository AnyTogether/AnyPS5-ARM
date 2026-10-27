import XCTest
@testable import AnyPS5Core

/// Join codes for a party or a share play, the party's Discord link and deafening in a call.
final class TogetherJoinCodeTests: TogetherSignedInCase {
    static let code: [String: Any] = ["code": "K7QM3XPA", "url": "https://anytogether.net/join/K7QM3XPA", "expiresAt": "2099-10-26T10:00:00.000Z"]

    // MARK: The code itself

    func testACodeIsShownInTwoHalves() {
        XCTAssertEqual(TogetherJoinCode.display("K7QM3XPA"), "K7QM-3XPA")
        XCTAssertEqual(TogetherJoinCode.display("k7qm3xpa"), "K7QM-3XPA")
        XCTAssertEqual(TogetherJoinCode.display("ABC"), "ABC", "anything else is left as it is")
    }

    func testWhatIsTypedOrPastedIsReadAsACode() {
        XCTAssertEqual(TogetherJoinCode.normalize("K7QM-3XPA"), "K7QM3XPA")
        XCTAssertEqual(TogetherJoinCode.normalize(" k7qm 3xpa "), "K7QM3XPA")
        XCTAssertEqual(TogetherJoinCode.normalize("https://anytogether.net/join/K7QM3XPA"), "K7QM3XPA", "the link works too")
        XCTAssertEqual(TogetherJoinCode.normalize("anytogether.net/join/k7qm-3xpa?x=1"), "K7QM3XPA")
        XCTAssertNil(TogetherJoinCode.normalize("K7QM3XP"), "too short")
        XCTAssertNil(TogetherJoinCode.normalize("K7QM3XPAB"), "too long")
        XCTAssertNil(TogetherJoinCode.normalize("K7QM3XP0"), "no 0, O, 1 or I")
        XCTAssertNil(TogetherJoinCode.normalize("K7QM3XPI"))
        XCTAssertNil(TogetherJoinCode.normalize(""))
    }

    func testACodeThatRanOutDoesNotWork() throws {
        let code = try JSONDecoder.together.decode(TogetherJoinCode.self, from: JSONSerialization.data(withJSONObject: Self.code))
        XCTAssertEqual(code.display, "K7QM-3XPA")
        XCTAssertTrue(code.works(at: Date()))
        XCTAssertFalse(code.works(at: Date(timeIntervalSince1970: 4_100_000_000)))
    }

    // MARK: Models

    func testThePartyCarriesItsCodeDiscordAndWhoIsDeafened() throws {
        var json = TogetherPartyTests.party(call: ["id": "c1", "in": ["u1", "f1"], "muted": ["f1"], "deafened": ["f1"]])
        json["joinCode"] = Self.code
        json["discord"] = "https://discord.gg/abc"
        let party = try JSONDecoder.together.decode(TogetherParty.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(party.joinCode?.code, "K7QM3XPA")
        XCTAssertEqual(party.joinCode?.url, "https://anytogether.net/join/K7QM3XPA")
        XCTAssertEqual(party.discord, "https://discord.gg/abc")
        XCTAssertEqual(party.call?.deafened, ["f1"])
        XCTAssertEqual(party.with(members: party.members, call: party.call).joinCode?.code, "K7QM3XPA", "kept through a local change")
        XCTAssertNil(party.with(joinCode: nil).joinCode)
    }

    func testAnOlderServerWithoutTheNewFieldsStillWorks() throws {
        let party = try JSONDecoder.together.decode(TogetherParty.self, from: JSONSerialization.data(withJSONObject: TogetherPartyTests.party(call: ["id": "c1", "in": ["u1"]])))
        XCTAssertNil(party.joinCode)
        XCTAssertNil(party.discord)
        XCTAssertEqual(party.call?.deafened, [])
        let peer = try JSONDecoder.together.decode(TogetherCallPeer.self, from: Data(#"{"userId":"u1","device":"d1","muted":true}"#.utf8))
        XCTAssertFalse(peer.deafened)
        let change = try JSONDecoder.together.decode(TogetherMuteChange.self, from: Data(#"{"callId":"c1","partyId":null,"userId":"u1","muted":true}"#.utf8))
        XCTAssertFalse(change.deafened)
        let share = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONSerialization.data(withJSONObject: Self.share()))
        XCTAssertNil(share.joinCode)
        let ask = try JSONDecoder.together.decode(TogetherJoinRequest.self, from: Data(#"{"partyId":"p1","from":{"userId":"f2","handle":"sol","displayName":"Sol","avatar":null}}"#.utf8))
        XCTAssertFalse(ask.withCode)
    }

    func testDeafenedPeersAndChanges() throws {
        let peer = try JSONDecoder.together.decode(TogetherCallPeer.self, from: Data(#"{"userId":"u1","device":"d1","muted":true,"deafened":true}"#.utf8))
        XCTAssertTrue(peer.deafened)
        let change = try JSONDecoder.together.decode(TogetherMuteChange.self, from: Data(#"{"callId":"c1","partyId":"p1","userId":"u1","muted":true,"deafened":true}"#.utf8))
        XCTAssertTrue(change.deafened)
    }

    func testTheShareHostSeesItsCode() throws {
        var json = Self.share()
        json["joinCode"] = Self.code
        let share = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(share.joinCode?.display, "K7QM-3XPA")
        let again = try JSONDecoder.together.decode(TogetherSharePlay.self, from: JSONEncoder.together.encode(share))
        XCTAssertEqual(again, share, "kept as the launcher saves it")
    }

    func testARequestSaysWhetherItCameWithTheCode() throws {
        let ask = try JSONDecoder.together.decode(TogetherJoinRequest.self, from: Data(#"{"sharePlayId":"s1","from":{"userId":"f2","handle":"sol","displayName":"Sol","avatar":null},"via":"code"}"#.utf8))
        XCTAssertTrue(ask.withCode)
        XCTAssertEqual(ask.sharePlayId, "s1")
        XCTAssertEqual(ask.from.displayName, "Sol")
    }

    static func share() -> [String: Any] {
        ["id": "s1", "host": TogetherDiscoverTests.person("u1", "Utku"), "hostDevice": "d1", "titleId": "PPSA01234", "title": "Stray", "open": true, "maxViewers": 2,
         "viewers": [], "startedAt": "2026-10-25T10:00:00.000Z"]
    }

    // MARK: Calls to the server

    func testThePartyLeaderMakesAndStopsACode() async throws {
        FakeTogether.handler = { _, _ in (201, Self.code) }
        let code = try await client.makeJoinCode(party: "p1")
        XCTAssertEqual(last(), "POST /api/v1/parties/p1/code")
        XCTAssertEqual(body()?.count, 0, "the default lifetime")
        XCTAssertEqual(code.code, "K7QM3XPA")
        _ = try await client.makeJoinCode(party: "p1", hours: 2)
        XCTAssertEqual(body()?["hours"] as? Int, 2)
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.stopJoinCode(party: "p1")
        XCTAssertEqual(last(), "DELETE /api/v1/parties/p1/code")
    }

    func testTheShareHostMakesAndStopsACode() async throws {
        FakeTogether.handler = { _, _ in (201, Self.code) }
        let code = try await client.makeJoinCode(sharePlay: "s1")
        XCTAssertEqual(last(), "POST /api/v1/share-plays/s1/code")
        XCTAssertEqual(code.display, "K7QM-3XPA")
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.stopJoinCode(sharePlay: "s1")
        XCTAssertEqual(last(), "DELETE /api/v1/share-plays/s1/code")
    }

    func testReadingACode() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["code": "K7QM3XPA", "kind": "party", "id": "p1", "host": ["userId": "f1", "handle": "mira", "displayName": "Mira", "avatar": NSNull()],
                   "game": ["titleId": "PPSA01234", "title": "Stray", "names": ["en": "Stray", "tr": "Stray TR"], "iconUrl": NSNull()],
                   "size": 3, "max": 8, "expiresAt": "2099-10-26T10:00:00.000Z", "state": "none"])
        }
        let info = try await client.joinCodeInfo("k7qm-3xpa")
        XCTAssertEqual(last(), "GET /api/v1/join/K7QM3XPA")
        XCTAssertNotNil(FakeTogether.requests.last?.0.value(forHTTPHeaderField: "Authorization"), "signed in, it says who reads it")
        XCTAssertEqual(info.kind, .party)
        XCTAssertEqual(info.id, "p1")
        XCTAssertEqual(info.host?.displayName, "Mira")
        XCTAssertEqual(info.game?.name(in: "tr"), "Stray TR")
        XCTAssertEqual(info.size, 3)
        XCTAssertEqual(info.max, 8)
        XCTAssertEqual(info.state, .notIn)

        FakeTogether.handler = { _, _ in
            (200, ["code": "K7QM3XPA", "kind": "share_play", "id": "s1", "host": ["handle": "mira", "displayName": "Mira", "avatar": NSNull()], "game": NSNull(),
                   "size": 1, "max": 4, "expiresAt": "2099-10-26T10:00:00.000Z"])
        }
        let signedOut = try await client.joinCodeInfo("K7QM3XPA")
        XCTAssertEqual(signedOut.kind, .sharePlay)
        XCTAssertNil(signedOut.host?.userId)
        XCTAssertNil(signedOut.game)
        XCTAssertNil(signedOut.state)

        FakeTogether.handler = { _, _ in (404, ["type": "x", "title": "No such code", "status": 404, "code": "not_found"]) }
        do {
            _ = try await client.joinCodeInfo("K7QM3XPA")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "not_found")
        }
    }

    func testAskingToJoinWithACode() async throws {
        FakeTogether.handler = { _, _ in (201, ["kind": "party", "id": "p1", "state": "requested"]) }
        let answer = try await client.redeemJoinCode("K7QM-3XPA")
        XCTAssertEqual(last(), "POST /api/v1/join/K7QM3XPA")
        XCTAssertEqual(answer.kind, .party)
        XCTAssertEqual(answer.state, .requested)
        FakeTogether.handler = { _, _ in (200, ["kind": "share_play", "id": "s1", "state": "invited"]) }
        let invited = try await client.redeemJoinCode("K7QM3XPA")
        XCTAssertEqual(invited.state, .invited)
        XCTAssertEqual(invited.kind, .sharePlay)

        FakeTogether.handler = { _, _ in
            (403, ["type": "x", "title": "Family settings", "status": 403, "code": "restricted_by_family", "feature": "share_play", "side": "other"])
        }
        do {
            _ = try await client.redeemJoinCode("K7QM3XPA")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "restricted_by_family")
            XCTAssertEqual(problem.side, "other")
        }
    }

    func testThePartysDiscordLink() async throws {
        var linked = TogetherPartyTests.party()
        linked["discord"] = "https://discord.gg/abc"
        FakeTogether.handler = { _, _ in (200, linked) }
        let party = try await client.setPartyDiscord("p1", "https://discord.gg/abc")
        XCTAssertEqual(last(), "PATCH /api/v1/parties/p1")
        XCTAssertEqual(body()?["discord"] as? String, "https://discord.gg/abc")
        XCTAssertEqual(party.discord, "https://discord.gg/abc")
        FakeTogether.handler = { _, _ in (200, TogetherPartyTests.party()) }
        let off = try await client.setPartyDiscord("p1", nil)
        XCTAssertTrue(body()?["discord"] is NSNull)
        XCTAssertNil(off.discord)
    }

    func testADiscordLinkIsCheckedBeforeItGoes() {
        XCTAssertEqual(TogetherPartyDiscord.clean("https://discord.gg/abc"), "https://discord.gg/abc")
        XCTAssertEqual(TogetherPartyDiscord.clean(" discord.gg/abc "), "https://discord.gg/abc", "https is added")
        XCTAssertEqual(TogetherPartyDiscord.clean("https://discord.com/invite/abc?x=1#y"), "https://discord.com/invite/abc")
        XCTAssertEqual(TogetherPartyDiscord.clean("https://ptb.discord.com/channels/123/456"), "https://ptb.discord.com/channels/123/456")
        XCTAssertNil(TogetherPartyDiscord.clean("http://discord.gg/abc"), "https only")
        XCTAssertNil(TogetherPartyDiscord.clean("https://discord.gg/"))
        XCTAssertNil(TogetherPartyDiscord.clean("https://evil.example/discord.gg/abc"))
        XCTAssertNil(TogetherPartyDiscord.clean("https://discord.com/app"))
        XCTAssertNil(TogetherPartyDiscord.clean(""))
    }

    func testMutedAndDeafenedGoTogether() async throws {
        FakeTogether.handler = { _, _ in (200, ["ok": true]) }
        try await client.setMuted(true, deafened: true, in: "c1")
        XCTAssertEqual(last(), "POST /api/v1/calls/c1/mute")
        XCTAssertEqual(body()?["muted"] as? Bool, true)
        XCTAssertEqual(body()?["deafened"] as? Bool, true)
        try await client.setMuted(false, in: "c1")
        XCTAssertEqual(body()?["muted"] as? Bool, false)
        XCTAssertNil(body()?["deafened"], "left out when not said")
    }

    // MARK: The microphone and deafening

    func testDeafenMutesAndUndeafenGivesTheMicrophoneBack() {
        var mic = TogetherVoiceMic()
        XCTAssertTrue(mic.on)
        mic.deafen()
        XCTAssertTrue(mic.deafened)
        XCTAssertFalse(mic.on)
        XCTAssertTrue(mic.muted(pushToTalk: false))
        XCTAssertTrue(mic.muted(pushToTalk: true), "deafened is muted with push-to-talk too")
        XCTAssertFalse(mic.sending(pushToTalk: true, held: true), "holding the key sends nothing while deafened")
        mic.undeafen()
        XCTAssertFalse(mic.deafened)
        XCTAssertTrue(mic.on, "on as it was before")

        mic.set(on: false)
        mic.deafen()
        mic.undeafen()
        XCTAssertFalse(mic.on, "muted before deafening stays muted")
    }

    func testUnmutingWhileDeafenedUndeafens() {
        var mic = TogetherVoiceMic()
        mic.deafen()
        mic.set(on: true)
        XCTAssertFalse(mic.deafened)
        XCTAssertTrue(mic.on)
        XCTAssertFalse(mic.muted(pushToTalk: false))

        mic.deafen()
        mic.set(on: false)
        XCTAssertTrue(mic.deafened, "muting again keeps it deafened")
        mic.toggleDeafen()
        XCTAssertFalse(mic.deafened)
        mic.toggleDeafen()
        XCTAssertTrue(mic.deafened)
    }

    func testWhatTheServerIsTold() {
        var mic = TogetherVoiceMic()
        XCTAssertEqual(mic.state(pushToTalk: false), .init(muted: false, deafened: false))
        mic.set(on: false)
        XCTAssertEqual(mic.state(pushToTalk: false), .init(muted: true, deafened: false))
        XCTAssertEqual(mic.state(pushToTalk: true), .init(muted: false, deafened: false), "push-to-talk is not muted")
        mic.deafen()
        XCTAssertEqual(mic.state(pushToTalk: true), .init(muted: true, deafened: true))
    }
}
