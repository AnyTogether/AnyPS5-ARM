import Darwin
import XCTest
@testable import AnyPS5Core

/// The engine's side of the bridge, as libSceNetCtl speaks it, for driving the launcher's side.
final class FakeEngine {
    let socket: Int32
    private(set) var account: OnlineWire.Account?
    private var nextCall: UInt32 = 1

    init?(port: UInt16, secret: Data, protocolVersion: UInt16 = OnlineWire.protocolVersion, build: String = "engine-test", expectRefusal: Bool = false) {
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { return nil }
        let nonce = OnlineWire.randomBytes(16)
        write(OnlineWire.frame(.hello, OnlineWire.Hello(protocolVersion: protocolVersion, nonce: nonce, build: build, pid: 1).payload))
        guard let welcome = readFrame() else { return nil }
        lastRefusal = welcome.header.kind == OnlineWire.Kind.refuse.rawValue ? welcome.payload : nil
        guard welcome.header.kind == OnlineWire.Kind.welcome.rawValue else {
            if expectRefusal { return }
            return nil
        }
        var reader = OnlineWire.Reader(welcome.payload)
        _ = reader.u16()
        let launcherNonce = reader.raw(16)
        let proof = reader.raw(32)
        launcherProven = OnlineWire.sameProof(proof, OnlineWire.proof(secret: secret, side: .launcher, engineNonce: nonce, launcherNonce: launcherNonce))
        write(OnlineWire.frame(.proof, OnlineWire.proof(secret: secret, side: .engine, engineNonce: nonce, launcherNonce: launcherNonce)))
        guard let next = readFrame() else { return nil }
        if next.header.kind == OnlineWire.Kind.refuse.rawValue {
            lastRefusal = next.payload
            if expectRefusal { return }
            return nil
        }
        guard next.header.kind == OnlineWire.Kind.account.rawValue else { return nil }
        account = FakeEngine.decodeAccount(next.payload)
    }

    private(set) var lastRefusal: Data?
    private(set) var launcherProven = false

    deinit { close(socket) }

    static func decodeAccount(_ payload: Data) -> OnlineWire.Account {
        var reader = OnlineWire.Reader(payload)
        return OnlineWire.Account(signedIn: reader.u8() != 0, accountId: reader.u64(), onlineId: reader.str(), country: reader.str(),
                                  language: reader.str(), age: reader.u8(), address: reader.u32(), nat: reader.u8())
    }

    func web(_ request: OnlineWire.WebRequest) -> OnlineWire.WebReply? {
        let call = nextCall
        nextCall += 1
        write(OnlineWire.frame(.webRequest, call: call, request.payload))
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.account.rawValue {
                account = FakeEngine.decodeAccount(frame.payload)
                continue
            }
            if frame.header.kind == OnlineWire.Kind.webRequest.rawValue, frame.header.call == call, frame.header.flags & OnlineWire.flagReply != 0 {
                return OnlineWire.WebReply(frame.payload)
            }
        }
        return nil
    }

    func send(_ datagram: OnlineWire.Datagram) { write(OnlineWire.frame(.datagram, datagram.payload)) }

    func nextDatagram() -> OnlineWire.Datagram? {
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.account.rawValue {
                account = FakeEngine.decodeAccount(frame.payload)
                continue
            }
            if frame.header.kind == OnlineWire.Kind.datagram.rawValue { return OnlineWire.Datagram(frame.payload) }
        }
        return nil
    }

    func send(_ stream: OnlineWire.Stream) { write(stream.frame) }

    /// The next stream frame, taking account changes on the way.
    func nextStream() -> OnlineWire.Stream? {
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.account.rawValue {
                account = FakeEngine.decodeAccount(frame.payload)
                continue
            }
            if let kind = OnlineWire.Kind(rawValue: frame.header.kind), kind.isStream { return OnlineWire.Stream(kind: kind, frame.payload) }
        }
        return nil
    }

    func nextPushEvent() -> OnlineWire.PushEvent? {
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.pushEvent.rawValue { return OnlineWire.PushEvent(frame.payload) }
        }
        return nil
    }

    func nextAccount() -> OnlineWire.Account? {
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.account.rawValue {
                account = FakeEngine.decodeAccount(frame.payload)
                return account
            }
        }
        return nil
    }

    func write(_ data: Data) {
        _ = data.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) }
    }

    func readFrame() -> (header: OnlineWire.Header, payload: Data)? {
        guard let head = read(OnlineWire.headerSize), let header = OnlineWire.Header(head) else { return nil }
        guard header.length > 0 else { return (header, Data()) }
        guard let payload = read(Int(header.length)) else { return nil }
        return (header, payload)
    }

    private func read(_ count: Int) -> Data? {
        var data = Data(count: count)
        var done = 0
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            while done < count {
                let got = recv(socket, buffer.baseAddress! + done, count - done, 0)
                if got <= 0 { return false }
                done += got
            }
            return true
        }
        return ok ? data : nil
    }
}

