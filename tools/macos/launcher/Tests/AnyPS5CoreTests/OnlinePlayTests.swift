import XCTest
@testable import AnyPS5Core

/// AnyTogether as the online pieces ask it: friends, game sessions and member publishing, with
/// every call written down.
final class FakeOnlineTogether: OnlineSessionService, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(method: String, path: String, body: String)] = []
    var friends: [[String: Any]]
    var session: [String: Any]?

    init(friends: [(id: String, handle: String, state: String)] = [], session: [String: Any]? = nil) {
        self.friends = friends.map { ["userId": $0.id, "handle": $0.handle, "displayName": $0.handle.capitalized, "avatar": NSNull(),
                                      "presence": ["state": $0.state, "titleId": NSNull(), "since": NSNull()]] }
        self.session = session
    }

    var calls: [(method: String, path: String, body: String)] { lock.withLock { log } }

    func call(_ method: String, _ path: String, _ body: Data?) async throws -> Data {
        lock.withLock { log.append((method, path, body.map { String(decoding: $0, as: UTF8.self) } ?? "")) }
        if path == "me/friends" { return try JSONSerialization.data(withJSONObject: ["friends": friends]) }
        if path.hasPrefix("game-sessions/"), let session { return try JSONSerialization.data(withJSONObject: session) }
        throw TogetherProblem(status: 404, code: "not_found", title: "Not found")
    }

    static func session(id: String, players: [String], devices: [String: String]) -> [String: Any] {
        ["id": id, "titleId": "PPSA00000", "gameVersion": "01.000", "engineBuild": "engine-test", "capacity": 4, "joinable": true,
         "players": players.map { ["userId": $0, "handle": $0, "displayName": $0, "avatar": NSNull()] },
         "members": players.map { ["userId": $0, "device": devices[$0].map { $0 as Any } ?? NSNull(), "properties": [:], "joinedAt": "2026-10-25T10:00:00Z", "updatedAt": NSNull()] },
         "properties": [:], "createdAt": "2026-10-25T10:00:00Z", "endedAt": NSNull()]
    }
}

/// A transport that only remembers what it was told.
final class RecordingTransport: OnlinePeerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [OnlinePeerSession?] = []
    private var signals: [OnlinePeerSignal] = []
    var updates: [OnlinePeerSession?] { lock.withLock { sessions } }
    var received: [OnlinePeerSignal] { lock.withLock { signals } }
    func update(_ session: OnlinePeerSession?) { lock.withLock { sessions.append(session) } }
    func send(_ datagram: OnlineWire.Datagram) -> Bool { false }
    func receive(_ signal: OnlinePeerSignal) { lock.withLock { signals.append(signal) } }
    func stop() {}
}

final class OnlinePlayTests: XCTestCase {
    let me = TogetherUser(id: "0190a0b1-0000-7000-8000-00000000000a", handle: "alice.the.great.player", displayName: "Alice", avatar: nil)

    func testIdentityIsTheSameEverywhereAndNeverMovesAnyone() {
        XCTAssertEqual(OnlineIdentity.accountId(forUser: "a-id"), OnlineIdentity.accountId(forUser: "a-id"))
        XCTAssertNotEqual(OnlineIdentity.accountId(forUser: "a-id"), OnlineIdentity.accountId(forUser: "b-id"))
        XCTAssertEqual(OnlineIdentity.accountId(forUser: "a-id"), 0xE222_F8A6_FD35_326F, "the first 8 bytes of SHA-256 of the user ID")
        XCTAssertEqual(OnlineIdentity.onlineId(handle: me.handle), "alice.the.great.", "cut to the platform's 16 letters")
        XCTAssertEqual(OnlineIdentity.onlineId(handle: ""), "player")

        let users = (0 ..< 16).map { "user-\($0)" }
        let all = OnlineIdentity.addresses(for: users)
        XCTAssertEqual(Set(all.values).count, 16, "everyone gets their own address")
        for address in all.values {
            XCTAssertTrue(OnlineWire.isVirtual(address))
            XCTAssertNotEqual(address & 0xFF, 0)
            XCTAssertNotEqual(address & 0xFF, 0xFF)
        }
        let fewer = OnlineIdentity.addresses(for: Array(users.dropFirst(3).reversed()))
        for (user, address) in fewer { XCTAssertEqual(all[user], address, "leaving or join order moves nobody") }
    }

