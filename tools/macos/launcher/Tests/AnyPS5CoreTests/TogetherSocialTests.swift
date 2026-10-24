import XCTest
@testable import AnyPS5Core

/// A client signed in against FakeTogether, for the social tests.
class TogetherSignedInCase: XCTestCase {
    var folder: URL!
    var client: TogetherClient!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-social-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: TokenStore(file: folder.appendingPathComponent("s.json")),
                                session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
        FakeTogether.requests = []
        FakeTogether.handler = { _, _ in (200, TogetherTests.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
        FakeTogether.requests = []
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func body(_ index: Int = -1) -> [String: Any]? {
        let request = index < 0 ? FakeTogether.requests.last : FakeTogether.requests[index]
        return (request?.1).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func last() -> String {
        guard let request = FakeTogether.requests.last?.0 else { return "" }
        return "\(request.httpMethod ?? "") \(request.url!.path)" + (request.url!.query.map { "?\($0)" } ?? "")
    }
}

final class TogetherAccountTests: TogetherSignedInCase {
    static func own(handle: String = "utku", name: String = "Utku", bio: Any = NSNull(), changeAt: Any = NSNull()) -> [String: Any] {
        ["handle": handle, "displayName": name, "bio": bio, "avatar": "https://cdn.test/u.webp", "country": "TR", "handleChangedAt": NSNull(), "handleChangeAt": changeAt,
         "privacy": ["library": "friends", "trophies": "everyone", "friends": "friends", "presence": "nobody", "search": "everyone"]]
    }

    func testMyProfileWithItsPrivacy() async throws {
        FakeTogether.handler = { _, _ in (200, ["account": ["id": "u1", "email": "u@example.com", "createdAt": "2026-10-01T10:00:00.000Z"], "profile": Self.own()]) }
        let mine = try await client.myProfile()
        XCTAssertEqual(mine.handle, "utku")
        XCTAssertEqual(mine.country, "TR")
        XCTAssertNil(mine.handleChangeAt)
        XCTAssertEqual(mine.privacy[.trophies], .everyone)
        XCTAssertEqual(mine.privacy[.presence], .nobody)
        XCTAssertEqual(last(), "GET /api/v1/me")
    }

    /// Only what changed goes up; the name the launcher keeps for the session follows.
    func testEditingTheProfileSendsWhatChanged() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(name: "Utku H.", bio: "Platinum hunter")) }
        let mine = try await client.updateProfile(displayName: "Utku H.", bio: "Platinum hunter")
        XCTAssertEqual(mine.displayName, "Utku H.")
        XCTAssertEqual(last(), "PATCH /api/v1/me/profile")
        XCTAssertEqual(body()?.keys.sorted(), ["bio", "displayName"])
        XCTAssertEqual(client.user?.displayName, "Utku H.")
        _ = try await client.updateProfile(bio: "")
        XCTAssertTrue(body()?["bio"] is NSNull, "an empty bio clears it")
    }

    func testANewHandleAndItsRefusals() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(handle: "utkuh")) }
        let mine = try await client.changeHandle("@UtkuH ")
        XCTAssertEqual(mine.handle, "utkuh")
        XCTAssertEqual(body()?["handle"] as? String, "utkuh")
        XCTAssertEqual(client.user?.handle, "utkuh", "the session's user follows")
        FakeTogether.handler = { _, _ in (429, ["code": "handle_cooldown", "status": 429, "title": "The handle can change again on 2026-11-20", "handleChangeAt": "2026-11-20T09:00:00.000Z"]) }
        do {
            _ = try await client.changeHandle("other")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "handle_cooldown")
            XCTAssertEqual(problem.handleChangeAt, ISO8601DateFormatter().date(from: "2026-11-20T09:00:00Z"))
        }
    }

    func testPrivacyChangesOneSection() async throws {
        FakeTogether.handler = { _, _ in (200, ["library": "nobody", "trophies": "friends", "friends": "friends", "presence": "friends", "search": "everyone"]) }
        let privacy = try await client.updatePrivacy(.library, to: .nobody)
        XCTAssertEqual(last(), "PATCH /api/v1/me/privacy")
        XCTAssertEqual(body() as? [String: String], ["library": "nobody"])
        XCTAssertEqual(privacy[.library], .nobody)
        XCTAssertEqual(privacy[.search], .everyone)
    }

    /// A 403 for a private section names it, for the launchers that read it.
    func testAPrivateSectionIsNamed() async throws {
        FakeTogether.handler = { _, _ in (403, ["code": "forbidden", "status": 403, "title": "This is private", "section": "library"]) }
        do {
            _ = try await client.authorized("GET", "users/ayse/library", nil)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.section, "library")
        }
    }
}