/// AnyTogether's game sessions without a server: records calls and answers with a fixed session.
final class FakeSessions: OnlineSessionService, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(method: String, path: String, body: [String: Any]?)] = []
    var answer: Data
    var failure: TogetherProblem?

    init(players: [(String, String)], id: String = "0190a0b1-0000-7000-8000-000000000001") {
        let members: [Any] = players.map { ["userId": $0.0, "handle": $0.1, "displayName": $0.1, "avatar": NSNull()] as [String: Any] }
        let host: Any = members.first ?? NSNull()
        answer = try! JSONSerialization.data(withJSONObject: ["id": id, "host": host, "titleId": "PPSA00000", "gameVersion": "01.000", "engineBuild": "engine-test",
                                                               "capacity": 4, "joinable": true, "players": members, "properties": [:], "createdAt": "2026-10-24T10:00:00Z", "endedAt": NSNull()])
    }

    func call(_ method: String, _ path: String, _ body: Data?) async throws -> Data {
        let object = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        lock.withLock { calls.append((method, path, object)) }
        if let failure { throw failure }
        return answer
    }
}

final class OnlineBridgeTests: XCTestCase {
    let secret = Data((0 ..< 32).map { UInt8($0) })

    func testWireMatchesTheEngineByteForByte() {
        let header = OnlineWire.Header(length: 0x0002_0304, kind: 0x0201, flags: OnlineWire.flagReply, call: 0xA0B0_C0D0)
        XCTAssertEqual(OnlineWire.hex(header.bytes), "040302000102" + "0100" + "d0c0b0a0")
        XCTAssertEqual(OnlineWire.Header(header.bytes), header)
        XCTAssertNil(OnlineWire.Header(OnlineWire.Header(length: UInt32(OnlineWire.maxPayload + 1), kind: 1, flags: 0, call: 0).bytes))

        let writer = OnlineWire.Writer()
        writer.u8(1).u16(0x0203).u32(0x0405_0607).u64(0x0809_0A0B_0C0D_0E0F).str("hi").bytes(Data([9, 8])).pairs([("a", "b")])
        XCTAssertEqual(OnlineWire.hex(writer.data), "01030207060504" + "0f0e0d0c0b0a0908" + "02006869" + "020000000908" + "0100" + "010061" + "010062")

        let datagram = OnlineWire.Datagram(peer: 0xC612_0002, peerPort: 3658, peerVport: 1, localPort: 3658, localVport: 2, kind: .p2p, data: Data([1, 2, 3]))
        XCTAssertEqual(OnlineWire.hex(datagram.payload), "020012c6" + "4a0e" + "0100" + "4a0e" + "0200" + "02" + "03000000" + "010203")
        XCTAssertEqual(OnlineWire.Datagram(datagram.payload), datagram)
        var outside = datagram
        outside.peer = 0x0A00_0001
        XCTAssertNil(OnlineWire.Datagram(outside.payload))

        // The same bytes as the engine's test (online_bridge "push events").
        let push = OnlineWire.PushEvent(service: "sm", label: 1, pushContextId: "c", dataType: "t:x", data: Data("{}".utf8), extended: [.init("k", "v")], to: 2, from: 3, fromOnlineId: "b")
        XCTAssertEqual(OnlineWire.hex(push.payload), "0200736d" + "01000000" + "010063" + "0300743a78" + "020000007b7d" + "0100" + "01006b" + "010076"
                       + "0200000000000000" + "0300000000000000" + "010062")
        XCTAssertEqual(OnlineWire.PushEvent(push.payload), push)
        var untyped = push
        untyped.dataType = ""
        XCTAssertNil(OnlineWire.PushEvent(untyped.payload), "a push event needs a data type")
        var longKey = push
        longKey.extended = [.init(String(repeating: "k", count: 33), "v")]
        XCTAssertFalse(longKey.isValid, "extended data keys hold 32 letters")

        let engineNonce = Data((0x10 ..< 0x20).map { UInt8($0) })
        let launcherNonce = Data((0x20 ..< 0x30).map { UInt8($0) })
        XCTAssertEqual(OnlineWire.hex(OnlineWire.proof(secret: secret, side: .launcher, engineNonce: engineNonce, launcherNonce: launcherNonce)),
                       "2f21186674e36ff3b7a3c64d49553ec40d66baf6fb0700e734cc6f09e6af4ab1")
        XCTAssertEqual(OnlineWire.hex(OnlineWire.proof(secret: secret, side: .engine, engineNonce: engineNonce, launcherNonce: launcherNonce)),
                       "01c14bd9997ca8a60d1c14d1002ad65161b53ba7499fe653d2f73bc4b6641a4d")
        XCTAssertTrue(OnlineWire.isVirtual(0xC613_FFFF))
        XCTAssertFalse(OnlineWire.isVirtual(0xC614_0000))
    }

