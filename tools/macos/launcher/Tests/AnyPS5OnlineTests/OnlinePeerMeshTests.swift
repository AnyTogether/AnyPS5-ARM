import AnyPS5Core
import Darwin
import XCTest
@testable import AnyPS5Online

/// The engine's side of the bridge, as much as these tests need: the handshake, the account and
/// datagrams.
final class MiniEngine {
    let socket: Int32
    private(set) var account: OnlineWire.Account?

    init?(environment: [String: String]) {
        guard let port = environment["ANYPS5_ONLINE"]?.split(separator: ":").last.flatMap({ UInt16($0) }),
              let hex = environment["ANYPS5_ONLINE_SECRET"] else { return nil }
        let secret = Data(stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! })
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        guard withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }) == 0 else { return nil }
        let nonce = OnlineWire.randomBytes(16)
        write(OnlineWire.frame(.hello, OnlineWire.Hello(protocolVersion: OnlineWire.protocolVersion, nonce: nonce, build: "mesh-test", pid: 1).payload))
        guard let welcome = readFrame(), welcome.header.kind == OnlineWire.Kind.welcome.rawValue else { return nil }
        var reader = OnlineWire.Reader(welcome.payload)
        _ = reader.u16()
        let launcherNonce = reader.raw(16)
        write(OnlineWire.frame(.proof, OnlineWire.proof(secret: secret, side: .engine, engineNonce: nonce, launcherNonce: launcherNonce)))
        guard let first = readFrame(), first.header.kind == OnlineWire.Kind.account.rawValue else { return nil }
        account = MiniEngine.account(first.payload)
    }

    deinit { close(socket) }

    static func account(_ payload: Data) -> OnlineWire.Account {
        var reader = OnlineWire.Reader(payload)
        return OnlineWire.Account(signedIn: reader.u8() != 0, accountId: reader.u64(), onlineId: reader.str(), country: reader.str(),
                                  language: reader.str(), age: reader.u8(), address: reader.u32(), nat: reader.u8())
    }

    func send(_ datagram: OnlineWire.Datagram) { write(OnlineWire.frame(.datagram, datagram.payload)) }

    /// The next datagram, taking account changes on the way.
    func nextDatagram() -> OnlineWire.Datagram? {
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.account.rawValue { account = MiniEngine.account(frame.payload) }
            if frame.header.kind == OnlineWire.Kind.datagram.rawValue { return OnlineWire.Datagram(frame.payload) }
        }
        return nil
    }

    func send(_ stream: OnlineWire.Stream) { write(stream.frame) }

    /// The next stream frame, skipping datagrams and taking account changes on the way.
    func nextStream() -> OnlineWire.Stream? {
        while let frame = readFrame() {
            if frame.header.kind == OnlineWire.Kind.account.rawValue { account = MiniEngine.account(frame.payload) }
            if let kind = OnlineWire.Kind(rawValue: frame.header.kind), kind.isStream { return OnlineWire.Stream(kind: kind, frame.payload) }
        }
        return nil
    }

    func addressSoon(_ wanted: UInt32) -> Bool {
        while account?.address != wanted {
            guard let frame = readFrame() else { return false }
            if frame.header.kind == OnlineWire.Kind.account.rawValue { account = MiniEngine.account(frame.payload) }
        }
        return true
    }

    private func write(_ data: Data) { _ = data.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, $0.count, 0) } }

    private func readFrame() -> (header: OnlineWire.Header, payload: Data)? {
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

/// AnyTogether for one game session: every player sees the same session with everyone's
/// device; the gateway hands each signal to the launcher it is for, as `game_session.signal`.
final class OneSession: OnlineSessionService, @unchecked Sendable {
    let id = "0190a0b1-0000-7000-8000-0000000000aa"
    private let lock = NSLock()
    private var players: [(userId: String, device: String)] = []
    private var plays: [String: OnlinePlay] = [:]
    private var log: [String] = []

    func add(_ userId: String, device: String) { lock.withLock { players.append((userId, device)) } }
    func attach(_ play: OnlinePlay, as userId: String) { lock.withLock { plays[userId] = play } }
    var signals: [String] { lock.withLock { log } }

    var json: Data {
        let players = lock.withLock { self.players }
        let object: [String: Any] = ["id": id, "titleId": "PPSA00000", "gameVersion": "01.000", "engineBuild": "mesh-test", "capacity": 4, "joinable": true,
                                     "players": players.map { ["userId": $0.userId, "handle": $0.userId, "displayName": $0.userId, "avatar": NSNull()] },
                                     "members": players.map { ["userId": $0.userId, "device": $0.device, "properties": ["online": 1], "joinedAt": "2026-10-25T10:00:00Z", "updatedAt": NSNull()] },
                                     "properties": [:], "createdAt": "2026-10-25T10:00:00Z", "endedAt": NSNull()]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func call(_ method: String, _ path: String, _ body: Data?) async throws -> Data {
        if path.hasSuffix("/ice-servers") { return Data(#"{"iceServers":[],"expiresAt":null}"#.utf8) }
        return json
    }

    /// The gateway: (to, device, session, kind, data) from `from`.
    func relay(from: String, fromDevice: String) -> @Sendable (String, String, String, String, Data) -> Void {
        { [weak self] to, device, session, kind, data in
            guard let self else { return }
            let play = self.lock.withLock { () -> OnlinePlay? in
                self.log.append("\(from)>\(to) \(kind)")
                guard self.players.contains(where: { $0.userId == to && $0.device == device }) else { return nil }
                return self.plays[to]
            }
            DispatchQueue.global().async { play?.receive(OnlinePeerSignal(from: from, device: fromDevice, kind: kind, json: data), sessionId: session) }
        }
    }
}

final class OnlinePeerMeshTests: XCTestCase {
    func waitUntil(_ seconds: Double = 20, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    func testTwoLaunchersCarryGamePacketsOverDataChannels() async throws {
        let together = OneSession()
        let users = ["0190a0b1-0000-7000-8000-00000000000a", "0190a0b1-0000-7000-8000-00000000000b"]
        let (alice, bob) = (users[0], users[1])
        together.add(alice, device: "dev-a")
        together.add(bob, device: "dev-b")
        let game = OnlineWebRouter.Game(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "mesh-test")
        var meshes: [String: OnlinePeerMesh] = [:]
        func play(_ userId: String, device: String) -> OnlinePlay {
            let made = OnlinePlay(service: together, user: TogetherUser(id: userId, handle: String(userId.suffix(1)), displayName: userId, avatar: nil), game: game,
                                  signal: together.relay(from: userId, fromDevice: device), transport: { context in
                                      let mesh = OnlinePeerMesh(context: context, iceServers: [])
                                      meshes[userId] = mesh
                                      return mesh
                                  })
            together.attach(made, as: userId)
            return made
        }
        let alicePlay = play(alice, device: "dev-a"), bobPlay = play(bob, device: "dev-b")
        let aliceEngine = try XCTUnwrap(MiniEngine(environment: try alicePlay.start()))
        let bobEngine = try XCTUnwrap(MiniEngine(environment: try bobPlay.start()))
        defer {
            alicePlay.stop()
            bobPlay.stop()
        }
        let addresses = OnlineIdentity.addresses(for: users)
        let (a, b) = (try XCTUnwrap(addresses[alice]), try XCTUnwrap(addresses[bob]))

        // Bob's launcher follows the session first; Alice's (who offers, her ID being smaller) later.
        await bobPlay.follow(sessionId: together.id)
        await alicePlay.follow(sessionId: together.id)
        XCTAssertTrue(aliceEngine.addressSoon(a) && bobEngine.addressSoon(b), "each game learns its own virtual address")
        let aliceMesh = try XCTUnwrap(meshes[alice]), bobMesh = try XCTUnwrap(meshes[bob])
        XCTAssertTrue(waitUntil { aliceMesh.states[bob] == .connected && bobMesh.states[alice] == .connected }, "the data channel connects: \(together.signals)")
        XCTAssertTrue(together.signals.contains("\(alice)>\(bob) offer"), "the smaller user ID offers")
        XCTAssertFalse(together.signals.contains("\(bob)>\(alice) offer"))
        // The party panel's line for Bob: reached straight (host candidates only here), with a round trip.
        let seen = Box<[OnlinePeerLinkInfo]>()
        XCTAssertTrue(waitUntil {
            aliceMesh.links { seen.value = $0 }
            return seen.value?.first?.route == .direct && seen.value?.first?.rttMs != nil
        }, "links: \(String(describing: seen.value))")
        XCTAssertEqual(seen.value?.first?.userId, bob)

        // The channel opens a moment after the connection.
        let ping = OnlineWire.Datagram(peer: b, peerPort: 3658, peerVport: 1, localPort: 3658, localVport: 2, kind: .p2p, data: Data("ping".utf8))
        XCTAssertTrue(waitUntil { aliceMesh.send(ping) })
        let atBob = try XCTUnwrap(bobEngine.nextDatagram())
        XCTAssertEqual(atBob, OnlineWire.Datagram(peer: a, peerPort: 3658, peerVport: 2, localPort: 3658, localVport: 1, kind: .p2p, data: Data("ping".utf8)),
                       "the packet reaches the other game from the sender's virtual address and ports")

        bobEngine.send(.init(peer: a, peerPort: 3658, peerVport: 2, localPort: 3658, localVport: 1, kind: .p2p, data: Data("pong".utf8)))
        let atAlice = try XCTUnwrap(aliceEngine.nextDatagram())
        XCTAssertEqual(atAlice.data, Data("pong".utf8))
        XCTAssertEqual(atAlice.peer, b)

        for index in 0 ..< 200 {
            aliceEngine.send(.init(peer: b, peerPort: 9000, peerVport: 0, localPort: 9001, localVport: 0, kind: .udp, data: Data(repeating: UInt8(index), count: 1200)))
        }
        var received = 0
        while received < 200, let datagram = bobEngine.nextDatagram() {
            XCTAssertEqual(datagram.data.count, 1200)
            received += 1
        }
        XCTAssertGreaterThan(received, 190, "a burst of game-sized packets crosses (unreliable, so a few may drop)")

        let stranger = OnlineWire.Datagram(peer: OnlineWire.virtualNetwork | 0x1234, peerPort: 1, peerVport: 0, localPort: 1, localVport: 0, kind: .udp, data: Data([1]))
        XCTAssertFalse(aliceMesh.send(stranger), "a packet for someone outside the session goes nowhere")

        // A game's broadcast (LAN-style discovery) reaches every other player, from the sender.
        for group: UInt32 in [0xFFFF_FFFF, OnlineWire.virtualBroadcast, 0xE000_00FB] {
            aliceEngine.send(.init(peer: group, peerPort: 3659, peerVport: 0, localPort: 3660, localVport: 0, kind: .udp, data: Data("who is there".utf8)))
            let heard = try XCTUnwrap(bobEngine.nextDatagram())
            XCTAssertEqual(heard, OnlineWire.Datagram(peer: a, peerPort: 3660, peerVport: 0, localPort: 3659, localVport: 0, kind: .udp, data: Data("who is there".utf8)),
                           "a datagram to \(String(group, radix: 16)) arrives at the other game from the sender's virtual address")
        }
        // The largest UDP datagram crosses; a bigger one is dropped and counted, never fatal.
        aliceEngine.send(.init(peer: b, peerPort: 9000, peerVport: 0, localPort: 9001, localVport: 0, kind: .udp, data: Data(repeating: 7, count: OnlineWire.maxGameDatagram)))
        XCTAssertEqual(try XCTUnwrap(bobEngine.nextDatagram()).data.count, OnlineWire.maxGameDatagram)
        let tooBig = OnlineWire.Datagram(peer: b, peerPort: 9000, peerVport: 0, localPort: 9001, localVport: 0, kind: .udp, data: Data(count: OnlineWire.maxGameDatagram + 1))
        XCTAssertFalse(aliceMesh.send(tooBig))
        XCTAssertEqual(aliceMesh.droppedTooLarge, 1)

        // Bob leaves: Alice's connection to him closes and the game's packets to him are dropped.
        await bobPlay.follow(sessionId: nil)
        XCTAssertTrue(waitUntil { aliceMesh.states[bob] == nil || aliceMesh.states[bob] == .closed }, "a goodbye closes the other side: \(together.signals)")
        XCTAssertFalse(aliceMesh.send(ping))
    }
}

extension OnlinePeerMeshTests {
    /// A game stream between two launchers over the reliable `stream` channel: open, accept, bytes
    /// both ways (more than one channel message), a half close, the end; then a refusal, and a
    /// player leaving breaks the streams with them.
    func testTwoLaunchersCarryAGameStream() async throws {
        let together = OneSession()
        let users = ["0190a0b1-0000-7000-8000-00000000000a", "0190a0b1-0000-7000-8000-00000000000b"]
        let (alice, bob) = (users[0], users[1])
        together.add(alice, device: "dev-a")
        together.add(bob, device: "dev-b")
        let game = OnlineWebRouter.Game(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "mesh-test")
        let meshes = Box<[String: OnlinePeerMesh]>()
        meshes.value = [:]
        func play(_ userId: String, device: String) -> OnlinePlay {
            let made = OnlinePlay(service: together, user: TogetherUser(id: userId, handle: String(userId.suffix(1)), displayName: userId, avatar: nil), game: game,
                                  signal: together.relay(from: userId, fromDevice: device), transport: { context in
                                      let mesh = OnlinePeerMesh(context: context, iceServers: [])
                                      meshes.value?[userId] = mesh
                                      return mesh
                                  })
            together.attach(made, as: userId)
            return made
        }
        let alicePlay = play(alice, device: "dev-a"), bobPlay = play(bob, device: "dev-b")
        let aliceEngine = try XCTUnwrap(MiniEngine(environment: try alicePlay.start()))
        let bobEngine = try XCTUnwrap(MiniEngine(environment: try bobPlay.start()))
        defer {
            alicePlay.stop()
            bobPlay.stop()
        }
        let addresses = OnlineIdentity.addresses(for: users)
        let (a, b) = (try XCTUnwrap(addresses[alice]), try XCTUnwrap(addresses[bob]))
        await bobPlay.follow(sessionId: together.id)
        await alicePlay.follow(sessionId: together.id)
        XCTAssertTrue(aliceEngine.addressSoon(a) && bobEngine.addressSoon(b))
        let aliceMesh = try XCTUnwrap(meshes.value?[alice]), bobMesh = try XCTUnwrap(meshes.value?[bob])
        // Bob followed later and asked for a fresh offer, which replaces the first connection:
        // open the stream once the connection has settled.
        XCTAssertTrue(waitUntil { aliceMesh.canStream(to: b) && bobMesh.canStream(to: a) }, "the stream channel opens: \(together.signals)")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(waitUntil { aliceMesh.canStream(to: b) && bobMesh.canStream(to: a) })
        let stream: UInt32 = 1
        aliceEngine.send(.open(stream: stream, peer: b, peerPort: 3659, peerVport: 1, localPort: 3660, localVport: 5))
        let opened = bobEngine.nextStream()
        guard case .open(let id, let peer, let peerPort, let peerVport, let localPort, let localVport)? = opened else { return XCTFail("\(String(describing: opened))") }
        XCTAssertTrue(id & OnlineWire.launcherStream != 0)
        XCTAssertEqual([peer, UInt32(peerPort), UInt32(peerVport), UInt32(localPort), UInt32(localVport)], [a, 3660, 5, 3659, 1],
                       "the other game is asked for its port 3659/1 by Alice's address and port")
        bobEngine.send(.accept(stream: id))
        XCTAssertEqual(aliceEngine.nextStream(), .accept(stream: stream))

        let big = Data((0 ..< 60000).map { UInt8(truncatingIfNeeded: $0 * 13) })
        aliceEngine.send(.data(stream: stream, big))
        var received = Data()
        while received.count < big.count, case .data(id, let data)? = bobEngine.nextStream() { received.append(data) }
        XCTAssertEqual(received, big, "the bytes arrive whole and in order")
        bobEngine.send(.data(stream: id, Data("pong".utf8)))
        XCTAssertEqual(aliceEngine.nextStream(), .data(stream: stream, Data("pong".utf8)))
        aliceEngine.send(.close(stream: stream, .closed))
        XCTAssertEqual(bobEngine.nextStream(), .close(stream: id, .closed))
        bobEngine.send(.data(stream: id, Data("late".utf8)))
        XCTAssertEqual(aliceEngine.nextStream(), .data(stream: stream, Data("late".utf8)), "a half-closed stream still carries the other way")
        bobEngine.send(.close(stream: id, .closed))
        XCTAssertEqual(aliceEngine.nextStream(), .close(stream: stream, .closed))

        aliceEngine.send(.open(stream: 100, peer: b, peerPort: 4000, peerVport: 1, localPort: 0, localVport: 0))
        guard case .open(let refusedId, _, _, _, _, _)? = bobEngine.nextStream() else { return XCTFail() }
        bobEngine.send(.close(stream: refusedId, .refused))
        XCTAssertEqual(aliceEngine.nextStream(), .close(stream: 100, .refused), "a refusal reaches the opener")

        aliceEngine.send(.open(stream: 101, peer: b, peerPort: 3659, peerVport: 1, localPort: 0, localVport: 0))
        guard case .open(let lastId, _, _, _, _, _)? = bobEngine.nextStream() else { return XCTFail() }
        bobEngine.send(.accept(stream: lastId))
        XCTAssertEqual(aliceEngine.nextStream(), .accept(stream: 101))
        await bobPlay.follow(sessionId: nil)
        XCTAssertEqual(aliceEngine.nextStream(), .close(stream: 101, .reset), "a player who leaves breaks the streams with them")
    }
}

/// Phase 1 end to end: two real engines (the engine's `online_probe` stand-in game, each in its
/// own process with its own bridge) behind two launchers, a datagram P2P socket on each side,
/// packets over WebRTC data channels. Skipped when the probe is not built (ANYPS5_ONLINE_PROBE, or
/// `ninja -C build-mac online_probe`).
final class OnlineEngineP2pTests: XCTestCase {
    static var probe: URL? {
        if let path = ProcessInfo.processInfo.environment["ANYPS5_ONLINE_PROBE"], !path.isEmpty { return URL(fileURLWithPath: path) }
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { folder.deleteLastPathComponent() }
        let built = folder.appendingPathComponent("build-mac/tests/online_probe")
        return FileManager.default.isExecutableFile(atPath: built.path) ? built : nil
    }

    func waitUntil(_ seconds: Double = 20, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    static func dotted(_ address: UInt32) -> String { "\(address >> 24).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)" }

    func start(_ probe: URL, environment: [String: String], arguments: [String]) throws -> (Process, Pipe) {
        let process = Process()
        process.executableURL = probe
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ANYPS5_") }.merging(environment) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        return (process, output)
    }

    func finish(_ started: (Process, Pipe)) -> [String: String] {
        let (process, output) = started
        let deadline = Date().addingTimeInterval(40)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }

    func testTwoGamesPlayPeerToPeerThroughTwoLaunchers() async throws {
        guard let probe = OnlineEngineP2pTests.probe else { throw XCTSkip("online_probe is not built") }
        let together = OneSession()
        let users = ["0190a0b1-0000-7000-8000-00000000000a", "0190a0b1-0000-7000-8000-00000000000b"]
        together.add(users[0], device: "dev-a")
        together.add(users[1], device: "dev-b")
        let game = OnlineWebRouter.Game(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "mesh-test")
        let plays = users.enumerated().map { index, userId in
            let device = index == 0 ? "dev-a" : "dev-b"
            let play = OnlinePlay(service: together, user: TogetherUser(id: userId, handle: index == 0 ? "alice" : "bob", displayName: userId, avatar: nil), game: game,
                                  signal: together.relay(from: userId, fromDevice: device), transport: { OnlinePeerMesh(context: $0, iceServers: []) })
            together.attach(play, as: userId)
            return play
        }
        let environments = try plays.map { try $0.start() }
        defer { plays.forEach { $0.stop() } }
        for play in plays { await play.follow(sessionId: together.id) }
        let addresses = OnlineIdentity.addresses(for: users)
        let (a, b) = (try XCTUnwrap(addresses[users[0]]), try XCTUnwrap(addresses[users[1]]))

        let pong = try start(probe, environment: environments[1], arguments: ["p2p", OnlineEngineP2pTests.dotted(a), "pong"])
        let ping = try start(probe, environment: environments[0], arguments: ["p2p", OnlineEngineP2pTests.dotted(b), "ping"])
        let pinged = finish(ping)
        let ponged = finish(pong)
        XCTAssertEqual(pinged["got"], "pong", "\(pinged) \(together.signals)")
        XCTAssertEqual(pinged["from"], "\(OnlineEngineP2pTests.dotted(b)):3658/1", "the answer comes from the other game's virtual address, port and virtual port")
        XCTAssertEqual(ponged["got"], "ping", "\(ponged)")
        XCTAssertEqual(ponged["from"], "\(OnlineEngineP2pTests.dotted(a)):3658/1")
    }

    /// Stream P2P end to end: one game listens on 3658/1, the other connects through both
    /// launchers and the `stream` channel, writes 300 KB and reads it back.
    func testTwoGamesStreamThroughTwoLaunchers() async throws {
        guard let probe = OnlineEngineP2pTests.probe else { throw XCTSkip("online_probe is not built") }
        let together = OneSession()
        let users = ["0190a0b1-0000-7000-8000-00000000000a", "0190a0b1-0000-7000-8000-00000000000b"]
        together.add(users[0], device: "dev-a")
        together.add(users[1], device: "dev-b")
        let game = OnlineWebRouter.Game(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "mesh-test")
        let meshes = Box<[String: OnlinePeerMesh]>()
        meshes.value = [:]
        let plays = users.enumerated().map { index, userId in
            let device = index == 0 ? "dev-a" : "dev-b"
            let play = OnlinePlay(service: together, user: TogetherUser(id: userId, handle: index == 0 ? "alice" : "bob", displayName: userId, avatar: nil), game: game,
                                  signal: together.relay(from: userId, fromDevice: device), transport: { context in
                                      let mesh = OnlinePeerMesh(context: context, iceServers: [])
                                      meshes.value?[userId] = mesh
                                      return mesh
                                  })
            together.attach(play, as: userId)
            return play
        }
        let environments = try plays.map { try $0.start() }
        defer { plays.forEach { $0.stop() } }
        for play in plays { await play.follow(sessionId: together.id) }
        let addresses = OnlineIdentity.addresses(for: users)
        let (a, b) = (try XCTUnwrap(addresses[users[0]]), try XCTUnwrap(addresses[users[1]]))
        // Bob followed later, so he asked for a fresh offer, which replaces the first connection
        // (and would break a stream opened on it): start once the connection has settled.
        let aliceMesh = try XCTUnwrap(meshes.value?[users[0]]), bobMesh = try XCTUnwrap(meshes.value?[users[1]])
        let settled = { aliceMesh.canStream(to: b) && bobMesh.canStream(to: a) }
        XCTAssertTrue(waitUntil { settled() }, "the stream channel opens: \(together.signals)")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(waitUntil { settled() })

        let pong = try start(probe, environment: environments[1], arguments: ["stream", OnlineEngineP2pTests.dotted(a), "pong", "300000"])
        let ping = try start(probe, environment: environments[0], arguments: ["stream", OnlineEngineP2pTests.dotted(b), "ping", "300000"])
        let pinged = finish(ping)
        let ponged = finish(pong)
        XCTAssertEqual(pinged["peer"], "\(OnlineEngineP2pTests.dotted(b)):3658/1", "\(pinged) \(together.signals)")
        XCTAssertEqual(pinged["echoed"], "300000", "\(pinged)")
        XCTAssertEqual(pinged["same"], "1")
        XCTAssertEqual(ponged["from"]?.hasPrefix("\(OnlineEngineP2pTests.dotted(a)):"), true, "the stream comes from the other game's virtual address: \(ponged)")
        XCTAssertEqual(ponged["got"], "300000")
        XCTAssertEqual(ponged["same"], "1")
        XCTAssertEqual(ponged["end"], "0", "the pinger's close ends the stream")
    }

    /// LAN-style discovery: a game broadcasts on its UDP socket, the other game hears it from the
    /// sender's virtual address and answers directly; the largest UDP datagram crosses, and a
    /// bigger one fails with EMSGSIZE in the sending game.
    func testAGamesBroadcastReachesTheOtherGame() async throws {
        guard let probe = OnlineEngineP2pTests.probe else { throw XCTSkip("online_probe is not built") }
        let together = OneSession()
        let users = ["0190a0b1-0000-7000-8000-00000000000a", "0190a0b1-0000-7000-8000-00000000000b"]
        together.add(users[0], device: "dev-a")
        together.add(users[1], device: "dev-b")
        let game = OnlineWebRouter.Game(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "mesh-test")
        let plays = users.enumerated().map { index, userId in
            let device = index == 0 ? "dev-a" : "dev-b"
            let play = OnlinePlay(service: together, user: TogetherUser(id: userId, handle: index == 0 ? "alice" : "bob", displayName: userId, avatar: nil), game: game,
                                  signal: together.relay(from: userId, fromDevice: device), transport: { OnlinePeerMesh(context: $0, iceServers: []) })
            together.attach(play, as: userId)
            return play
        }
        let environments = try plays.map { try $0.start() }
        defer { plays.forEach { $0.stop() } }
        for play in plays { await play.follow(sessionId: together.id) }
        let addresses = OnlineIdentity.addresses(for: users)
        let (a, b) = (try XCTUnwrap(addresses[users[0]]), try XCTUnwrap(addresses[users[1]]))

        for (destination, size) in [("255.255.255.255", OnlineWire.maxGameDatagram), (OnlineEngineP2pTests.dotted(OnlineWire.virtualBroadcast), 4)] {
            let pong = try start(probe, environment: environments[1], arguments: ["udp", OnlineEngineP2pTests.dotted(a), "pong"])
            let ping = try start(probe, environment: environments[0], arguments: ["udp", destination, "ping", String(size)])
            let pinged = finish(ping)
            let ponged = finish(pong)
            XCTAssertEqual(pinged["oversize"], "0x80410128", "a datagram larger than UDP allows fails with EMSGSIZE: \(pinged)")
            XCTAssertEqual(ponged["got"], "ping", "\(destination): \(ponged)")
            XCTAssertEqual(ponged["from"], "\(OnlineEngineP2pTests.dotted(a)):3660", "the broadcast comes from the sender's virtual address")
            XCTAssertEqual(ponged["size"], String(size))
            XCTAssertEqual(pinged["got"], "pong", "\(destination): \(pinged) \(together.signals)")
            XCTAssertEqual(pinged["from"], "\(OnlineEngineP2pTests.dotted(b)):3659")
            XCTAssertEqual(pinged["size"], String(size))
        }
    }
}

/// A value set from another thread, for polling in a test.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