    func testFriendsProfilesAndPresenceComeFromAnyTogether() async throws {
        let together = FakeOnlineTogether(friends: [("b-id", "bob", "online"), ("c-id", "carol", "offline"), ("d-id", "dave", "in_game")])
        let clock = OnlineClock()
        let profile = OnlineUserProfile(service: together, me: me, language: "en", now: { clock.now })
        let router = OnlineWebRouter(service: together, game: .init(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "x"), profile: profile)
        let mine = String(OnlineIdentity.accountId(forUser: me.id))
        let bob = String(OnlineIdentity.accountId(forUser: "b-id"))
        let carol = String(OnlineIdentity.accountId(forUser: "c-id"))

        // As Minecraft Dungeons II asks: the game's local user and an empty query.
        let friends = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/local_268435456/friends?", method: "GET"))
        XCTAssertEqual(friends.status, 200)
        XCTAssertEqual(friends.headers, [.init("Content-Type", "application/json")])
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: friends.body) as? [String: Any])
        XCTAssertEqual(list["friends"] as? [String], [bob, carol, String(OnlineIdentity.accountId(forUser: "d-id"))])
        XCTAssertEqual(list["totalItemCount"] as? Int, 3)
        XCTAssertNil(list["nextOffset"])

        let page = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/me/friends?offset=1&limit=1", method: "GET"))
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: page.body) as? [String: Any])
        XCTAssertEqual(second["friends"] as? [String], [carol])
        XCTAssertEqual(second["nextOffset"] as? Int, 2)
        XCTAssertEqual(second["previousOffset"] as? Int, 0)
        let byNumber = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/\(mine)/friends", method: "GET"))
        XCTAssertEqual(byNumber.status, 200, "our own account number is us too")
        XCTAssertEqual(together.calls.filter { $0.path == "me/friends" }.count, 1, "games poll; AnyTogether is asked at most every 30 s")
        clock.now = clock.now.addingTimeInterval(31)
        _ = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/me/friends", method: "GET"))
        XCTAssertEqual(together.calls.filter { $0.path == "me/friends" }.count, 2)

        let others = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/\(bob)/friends", method: "GET"))
        XCTAssertEqual(others.status, 403, "only our own friends")

        let bobProfile = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/\(bob)/profiles", method: "GET"))
        let shown = try XCTUnwrap(JSONSerialization.jsonObject(with: bobProfile.body) as? [String: Any])
        XCTAssertEqual(shown["onlineId"] as? String, "bob")
        XCTAssertEqual(shown["isMe"] as? Bool, false)
        let myProfile = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/me/profiles", method: "GET"))
        let own = try XCTUnwrap(JSONSerialization.jsonObject(with: myProfile.body) as? [String: Any])
        XCTAssertEqual(own["onlineId"] as? String, "alice.the.great.")
        XCTAssertEqual(own["isMe"] as? Bool, true)
        XCTAssertEqual(own["languages"] as? [String], ["en"])
        let stranger = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/12345/profiles", method: "GET"))
        XCTAssertEqual(stranger.status, 404, "someone who is not a friend is not shown")

        let presences = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/basicPresences?type=primary&accountIds=\(bob),\(carol),999", method: "GET"))
        let found = try XCTUnwrap((JSONSerialization.jsonObject(with: presences.body) as? [String: Any])?["basicPresences"] as? [[String: Any]])
        XCTAssertEqual(found.map { $0["accountId"] as? String }, [bob, carol])
        XCTAssertEqual(found.map { $0["availability"] as? String }, ["availableToPlay", "unavailable"])
        let single = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/\(carol)/basicPresences?type=primary", method: "GET"))
        let presence = try XCTUnwrap((JSONSerialization.jsonObject(with: single.body) as? [String: Any])?["basicPresence"] as? [String: Any])
        XCTAssertEqual((presence["primaryPlatformInfo"] as? [String: Any])?["onlineStatus"] as? String, "offline")

        let post = await router.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/me/friends", method: "POST"))
        XCTAssertEqual(post.status, 405)

        let quiet = OnlineWebRouter(service: together, game: .init(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "x"), profile: profile, platformGroups: false)
        let off = await quiet.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/me/friends", method: "GET"))
        XCTAssertEqual(off, .notOffered, "platform groups switched off are not offered")
        XCTAssertEqual(quiet.notOffered["userProfile GET /v1/users/me/friends"], 1)
        let signedOut = OnlineWebRouter(service: together, game: .init(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "x"))
        let nobody = await signedOut.handle(.init(userId: 1, apiGroup: "userProfile", path: "/v1/users/me/friends", method: "GET"))
        XCTAssertEqual(nobody, .notOffered, "signed out there are no friends to offer")
    }

    func testFollowingASessionPublishesTheLauncherAndHandsThePlayersToTheTransport() async throws {
        let sessionId = "0190a0b1-0000-7000-8000-000000000001"
        let together = FakeOnlineTogether(session: FakeOnlineTogether.session(id: sessionId, players: [me.id, "b-id", "c-id"], devices: [me.id: "dev-a", "b-id": "dev-b"]))
        let transport = RecordingTransport()
        let play = OnlinePlay(service: together, user: me, game: .init(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "x"), transport: { _ in transport })
        let environment = try play.start()
        defer { play.stop() }
        let port = try XCTUnwrap(environment["ANYPS5_ONLINE"]?.split(separator: ":").last.flatMap { UInt16($0) })
        let engine = try XCTUnwrap(FakeEngine(port: port, secret: play.bridge.secret))
        XCTAssertEqual(engine.account?.accountId, OnlineIdentity.accountId(forUser: me.id))

        await play.follow(sessionId: sessionId)
        let publish = try XCTUnwrap(together.calls.first)
        XCTAssertEqual(publish.method, "PUT")
        XCTAssertEqual(publish.path, "game-sessions/\(sessionId)/members/me", "the launcher publishes itself so the others' signals reach it")
        let addresses = OnlineIdentity.addresses(for: [me.id, "b-id", "c-id"])
        let session = try XCTUnwrap(transport.updates.last ?? nil)
        XCTAssertEqual(session.id, sessionId)
        XCTAssertEqual(session.me, me.id)
        XCTAssertEqual(session.addresses, addresses)
        XCTAssertEqual(session.devices, [me.id: "dev-a", "b-id": "dev-b"], "a player who has not published yet has no device")
        XCTAssertEqual(engine.nextAccount()?.address, addresses[me.id], "the game learns its own virtual address")

        play.receive(OnlinePeerSignal(from: "b-id", device: "dev-b", kind: "offer", json: Data("{}".utf8)), sessionId: "another")
        XCTAssertTrue(transport.received.isEmpty, "a signal for another session is dropped")
        let signal = OnlinePeerSignal(from: "b-id", device: "dev-b", kind: "offer", json: Data(#"{"type":"offer","sdp":"v=0"}"#.utf8))
        play.receive(signal, sessionId: sessionId)
        XCTAssertEqual(transport.received, [signal])

        await play.follow(sessionId: nil)
        XCTAssertNil(transport.updates.last ?? nil, "leaving the session tells the transport")
        XCTAssertEqual(engine.nextAccount()?.address, 0)
    }

    func testSocketSignalsAreReadAsTheGatewaySendsThem() throws {
        let event = Data(#"{"sessionId":"s1","from":"b-id","device":"dev-b","kind":"candidate","data":{"candidate":"candidate:1 1 udp 1 10.0.0.2 5000 typ host","sdpMid":"0","sdpMLineIndex":0}}"#.utf8)
        let signal = try XCTUnwrap(OnlinePeerSignal(event: event))
        XCTAssertEqual(signal.from, "b-id")
        XCTAssertEqual(signal.device, "dev-b")
        XCTAssertEqual(signal.kind, "candidate")
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: signal.json) as? [String: Any])
        XCTAssertEqual(data["sdpMid"] as? String, "0")
        XCTAssertNil(OnlinePeerSignal(event: Data(#"{"from":"b-id"}"#.utf8)))
    }

    func testEachTitleHasItsObservationLogAndABigOneIsKeptAside() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("online-logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = OnlinePlayHost.observationLog(titleId: "PPSA01234", folder: folder)
        XCTAssertEqual(file.lastPathComponent, "PPSA01234.jsonl")
        XCTAssertEqual(OnlinePlayHost.observationLog(titleId: "../x", folder: folder).lastPathComponent, "___x.jsonl", "a title ID never leaves the folder")
        try Data(count: 20 * 1024 * 1024 + 1).write(to: file)
        _ = OnlinePlayHost.observationLog(titleId: "PPSA01234", folder: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("1").path))

        let play = OnlinePlay(service: FakeOnlineTogether(), user: me, game: .init(titleId: "PPSA01234", gameVersion: "01.000", engineBuild: "x"), observationLog: file,
                              transport: { _ in OnlineNoTransport() })
        let environment = try play.start()
        defer { play.stop() }
        XCTAssertEqual(environment["ANYPS5_ONLINE_LOG"], file.path, "the engine writes the title's log itself, so a crash keeps the last line")
        XCTAssertEqual(environment["ANYPS5_ONLINE_SECRET"]?.count, 64)
    }
}

final class OnlineClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date {
        get { lock.withLock { time } }
        set { lock.withLock { time = newValue } }
    }
}
