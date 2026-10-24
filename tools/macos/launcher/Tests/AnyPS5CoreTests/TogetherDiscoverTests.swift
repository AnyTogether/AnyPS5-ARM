import XCTest
@testable import AnyPS5Core

final class TogetherDiscoverTests: TogetherSignedInCase {
    static func person(_ id: String, _ name: String = "Mira") -> [String: Any] { ["userId": id, "handle": name.lowercased(), "displayName": name, "avatar": NSNull()] }

    static func post(_ id: String = "l1", mine: Bool = false, purpose: String = "coop", slots: Int = 2, filled: Int = 0, status: String = "open", startsAt: Any = NSNull(),
                     expiresAt: String = "2099-01-01T10:00:00.000Z", myRequest: Any = NSNull(), requests: [[String: Any]]? = nil) -> [String: Any] {
        var post: [String: Any] = [
            "id": id, "author": person(mine ? "u1" : "f1", mine ? "Utku" : "Mira"), "titleId": "PPSA01234",
            "game": ["names": ["en": "Stray", "tr": "Stray TR"], "iconUrl": NSNull()], "purpose": purpose, "startsAt": startsAt,
            "languages": ["en", "tr"], "region": NSNull(), "slots": slots, "filled": filled, "note": "Chill run", "expiresAt": expiresAt,
            "status": status, "createdAt": "2026-10-25T10:00:00.000Z", "mine": mine, "myRequest": myRequest,
        ]
        if let requests { post["requests"] = requests }
        return post
    }

    // MARK: The board

    func testTheBoardWithFilters() async throws {
        FakeTogether.handler = { _, _ in (200, ["posts": [Self.post()], "more": true]) }
        let page = try await client.lfgBoard(TogetherLfgFilter(titleId: "PPSA01234", purpose: .coop, language: "tr", now: true))
        XCTAssertEqual(last(), "GET /api/v1/lfg?titleId=PPSA01234&purpose=coop&language=tr&now=1")
        XCTAssertTrue(page.more)
        let post = try XCTUnwrap(page.posts.first)
        XCTAssertEqual(post.name(in: "tr"), "Stray TR")
        XCTAssertEqual(post.purpose, .coop)
        XCTAssertEqual(post.languages, ["en", "tr"])
        XCTAssertNil(post.startsAt)
        XCTAssertEqual(post.standing(), .canAsk)
        XCTAssertEqual(post.when(), .now)

        _ = try await client.lfgBoard(before: "l9")
        XCTAssertEqual(last(), "GET /api/v1/lfg?before=l9")
        _ = try await client.lfgBoard()
        XCTAssertEqual(last(), "GET /api/v1/lfg")
    }

    func testFilterTopics() {
        XCTAssertEqual(TogetherLfgFilter().topic, "lfg")
        XCTAssertEqual(TogetherLfgFilter(titleId: "PPSA01234").topic, "lfg:PPSA01234")
    }

    func testGamesAndMyPosts() async throws {
        FakeTogether.handler = { _, _ in (200, ["games": [["titleId": "PPSA01234", "posts": 4, "names": ["en": "Stray"], "iconUrl": NSNull()]]]) }
        let games = try await client.lfgGames()
        XCTAssertEqual(last(), "GET /api/v1/lfg/games")
        XCTAssertEqual(games.first?.posts, 4)
        XCTAssertEqual(games.first?.name(in: "en"), "Stray")

        let asking = ["user": Self.person("f2", "Sol"), "status": "pending", "invite": NSNull(), "createdAt": "2026-10-25T10:05:00.000Z"] as [String: Any]
        let accepted = ["user": Self.person("f3", "Kenji"), "status": "accepted", "invite": ["kind": "party", "id": "p1"], "createdAt": "2026-10-25T10:01:00.000Z"] as [String: Any]
        FakeTogether.handler = { _, _ in
            (200, ["posts": [Self.post("l2", mine: true, filled: 1, requests: [asking, accepted])],
                   "asked": [Self.post("l3", myRequest: ["status": "accepted", "invite": ["kind": "share_play", "id": "s1"]])]])
        }
        let mine = try await client.myLfg()
        XCTAssertEqual(last(), "GET /api/v1/me/lfg")
        XCTAssertEqual(mine.posts.first?.standing(), .own)
        XCTAssertEqual(mine.posts.first?.pending.map(\.user.displayName), ["Sol"])
        XCTAssertEqual(mine.posts.first?.requests?.last?.invite, TogetherLfgInvite(kind: "party", id: "p1"))
        XCTAssertEqual(mine.asked.first?.standing(), .accepted(TogetherLfgInvite(kind: "share_play", id: "s1")))
        XCTAssertEqual(mine.asked.first?.myRequest?.invite?.isSharePlay, true)
    }

