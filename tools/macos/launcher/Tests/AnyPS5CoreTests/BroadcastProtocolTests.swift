import XCTest
@testable import AnyPS5Core

final class BroadcastProtocolTests: XCTestCase {
    // MARK: AMF0

    /// connect's command object, byte for byte as Flash and ffmpeg write it.
    func testAMF0WritesCommandsAsServersReadThem() {
        let bytes = AMF0.encode([.string("connect"), .number(1), .object([.init("app", .string("live"))]), .null, .boolean(true)])
        XCTAssertEqual([UInt8](bytes), [
            0x02, 0x00, 0x07] + Array("connect".utf8) + [
            0x00, 0x3F, 0xF0, 0, 0, 0, 0, 0, 0,
            0x03, 0x00, 0x03] + Array("app".utf8) + [0x02, 0x00, 0x04] + Array("live".utf8) + [0x00, 0x00, 0x09,
            0x05,
            0x01, 0x01,
        ])
    }

    func testAMF0ReadsBackWhatItWrites() throws {
        let values: [AMF0] = [
            .string("onMetaData"),
            .ecmaArray([.init("width", .number(1280)), .init("stereo", .boolean(true)), .init("encoder", .string("AnyPS5"))]),
            .strictArray([.number(1), .string("two"), .null, .undefined]),
            .object([.init("nested", .object([.init("deep", .number(-0.5))]))]),
            .date(1_700_000_000_000),
            .string(String(repeating: "x", count: 70000)),
        ]
        XCTAssertEqual(try AMF0.decodeAll(AMF0.encode(values)), values)
        XCTAssertEqual(values[1]["width"], .number(1280))
        XCTAssertEqual(values[3]["nested"]?["deep"]?.number, -0.5)
    }

    func testAMF0RefusesATruncatedMessage() {
        let bytes = AMF0.encode([.string("publish")])
        XCTAssertThrowsError(try AMF0.decodeAll(bytes.dropLast(2)))
        XCTAssertThrowsError(try AMF0.decodeAll(Data([0x0D])))
    }

    func testAMF0RefusesValuesNestedTooDeep() {
        // A strict array of one inside another, 200 000 deep: read without a limit, this runs
        // out of stack long before it runs out of bytes.
        var bytes = Data()
        for _ in 0 ..< 200_000 { bytes.append(contentsOf: [0x0A, 0, 0, 0, 1]) }
        bytes.append(0x05)
        XCTAssertThrowsError(try AMF0.decodeAll(bytes))
        var shallow = AMF0.null
        for _ in 0 ..< 30 { shallow = .strictArray([shallow]) }
        XCTAssertEqual(try AMF0.decodeAll(AMF0.encode([shallow])), [shallow])
    }

    // MARK: Chunks

    /// The first message on a chunk stream has a full header (type 0); a message longer than the
    /// chunk size goes on in type 3 chunks of one byte of header.
    func testChunksAreCutAtTheChunkSize() {
        var writer = RTMPChunkWriter()
        writer.setChunkSize(4096)
        let payload = Data((0 ..< 10000).map { UInt8($0 & 0xFF) })
        let bytes = [UInt8](writer.chunks(RTMPMessage(chunkStream: 6, kind: .video, streamID: 1, timestamp: 40, payload: payload)))
        // fmt 0, csid 6 | timestamp 40 | length 10000 | type 9 | stream 1 little endian.
        XCTAssertEqual(Array(bytes.prefix(12)), [0x06, 0, 0, 40, 0x00, 0x27, 0x10, 9, 1, 0, 0, 0])
        XCTAssertEqual(bytes.count, 12 + 10000 + 2)
        XCTAssertEqual(bytes[12 + 4096], 0xC6, "a type 3 header for chunk stream 6")
        XCTAssertEqual(bytes[12 + 4096 + 1 + 4096], 0xC6)
        XCTAssertEqual(Array(bytes[12 ..< 12 + 4096]), Array(payload.prefix(4096)))
    }

    /// The next message on the same chunk stream carries only what changed: the time since the
    /// last (type 2) or that and its length and type (type 1).
    func testLaterHeadersCarryOnlyWhatChanged() {
        var writer = RTMPChunkWriter()
        _ = writer.chunks(RTMPMessage(chunkStream: 4, kind: .audio, streamID: 1, timestamp: 0, payload: Data(count: 10)))
        XCTAssertEqual([UInt8](writer.chunks(RTMPMessage(chunkStream: 4, kind: .audio, streamID: 1, timestamp: 21, payload: Data(count: 10)))).prefix(4), [0x84, 0, 0, 21])
        XCTAssertEqual([UInt8](writer.chunks(RTMPMessage(chunkStream: 4, kind: .audio, streamID: 1, timestamp: 42, payload: Data(count: 12)))).prefix(8), [0x44, 0, 0, 21, 0, 0, 12, 8])
        // Time going backwards needs the absolute time again.
        XCTAssertEqual([UInt8](writer.chunks(RTMPMessage(chunkStream: 4, kind: .audio, streamID: 1, timestamp: 5, payload: Data(count: 12)))).first, 0x04)
    }

