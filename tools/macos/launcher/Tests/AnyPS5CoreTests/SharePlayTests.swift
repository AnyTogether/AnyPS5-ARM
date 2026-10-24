import Darwin
import XCTest
@testable import AnyPS5Core

/// Share play's server half as the launcher uses it: the REST calls, the signals, and which
/// viewers the host has to call or hang up on as the share play changes.
final class TogetherSharePlayTests: TogetherSignedInCase {
    static func person(_ id: String, _ name: String) -> [String: Any] { ["userId": id, "handle": name.lowercased(), "displayName": name, "avatar": NSNull()] }

    static func viewer(_ id: String, _ name: String, device: String, slot: Any = NSNull()) -> [String: Any] {
        ["user": person(id, name), "device": device, "slot": slot, "joinedAt": "2026-10-24T10:00:00.000Z"]
    }

    static func share(viewers: [[String: Any]] = [], invited: [[String: Any]]? = nil, open: Bool = true) -> [String: Any] {
        var share: [String: Any] = ["id": "sp1", "host": person("u1", "Utku"), "hostDevice": "mac", "titleId": "PPSA01234", "title": "Cat Quest III",
                                    "open": open, "maxViewers": 3, "viewers": viewers, "startedAt": "2026-10-24T10:00:00.000Z"]
        if let invited { share["invited"] = invited }
        return share
    }

    static let ice: [[String: Any]] = [["urls": ["stun:relay.test:3478"]], ["urls": ["turn:relay.test:3478"], "username": "1:u1", "credential": "c"]]

    func testStartingGivesTheShareAndItsRelays() async throws {
        FakeTogether.handler = { _, _ in (201, ["sharePlay": Self.share(invited: []), "iceServers": Self.ice, "expiresAt": "2026-10-24T22:00:00.000Z"]) }
        let started = try await client.startSharePlay(titleId: "PPSA01234", title: "Cat Quest III", open: true, maxViewers: 3)
        XCTAssertEqual(last(), "POST /api/v1/share-plays")
        XCTAssertEqual(body()?["titleId"] as? String, "PPSA01234")
        XCTAssertEqual(body()?["title"] as? String, "Cat Quest III")
        XCTAssertEqual(body()?["maxViewers"] as? Int, 3)
        XCTAssertEqual(body()?["open"] as? Bool, true)
        XCTAssertEqual(started.sharePlay.id, "sp1")
        XCTAssertEqual(started.sharePlay.hostDevice, "mac")
        XCTAssertEqual(started.sharePlay.invited, [])
        XCTAssertEqual(started.iceServers.count, 2)
        XCTAssertNotNil(started.expiresAt)
    }

    func testTheHostsCalls() async throws {
        FakeTogether.handler = { _, _ in (200, Self.share(viewers: [Self.viewer("f1", "Ayşe", device: "web1", slot: 2)])) }
        let granted = try await client.setSharePad("f1", slot: 2, in: "sp1")
        XCTAssertEqual(last(), "PUT /api/v1/share-plays/sp1/viewers/f1/slot")
        XCTAssertEqual(body()?["slot"] as? Int, 2)
        XCTAssertEqual(granted.viewers.first?.slot, 2)
        _ = try await client.setSharePad("f1", slot: nil, in: "sp1")
        XCTAssertTrue(body()?["slot"] is NSNull)
        _ = try await client.updateSharePlay("sp1", open: false)
        XCTAssertEqual(last(), "PATCH /api/v1/share-plays/sp1")
        XCTAssertEqual(body()?["open"] as? Bool, false)
        FakeTogether.handler = { _, _ in (200, ["invited": ["f2"]]) }
        try await client.inviteToSharePlay(["f2"], share: "sp1")
        XCTAssertEqual(last(), "POST /api/v1/share-plays/sp1/invites")
        XCTAssertEqual(body()?["userIds"] as? [String], ["f2"])
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.removeShareViewer("f1", from: "sp1")
        XCTAssertEqual(last(), "DELETE /api/v1/share-plays/sp1/viewers/f1")
        try await client.endSharePlay("sp1")
        XCTAssertEqual(last(), "DELETE /api/v1/share-plays/sp1")
        FakeTogether.handler = { _, _ in (200, ["iceServers": Self.ice, "expiresAt": NSNull()]) }
        let renewed = try await client.shareIceServers("sp1")
        XCTAssertEqual(last(), "GET /api/v1/share-plays/sp1/ice-servers")
        XCTAssertEqual(renewed.iceServers.count, 2)
    }