final class TogetherMessagesTests: TogetherSignedInCase {
    static func message(_ seq: Int, in conversation: String = "c1", from author: String = "f1", text: String? = "hi", at: String = "2026-10-24T10:00:00.000Z") -> [String: Any] {
        ["id": "m\(conversation)\(seq)", "conversationId": conversation, "seq": seq, "authorId": author, "text": text ?? NSNull(), "replyTo": NSNull(),
         "editedAt": NSNull(), "deletedAt": text == nil ? at : NSNull(), "createdAt": at]
    }

    static func conversation(_ id: String = "c1", unread: Int = 2, last: Int = 5) -> [String: Any] {
        ["id": id, "kind": "direct", "title": NSNull(), "createdBy": "u1",
         "members": [["userId": "u1", "handle": "utku", "displayName": "Utku", "avatar": NSNull()], ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull()]],
         "lastSeq": last, "readSeq": last - unread, "unread": unread, "lastMessage": message(last, in: id), "updatedAt": "2026-10-24T10:00:00.000Z"]
    }

    func testConversationsWithTheirUnreadCounts() async throws {
        FakeTogether.handler = { _, _ in (200, ["conversations": [Self.conversation(), Self.conversation("c2", unread: 0, last: 1)]]) }
        let list = try await client.conversations()
        XCTAssertEqual(last(), "GET /api/v1/me/conversations")
        XCTAssertEqual(list.map(\.unread), [2, 0])
        XCTAssertEqual(list.first?.lastMessage?.text, "hi")
        XCTAssertEqual(list.first?.others(than: "u1").map(\.handle), ["ayse"])
        XCTAssertEqual(list.first?.name(for: "u1"), "Ayşe")
    }

    func testADirectConversationWithAFriend() async throws {
        FakeTogether.handler = { _, _ in (200, Self.conversation()) }
        let conversation = try await client.conversation(with: "f1")
        XCTAssertEqual(conversation.id, "c1")
        XCTAssertEqual(last(), "POST /api/v1/conversations")
        XCTAssertEqual(body()?["members"] as? [String], ["f1"])
    }

    func testAPageOfHistoryAndOlderOnes() async throws {
        FakeTogether.handler = { _, _ in (200, ["messages": [Self.message(4), Self.message(5)], "more": true]) }
        let page = try await client.messages(in: "c1")
        XCTAssertEqual(page.messages.map(\.seq), [4, 5])
        XCTAssertTrue(page.more)
        XCTAssertEqual(last(), "GET /api/v1/conversations/c1/messages?limit=50")
        _ = try await client.messages(in: "c1", before: 4)
        XCTAssertEqual(last(), "GET /api/v1/conversations/c1/messages?limit=50&before=4")
    }

    func testSendingCarriesItsOwnIDAndReadingMovesTheMark() async throws {
        FakeTogether.handler = { _, _ in (201, Self.message(6, from: "u1", text: "on my way")) }
        let id = UUID()
        let sent = try await client.send("on my way", in: "c1", id: id)
        XCTAssertEqual(sent.seq, 6)
        XCTAssertEqual(last(), "POST /api/v1/conversations/c1/messages")
        XCTAssertEqual(body()?["clientId"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(body()?["text"] as? String, "on my way")
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.markRead("c1", upTo: 6)
        XCTAssertEqual(last(), "POST /api/v1/conversations/c1/read")
        XCTAssertEqual(body()?["upToSeq"] as? Int, 6)
    }

    func testTheUnreadBadge() async throws {
        FakeTogether.handler = { _, _ in (200, ["conversations": 2, "messages": 7]) }
        let unread = try await client.unreadMessages()
        XCTAssertEqual(unread, 7)
        XCTAssertEqual(last(), "GET /api/v1/me/conversations/unread")
    }

    static func decoded<T: Decodable>(_ json: [String: Any]) -> T {
        try! JSONDecoder.together.decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// What the socket says, applied to what the launcher holds: new messages count as unread
    /// unless they are the user's own or the thread is open, repeats are ignored, a deletion
    /// empties the text, reading elsewhere clears the count.
    func testTheInboxFollowsTheSocket() {
        var inbox = TogetherInbox(me: "u1", conversations: [Self.decoded(Self.conversation("c1", unread: 0, last: 5)), Self.decoded(Self.conversation("c2", unread: 0, last: 3))])
        inbox.threads["c2"] = [Self.decoded(Self.message(3, in: "c2"))]
        XCTAssertTrue(inbox.apply(Self.decoded(Self.message(4, in: "c2", at: "2026-10-24T11:00:00.000Z")), open: nil))
        XCTAssertEqual(inbox.conversations.map(\.id), ["c2", "c1"], "the newest first")
        XCTAssertEqual(inbox.unread, 1)
        XCTAssertEqual(inbox.threads["c2"]?.map(\.seq), [3, 4])
        XCTAssertTrue(inbox.apply(Self.decoded(Self.message(4, in: "c2")), open: nil))
        XCTAssertEqual(inbox.threads["c2"]?.count, 2, "a repeat is ignored")
        XCTAssertEqual(inbox.unread, 1)
        XCTAssertTrue(inbox.apply(Self.decoded(Self.message(6, in: "c1", from: "u1")), open: nil))
        XCTAssertEqual(inbox.unread, 1, "your own message is read")
        XCTAssertTrue(inbox.apply(Self.decoded(Self.message(7, in: "c1")), open: "c1"))
        XCTAssertEqual(inbox.unread, 1, "an open thread is being read")
        XCTAssertTrue(inbox.apply(Self.decoded(Self.message(4, in: "c2", text: nil)), open: nil))
        XCTAssertNil(inbox.threads["c2"]?.last?.text)
        inbox.read("c2", by: "u1", upTo: 4)
        XCTAssertEqual(inbox.unread, 0)
        XCTAssertFalse(inbox.apply(Self.decoded(Self.message(1, in: "c9")), open: nil), "an unknown conversation: load the list again")
    }

    func testASocketEventDecodesItsData() {
        let event = TogetherSocket.Event(id: "1", type: "message.created", json: try! JSONSerialization.data(withJSONObject: Self.message(2)))
        let message: TogetherMessage? = event.decode()
        XCTAssertEqual(message?.seq, 2)
        XCTAssertEqual(event.data["conversationId"], "c1")
    }
}

final class TogetherPartyTests: TogetherSignedInCase {
    static func member(_ id: String, _ name: String) -> [String: Any] { ["userId": id, "handle": name.lowercased(), "displayName": name, "avatar": NSNull()] }

    static func party(members: [[String: Any]] = [member("u1", "Utku")], invited: [[String: Any]] = [], call: Any = NSNull(), privacy: String = "invite") -> [String: Any] {
        ["id": "p1", "leaderId": "u1", "privacy": privacy, "members": members.map { $0.merging(["joinedAt": "2026-10-24T10:00:00.000Z"]) { a, _ in a } },
         "invited": invited, "call": call, "createdAt": "2026-10-24T10:00:00.000Z"]
    }

    func testThePartyIAmInAndMyInvites() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["party": Self.party(members: [Self.member("u1", "Utku"), Self.member("f1", "Ayşe")], call: ["id": "call1", "in": ["f1"]]),
                   "invites": [["partyId": "p2", "from": Self.member("f2", "Kral"), "size": 3, "invitedAt": "2026-10-24T10:00:00.000Z"]]])
        }
        let mine = try await client.myParty()
        XCTAssertEqual(last(), "GET /api/v1/me/party")
        XCTAssertEqual(mine.party?.members.map(\.displayName), ["Utku", "Ayşe"])
        XCTAssertEqual(mine.party?.call?.in, ["f1"])
        XCTAssertEqual(mine.party?.isLeader("u1"), true)
        XCTAssertEqual(mine.invites.first?.from?.displayName, "Kral")
        XCTAssertEqual(mine.invites.first?.size, 3)
        FakeTogether.handler = { _, _ in (200, ["party": NSNull(), "invites": []]) }
        let none = try await client.myParty()
        XCTAssertNil(none.party)
    }

    func testStartingInvitingJoiningAndLeaving() async throws {
        FakeTogether.handler = { _, _ in (201, Self.party(privacy: "friends")) }
        let party = try await client.startParty(open: true)
        XCTAssertEqual(last(), "POST /api/v1/parties")
        XCTAssertEqual(body()?["privacy"] as? String, "friends")
        XCTAssertTrue(party.open)
        FakeTogether.handler = { _, _ in (200, Self.party(invited: [Self.member("f1", "Ayşe")])) }
        let invited = try await client.invite(["f1"], to: "p1")
        XCTAssertEqual(last(), "POST /api/v1/parties/p1/invites")
        XCTAssertEqual(body()?["userIds"] as? [String], ["f1"])
        XCTAssertEqual(invited.invited.map(\.userId), ["f1"])
        _ = try await client.joinParty("p2")
        XCTAssertEqual(last(), "POST /api/v1/parties/p2/join")
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.leaveParty("p1")
        XCTAssertEqual(last(), "POST /api/v1/parties/p1/leave")
        try await client.declineParty("p2")
        XCTAssertEqual(last(), "POST /api/v1/parties/p2/decline")
        FakeTogether.handler = { _, _ in (200, Self.party(privacy: "invite")) }
        _ = try await client.setParty("p1", open: false)
        XCTAssertEqual(last(), "PATCH /api/v1/parties/p1")
        XCTAssertEqual(body()?["privacy"] as? String, "invite")
    }

    /// A friend's presence carries their party and the game they host.
    func testPresenceWithAPartyAndAGame() throws {
        let json: [String: Any] = ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull(),
                                   "presence": ["state": "in_game", "titleId": "PPSA01234", "since": "2026-10-24T10:00:00.000Z",
                                                "party": ["id": "p9", "size": 2, "max": 8, "open": true],
                                                "game": ["sessionId": "s1", "titleId": "PPSA01234", "joinable": true, "players": 1, "capacity": 4]]]
        let friend = try JSONDecoder.together.decode(TogetherFriend.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(friend.presence?.party, .init(id: "p9", size: 2, max: 8, open: true))
        XCTAssertEqual(friend.presence?.game?.joinable, true)
        XCTAssertEqual(friend.presence?.game?.sessionId, "s1")
    }
}

