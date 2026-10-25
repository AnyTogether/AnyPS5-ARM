import XCTest
@testable import AnyPS5Core

final class RTMPPublisherTests: XCTestCase {
    let sps = Data([0x67, 0x64, 0x00, 0x1F, 0xAC, 0xD9, 0x40])
    let pps = Data([0x68, 0xEB, 0xE3, 0xCB, 0x22, 0xC0])

    func endpoint(_ server: FakeRTMPServer, key: String = "test-key") -> RTMPEndpoint {
        RTMPEndpoint(tls: false, host: "127.0.0.1", port: server.port, app: "live", streamKey: key)
    }

    func options(backoff: Double = 0.05) -> RTMPPublisher.Options {
        var options = RTMPPublisher.Options()
        options.backoff = [backoff]
        options.timeout = 5
        return options
    }

    /// A frame of two NAL units in AVCC form, `size` bytes of slice.
    func frame(_ size: Int, key: Bool) -> Data {
        var data = Data()
        data.appendBigEndian(UInt32(size))
        data.append(key ? 0x65 : 0x41)
        data.append(Data(count: size - 1))
        return data
    }

    func waitFor(_ states: Locked<[RTMPPublisher.State]>, _ timeout: Double = 10, _ condition: ([RTMPPublisher.State]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition(states.value) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition(states.value)
    }

    /// The whole conversation with a server: handshake, connect, createStream, publish, the
    /// metadata and sequence headers before the first key frame, the frames on one clock from
    /// zero, the ping answered, and FCUnpublish and deleteStream at the end.
    func testPublishesAStreamAsAServerExpects() throws {
        let server = try FakeRTMPServer()
        let states = Locked<[RTMPPublisher.State]>([])
        let keys = Locked(0)
        let metadata = FLV.metadata(width: 1280, height: 720, frameRate: 60, videoBitRate: 3_000_000, audioBitRate: 160_000)
        let publisher = RTMPPublisher(endpoint: endpoint(server), metadata: metadata, options: options(),
                                      onState: { state in states.withLock { $0.append(state) } }, wantKeyFrame: { keys.withLock { $0 += 1 } })
        publisher.setAudioConfig(FLV.audioSpecificConfig(sampleRate: 48000, channels: 2))
        publisher.start()
        XCTAssertTrue(waitFor(states) { $0.contains(.live) })
        XCTAssertGreaterThan(keys.value, 0, "going live asks for a key frame")
        // A frame before the key frame and audio before it are not sent.
        publisher.sendVideo(frame(500, key: false), key: false, milliseconds: 980)
        publisher.sendAudio(Data(repeating: 0x21, count: 300), milliseconds: 990)
        publisher.sendVideo(frame(9000, key: true), key: true, milliseconds: 1000, parameterSets: [sps, pps])
        for index in 1 ... 20 {
            publisher.sendAudio(Data(repeating: 0x21, count: 300), milliseconds: 1000 + UInt32(index) * 21)
            publisher.sendVideo(frame(1200, key: false), key: false, milliseconds: 1000 + UInt32(index) * 17)
        }
        XCTAssertTrue(server.wait { $0.first?.media.count ?? 0 >= 43 })
        let done = expectation(description: "stopped")
        publisher.stop { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(server.wait { $0.first?.commands.contains { $0.name == "deleteStream" } ?? false })

        let session = try XCTUnwrap(server.sessions.first)
        XCTAssertTrue(session.handshakeIsValid, "C0 is 3, C1 has its zero field, C2 echoes S1")
        XCTAssertEqual(session.problems, [])
        // The first thing after the handshake: Set Chunk Size 4096, on chunk stream 2.
        XCTAssertEqual(Array(session.raw.prefix(16)), [0x02, 0, 0, 0, 0, 0, 4, 0x01, 0, 0, 0, 0, 0x00, 0x00, 0x10, 0x00])
        XCTAssertEqual(session.commands.map(\.name), ["connect", "releaseStream", "FCPublish", "createStream", "publish", "FCUnpublish", "deleteStream"])
        let connect = session.commands[0].values
        XCTAssertEqual(connect[1].number, 1)
        XCTAssertEqual(connect[2]["app"]?.string, "live")
        XCTAssertEqual(connect[2]["tcUrl"]?.string, "rtmp://127.0.0.1:\(server.port)/live")
        XCTAssertEqual(connect[2]["type"]?.string, "nonprivate")
        let publish = session.commands[4]
        XCTAssertEqual(publish.streamID, 1)
        XCTAssertEqual(publish.values[3].string, "test-key")
        XCTAssertEqual(publish.values[4].string, "live")
        XCTAssertEqual(session.commands[6].values[3].number, 1, "deleteStream names the stream")
        // The ping is answered with its time.
        XCTAssertTrue(session.messages.contains { $0.kind == .userControl && [UInt8]($0.payload) == [0, 7, 0, 0, 0x10, 0x92] })

        let afterPublish = session.messages.filter { $0.kind == .dataAMF0 || $0.kind == .audio || $0.kind == .video }
        let script = try AMF0.decodeAll(afterPublish[0].payload)
        XCTAssertEqual(script.first?.string, "@setDataFrame")
        XCTAssertEqual(script[2]["width"]?.number, 1280)
        XCTAssertEqual(afterPublish[1].kind, .video)
        XCTAssertEqual(Array(afterPublish[1].payload.prefix(2)), [0x17, 0x00], "the AVC sequence header")
        XCTAssertEqual(afterPublish[1].payload.count, 16 + sps.count + pps.count, "header, record, both sets")
        XCTAssertEqual([UInt8](afterPublish[2].payload), [0xAF, 0x00, 0x11, 0x90], "the AAC sequence header")
        XCTAssertEqual(Array(afterPublish[3].payload.prefix(2)), [0x17, 0x01], "the first frame is the key frame")
        XCTAssertEqual(afterPublish[3].timestamp, 0, "at time zero")
        XCTAssertEqual(afterPublish[3].payload.count, 5 + 4 + 9000)
        XCTAssertEqual(afterPublish[3].streamID, 1)
        let video = session.media.filter { $0.kind == .video }.dropFirst(2)
        XCTAssertEqual(video.map(\.timestamp), (1 ... 20).map { UInt32($0) * 17 })
        let audio = session.media.filter { $0.kind == .audio }.dropFirst()
        XCTAssertEqual(audio.map(\.timestamp), (1 ... 20).map { UInt32($0) * 21 })
        XCTAssertTrue(audio.allSatisfy { $0.payload.prefix(2) == Data([0xAF, 0x01]) })

        let stats = publisher.stats
        XCTAssertEqual(stats.videoSent, 21)
        XCTAssertEqual(stats.audioSent, 20)
        XCTAssertEqual(stats.reconnects, 0)
        XCTAssertGreaterThan(stats.bytesSent, 9000 + 20 * 1200)
        XCTAssertEqual(states.value.last, .stopped)
    }

    /// The server going away mid-broadcast: the publisher connects again by itself and starts
    /// over with the metadata, the sequence headers and a key frame.
    func testReconnectsWhenTheConnectionDrops() throws {
        let server = try FakeRTMPServer(options: .init(closeAfterMedia: 12))
        let states = Locked<[RTMPPublisher.State]>([])
        let wantsKey = Locked(false)
        let publisher = RTMPPublisher(endpoint: endpoint(server), metadata: [], options: options(),
                                      onState: { state in states.withLock { $0.append(state) } }, wantKeyFrame: { wantsKey.value = true })
        publisher.setAudioConfig(FLV.audioSpecificConfig(sampleRate: 48000, channels: 2))
        publisher.start()
        XCTAssertTrue(waitFor(states) { $0.contains(.live) })
        var milliseconds: UInt32 = 0
        let deadline = Date().addingTimeInterval(10)
        // Frames keep coming, a key frame whenever one is asked for, until the second
        // connection has some.
        while Date() < deadline, !server.wait(0, until: { $0.count >= 2 && $0[1].media.count >= 10 }) {
            let key = wantsKey.withLock { let was = $0; $0 = false; return was } || milliseconds % 1000 == 0
            publisher.sendVideo(frame(800, key: key), key: key, milliseconds: milliseconds, parameterSets: key ? [sps, pps] : [])
            publisher.sendAudio(Data(count: 200), milliseconds: milliseconds)
            milliseconds += 20
            Thread.sleep(forTimeInterval: 0.005)
        }
        publisher.stop()
        let sessions = server.sessions
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions[0].closed)
        XCTAssertTrue(sessions[1].handshakeIsValid)
        XCTAssertEqual(sessions[1].commands.prefix(5).map(\.name), ["connect", "releaseStream", "FCPublish", "createStream", "publish"])
        let again = sessions[1].messages.filter { $0.kind == .dataAMF0 || $0.kind == .audio || $0.kind == .video }
        XCTAssertEqual(again[0].kind, .dataAMF0)
        XCTAssertEqual(Array(again[1].payload.prefix(2)), [0x17, 0x00])
        XCTAssertEqual(Array(again[2].payload.prefix(2)), [0xAF, 0x00])
        XCTAssertEqual(Array(again[3].payload.prefix(2)), [0x17, 0x01])
        XCTAssertEqual(again[3].timestamp, 0, "each connection's stream starts at zero")
        XCTAssertTrue(states.value.contains { if case .reconnecting(1, _, _) = $0 { return true } else { return false } })
        XCTAssertEqual(publisher.stats.reconnects, 1)
    }

    /// A key the service refuses ends the broadcast after a few tries, saying why.
    func testARefusedKeyFails() throws {
        let server = try FakeRTMPServer(options: .init(refusedKey: "wrong"))
        let states = Locked<[RTMPPublisher.State]>([])
        let publisher = RTMPPublisher(endpoint: endpoint(server, key: "wrong"), metadata: [], options: options(backoff: 0.01),
                                      onState: { state in states.withLock { $0.append(state) } })
        publisher.start()
        XCTAssertTrue(waitFor(states) { $0.contains { if case .failed = $0 { return true } else { return false } } })
        guard case .failed(let reason) = states.value.last else { return XCTFail("\(states.value)") }
        XCTAssertTrue(reason.contains("Bad stream key"), reason)
        XCTAssertEqual(server.sessions.count, 4, "the first try and three more")
        XCTAssertFalse(states.value.contains(.live))
    }

    /// Nothing listening: a few tries, then a failure, not a broadcast that never ends.
    func testAServerThatIsNotThereFails() throws {
        let server = try FakeRTMPServer()
        let port = server.port
        server.stop()
        let states = Locked<[RTMPPublisher.State]>([])
        let publisher = RTMPPublisher(endpoint: RTMPEndpoint(tls: false, host: "127.0.0.1", port: port, app: "live", streamKey: "k"), metadata: [],
                                      options: options(backoff: 0.01), onState: { state in states.withLock { $0.append(state) } })
        publisher.start()
        XCTAssertTrue(waitFor(states, 20) { $0.contains { if case .failed = $0 { return true } else { return false } } })
        XCTAssertEqual(states.value.filter { if case .reconnecting = $0 { return true } else { return false } }.count, 3)
    }

    /// A network that cannot keep up: frames are dropped, not queued without end, and the
    /// backlog stays near what a second of the stream is.
    func testASlowNetworkDropsFramesInsteadOfQueueing() throws {
        let server = try FakeRTMPServer(options: .init(stall: true))
        let states = Locked<[RTMPPublisher.State]>([])
        var tuned = options()
        tuned.bitRate = 1_000_000
        let publisher = RTMPPublisher(endpoint: endpoint(server), metadata: [], options: tuned, onState: { state in states.withLock { $0.append(state) } })
        publisher.start()
        XCTAssertTrue(waitFor(states) { $0.contains(.live) })
        // 60 MB offered in bursts, far more than a socket holds.
        for index in 0 ..< 1200 {
            publisher.sendVideo(frame(50_000, key: index % 60 == 0), key: index % 60 == 0, milliseconds: UInt32(index) * 16, parameterSets: index % 60 == 0 ? [sps, pps] : [])
            if index % 30 == 29 { Thread.sleep(forTimeInterval: 0.02) }
        }
        let stats = publisher.stats
        XCTAssertGreaterThan(stats.videoDropped, 600)
        XCTAssertLessThan(stats.backlog, 125_000 + 2 * 50_100, "a second of the stream and the frame that crossed it")
        publisher.stop()
    }
}