    func testMineAndTheViewersCalls() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["hosting": NSNull(), "watching": Self.share(),
                   "invites": [["sharePlayId": "sp2", "from": Self.person("f2", "Kral"), "titleId": "PPSA05678", "title": NSNull(), "invitedAt": "2026-10-24T10:00:00.000Z"]]])
        }
        let mine = try await client.mySharePlay()
        XCTAssertEqual(last(), "GET /api/v1/me/share-play")
        XCTAssertNil(mine.hosting)
        XCTAssertEqual(mine.watching?.title, "Cat Quest III")
        XCTAssertEqual(mine.invites.first?.from?.displayName, "Kral")
        XCTAssertNil(mine.invites.first?.title)
        FakeTogether.handler = { _, _ in (201, ["sharePlay": Self.share(viewers: [Self.viewer("u1", "Utku", device: "mac2")]), "iceServers": [], "expiresAt": NSNull()]) }
        let joined = try await client.joinSharePlay("sp2")
        XCTAssertEqual(last(), "POST /api/v1/share-plays/sp2/join")
        XCTAssertEqual(joined.sharePlay.viewers.first?.device, "mac2")
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.leaveSharePlay("sp2")
        XCTAssertEqual(last(), "POST /api/v1/share-plays/sp2/leave")
        try await client.declineSharePlay("sp2")
        XCTAssertEqual(last(), "POST /api/v1/share-plays/sp2/decline")
    }

    func testASignalAndTheFrameThatSendsOne() throws {
        let event = TogetherSocket.event(["op": "event", "id": "e1", "type": "share_play.signal",
                                          "data": ["sharePlayId": "sp1", "from": "f1", "device": "web1", "kind": "answer", "data": ["type": "answer", "sdp": "v=0"]]])
        let signal = try XCTUnwrap(event?.decode(TogetherShareSignal.self))
        XCTAssertEqual(signal.sharePlayId, "sp1")
        XCTAssertEqual(signal.kind, .answer)
        XCTAssertEqual(signal.description?.sdp, "v=0")
        let candidate = TogetherSocket.event(["op": "event", "id": "e2", "type": "share_play.signal",
                                              "data": ["sharePlayId": "sp1", "from": "f1", "device": "web1", "kind": "candidate",
                                                       "data": ["candidate": "candidate:1 1 udp 1 192.0.2.1 5000 typ host", "sdpMid": "0", "sdpMLineIndex": 0]]])
        XCTAssertEqual(candidate?.decode(TogetherShareSignal.self)?.candidate?.sdpMid, "0")
        let ask = TogetherSocket.event(["op": "event", "id": "e3", "type": "share_play.signal",
                                        "data": ["sharePlayId": "sp1", "from": "f1", "device": "web1", "kind": "renegotiate", "data": NSNull()]])
        XCTAssertEqual(ask?.decode(TogetherShareSignal.self)?.kind, .renegotiate)
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: TogetherSocket.shareSignalFrame(to: "f1", device: "web1", share: "sp1", kind: .offer, data: ["type": "offer", "sdp": "v=0"])) as? [String: Any])
        XCTAssertEqual(frame["op"] as? String, "signal")
        XCTAssertEqual(frame["share"] as? String, "sp1")
        XCTAssertNil(frame["call"])
        XCTAssertEqual(frame["device"] as? String, "web1")
        XCTAssertEqual(frame["kind"] as? String, "offer")
    }

    func testAnUpdateDecodesAsTheShare() {
        let event = TogetherSocket.event(["op": "event", "id": "e1", "type": "share_play.updated", "data": Self.share(viewers: [Self.viewer("f1", "Ayşe", device: "web1", slot: 3)])])
        let share = event?.decode(TogetherSharePlay.self)
        XCTAssertEqual(share?.viewers.first?.user.displayName, "Ayşe")
        XCTAssertEqual(share?.viewers.first?.slot, 3)
        XCTAssertNil(share?.invited)
    }

    func testAFriendsPresenceSaysTheyShare() throws {
        let json = Data(#"{"state":"in_game","titleId":"PPSA01234","share":{"sharePlayId":"sp1","titleId":"PPSA01234","title":"Cat Quest III","open":true,"viewers":1,"maxViewers":3}}"#.utf8)
        let presence = try JSONDecoder.together.decode(TogetherSharePresence.Holder.self, from: json)
        XCTAssertEqual(presence.share?.sharePlayId, "sp1")
        XCTAssertEqual(presence.share?.open, true)
        XCTAssertEqual(presence.share?.viewers, 1)
    }
}