    func testStandings() throws {
        let decode = { (json: [String: Any]) throws -> TogetherLfgPost in try JSONDecoder.together.decode(TogetherLfgPost.self, from: JSONSerialization.data(withJSONObject: json)) }
        XCTAssertEqual(try decode(Self.post(myRequest: ["status": "pending", "invite": NSNull()])).standing(), .waiting)
        XCTAssertEqual(try decode(Self.post(myRequest: ["status": "declined", "invite": NSNull()])).standing(), .declined)
        XCTAssertEqual(try decode(Self.post(slots: 2, filled: 2, status: "full")).standing(), .closed)
        XCTAssertEqual(try decode(Self.post(expiresAt: "2020-01-01T10:00:00.000Z")).standing(), .closed)
        // Waiting on a post that went: closed.
        XCTAssertEqual(try decode(Self.post(status: "closed", myRequest: ["status": "pending", "invite": NSNull()])).standing(), .closed)
    }

    func testWhen() throws {
        let now = Date()
        let later = ISO8601DateFormatter().string(from: now.addingTimeInterval(45 * 60))
        let post = try JSONDecoder.together.decode(TogetherLfgPost.self, from: JSONSerialization.data(withJSONObject: Self.post(startsAt: later)))
        XCTAssertEqual(post.when(at: now), .inMinutes(45))
        XCTAssertEqual(post.when(at: now.addingTimeInterval(45 * 60 + 20)), .now)
    }

    // MARK: Posting

    func testDraftBody() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-25T10:00:00Z")!
        var draft = TogetherLfgDraft(titleId: "PPSA01234", purpose: .online, slots: 6, languages: ["tr", "en", "de", "fr"], note: "  Ranked tonight  ", startsIn: 30, hours: 2)
        let body = draft.body(now: now)
        XCTAssertEqual(body["purpose"] as? String, "online")
        XCTAssertEqual(body["slots"] as? Int, 6)
        XCTAssertEqual(body["languages"] as? [String], ["tr", "en", "de"])
        XCTAssertEqual(body["note"] as? String, "Ranked tonight")
        XCTAssertEqual(body["startsAt"] as? String, "2026-10-25T10:30:00Z")
        XCTAssertEqual(body["expiresAt"] as? String, "2026-10-25T12:30:00Z")

        // Co-op has room for three more (pads 2-4): the slots follow.
        draft.setPurpose(.coop)
        XCTAssertEqual(draft.slots, 3)
        XCTAssertEqual(draft.slotRange, 1 ... 3)
        draft.setPurpose(.party)
        XCTAssertEqual(draft.slotRange, 1 ... 7)

