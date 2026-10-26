import XCTest
@testable import AnyPS5Core

/// One launcher's stream relay with a recording engine, wired to another's as two players'
/// launchers are over the reliable channel.
private final class RelayEnd: @unchecked Sendable {
    let address: UInt32
    private let lock = NSLock()
    private var frames: [OnlineWire.Stream] = []
    var relay: OnlineStreamRelay!
    var reachable = true

    init(address: UInt32) { self.address = address }

    func got(_ frame: OnlineWire.Stream) { lock.withLock { frames.append(frame) } }
    var engine: [OnlineWire.Stream] { lock.withLock { frames } }
    func take() -> [OnlineWire.Stream] { lock.withLock { defer { frames = [] }; return frames } }

    static func pair(_ a: UInt32, _ b: UInt32) -> (RelayEnd, RelayEnd) {
        let left = RelayEnd(address: a), right = RelayEnd(address: b)
        left.relay = OnlineStreamRelay(toEngine: { left.got($0) }, toPeer: { peer, bytes in
            guard left.reachable, peer == right.address else { return false }
            right.relay.fromPeer(left.address, bytes)
            return true
        })
        right.relay = OnlineStreamRelay(toEngine: { right.got($0) }, toPeer: { peer, bytes in
            guard right.reachable, peer == left.address else { return false }
            left.relay.fromPeer(right.address, bytes)
            return true
        })
        return (left, right)
    }
}

final class OnlineStreamRelayTests: XCTestCase {
    let a: UInt32 = 0xC612_0001
    let b: UInt32 = 0xC612_0002

    func testStreamFramesMatchTheEngineByteForByte() {
        // The same bytes as the engine's test (online_bridge "streams").
        let open = OnlineWire.Stream.open(stream: 5, peer: 0xC612_0002, peerPort: 3659, peerVport: 1, localPort: 3660, localVport: 5)
        XCTAssertEqual(OnlineWire.hex(open.frame), "10000000" + "1103" + "0000" + "00000000" + "05000000" + "020012c6" + "4b0e" + "0100" + "4c0e" + "0500")
        XCTAssertEqual(OnlineWire.hex(OnlineWire.Stream.data(stream: 0x8000_0001, Data([1, 2, 3])).payload), "01000080" + "03000000" + "010203")
        XCTAssertEqual(OnlineWire.hex(OnlineWire.Stream.close(stream: 5, .refused).payload), "05000000" + "01")
        XCTAssertEqual(OnlineWire.hex(OnlineWire.Stream.accept(stream: 0x8000_0001).payload), "01000080")
        for frame in [open, .accept(stream: 9), .data(stream: 9, Data("x".utf8)), .close(stream: 9, .reset)] {
            XCTAssertEqual(OnlineWire.Stream(kind: frame.kind, frame.payload), frame)
        }
        XCTAssertEqual(OnlineWire.Stream(kind: .streamClose, Data([5, 0, 0, 0, 9])), .close(stream: 5, .reset), "an unknown reason is a break")
        XCTAssertNil(OnlineWire.Stream(kind: .streamAccept, Data([0, 0, 0, 0])), "stream 0 is never one")
        XCTAssertNil(OnlineWire.Stream(kind: .streamOpen, OnlineWire.Stream.open(stream: 5, peer: 0x0A00_0001, peerPort: 1, peerVport: 0, localPort: 1, localVport: 0).payload))
        XCTAssertNil(OnlineWire.Stream(kind: .datagram, Data([1, 0, 0, 0])))

        // Between launchers (the same bytes in the Flutter launcher's tests).
        let message = OnlineStreamRelay.Message(op: .open, senderOpened: true, stream: 5, sourcePort: 3660, sourceVport: 5, destinationPort: 3659, destinationVport: 1)
        XCTAssertEqual(OnlineWire.hex(message.bytes), "01" + "01" + "05000000" + "4c0e" + "0500" + "4b0e" + "0100")
        XCTAssertEqual(OnlineStreamRelay.Message(message.bytes), message)
        let data = OnlineStreamRelay.Message(op: .data, senderOpened: false, stream: 5, data: Data([7, 8]))
        XCTAssertEqual(OnlineWire.hex(data.bytes), "03" + "00" + "05000000" + "0708")
        XCTAssertEqual(OnlineStreamRelay.Message(data.bytes), data)
        XCTAssertEqual(OnlineWire.hex(OnlineStreamRelay.Message(op: .close, senderOpened: true, stream: 5, reason: .refused).bytes), "04" + "01" + "05000000" + "01")
        XCTAssertEqual(OnlineWire.hex(OnlineStreamRelay.Message(op: .accept, senderOpened: false, stream: 5).bytes), "02" + "00" + "05000000")
        XCTAssertNil(OnlineStreamRelay.Message(Data([1, 0, 5, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0])), "only the opener opens")
        XCTAssertNil(OnlineStreamRelay.Message(Data([9, 0, 5, 0, 0, 0])), "an unknown op is dropped")
    }