final class TogetherServerTests: XCTestCase {
    /// Another AnyTogether (it is self-hostable): https, or http only on this Mac.
    func testAServerAddressIsChecked() {
        XCTAssertEqual(TogetherServer.address(" https://together.example.org/ ")?.absoluteString, "https://together.example.org")
        XCTAssertEqual(TogetherServer.address("https://example.org:8443/anytogether")?.absoluteString, "https://example.org:8443/anytogether")
        XCTAssertEqual(TogetherServer.address("http://localhost:3000")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(TogetherServer.address("http://127.0.0.1:3000")?.absoluteString, "http://127.0.0.1:3000")
        XCTAssertEqual(TogetherServer.address("http://[::1]:3000")?.absoluteString, "http://[::1]:3000")
        XCTAssertNil(TogetherServer.address("http://together.example.org"), "plain http only on this Mac")
        XCTAssertNil(TogetherServer.address("together.example.org"), "a scheme is needed")
        XCTAssertNil(TogetherServer.address("ftp://example.org"))
        XCTAssertNil(TogetherServer.address("https://"))
        XCTAssertNil(TogetherServer.address("https://example.org/?q=1"))
        XCTAssertNil(TogetherServer.address("https://user:pass@example.org"))
    }

    func testTheEnvironmentWinsThenTheChoiceThenTheDefault() {
        XCTAssertEqual(TogetherServer.base(environment: ["ANYTOGETHER_URL": "http://localhost:4000"], chosen: "https://mine.example.org"), URL(string: "http://localhost:4000"))
        XCTAssertEqual(TogetherServer.base(environment: [:], chosen: "https://mine.example.org"), URL(string: "https://mine.example.org"))
        XCTAssertEqual(TogetherServer.base(environment: [:], chosen: nil), TogetherServer.standard)
        XCTAssertEqual(TogetherServer.base(environment: [:], chosen: "not a url"), TogetherServer.standard)
    }
}

final class TogetherGameSessionTests: TogetherSignedInCase {
    static func session(players: [[String: Any]] = [TogetherPartyTests.member("u1", "Utku")], joinable: Bool = true) -> [String: Any] {
        ["id": "s1", "host": TogetherPartyTests.member("u1", "Utku"), "titleId": "PPSA01234", "gameVersion": "01.000.002", "engineBuild": "0.2.13-a1b2c3d4e5f6",
         "capacity": 4, "joinable": joinable, "players": players, "properties": ["mode": "coop", "slots": [1, 2]], "createdAt": "2026-10-24T10:00:00.000Z", "endedAt": NSNull()]
    }