    /// Past 0xFFFFFF milliseconds (4.6 hours) the time moves to the extended field, repeated in
    /// every type 3 chunk of the message.
    func testLongBroadcastsUseTheExtendedTimestamp() throws {
        var writer = RTMPChunkWriter()
        let stamp: UInt32 = 0x0100_0000 + 7
        let bytes = [UInt8](writer.chunks(RTMPMessage(chunkStream: 6, kind: .video, streamID: 1, timestamp: stamp, payload: Data(count: 200))))
        XCTAssertEqual(Array(bytes[1 ..< 4]), [0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(bytes[12 ..< 16]), [0x01, 0x00, 0x00, 0x07])
        XCTAssertEqual(bytes[16 + 128], 0xC6)
        XCTAssertEqual(Array(bytes[16 + 128 + 1 ..< 16 + 128 + 5]), [0x01, 0x00, 0x00, 0x07])
        var reader = RTMPChunkReader()
        reader.append(Data(bytes))
        XCTAssertEqual(try reader.messages().first?.timestamp, stamp)
    }

    /// Messages on several chunk streams, cut small and fed a few bytes at a time, come back whole.
    func testTheReaderPutsInterleavedMessagesBackTogether() throws {
        var writer = RTMPChunkWriter()
        var stream = Data()
        let sent = [
            RTMPMessage.setChunkSize(64),
            RTMPMessage(chunkStream: 3, kind: .commandAMF0, payload: AMF0.encode([.string("connect"), .number(1), .object([.init("app", .string("live2"))])])),
            RTMPMessage(chunkStream: 6, kind: .video, streamID: 1, timestamp: 0, payload: Data((0 ..< 300).map { UInt8($0 % 251) })),
            RTMPMessage(chunkStream: 4, kind: .audio, streamID: 1, timestamp: 0, payload: Data(count: 90)),
            RTMPMessage(chunkStream: 6, kind: .video, streamID: 1, timestamp: 16, payload: Data(count: 300)),
            RTMPMessage(chunkStream: 4, kind: .audio, streamID: 1, timestamp: 21, payload: Data(count: 90)),
            RTMPMessage(chunkStream: 400, kind: .dataAMF0, streamID: 1, timestamp: 33, payload: Data(count: 5)),
            RTMPMessage(chunkStream: 70, kind: .dataAMF0, streamID: 1, timestamp: 34, payload: Data(count: 5)),
        ]
        stream += writer.chunks(sent[0])
        writer.setChunkSize(64)
        for message in sent.dropFirst() { stream += writer.chunks(message) }
        var reader = RTMPChunkReader()
        var got: [RTMPMessage] = []
        var offset = 0
        while offset < stream.count {
            let end = min(stream.count, offset + 7)
            reader.append(stream.subdata(in: offset ..< end))
            got += try reader.messages()
            offset = end
        }
        XCTAssertEqual(got, sent)
        XCTAssertEqual(reader.chunkSize, 64)
        XCTAssertEqual(reader.received, UInt64(stream.count))
    }

    /// A server whose type 1 header makes a message shorter than what already came of it, or
    /// that sets a chunk size of 0 through the top bit, is refused, not a crash.
    func testTheReaderRefusesAMessageShorterThanWhatCame() {
        var bytes: [UInt8] = [0x03, 0, 0, 0, 0, 0, 200, 20, 0, 0, 0, 0]
        bytes += [UInt8](repeating: 0x05, count: 128)
        // Type 1 on the same chunk stream, mid-message: length 50, fewer than the 128 read.
        bytes += [0x43, 0, 0, 0, 0, 0, 50, 20]
        bytes += [UInt8](repeating: 0x05, count: 50)
        var reader = RTMPChunkReader()
        reader.append(Data(bytes))
        XCTAssertThrowsError(try reader.messages())

        var zero = RTMPChunkReader()
        zero.append(Data([0x02, 0, 0, 0, 0, 0, 4, 1, 0, 0, 0, 0, 0x80, 0, 0, 0]))
        XCTAssertThrowsError(try zero.messages())
    }

    // MARK: Handshake

    func testTheHandshakeIsVersionThreeAndEchoesTheServer() throws {
        let c0c1 = RTMPHandshake.c0c1(time: 0)
        XCTAssertEqual(c0c1.count, 1537)
        XCTAssertEqual(c0c1[0], 3)
        XCTAssertEqual(Array(c0c1[1 ..< 9]), [0, 0, 0, 0, 0, 0, 0, 0])
        let s1 = Data((0 ..< 1536).map { UInt8($0 % 256) })
        XCTAssertEqual(try RTMPHandshake.c2(answering: Data([3]) + s1 + c0c1.dropFirst()), s1)
        XCTAssertThrowsError(try RTMPHandshake.c2(answering: Data([6]) + s1 + s1), "RTMPE is not spoken")
        XCTAssertThrowsError(try RTMPHandshake.c2(answering: Data([3]) + s1))
    }

    // MARK: FLV

    func testTheAVCSequenceHeaderDescribesTheParameterSets() {
        let sps = Data([0x67, 0x64, 0x00, 0x28, 0xAC, 0xD9])
        let pps = Data([0x68, 0xEB, 0xE3, 0xCB])
        XCTAssertEqual([UInt8](FLV.avcSequenceHeader(sps: sps, pps: pps)), [
            0x17, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x64, 0x00, 0x28, 0xFF, 0xE1, 0x00, 0x06, 0x67, 0x64, 0x00, 0x28, 0xAC, 0xD9,
            0x01, 0x00, 0x04, 0x68, 0xEB, 0xE3, 0xCB,
        ])
        XCTAssertEqual([UInt8](FLV.avcFrame(Data([0, 0, 0, 1, 0x65]), key: true)), [0x17, 0x01, 0, 0, 0, 0, 0, 0, 1, 0x65])
        XCTAssertEqual([UInt8](FLV.avcFrame(Data([0, 0, 0, 1, 0x41]), key: false)), [0x27, 0x01, 0, 0, 0, 0, 0, 0, 1, 0x41])
    }

    func testAACIsDescribedForFortyEightKilohertzStereo() {
        XCTAssertEqual([UInt8](FLV.audioSpecificConfig(sampleRate: 48000, channels: 2)), [0x11, 0x90])
        XCTAssertEqual([UInt8](FLV.audioSpecificConfig(sampleRate: 44100, channels: 2)), [0x12, 0x10])
        XCTAssertEqual([UInt8](FLV.aacSequenceHeader(Data([0x11, 0x90]))), [0xAF, 0x00, 0x11, 0x90])
        XCTAssertEqual([UInt8](FLV.aacFrame(Data([0x21, 0x10]))), [0xAF, 0x01, 0x21, 0x10])
    }

    func testFLVFileTagsCarryTheirSizes() {
        XCTAssertEqual([UInt8](FLV.fileHeader), [0x46, 0x4C, 0x56, 0x01, 0x05, 0, 0, 0, 9, 0, 0, 0, 0])
        let tag = [UInt8](FLV.fileTag(.video, timestamp: 0x0123_4567, body: Data([1, 2, 3])))
        XCTAssertEqual(tag, [9, 0, 0, 3, 0x23, 0x45, 0x67, 0x01, 0, 0, 0, 1, 2, 3, 0, 0, 0, 14])
    }

    func testMetadataGoesThroughSetDataFrame() throws {
        let values = try AMF0.decodeAll(FLV.setDataFrame(FLV.metadata(width: 1920, height: 1080, frameRate: 60, videoBitRate: 6_000_000, audioBitRate: 160_000)))
        XCTAssertEqual(values.first?.string, "@setDataFrame")
        XCTAssertEqual(values[1].string, "onMetaData")
        XCTAssertEqual(values[2]["width"]?.number, 1920)
        XCTAssertEqual(values[2]["videodatarate"]?.number, 6000)
        XCTAssertEqual(values[2]["videocodecid"]?.number, 7)
        XCTAssertEqual(values[2]["audiocodecid"]?.number, 10)
    }

    // MARK: Endpoints and settings

    func testEndpointsAreReadFromTheServersAddress() throws {
        let twitch = try RTMPEndpoint.parse(url: BroadcastSettings.Service.twitch.ingest!, key: " live_123_abc ")
        XCTAssertEqual(twitch, RTMPEndpoint(tls: true, host: "ingest.global-contribute.live-video.net", port: 443, app: "app", streamKey: "live_123_abc"))
        XCTAssertEqual(twitch.tcURL, "rtmps://ingest.global-contribute.live-video.net/app")
        let youtube = try RTMPEndpoint.parse(url: BroadcastSettings.Service.youtube.ingest!, key: "abcd-efgh")
        XCTAssertEqual(youtube.app, "live2")
        XCTAssertEqual(youtube.port, 443)
        let custom = try RTMPEndpoint.parse(url: "rtmp://192.168.1.5:1936/live/room?token=x", key: "key")
        XCTAssertEqual(custom, RTMPEndpoint(tls: false, host: "192.168.1.5", port: 1936, app: "live/room?token=x", streamKey: "key"))
        XCTAssertEqual(custom.tcURL, "rtmp://192.168.1.5:1936/live/room?token=x")
        // The key at the end of the address, when no key is given.
        let whole = try RTMPEndpoint.parse(url: "rtmp://example.com/live/my-key/", key: "")
        XCTAssertEqual(whole.app, "live")
        XCTAssertEqual(whole.streamKey, "my-key")
        XCTAssertEqual(whole.port, 1935)
    }

    func testBadAddressesSayWhatIsWrong() {
        XCTAssertThrowsError(try RTMPEndpoint.parse(url: "https://twitch.tv", key: "k")) { XCTAssertEqual($0 as? RTMPEndpoint.Problem, .notRTMP) }
        XCTAssertThrowsError(try RTMPEndpoint.parse(url: "rtmp:///live", key: "k")) { XCTAssertEqual($0 as? RTMPEndpoint.Problem, .noHost) }
        XCTAssertThrowsError(try RTMPEndpoint.parse(url: "rtmp://host", key: "k")) { XCTAssertEqual($0 as? RTMPEndpoint.Problem, .noApplication) }
        XCTAssertThrowsError(try RTMPEndpoint.parse(url: "rtmp://host/live", key: "  ")) { XCTAssertEqual($0 as? RTMPEndpoint.Problem, .noKey) }
    }

    func testQualityPresets() {
        XCTAssertEqual(BroadcastSettings.Quality.allCases.map(\.title), ["720p60 · 3 Mbit/s", "1080p30 · 4.5 Mbit/s", "1080p60 · 6 Mbit/s"])
        XCTAssertEqual(BroadcastSettings.Quality.hd1080p30.frameRate, 30)
        XCTAssertEqual(BroadcastSettings.Quality.hd720p60.width, 1280)
    }

    func testSettingsKeepWhatTheyKnowAndDefaultTheRest() throws {
        var settings = BroadcastSettings()
        settings.service = .youtube
        settings.quality = .hd1080p60
        settings.microphone = true
        settings.viewerLink = "youtube.com/@me/live"
        let defaults = UserDefaults(suiteName: "broadcast-test-\(UUID().uuidString)")!
        settings.save(to: defaults)
        XCTAssertEqual(BroadcastSettings.load(from: defaults), settings)
        XCTAssertEqual(settings.viewerURL?.absoluteString, "https://youtube.com/@me/live")
        let old = try JSONDecoder().decode(BroadcastSettings.self, from: Data(#"{"service":"custom","quality":"hd4k"}"#.utf8))
        XCTAssertEqual(old.service, .custom)
        XCTAssertEqual(old.quality, .hd720p60, "an unknown preset falls back")
        XCTAssertTrue(old.liveBadge)
    }

    /// Stream keys are kept in a file only the user can read, one a service.
    func testStreamKeysStayPrivate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("broadcast-keys-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BroadcastKeyStore(file: folder.appendingPathComponent("keys.json"))
        XCTAssertEqual(store.key(for: .twitch), "")
        store.setKey(" live_42 ", for: .twitch)
        store.setKey("yt-key", for: .youtube)
        XCTAssertEqual(BroadcastKeyStore(file: store.file).key(for: .twitch), "live_42")
        XCTAssertEqual(store.key(for: .youtube), "yt-key")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(Set(store.secrets), ["live_42", "yt-key"])
        store.setKey("", for: .youtube)
        XCTAssertEqual(store.key(for: .youtube), "")
        XCTAssertEqual(BroadcastKeyStore.masked("live_123456789"), "••••••••••6789")
        XCTAssertEqual(BroadcastKeyStore.masked("abc"), "•••")
    }

    // MARK: The phone

    /// The phone hears whether the game is broadcast, and asks to start or stop it with commands.
    func testThePhoneIsToldWhetherTheGameIsBroadcast() throws {
        let message = RemoteMessage.broadcast(on: true)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(message)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "broadcast")
        XCTAssertEqual(json?["on"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: Data(#"{"type":"command","name":"broadcastStop"}"#.utf8)), .command(name: "broadcastStop"))
    }
}