/// Which viewers the host calls, hangs up on, or calls again on another device.
final class SharePlayRosterTests: XCTestCase {
    func viewer(_ id: String, _ device: String, slot: Int? = nil) -> TogetherSharePlay.Viewer {
        TogetherSharePlay.Viewer(user: TogetherPerson(userId: id, handle: id, displayName: id, avatar: nil), device: device, slot: slot, joinedAt: nil)
    }

    func testNewcomersAreCalledLeaversHungUpAndAMovedSeatCalledAgain() {
        let before = [viewer("a", "web"), viewer("b", "phone")]
        let after = [viewer("a", "mac"), viewer("c", "web2")]
        let plan = SharePlayRoster.plan(from: before, to: after)
        XCTAssertEqual(plan.call.map(\.user.userId).sorted(), ["a", "c"])
        XCTAssertEqual(plan.call.first { $0.user.userId == "a" }?.device, "mac")
        XCTAssertEqual(plan.hangUp.sorted(), ["a", "b"])
        let same = SharePlayRoster.plan(from: after, to: after)
        XCTAssertTrue(same.call.isEmpty)
        XCTAssertTrue(same.hangUp.isEmpty)
    }

    func testAPadChangeIsNoReasonToCallAgain() {
        let plan = SharePlayRoster.plan(from: [viewer("a", "web")], to: [viewer("a", "web", slot: 2)])
        XCTAssertTrue(plan.call.isEmpty)
        XCTAssertTrue(plan.hangUp.isEmpty)
    }

    func testThePadsByViewer() {
        XCTAssertEqual(SharePlayRoster.pads([viewer("a", "web", slot: 2), viewer("b", "web", slot: nil), viewer("c", "x", slot: 4)]), ["a": 2, "c": 4])
    }

    func testTheFreePadForTheNextViewer() {
        XCTAssertEqual(SharePlayRoster.freePad([viewer("a", "web", slot: 2)]), 3)
        XCTAssertEqual(SharePlayRoster.freePad([]), 2)
        XCTAssertNil(SharePlayRoster.freePad([viewer("a", "w", slot: 2), viewer("b", "w", slot: 3), viewer("c", "w", slot: 4)]))
    }

    func testSeveralViewersGetASmallerStreamEach() {
        XCTAssertEqual(SharePlayRoster.encoding(viewers: 1).maxFramerate, 60)
        XCTAssertEqual(SharePlayRoster.encoding(viewers: 2).maxBitrate, 10_000_000)
        XCTAssertEqual(SharePlayRoster.encoding(viewers: 3).maxFramerate, 30)
        XCTAssertEqual(SharePlayRoster.encoding(viewers: 4).scaleDown, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(SharePlayRoster.encoding(viewers: 3).maxBitrate, 5_000_000)
    }

    func testStartBitrateGoesOnTheH264LinesOfTheAnswer() {
        let sdp = "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96 102\r\na=rtpmap:96 VP8/90000\r\na=rtpmap:102 H264/90000\r\na=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f\r\n"
        let tuned = SharePlayRoster.tuneVideo(sdp, startKbps: 2500, maxKbps: 10000)
        XCTAssertTrue(tuned.contains("a=fmtp:102 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f;x-google-start-bitrate=2500;x-google-max-bitrate=10000;x-google-min-bitrate=600"))
        XCTAssertFalse(tuned.contains("a=fmtp:96"))
        XCTAssertEqual(SharePlayRoster.tuneVideo(tuned, startKbps: 2500, maxKbps: 10000), tuned)
    }
}

/// A fake set of game bridges: what was reserved, released and sent.
final class FakeBridges: SharePadBridges, @unchecked Sendable {
    var free: [Int] = [3, 2, 1]
    var sent: [(Data, Int)] = []
    var released: [Int] = []