    func testHandshakeAccountWebAndObservations() throws {
        let observed = Expectations()
        let account = OnlineWire.Account(signedIn: true, accountId: 42, onlineId: "alice", country: "tr", language: "tr")
        let server = OnlineBridgeServer(secret: secret, account: account, handlers: .init(
            web: { request in
                OnlineWire.WebReply(status: 200, headers: [.init("X-Path", request.path)], body: request.body + Data(request.apiGroup.utf8))
            },
            observation: { observed.add($0) }))
        try server.start()
        defer { server.stop() }
        XCTAssertEqual(server.environment["ANYPS5_ONLINE"], "127.0.0.1:\(server.port)")
        XCTAssertEqual(server.environment["ANYPS5_ONLINE_SECRET"], OnlineWire.hex(secret))
        let engine = try XCTUnwrap(FakeEngine(port: server.port, secret: secret))
        XCTAssertTrue(engine.launcherProven, "the launcher proves the secret")
        XCTAssertEqual(engine.account, account, "the account is the first frame after the handshake")
        let reply = try XCTUnwrap(engine.web(OnlineWire.WebRequest(userId: 1, apiGroup: "g", path: "/p?x=1", method: "GET", body: Data("b".utf8))))
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.body, Data("bg".utf8))
        XCTAssertEqual(reply.headers, [.init("X-Path", "/p?x=1")])
        let writer = OnlineWire.Writer()
        writer.str("{\"fn\":\"sceNpGetState\"}")
        engine.write(OnlineWire.frame(.observation, writer.data))
        XCTAssertTrue(observed.wait(count: 1))
        XCTAssertEqual(observed.items.first, "{\"fn\":\"sceNpGetState\"}")
        XCTAssertEqual(eventually { server.engine?.build }, "engine-test")

        var changed = account
        changed.onlineId = "alice2"
        server.setAccount(changed)
        XCTAssertEqual(engine.nextAccount()?.onlineId, "alice2", "account changes are pushed")