    func testTwoRelaysCarryAStreamBothWays() {
        let (alice, bob) = RelayEnd.pair(a, b)
        alice.relay.fromEngine(.open(stream: 1, peer: b, peerPort: 3659, peerVport: 1, localPort: 3660, localVport: 5))
        let opened = bob.take()
        guard case .open(let id, let peer, let peerPort, let peerVport, let localPort, let localVport)? = opened.first else { return XCTFail("\(opened)") }
        XCTAssertTrue(id & OnlineWire.launcherStream != 0, "the launcher numbers the streams it opens to the engine with the top bit set")
        XCTAssertEqual([peer, UInt32(peerPort), UInt32(peerVport), UInt32(localPort), UInt32(localVport)], [a, 3660, 5, 3659, 1],
                       "the other engine gets the opener's address, port and virtual port, and its own port and virtual port")
        bob.relay.fromEngine(.accept(stream: id))
        XCTAssertEqual(alice.take(), [.accept(stream: 1)])

        alice.relay.fromEngine(.data(stream: 1, Data("ping".utf8)))
        XCTAssertEqual(bob.take(), [.data(stream: id, Data("ping".utf8))])
        let big = Data((0 ..< 40000).map { UInt8(truncatingIfNeeded: $0 * 7) })
        bob.relay.fromEngine(.data(stream: id, big))
        let chunks = alice.take()
        XCTAssertEqual(chunks.count, 3, "stream data crosses in chunks of at most 16 KiB")
        XCTAssertEqual(chunks.reduce(into: Data()) { joined, frame in if case .data(1, let data) = frame { joined.append(data) } }, big)

        // Alice's game stops writing; Bob's can still answer until it closes too.
        alice.relay.fromEngine(.close(stream: 1, .closed))
        XCTAssertEqual(bob.take(), [.close(stream: id, .closed)])
        bob.relay.fromEngine(.data(stream: id, Data("late".utf8)))
        XCTAssertEqual(alice.take(), [.data(stream: 1, Data("late".utf8))])
        bob.relay.fromEngine(.close(stream: id, .closed))
        XCTAssertEqual(alice.take(), [.close(stream: 1, .closed)])
        XCTAssertEqual(alice.relay.count, 0, "a stream both sides ended is forgotten")
        XCTAssertEqual(bob.relay.count, 0)
    }

    func testRefusedUnreachableAndGoneStreams() {
        let (alice, bob) = RelayEnd.pair(a, b)
        alice.relay.fromEngine(.open(stream: 1, peer: b, peerPort: 4000, peerVport: 1, localPort: 0, localVport: 0))
        guard case .open(let id, _, _, _, _, _)? = bob.take().first else { return XCTFail() }
        bob.relay.fromEngine(.close(stream: id, .refused))
        XCTAssertEqual(alice.take(), [.close(stream: 1, .refused)], "a refusal reaches the opener")
        XCTAssertEqual(alice.relay.count + bob.relay.count, 0)

        alice.relay.fromEngine(.open(stream: 2, peer: 0xC612_0099, peerPort: 1, peerVport: 0, localPort: 0, localVport: 0))
        XCTAssertEqual(alice.take(), [.close(stream: 2, .reset)], "a stream to someone who cannot be reached breaks at once")

        alice.relay.fromEngine(.open(stream: 3, peer: b, peerPort: 1, peerVport: 0, localPort: 0, localVport: 0))
        guard case .open(let third, _, _, _, _, _)? = bob.take().first else { return XCTFail() }
        bob.relay.fromEngine(.accept(stream: third))
        _ = alice.take()
        alice.relay.peerGone(b)
        XCTAssertEqual(alice.take(), [.close(stream: 3, .reset)], "streams with a player who is gone break")
        bob.relay.fromEngine(.data(stream: third, Data("x".utf8)))
        XCTAssertEqual(bob.take(), [.close(stream: third, .reset)], "data for a stream the other side forgot breaks it there too")

        alice.relay.fromEngine(.open(stream: 4, peer: b, peerPort: 1, peerVport: 0, localPort: 0, localVport: 0))
        guard case .open(let fourth, _, _, _, _, _)? = bob.take().first else { return XCTFail() }
        alice.relay.engineGone()
        XCTAssertEqual(bob.take(), [.close(stream: fourth, .reset)], "when the game goes its streams break for the players")
        XCTAssertEqual(alice.relay.count, 0)

        alice.relay.fromEngine(.open(stream: 5, peer: b, peerPort: 1, peerVport: 0, localPort: 0, localVport: 0))
        guard case .open(let fifth, _, _, _, _, _)? = bob.take().first else { return XCTFail() }
        bob.reachable = false
        bob.relay.fromEngine(.accept(stream: fifth))
        XCTAssertEqual(bob.take(), [.close(stream: fifth, .reset)], "a message that cannot be sent breaks the stream")
    }

    func testTheBridgeCarriesStreamFrames() throws {
        let secret = Data((0 ..< 32).map { UInt8($0) })
        let received = Expectations()
        let server = OnlineBridgeServer(secret: secret, handlers: .init(stream: { received.add("\($0)") }))
        try server.start()
        defer { server.stop() }
        let engine = try XCTUnwrap(FakeEngine(port: server.port, secret: secret))
        engine.send(.open(stream: 1, peer: b, peerPort: 3659, peerVport: 1, localPort: 3660, localVport: 0))
        engine.send(.data(stream: 1, Data("hi".utf8)))
        XCTAssertTrue(received.wait(count: 2))
        XCTAssertEqual(received.items, ["\(OnlineWire.Stream.open(stream: 1, peer: b, peerPort: 3659, peerVport: 1, localPort: 3660, localVport: 0))",
                                        "\(OnlineWire.Stream.data(stream: 1, Data("hi".utf8)))"])
        let until = Date().addingTimeInterval(3)
        while server.engine == nil, Date() < until { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(server.deliver(.accept(stream: 1)))
        XCTAssertEqual(engine.nextStream(), .accept(stream: 1))
        XCTAssertFalse(server.deliver(.data(stream: 1, Data(count: OnlineWire.maxStreamData + 1))), "stream data over 64 KiB is refused")
    }
}