        // Now, no note, and never past a day.
        let quick = TogetherLfgDraft(titleId: "PPSA01234", languages: ["en"], startsIn: 0, hours: 40).body(now: now)
        XCTAssertNil(quick["startsAt"])
        XCTAssertNil(quick["note"])
        XCTAssertEqual(quick["expiresAt"] as? String, "2026-10-26T10:00:00Z")
        XCTAssertEqual(TogetherLfgDraft(titleId: "X", languages: ["en"], startsIn: 600).hourRange, 1 ... 14)
        let long = TogetherLfgDraft(titleId: "X", languages: ["en"], note: String(repeating: "a", count: 200)).body(now: now)
        XCTAssertEqual((long["note"] as? String)?.count, 140)
    }

    func testPostingAndAnswering() async throws {
        FakeTogether.handler = { _, _ in (201, Self.post(mine: true)) }
        let post = try await client.postLfg(TogetherLfgDraft(titleId: "PPSA01234", languages: ["en"]))
        XCTAssertEqual(last(), "POST /api/v1/lfg")
        XCTAssertEqual(body()?["titleId"] as? String, "PPSA01234")
        XCTAssertTrue(post.mine)

        FakeTogether.handler = { _, _ in (200, Self.post(mine: true, filled: 1)) }
        let answered = try await client.answerLfg("l1", user: "f2", accept: true)
        XCTAssertEqual(last(), "POST /api/v1/lfg/l1/requests/f2/accept")
        XCTAssertEqual(answered.filled, 1)
        _ = try await client.answerLfg("l1", user: "f3", accept: false)
        XCTAssertEqual(last(), "POST /api/v1/lfg/l1/requests/f3/decline")

        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.closeLfg("l1")
        XCTAssertEqual(last(), "DELETE /api/v1/lfg/l1")
    }

    func testImInAndTakingItBack() async throws {
        FakeTogether.handler = { _, _ in (201, Self.post(myRequest: ["status": "pending", "invite": NSNull()])) }
        let post = try await client.joinLfg("l1")
        XCTAssertEqual(last(), "POST /api/v1/lfg/l1/requests")
        XCTAssertEqual(post.standing(), .waiting)
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.cancelLfgRequest("l1")
        XCTAssertEqual(last(), "DELETE /api/v1/lfg/l1/requests/me")

        FakeTogether.handler = { _, _ in (409, ["status": 409, "code": "conflict", "title": "This post is closed"]) }
        do {
            _ = try await client.joinLfg("l1")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "conflict")
        }
    }

    // MARK: Public parties and share plays

    func testPublicParties() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["parties": [["id": "p1", "host": Self.person("f1"), "titleId": "PPSA01234", "game": ["names": ["en": "Stray"], "iconUrl": NSNull()], "language": "tr",
                                "join": "request", "size": 3, "max": 8, "requested": true, "listedAt": "2026-10-25T10:00:00.000Z"]]])
        }
        let parties = try await client.publicParties(titleId: "PPSA01234", language: "tr")
        XCTAssertEqual(last(), "GET /api/v1/parties/public?titleId=PPSA01234&language=tr")
        XCTAssertEqual(parties.first?.join, .request)
        XCTAssertEqual(parties.first?.requested, true)
        XCTAssertEqual(parties.first?.full, false)
        _ = try await client.publicParties()
        XCTAssertEqual(last(), "GET /api/v1/parties/public")

        FakeTogether.handler = { _, _ in (201, ["requested": true]) }
        try await client.askToJoinParty("p1")
        XCTAssertEqual(last(), "POST /api/v1/parties/p1/requests")
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.cancelPartyRequest("p1")
        XCTAssertEqual(last(), "DELETE /api/v1/parties/p1/requests/me")
    }

    func testListingMyPartyAndAnsweringRequests() async throws {
        let listed = TogetherPartyTests.party().merging(["public": ["join": "open", "titleId": "PPSA01234", "language": "en"], "requests": [Self.person("f2", "Sol")]]) { _, new in new }
        FakeTogether.handler = { _, _ in (200, listed) }
        let party = try await client.setPartyListing("p1", TogetherPartyListing(join: .open, titleId: "PPSA01234", language: "en"))
        XCTAssertEqual(last(), "PATCH /api/v1/parties/p1")
        let listing = try XCTUnwrap(body()?["public"] as? [String: Any])
        XCTAssertEqual(listing["join"] as? String, "open")
        XCTAssertEqual(listing["titleId"] as? String, "PPSA01234")
        XCTAssertEqual(party.listing, TogetherPartyListing(join: .open, titleId: "PPSA01234", language: "en"))
        XCTAssertEqual(party.requests?.map(\.displayName), ["Sol"])

        FakeTogether.handler = { _, _ in (200, TogetherPartyTests.party()) }
        let off = try await client.setPartyListing("p1", nil)
        XCTAssertTrue(body()?["public"] is NSNull)
        XCTAssertNil(off.listing)

        _ = try await client.answerPartyRequest("p1", user: "f2", accept: true)
        XCTAssertEqual(last(), "POST /api/v1/parties/p1/requests/f2/accept")

        _ = try await client.startParty(open: false, listing: TogetherPartyListing(join: .request))
        XCTAssertEqual((body()?["public"] as? [String: Any])?["join"] as? String, "request")
        XCTAssertTrue((body()?["public"] as? [String: Any])?["language"] is NSNull)
    }

    func testMyPartyTellsWhatIAsked() async throws {
        FakeTogether.handler = { _, _ in (200, ["party": NSNull(), "invites": [], "requests": [["partyId": "p7", "askedAt": "2026-10-25T10:00:00.000Z"]]]) }
        let mine = try await client.myParty()
        XCTAssertEqual(mine.asked, ["p7"])
    }

    func testPublicShares() async throws {
        let share: [String: Any] = ["id": "s1", "host": Self.person("f1"), "titleId": "PPSA01234", "title": "Stray", "game": NSNull(), "language": "en", "join": "open", "live": true,
                                    "viewers": 1, "maxViewers": 2, "requested": false, "startedAt": "2026-10-25T10:00:00.000Z"]
        FakeTogether.handler = { _, _ in (200, ["sharePlays": [share]]) }
        let live = try await client.publicSharePlays(live: true)
        XCTAssertEqual(last(), "GET /api/v1/share-plays/public?live=1")
        XCTAssertEqual(live.first?.live, true)
        XCTAssertEqual(live.first?.name(in: "en"), "Stray")
        _ = try await client.publicSharePlays(titleId: "PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/share-plays/public?titleId=PPSA01234")

        FakeTogether.handler = { _, _ in (201, ["requested": true]) }
        try await client.askToWatch("s1")
        XCTAssertEqual(last(), "POST /api/v1/share-plays/s1/requests")
    }

    func testListingMySharePlay() async throws {
        let hosted: [String: Any] = ["id": "s1", "host": Self.person("u1", "Utku"), "hostDevice": "d1", "titleId": "PPSA01234", "title": "Stray", "open": true, "maxViewers": 2,
                                     "viewers": [], "public": ["join": "open", "language": NSNull(), "live": true], "requests": [Self.person("f2", "Sol")],
                                     "startedAt": "2026-10-25T10:00:00.000Z"]
        FakeTogether.handler = { _, _ in (200, hosted) }
        let share = try await client.setShareListing("s1", TogetherShareListing(join: .open, live: true))
        XCTAssertEqual(last(), "PATCH /api/v1/share-plays/s1")
        XCTAssertEqual((body()?["public"] as? [String: Any])?["live"] as? Bool, true)
        XCTAssertEqual(share.listing, TogetherShareListing(join: .open, live: true))
        XCTAssertEqual(share.requests?.first?.handle, "sol")
        _ = try await client.answerShareRequest("s1", user: "f2", accept: false)
        XCTAssertEqual(last(), "POST /api/v1/share-plays/s1/requests/f2/decline")
        _ = try await client.setShareListing("s1", nil)
        XCTAssertTrue(body()?["public"] is NSNull)
        // Live now needs an open one.
        XCTAssertFalse(TogetherShareListing(join: .request, live: true).live)
    }

    // MARK: Discovery

    func testDiscoverySetting() async throws {
        FakeTogether.handler = { _, _ in (200, ["discoverable": true, "chosen": NSNull(), "languages": ["tr"]]) }
        let discovery = try await client.discovery()
        XCTAssertEqual(last(), "GET /api/v1/me/discovery")
        XCTAssertEqual(discovery.choice, .followLibrary)
        XCTAssertTrue(discovery.discoverable)

        FakeTogether.handler = { _, _ in (200, ["discoverable": false, "chosen": false, "languages": ["tr", "en"]]) }
        let off = try await client.setDiscovery(.off)
        XCTAssertEqual(last(), "PATCH /api/v1/me/discovery")
        XCTAssertEqual(body()?["discoverable"] as? Bool, false)
        XCTAssertNil(body()?["languages"])
        XCTAssertEqual(off.choice, .off)
        _ = try await client.setDiscovery(.followLibrary)
        XCTAssertTrue(body()?["discoverable"] is NSNull)
        _ = try await client.setDiscovery(languages: ["tr", "en"])
        XCTAssertEqual(body()?["languages"] as? [String], ["tr", "en"])
        XCTAssertNil(body()?["discoverable"])
    }

    func testLanguagesUpToFive() {
        let some = TogetherDiscovery(discoverable: true, chosen: true, languages: ["tr", "en"])
        XCTAssertEqual(some.toggling("en"), ["tr"])
        XCTAssertEqual(some.toggling("de"), ["tr", "en", "de"])
        let full = TogetherDiscovery(discoverable: true, chosen: true, languages: ["tr", "en", "de", "fr", "es"])
        XCTAssertNil(full.toggling("it"))
        XCTAssertEqual(TogetherLanguages.name("tr", in: "tr"), "Türkçe")
        XCTAssertEqual(TogetherLanguages.name("de", in: "en"), "German")
    }

    func testSuggestionsWithTheirReasons() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["suggestions": [["user": Self.person("x1", "Lin"), "friendship": "none", "presence": ["state": "in_game", "titleId": "PPSA01234"],
                                    "reasons": [["kind": "game", "titleId": "PPSA01234", "names": ["en": "Stray"]], ["kind": "friends", "count": 2], ["kind": "language", "language": "tr"],
                                                ["kind": "future"]]]]])
        }
        let suggestions = try await client.suggestions()
        XCTAssertEqual(last(), "GET /api/v1/discover/suggestions")
        let lin = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(lin.reasons, [.game(titleId: "PPSA01234", names: ["en": "Stray"]), .friends(count: 2), .language("tr"), .other])
        XCTAssertEqual(lin.presence?.titleId, "PPSA01234")
        XCTAssertTrue(lin.canAsk)

        FakeTogether.handler = { _, _ in (200, ["players": [["user": Self.person("x2", "Ada"), "friendship": "pending_out", "lastPlayedAt": "2026-10-24T10:00:00.000Z"]]]) }
        let players = try await client.playersOf("PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/discover/players?titleId=PPSA01234")
        XCTAssertFalse(players[0].canAsk)
        XCTAssertNotNil(players[0].lastPlayedAt)
        XCTAssertEqual(players[0].reasons, [])
    }

    func testAGamesHub() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["game": ["titleId": "PPSA01234", "names": ["en": "Stray"], "iconUrl": NSNull()], "players": 120,
                   "playing": ["total": 1, "people": [["user": Self.person("f1"), "since": "2026-10-25T09:00:00.000Z"]]],
                   "lfg": [Self.post()], "parties": [], "sharePlays": [], "recentPlayers": [["user": Self.person("x2", "Ada"), "friendship": "none", "lastPlayedAt": NSNull()]]])
        }
        let hub = try await client.gameHub("PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/games/PPSA01234/hub")
        XCTAssertEqual(hub.game.name(in: "en"), "Stray")
        XCTAssertEqual(hub.players, 120)
        XCTAssertEqual(hub.playing.people.first?.user.displayName, "Mira")
        XCTAssertEqual(hub.lfg.count, 1)
        XCTAssertEqual(hub.recentPlayers.first?.user.handle, "ada")
    }

    // MARK: Topics

    func testTopics() throws {
        XCTAssertEqual(TogetherTopics.discovery(titleId: nil), ["lfg", "discover"])
        XCTAssertEqual(TogetherTopics.discovery(titleId: "PPSA01234"), ["lfg:PPSA01234", "discover:PPSA01234"])
        XCTAssertEqual(TogetherTopics.clean(["lfg", "lfg", "nope", "lfg:ppsa01234", "discover:CUSA1234", "discover:PPSA12345"]), ["lfg", "discover:PPSA12345"])
        XCTAssertEqual(TogetherTopics.clean((0 ..< 12).map { "lfg:PPSA0000\($0 % 10)" } + ["lfg", "discover"]).count, 8)
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: TogetherTopics.frame(["lfg", "bad"])) as? [String: Any])
        XCTAssertEqual(frame["op"] as? String, "watch")
        XCTAssertEqual(frame["topics"] as? [String], ["lfg"])
    }
}
