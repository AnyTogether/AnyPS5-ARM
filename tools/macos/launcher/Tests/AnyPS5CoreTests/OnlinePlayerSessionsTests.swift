import XCTest
@testable import AnyPS5Core

/// The `sessionManager` group answered by the launcher, driven the way Human Fall Flat (PPSA02429)
/// hosts: the checks it makes as it starts, a push context, a Player Session made with it, news
/// of another player pushed to that context, leaving it and a stale session.
final class OnlinePlayerSessionsTests: XCTestCase {
    let me = TogetherUser(id: "0190a0b1-0000-7000-8000-00000000000a", handle: "alice", displayName: "Alice", avatar: nil)
    let context = "6f1c2b9a-4d3e-4f5a-8b6c-7d8e9fa0b1c2"

    func body(_ reply: OnlineWire.WebReply?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(reply).body) as? [String: Any])
    }

    func request(_ method: String, _ path: String, _ json: String = "") -> OnlineWire.WebRequest {
        OnlineWire.WebRequest(userId: 0x1000_0000, apiGroup: "sessionManager", path: path, method: method,
                              headers: [.init("Content-Type", "application/json; charset=utf-8")], body: Data(json.utf8))
    }

    func testAGameHostsAPlayerSessionGetsNewsAndLeaves() throws {
        let together = FakeOnlineTogether()
        let play = OnlinePlay(service: together, user: me, game: .init(titleId: "PPSA02429", gameVersion: "01.017", engineBuild: "x"),
                              transport: { _ in OnlineNoTransport() })
        _ = try play.start()
        defer { play.stop() }
        let engine = try XCTUnwrap(FakeEngine(port: play.bridge.port, secret: play.bridge.secret))
        let mine = String(OnlineIdentity.accountId(forUser: me.id))

        // What the game asks as soon as it starts is answered from the first request on.
        let restriction = engine.web(.init(userId: 0x1000_0000, apiGroup: "communicationRestrictionStatus",
                                           path: "/v3/users/\(mine)/communication/restriction/status", method: "GET"))
        XCTAssertEqual(restriction?.status, 200)
        XCTAssertEqual(try body(restriction)["restricted"] as? Bool, false)
        let blocks = engine.web(.init(userId: 0x1000_0000, apiGroup: "userProfile", path: "/v1/users/me/blocks?offset=0&limit=0", method: "GET"))
        XCTAssertEqual(blocks?.status, 200)

        let created = engine.web(request("POST", "/v1/playerSessions", """
        {"playerSessions":[{"maxPlayers":8,"maxSpectators":0,"joinDisabled":false,"supportedPlatforms":["PS5"],
        "localizedSessionName":{"defaultLanguage":"en-US","localizedText":{"en-US":"Human Fall Flat"}},"joinableUserType":"ANYONE",
        "invitableUserType":"MEMBER","leaderPrivileges":["KICK"],"swapSupported":false,"customData1":"cm9vbQ==",
        "member":{"players":[{"accountId":"me","platform":"me","pushContexts":[{"pushContextId":"\(context)"}]}]}}]}
        """))
        XCTAssertEqual(created?.status, 200, "Host gets its Player Session")
        XCTAssertEqual(created?.headers, [.init("Content-Type", "application/json")])
        let made = try XCTUnwrap((try body(created)["playerSessions"] as? [[String: Any]])?.first)
        let sessionId = try XCTUnwrap(made["sessionId"] as? String)
        XCTAssertNotNil(UUID(uuidString: sessionId), "the session ID is a UUID")
        let createdPlayers = (made["member"] as? [String: Any])?["players"] as? [[String: Any]]
        XCTAssertEqual(createdPlayers?.first?["accountId"] as? String, mine, "\"me\" is the signed-in player")
        XCTAssertEqual(createdPlayers?.first?["platform"] as? String, "PS5")

        let got = try body(engine.web(request("GET", "/v1/playerSessions/\(sessionId)?fields=@default")))
        let session = try XCTUnwrap((got["playerSessions"] as? [[String: Any]])?.first)
        XCTAssertEqual(session["sessionId"] as? String, sessionId)
        XCTAssertEqual(session["maxPlayers"] as? Int, 8)
        XCTAssertEqual(session["customData1"] as? String, "cm9vbQ==")
        XCTAssertEqual(session["joinableUserType"] as? String, "ANYONE")
        XCTAssertEqual((session["leader"] as? [String: Any])?["accountId"] as? String, mine)
        let players = try XCTUnwrap((session["member"] as? [String: Any])?["players"] as? [[String: Any]])
        XCTAssertEqual(players.map { $0["onlineId"] as? String }, ["alice"])
        XCTAssertNotNil(players.first?["joinTimestamp"] as? String)

        XCTAssertEqual(engine.web(request("PATCH", "/v1/playerSessions/\(sessionId)", #"{"joinableUserType":"FRIENDS","maxPlayers":4,"sessionId":"x"}"#))?.status, 204)
        let patched = try XCTUnwrap((try body(engine.web(request("GET", "/v1/playerSessions/\(sessionId)")))["playerSessions"] as? [[String: Any]])?.first)
        XCTAssertEqual(patched["joinableUserType"] as? String, "FRIENDS")
        XCTAssertEqual(patched["maxPlayers"] as? Int, 4)
        XCTAssertEqual(patched["sessionId"] as? String, sessionId, "PATCH only changes what a game may set")

        let listed = try body(engine.web(request("GET", "/v1/users/me/playerSessions")))
        XCTAssertEqual((listed["playerSessions"] as? [[String: Any]])?.map { $0["sessionId"] as? String }, [sessionId])
        XCTAssertEqual(engine.web(request("GET", "/v1/users/\(mine)/playerSessionsInvitations"))?.status, 200)

        XCTAssertEqual(engine.web(request("PUT", "/v1/playerSessions/\(sessionId)/leader", #"{"accountId":"\#(mine)","platform":"PS5"}"#))?.status, 204)
        XCTAssertEqual(engine.web(request("PUT", "/v1/playerSessions/\(sessionId)/leader", #"{"accountId":"123","platform":"PS5"}"#))?.status, 400,
                       "only a player can lead")
        let invited = try body(engine.web(request("POST", "/v1/playerSessions/\(sessionId)/invitations", #"{"invitations":[{"to":{"accountId":"123"}}]}"#)))
        XCTAssertEqual((invited["invitations"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(engine.web(request("POST", "/v1/playerSessions/\(sessionId)/joinableSpecifiedUsers", #"{"joinableSpecifiedUsers":[{"accountId":"123"}]}"#))?.status, 200)
        XCTAssertEqual(engine.web(request("DELETE", "/v1/playerSessions/\(sessionId)/joinableSpecifiedUsers?accountIds=123"))?.status, 204)
        XCTAssertEqual(engine.web(request("POST", "/v1/playerSessions/\(sessionId)/sessionMessage", #"{"payload":"hi"}"#))?.status, 204)

        // News of another player goes to the push context the game made the session with.
        let sessions = try XCTUnwrap(play.router.playerSessions)
        XCTAssertTrue(sessions.playerJoined(sessionId: sessionId, account: 77, onlineId: "bob"))
        let joined = try XCTUnwrap(engine.nextPushEvent())
        XCTAssertEqual(joined.service, "sessionManager")
        XCTAssertEqual(joined.pushContextId, context)
        XCTAssertEqual(joined.dataType, "psn:sessionManager:ps:m:players:created")
        XCTAssertEqual(joined.from, 77)
        XCTAssertEqual(joined.fromOnlineId, "bob")
        XCTAssertEqual(joined.to, OnlineIdentity.accountId(forUser: me.id))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: joined.data) as? [String: Any])?["playerSessionId"] as? String, sessionId)
        sessions.playerLeft(sessionId: sessionId, account: 77)
        XCTAssertEqual(engine.nextPushEvent()?.dataType, "psn:sessionManager:ps:m:players:deleted")
        XCTAssertFalse(sessions.playerJoined(sessionId: "missing", account: 77, onlineId: "bob"))

        // Leaving: a stale session from an earlier lobby is already left; the last player closes the session.
        XCTAssertEqual(engine.web(request("DELETE", "/v1/playerSessions/cb8a5af3-067c-4fbc-87c3-f96b20fb4f33/members/\(mine)"))?.status, 204)
        XCTAssertEqual(engine.web(request("DELETE", "/v1/playerSessions/\(sessionId)/members/\(mine)"))?.status, 204)
        XCTAssertEqual(engine.web(request("GET", "/v1/playerSessions/\(sessionId)"))?.status, 404)
        XCTAssertTrue(sessions.sessionIds.isEmpty)
        XCTAssertTrue(together.calls.isEmpty, "Player Sessions are kept here; nothing goes anywhere")
        XCTAssertTrue(play.router.notOffered.isEmpty)
    }

    func testJoiningMembersLeadersAndBadRequests() async throws {
        let pushed = PushRecorder()
        let sessions = OnlinePlayerSessions(account: 42, onlineId: "alice", push: { pushed.add($0) })
        let created = sessions.handle(request("POST", "/v1/playerSessions", #"{"playerSessions":[{"maxPlayers":2}]}"#))
        XCTAssertEqual(created.status, 200)
        let id = try XCTUnwrap(((try body(created)["playerSessions"] as? [[String: Any]])?.first)?["sessionId"] as? String)
        let leader = { () throws -> String? in
            let got = try self.body(sessions.handle(self.request("GET", "/v1/playerSessions/\(id)")))
            return (((got["playerSessions"] as? [[String: Any]])?.first)?["leader"] as? [String: Any])?["accountId"] as? String
        }
        XCTAssertEqual(try leader(), "42", "without members the creator plays and leads")

        let joined = sessions.handle(request("POST", "/v1/playerSessions/\(id)/member/players", #"{"players":[{"accountId":"77","platform":"PS5"}]}"#))
        XCTAssertEqual(joined.status, 200)
        XCTAssertEqual((try body(joined)["players"] as? [[String: Any]])?.first?["accountId"] as? String, "77")
        XCTAssertEqual(sessions.handle(request("POST", "/v1/playerSessions/\(id)/member/spectators", #"{"spectators":[{"accountId":88}]}"#)).status, 200)
        XCTAssertEqual(sessions.handle(request("DELETE", "/v1/playerSessions/\(id)/members/me")).status, 204)
        XCTAssertEqual(try leader(), "77", "the next player leads when the leader leaves")
        XCTAssertTrue(pushed.events.isEmpty, "a game's own changes push nothing")

        XCTAssertEqual(sessions.handle(request("POST", "/v1/playerSessions", "[1]")).status, 400)
        XCTAssertEqual(sessions.handle(request("POST", "/v1/playerSessions", "{}")).status, 400)
        XCTAssertEqual(sessions.handle(request("PATCH", "/v1/playerSessions/nope", "{}")).status, 404)
        XCTAssertEqual(sessions.handle(request("GET", "/v1/playerSessions")).status, 404)
        XCTAssertEqual(sessions.handle(request("GET", "/v1/users/123/playerSessions")).status, 403)
        XCTAssertEqual(sessions.handle(request("DELETE", "/v1/playerSessions/\(id)")).status, 204)
        XCTAssertEqual(sessions.handle(request("DELETE", "/v1/playerSessions/\(id)")).status, 404)

        let together = FakeOnlineTogether()
        let quiet = OnlineWebRouter(service: together, game: .init(titleId: "PPSA02429", gameVersion: "01.017", engineBuild: "x"),
                                    playerSessions: sessions, platformGroups: false)
        let off = await quiet.handle(request("POST", "/v1/playerSessions", #"{"playerSessions":[{}]}"#))
        XCTAssertEqual(off, .notOffered, "with platform groups off, Player Sessions are not offered either")
    }
}

final class PushRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [OnlineWire.PushEvent] = []
    var events: [OnlineWire.PushEvent] { lock.withLock { list } }
    func add(_ event: OnlineWire.PushEvent) { lock.withLock { list.append(event) } }
}