    func testOpeningASessionForTheGamePlaying() async throws {
        FakeTogether.handler = { _, _ in (201, Self.session()) }
        let session = try await client.openGameSession(titleId: "PPSA01234", gameVersion: "01.000.002", engineBuild: "0.2.13-a1b2c3d4e5f6", capacity: 4)
        XCTAssertEqual(last(), "POST /api/v1/game-sessions")
        XCTAssertEqual(body()?["titleId"] as? String, "PPSA01234")
        XCTAssertEqual(body()?["capacity"] as? Int, 4)
        XCTAssertEqual(body()?["joinable"] as? Bool, true)
        XCTAssertEqual(session.properties["mode"], .string("coop"))
        XCTAssertEqual(session.properties["slots"], .array([.number(1), .number(2)]))
        FakeTogether.handler = { _, _ in (200, Self.session(joinable: false)) }
        _ = try await client.updateGameSession("s1", joinable: false)
        XCTAssertEqual(last(), "PATCH /api/v1/game-sessions/s1")
        XCTAssertEqual(body() as? [String: Bool], ["joinable": false])
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.endGameSession("s1")
        XCTAssertEqual(last(), "DELETE /api/v1/game-sessions/s1")
        try await client.leaveGameSession("s1")
        XCTAssertEqual(last(), "POST /api/v1/game-sessions/s1/leave")
    }