    func reservePadBridge() -> Int? { free.isEmpty ? nil : free.removeFirst() }
    func releasePadBridge(_ bridge: Int) {
        released.append(bridge)
        free.insert(bridge, at: 0)
    }
    func sendPad(_ data: Data, bridge: Int) { sent.append((data, bridge)) }
}

/// Only a viewer the host handed a pad reaches the game, through a bridge of their own.
final class SharePadRouterTests: XCTestCase {
    func pad(session: UInt64, sequence: UInt32 = 1, buttons: UInt32 = 0x4000) -> Data {
        var packet = RemoteProtocolTests.input(session: session)
        packet.replaceSubrange(8 ..< 12, with: withUnsafeBytes(of: sequence.littleEndian) { Data($0) })
        packet.replaceSubrange(32 ..< 36, with: withUnsafeBytes(of: buttons.littleEndian) { Data($0) })
        packet.replaceSubrange(36 ..< 40, with: Data([10, 20, 30, 40]))
        packet[40] = 200
        return packet
    }

    func testOnlyTheHolderOfAPadReachesTheGame() {
        let bridges = FakeBridges()
        let router = SharePadRouter(bridges: bridges)
        router.update(pads: ["a": 2])
        XCTAssertTrue(router.receive(pad(session: 7), from: "a"))
        XCTAssertFalse(router.receive(pad(session: 8), from: "b"))
        XCTAssertFalse(router.receive(Data(repeating: 0, count: 80), from: "a"))
        XCTAssertFalse(router.receive(pad(session: 7).prefix(79), from: "a"))
        XCTAssertEqual(bridges.sent.count, 1)
        XCTAssertEqual(bridges.sent.first?.0, pad(session: 7))
        XCTAssertEqual(bridges.sent.first?.1, 3)
        XCTAssertEqual(router.bridge(of: "a"), 3)
        XCTAssertNil(router.bridge(of: "b"))
    }

    func testEachViewerGetsTheirOwnBridgeAndAPadTakenBackLetsGo() {
        let bridges = FakeBridges()
        let router = SharePadRouter(bridges: bridges)
        router.update(pads: ["a": 2, "b": 3])
        let a = router.bridge(of: "a"), b = router.bridge(of: "b")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b)
        _ = router.receive(pad(session: 7, sequence: 41), from: "a")
        router.update(pads: ["b": 3])
        // Taking the pad back lets go of every button first, so nothing stays held in the game.
        let released = bridges.sent.last
        XCTAssertEqual(released?.1, a)
        XCTAssertEqual(released.map { RemotePacket.read($0.0, at: 8) as UInt32 }, 42)
        XCTAssertEqual(released.map { RemotePacket.read($0.0, at: 32) as UInt32 }, 0)
        XCTAssertEqual(released.map { [UInt8]($0.0[36 ..< 42]) }, [128, 128, 128, 128, 0, 0])
        XCTAssertEqual(released.map { RemotePacket.inputSession($0.0) }, 7)
        XCTAssertEqual(bridges.released, [a!])
        XCTAssertFalse(router.receive(pad(session: 7), from: "a"))
        XCTAssertEqual(router.bridge(of: "b"), b)
        router.update(pads: [:])
        XCTAssertEqual(bridges.released.count, 2)
    }

    func testTheGamesAnswerGoesBackToTheViewerOfThatBridge() {
        let bridges = FakeBridges()
        let router = SharePadRouter(bridges: bridges)
        router.update(pads: ["a": 2])
        let bridge = router.bridge(of: "a")!
        XCTAssertEqual(router.viewer(onBridge: bridge), "a")
        XCTAssertNil(router.viewer(onBridge: bridge + 10))
    }