        engine.write(OnlineWire.frame(.account, call: 77, Data()))
        let unsupported = engine.readFrame()
        XCTAssertEqual(unsupported?.header.call, 77)
        XCTAssertEqual(unsupported.map { $0.header.flags & OnlineWire.flagUnsupported != 0 }, true, "an unknown call is answered unsupported")
    }

    func testImpostorsAndOldEnginesAreRefused() throws {
        let server = OnlineBridgeServer(secret: secret)
        try server.start()
        defer { server.stop() }
        let wrong = try XCTUnwrap(FakeEngine(port: server.port, secret: Data(repeating: 7, count: 32), expectRefusal: true))
        XCTAssertFalse(wrong.launcherProven, "an engine with another secret sees the launcher cannot prove it")
        XCTAssertEqual(wrong.lastRefusal.map { var reader = OnlineWire.Reader($0); return reader.u16() }, OnlineWire.RefuseReason.badProof.rawValue)
        XCTAssertNil(server.engine)
        let old = try XCTUnwrap(FakeEngine(port: server.port, secret: secret, protocolVersion: 9, expectRefusal: true))
        XCTAssertEqual(old.lastRefusal.map { var reader = OnlineWire.Reader($0); return reader.u16() }, OnlineWire.RefuseReason.protocolVersion.rawValue)
    }

    func testRouterMapsTheAnyps5GroupOntoGameSessions() async throws {
        let sessions = FakeSessions(players: [("a-id", "alice"), ("b-id", "bob")])
        let changes = Expectations()
        let router = OnlineWebRouter(service: sessions, game: .init(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "unknown")) { view in
            changes.add(view?.id ?? "none")
        }
        router.setEngineBuild("engine-test")
        let opened = await router.handle(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions", method: "POST", body: Data("{\"capacity\":4,\"titleId\":\"OTHER\"}".utf8)))
        XCTAssertEqual(opened.status, 201)
        XCTAssertEqual(opened.headers, [.init("Content-Type", "application/json")])
        let open = try XCTUnwrap(sessions.calls.last)
        XCTAssertEqual(open.method, "POST")
        XCTAssertEqual(open.path, "game-sessions")
        XCTAssertEqual(open.body?["titleId"] as? String, "PPSA00000", "the title is the running game's, whatever the game says")
        XCTAssertEqual(open.body?["gameVersion"] as? String, "01.000")
        XCTAssertEqual(open.body?["engineBuild"] as? String, "engine-test")
        XCTAssertEqual(open.body?["capacity"] as? Int, 4)
        XCTAssertEqual(changes.items, ["0190a0b1-0000-7000-8000-000000000001"])

        let joined = await router.handle(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions/0190a0b1-0000-7000-8000-000000000001/join", method: "POST"))
        XCTAssertEqual(joined.status, 200)
        XCTAssertEqual(sessions.calls.last?.path, "game-sessions/0190a0b1-0000-7000-8000-000000000001/join")
        XCTAssertEqual(sessions.calls.last?.body?["engineBuild"] as? String, "engine-test")

        let invites = await router.handle(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions/0190a0b1-0000-7000-8000-000000000001/invites", method: "POST", body: Data("{\"userIds\":[\"b-id\"]}".utf8)))
        XCTAssertEqual(invites.status, 200)
        XCTAssertEqual(sessions.calls.last?.body?["userIds"] as? [String], ["b-id"])
        _ = await router.handle(.init(userId: 1, apiGroup: "anyps5", path: "/v1/me/session", method: "GET"))
        XCTAssertEqual(sessions.calls.last?.path, "me/game-session")

        let callsBefore = sessions.calls.count
        let escaped = await router.handle(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions/..%2Fadmin/join", method: "POST"))
        XCTAssertEqual(escaped.status, 404, "a session ID that is not one never reaches AnyTogether")
        XCTAssertEqual(sessions.calls.count, callsBefore)

        let platform = await router.handle(.init(userId: 1, apiGroup: "sessionManager", path: "/v1/playerSessions?fields=x", method: "POST", body: Data("{}".utf8)))
        XCTAssertEqual(platform, .notOffered, "platform groups are not offered until their formats are known")
        _ = await router.handle(.init(userId: 1, apiGroup: "sessionManager", path: "/v1/playerSessions", method: "POST"))
        XCTAssertEqual(router.notOffered["sessionManager POST /v1/playerSessions"], 2)
        XCTAssertEqual(sessions.calls.count, callsBefore, "nothing of a platform group goes anywhere")

        sessions.failure = TogetherProblem(status: 409, code: "version_mismatch", title: "This game needs version 1.02")
        let mismatch = await router.handle(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions/0190a0b1-0000-7000-8000-000000000001/join", method: "POST"))
        XCTAssertEqual(mismatch.status, 409)
        let problem = try XCTUnwrap(JSONSerialization.jsonObject(with: mismatch.body) as? [String: Any])
        XCTAssertEqual(problem["code"] as? String, "version_mismatch", "AnyTogether's refusal reaches the game as a problem")
    }

    func testPeerPacketsAreSealedToTheSession() {
        let key = OnlineWire.randomBytes(32)
        let alice = OnlinePeerLink(sessionKey: key, ownAddress: 0xC612_0001) { _ in }
        let bob = OnlinePeerLink(sessionKey: key, ownAddress: 0xC612_0002) { _ in }
        let aliceEndpoint = OnlinePeerLink.Endpoint(host: "127.0.0.1", port: 4000)
        bob.setPeer(0xC612_0001, at: aliceEndpoint)
        let datagram = OnlineWire.Datagram(peer: 0xC612_0002, peerPort: 3658, peerVport: 1, localPort: 3658, localVport: 2, kind: .p2p, data: Data("hi".utf8))
        let packet = alice.seal(source: 0xC612_0001, datagram: datagram)
        let opened = bob.open(packet, from: aliceEndpoint)
        XCTAssertEqual(opened, OnlineWire.Datagram(peer: 0xC612_0001, peerPort: 3658, peerVport: 2, localPort: 3658, localVport: 1, kind: .p2p, data: Data("hi".utf8)))
        var tampered = packet
        tampered[tampered.count - 20] ^= 1
        XCTAssertNil(bob.open(tampered, from: aliceEndpoint), "a changed packet is dropped")
        XCTAssertNil(bob.open(packet, from: .init(host: "127.0.0.1", port: 4001)), "a packet from another endpoint is dropped")
        let stranger = OnlinePeerLink(sessionKey: OnlineWire.randomBytes(32), ownAddress: 0xC612_0001) { _ in }
        XCTAssertNil(bob.open(stranger.seal(source: 0xC612_0001, datagram: datagram), from: aliceEndpoint), "a packet under another session's key is dropped")
        var elsewhere = datagram
        elsewhere.peer = 0xC612_0003
        XCTAssertNil(bob.open(alice.seal(source: 0xC612_0001, datagram: elsewhere), from: aliceEndpoint), "a packet for another player is dropped")
    }

    func testTwoLaunchersCarryGamePacketsBetweenTwoEngines() throws {
        let key = OnlineWire.randomBytes(32)
        let players = [("a-id", "alice"), ("b-id", "bob")]
        let addresses = OnlineIdentity.addresses(for: ["a-id", "b-id"])
        let (a, b) = (try XCTUnwrap(addresses["a-id"]), try XCTUnwrap(addresses["b-id"]))
        let game = OnlineWebRouter.Game(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "unknown")
        let alicePlay = OnlinePlay(service: FakeSessions(players: players), user: TogetherUser(id: "a-id", handle: "alice", displayName: "Alice", avatar: nil), game: game, sessionKey: key)
        let bobPlay = OnlinePlay(service: FakeSessions(players: players), user: TogetherUser(id: "b-id", handle: "bob", displayName: "Bob", avatar: nil), game: game, sessionKey: key)
        let aliceEnvironment = try alicePlay.start(peerHost: "127.0.0.1")
        let bobEnvironment = try bobPlay.start(peerHost: "127.0.0.1")
        defer {
            alicePlay.stop()
            bobPlay.stop()
        }
        XCTAssertNil(aliceEnvironment["ANYPS5_ONLINE_LOG"], "no observation log unless one was asked for")
        let alicePort = try XCTUnwrap(aliceEnvironment["ANYPS5_ONLINE"]?.split(separator: ":").last.flatMap { UInt16($0) })
        let bobPort = try XCTUnwrap(bobEnvironment["ANYPS5_ONLINE"]?.split(separator: ":").last.flatMap { UInt16($0) })
        let aliceEngine = try XCTUnwrap(FakeEngine(port: alicePort, secret: alicePlay.bridge.secret))
        let bobEngine = try XCTUnwrap(FakeEngine(port: bobPort, secret: bobPlay.bridge.secret))
        XCTAssertEqual(aliceEngine.account?.onlineId, "alice")
        XCTAssertEqual(aliceEngine.account?.address, 0, "no virtual address before a session")

        let opened = try XCTUnwrap(aliceEngine.web(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions", method: "POST", body: Data("{\"capacity\":2}".utf8))))
        XCTAssertEqual(opened.status, 201)
        let joined = try XCTUnwrap(bobEngine.web(.init(userId: 1, apiGroup: "anyps5", path: "/v1/sessions/0190a0b1-0000-7000-8000-000000000001/join", method: "POST")))
        XCTAssertEqual(joined.status, 200)
        XCTAssertEqual(aliceEngine.account?.address == a ? a : aliceEngine.nextAccount()?.address, a, "each player gets the address their user ID gives")
        XCTAssertEqual(bobEngine.account?.address == b ? b : bobEngine.nextAccount()?.address, b)

        let alicePeer = try XCTUnwrap(alicePlay.link), bobPeer = try XCTUnwrap(bobPlay.link)
        alicePlay.setEndpoint(of: "b-id", .init(host: "127.0.0.1", port: bobPeer.port))
        bobPlay.setEndpoint(of: "a-id", .init(host: "127.0.0.1", port: alicePeer.port))
        aliceEngine.send(.init(peer: b, peerPort: 3658, peerVport: 1, localPort: 3658, localVport: 1, kind: .p2p, data: Data("ping".utf8)))
        let atBob = try XCTUnwrap(bobEngine.nextDatagram())
        XCTAssertEqual(atBob, OnlineWire.Datagram(peer: a, peerPort: 3658, peerVport: 1, localPort: 3658, localVport: 1, kind: .p2p, data: Data("ping".utf8)),
                       "the packet reaches the other engine from the sender's virtual address")
        bobEngine.send(.init(peer: a, peerPort: 3658, peerVport: 1, localPort: 3658, localVport: 1, kind: .p2p, data: Data("pong".utf8)))
        let atAlice = try XCTUnwrap(aliceEngine.nextDatagram())
        XCTAssertEqual(atAlice.data, Data("pong".utf8))
        XCTAssertEqual(atAlice.peer, b)
        for index in 0 ..< 100 {
            aliceEngine.send(.init(peer: b, peerPort: 9000, peerVport: 0, localPort: 9001, localVport: 0, kind: .udp, data: Data([UInt8(index)])))
        }
        var received = 0
        while received < 100, let datagram = bobEngine.nextDatagram() {
            XCTAssertEqual(datagram.kind, .udp)
            received += 1
        }
        XCTAssertEqual(received, 100, "a burst of UDP packets crosses on loopback")
    }

    private func eventually<T: Equatable>(_ read: () -> T?, timeout: TimeInterval = 3) -> T? {
        let until = Date().addingTimeInterval(timeout)
        while Date() < until {
            if let value = read() { return value }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return read()
    }
}

/// Collects values from callbacks on other threads.
final class Expectations: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var items: [String] { lock.withLock { values } }
    func wait(count: Int, timeout: TimeInterval = 3) -> Bool {
        let until = Date().addingTimeInterval(timeout)
        while Date() < until {
            if items.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return items.count >= count
    }
}