    func testJoiningSendsTheVersionsAndAMismatchIsRefused() async throws {
        FakeTogether.handler = { _, _ in (200, Self.session(players: [TogetherPartyTests.member("u1", "Utku"), TogetherPartyTests.member("f1", "Ayse")])) }
        let joined = try await client.joinGameSession("s1", gameVersion: "01.000.002", engineBuild: "0.2.13-a1b2c3d4e5f6")
        XCTAssertEqual(last(), "POST /api/v1/game-sessions/s1/join")
        XCTAssertEqual(body() as? [String: String], ["gameVersion": "01.000.002", "engineBuild": "0.2.13-a1b2c3d4e5f6"])
        XCTAssertEqual(joined.players.count, 2)
        FakeTogether.handler = { _, _ in (409, ["code": "version_mismatch", "status": 409, "title": "This game needs version 01.000.002 on engine build 0.2.13-a1b2c3d4e5f6"]) }
        do {
            _ = try await client.joinGameSession("s1", gameVersion: "01.000.001", engineBuild: "0.2.13-a1b2c3d4e5f6")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "version_mismatch")
        }
    }

    func testMySessionAndInvites() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["session": NSNull(), "invites": [["sessionId": "s9", "from": TogetherPartyTests.member("f1", "Ayse"), "titleId": "PPSA01234", "gameVersion": "1.02",
                                                      "engineBuild": "0.2.13-x", "invitedAt": "2026-10-24T10:00:00.000Z"]]])
        }
        let mine = try await client.myGameSession()
        XCTAssertNil(mine.session)
        XCTAssertEqual(mine.invites.first?.from?.displayName, "Ayse")
        XCTAssertEqual(mine.invites.first?.gameVersion, "1.02")
        FakeTogether.handler = { _, _ in (200, ["invited": ["f1"]]) }
        try await client.inviteToGame(["f1"], session: "s1")
        XCTAssertEqual(last(), "POST /api/v1/game-sessions/s1/invites")
        XCTAssertEqual(body()?["userIds"] as? [String], ["f1"])
    }

    /// The same game version and engine build, or a clear reason why not, before asking.
    func testTheVersionGuard() throws {
        let session = try JSONDecoder.together.decode(TogetherGameSession.self, from: JSONSerialization.data(withJSONObject: Self.session()))
        XCTAssertEqual(session.mismatch(gameVersion: "01.000.002", engineBuild: "0.2.13-a1b2c3d4e5f6"), nil)
        XCTAssertEqual(session.mismatch(gameVersion: "01.000.001", engineBuild: "0.2.13-a1b2c3d4e5f6"), .gameVersion)
        XCTAssertEqual(session.mismatch(gameVersion: "01.000.002", engineBuild: "0.2.12-ffffffffffff"), .engineBuild)
        XCTAssertEqual(TogetherGameSession.engineBuild("0.2.13 dev/build+7"), "0.2.13-dev-build+7")
        XCTAssertEqual(TogetherGameSession.engineBuild(String(repeating: "a", count: 80)).count, 64)
        XCTAssertEqual(TogetherGameSession.engineBuild(""), "unknown")
    }

    /// What the engine's online bridge reads: the session, who the user is in it, and their role.
    func testTheSessionFileForTheEngine() throws {
        let session = try JSONDecoder.together.decode(TogetherGameSession.self, from: JSONSerialization.data(withJSONObject: Self.session()))
        let file = folder.appendingPathComponent("game-session.json")
        try TogetherGameSession.write(session, me: "u1", to: file)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        XCTAssertEqual(json?["role"] as? String, "host")
        XCTAssertEqual(json?["userId"] as? String, "u1")
        let written = json?["session"] as? [String: Any]
        XCTAssertEqual(written?["id"] as? String, "s1")
        XCTAssertEqual(written?["engineBuild"] as? String, "0.2.13-a1b2c3d4e5f6")
        XCTAssertEqual((written?["properties"] as? [String: Any])?["mode"] as? String, "coop")
        try TogetherGameSession.write(session, me: "f1", to: file)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])?["role"] as? String, "guest")
        try TogetherGameSession.write(nil, me: "u1", to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