    func testNoBridgeLeftMeansNoPad() {
        let bridges = FakeBridges()
        bridges.free = [3]
        let router = SharePadRouter(bridges: bridges)
        router.update(pads: ["a": 2, "b": 3])
        XCTAssertEqual([router.bridge(of: "a"), router.bridge(of: "b")].compactMap { $0 }.count, 1)
    }
}

/// The real relay: a viewer's pad, handed to the remote server, arrives on the game's socket for
/// the bridge that viewer got, and the game's answer comes back for that viewer; phones keep
/// clear of the bridges share play holds.
final class SharePadRelayTests: XCTestCase {
    var file: URL!
    var server: RemoteServer!
    var phoneKey = ""

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("share-relay-\(UUID().uuidString).json")
        let devices = PairedDevices(file: file)
        phoneKey = devices.add(id: "phone-1", name: "Pixel 8").key
        server = RemoteServer(name: "Test Mac", devices: devices, events: RemoteServer.Events(), advertise: false)
        try server.start()
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: file)
    }

    func testAViewersPadReachesItsBridgeOnLoopbackAndTheAnswerComesBack() throws {
        let outputs = Locked<[(Int, Data)]>([])
        server.padOutput = { bridge, data in outputs.withLock { $0.append((bridge, data)) } }
        let router = SharePadRouter(bridges: server)
        router.update(pads: ["viewer": 2])
        let bridge = try XCTUnwrap(router.bridge(of: "viewer"))
        // Share play takes the last bridge, keeping the first ones for phones.
        XCTAssertEqual(bridge, RemoteServer.maxPhones - 1)
        let games = (0 ..< RemoteServer.maxPhones).map { _ in UDPPeer() }
        for (index, game) in games.enumerated() { game.send(RemoteRelayTests.hello, to: server.bridgePorts[index]) }
        Thread.sleep(forTimeInterval: 0.05)
        let packet = SharePadRouterTests().pad(session: 99)
        XCTAssertTrue(router.receive(packet, from: "viewer"))
        XCTAssertEqual(games[bridge].receive(), packet)
        XCTAssertNil(games[0].receive())
        XCTAssertFalse(router.receive(packet, from: "stranger"))
        XCTAssertNil(games[bridge].receive())

        games[bridge].send(RemoteRelayTests.output, to: server.bridgePorts[bridge])
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(outputs.value.first?.0, bridge)
        XCTAssertEqual(outputs.value.first?.1, RemoteRelayTests.output)
        XCTAssertEqual(router.viewer(onBridge: bridge), "viewer")
    }

    func testAPhoneThatComesLaterGetsAFreeBridge() async throws {
        let router = SharePadRouter(bridges: server)
        router.update(pads: ["a": 2, "b": 3, "c": 4])
        XCTAssertEqual(server.reservedPadBridges, [1, 2, 3])
        let phone = FakePhone(port: server.controlPort!)
        defer { phone.close() }
        try await phone.hello(key: phoneKey)
        guard case .welcome = try await phone.receive() else { return XCTFail("no welcome") }
        XCTAssertEqual(server.phoneSlots, [0])
        router.update(pads: [:])
        XCTAssertEqual(server.reservedPadBridges, [])
    }
}

/// The capture's sound cut into share play's 5 ms packets.
final class SoundChunkerTests: XCTestCase {
    func testWholePacketsNumberedWithTheRestKeptForTheNext() {
        var chunker = SoundChunker()
        let first = chunker.add([Int16](repeating: 1, count: 300 * 2), at: 10)
        XCTAssertEqual(first.count, 1)
        let packet = StreamPacket.Audio(first[0])
        XCTAssertEqual(packet?.number, 1)
        XCTAssertEqual(packet?.milliseconds, 0)
        XCTAssertEqual(packet?.payload.count, 960)
        let second = chunker.add([Int16](repeating: 2, count: 180 * 2), at: 10.25)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(StreamPacket.Audio(second[0])?.number, 2)
        XCTAssertEqual(StreamPacket.Audio(second[0])?.milliseconds, 250)
        // The 60 frames left over from the first call come first in the second packet.
        let payload = [UInt8](StreamPacket.Audio(second[0])!.payload)
        XCTAssertEqual(payload[0 ..< 2], [1, 0])
        XCTAssertEqual(payload[60 * 4 ..< 60 * 4 + 2], [2, 0])
    }

    func testFloatsBecomeClampedStereo() {
        let left: [Float] = [0, 1, -2]
        let right: [Float] = [0.5, -1, 2]
        let planar = left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in
            SoundChunker.stereo16(first: l.baseAddress!, second: r.baseAddress!, planar: true, channels: 2, frames: 3)
        } }
        XCTAssertEqual(planar, [0, 16383, 32767, -32767, -32767, 32767])
        let interleaved: [Float] = [0, 0.5, 1, -1]
        let mixed = interleaved.withUnsafeBufferPointer { SoundChunker.stereo16(first: $0.baseAddress!, second: nil, planar: false, channels: 2, frames: 2) }
        XCTAssertEqual(mixed, [0, 16383, 32767, -32767])
        let mono: [Float] = [0.5, -0.5]
        XCTAssertEqual(mono.withUnsafeBufferPointer { SoundChunker.stereo16(first: $0.baseAddress!, second: nil, planar: false, channels: 1, frames: 2) }, [16383, 16383, -16383, -16383])
    }
}

/// A viewer's launcher: the controller as the engine's pad packet, and the sound kept steady.
final class SharePadStateTests: XCTestCase {
    func testThePacketHasThePhonesLayout() {
        var pad = SharePadState()
        pad.buttons = SharePadState.Button.cross | SharePadState.Button.l1
        pad.sticks = [SharePadState.axis(-1), SharePadState.axis(1, up: true), SharePadState.axis(0), SharePadState.axis(0.5)]
        pad.l2 = SharePadState.trigger(1)
        pad.r2 = SharePadState.trigger(0.5)
        let packet = pad.packet(sequence: 7, sentMicros: 123_456, session: 0xABCDEF)
        XCTAssertEqual(packet.count, 80)
        XCTAssertEqual(RemotePacket.inputSession(packet), 0xABCDEF)
        XCTAssertEqual(RemotePacket.read(packet, at: 8) as UInt32, 7)
        XCTAssertEqual(RemotePacket.read(packet, at: 12) as UInt32, 0)
        XCTAssertEqual(RemotePacket.read(packet, at: 16) as UInt64, 123_456)
        XCTAssertEqual(RemotePacket.read(packet, at: 32) as UInt32, 0x4400)
        XCTAssertEqual([UInt8](packet[36 ..< 42]), [0, 0, 128, 191, 255, 128])
        XCTAssertEqual(Float(bitPattern: RemotePacket.read(packet, at: 60) as UInt32), 9.80665, accuracy: 0.0001)
        XCTAssertEqual([UInt8](packet[44 ..< 56]), [UInt8](repeating: 0, count: 12))
    }

    func testTheSoundPrimesPlaysAndDropsWhatIsTooOld() {
        var buffer = SoundJitterBuffer(target: 480, limit: 960)
        func packet(_ number: UInt32, _ value: Int16) -> Data { StreamPacket.audio(Data([Int16](repeating: value.littleEndian, count: 480).withUnsafeBytes { Data($0) }), number: number, milliseconds: 0) }
        buffer.push(packet(1, 1))
        XCTAssertEqual(buffer.pull(100), [Int16](repeating: 0, count: 200))
        buffer.push(packet(2, 2))
        XCTAssertEqual(buffer.pull(240).first, 1)
        // A late, older packet is not played.
        buffer.push(packet(1, 9))
        XCTAssertEqual(buffer.buffered, 240)
        for number in UInt32(3) ... 8 { buffer.push(packet(number, Int16(number))) }
        XCTAssertLessThanOrEqual(buffer.buffered, 960)
        // Past the limit the oldest went down to the target: 5 to 8 are left.
        XCTAssertEqual(buffer.buffered, 960)
        XCTAssertEqual(buffer.pull(1).first, 5)
        // Dry: silence, then priming again.
        _ = buffer.pull(10_000)
        XCTAssertEqual(buffer.pull(10), [Int16](repeating: 0, count: 20))
    }
}
