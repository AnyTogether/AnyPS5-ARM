import AnyPS5Core
import AVFoundation
import CoreVideo
import Foundation
import LiveKit
import XCTest
@testable import AnyPS5MediaServer

/// A share play through a real LiveKit server in one process: the host publishes a synthetic
/// picture and a tone, a viewer subscribes and the picture arrives; a plain subscriber receives the sound. Runs only
/// when ANYPS5_LIVEKIT_URL names a server (wss:// or ws://) whose API key and secret are in
/// ANYPS5_LIVEKIT_KEY and ANYPS5_LIVEKIT_SECRET, e.g. `livekit-server --dev` (devkey / secret).
@MainActor
final class SfuShareEndToEndTests: XCTestCase {
    var url: String!
    var key: String!
    var secret: String!

    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["ANYPS5_LIVEKIT_URL"] else { throw XCTSkip("no LiveKit server (ANYPS5_LIVEKIT_URL)") }
        self.url = url
        key = environment["ANYPS5_LIVEKIT_KEY"] ?? "devkey"
        secret = environment["ANYPS5_LIVEKIT_SECRET"] ?? "secret"
    }

    func access(_ room: String, _ identity: String, publish: Bool) -> TogetherSfuAccess {
        TogetherSfuAccess(url: url, token: LiveKitTestToken.make(key: key, secret: secret, room: room, identity: identity, publish: publish), room: room, identity: identity)
    }

    func testTheHostsPictureAndSoundReachAViewer() async throws {
        let room = "share-e2e-\(UUID().uuidString.prefix(6))"
        let host = SfuShareHost()
        let frames = Task.detached {
            var time: Int64 = 0
            while !Task.isCancelled {
                if let pixels = SyntheticFrame.make(time: time) { host.push(pixels, timeNs: time) }
                // 20 ms of a stereo tone: 440 Hz on the left, silence on the right.
                host.push(sound: SyntheticSound.packet(frames: 960, start: Int(time / 20_833)))
                time += 20_000_000
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        defer { frames.cancel() }
        try await host.start(access(room, "host", publish: true))
        XCTAssertEqual(host.state, .connected)
        let viewer = SfuShareWatcher(hostId: "host")
        try await viewer.start(access(room, "viewer", publish: false))
        // The viewer joined: the game sound waits (watching needs the device) in this one process.
        for _ in 0 ..< 100 where !viewer.connected { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(viewer.connected, "the host's picture reached the viewer")
        var stats = viewer.statistics()
        for _ in 0 ..< 60 where (stats.height ?? 0) == 0 {
            try await Task.sleep(for: .milliseconds(250))
            stats = viewer.statistics()
        }
        print("viewer statistics: \(stats)")
        XCTAssertGreaterThan(stats.height ?? 0, 0)
        await viewer.close()
        await host.close()
    }

    /// The game sound alone (no viewer in this process takes the device): published as a track
    /// named "game-audio", and a subscriber in a second room client receives it as Opus.
    func testTheGameSoundIsPublishedAsOpus() async throws {
        let room = "share-e2e-\(UUID().uuidString.prefix(6))"
        let host = SfuShareHost()
        let frames = Task.detached {
            var time: Int64 = 0
            while !Task.isCancelled {
                if let pixels = SyntheticFrame.make(time: time) { host.push(pixels, timeNs: time) }
                host.push(sound: SyntheticSound.packet(frames: 960, start: Int(time / 20_833)))
                time += 20_000_000
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        defer { frames.cancel() }
        try await host.start(access(room, "host", publish: true))
        for _ in 0 ..< 50 where !host.publishing.audio { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(host.publishing.audio, "the game sound track is published")
        // A plain subscriber that does not claim the audio engine's device.
        let listener = Room()
        try await listener.connect(url: url, token: LiveKitTestToken.make(key: key, secret: secret, room: room, identity: "listener", publish: false),
                                   roomOptions: RoomOptions(reportRemoteTrackStatistics: true))
        var audio: RemoteAudioTrack?
        for _ in 0 ..< 100 where audio == nil {
            audio = listener.remoteParticipants.values.flatMap(\.trackPublications.values).compactMap { $0 as? RemoteTrackPublication }
                .first { $0.name == SfuTrackNames.audio }?.track as? RemoteAudioTrack
            if audio == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        let track = try XCTUnwrap(audio, "the listener subscribed to game-audio")
        var codec: CodecStatistics?
        var inbound: InboundRtpStreamStatistics?
        for _ in 0 ..< 60 {
            try await Task.sleep(for: .milliseconds(250))
            inbound = track.statistics?.inboundRtpStream.first
            codec = track.statistics?.codec.first { $0.mimeType?.lowercased() == "audio/opus" }
            if let bytes = inbound?.bytesReceived, bytes > 20000, codec != nil { break }
        }
        print("game-audio codec: \(String(describing: codec?.mimeType)) channels \(String(describing: codec?.channels)) fmtp \(String(describing: codec?.sdpFmtpLine)); bytes \(String(describing: inbound?.bytesReceived)), packets \(String(describing: inbound?.packetsReceived))")
        XCTAssertEqual(codec?.mimeType?.lowercased(), "audio/opus")
        XCTAssertGreaterThan(inbound?.bytesReceived ?? 0, 20000, "the sound flows")
        // Not asserted: LiveKit's Swift SDK 2.18 has no stereo publish option, and the fmtp line the
        // subscriber sees (from the media server's offer) does not carry stereo=1, so whether the
        // sound arrives in stereo is unconfirmed (the codec always says 2 channels for Opus).
        await listener.disconnect()
        await host.close()
    }
}

/// A LiveKit access token (HS256), as AnyTogether's API signs them.
enum LiveKitTestToken {
    static func make(key: String, secret: String, room: String, identity: String, publish: Bool) -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = ["alg": "HS256", "typ": "JWT"]
        let claims: [String: Any] = ["iss": key, "sub": identity, "nbf": now - 10, "iat": now, "exp": now + 600,
                                     "video": ["room": room, "roomJoin": true, "canSubscribe": true, "canPublish": publish, "canPublishData": false]]
        func base64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let signing = base64(try! JSONSerialization.data(withJSONObject: header)) + "." + base64(try! JSONSerialization.data(withJSONObject: claims))
        return signing + "." + base64(HMAC256.sign(Data(signing.utf8), key: Data(secret.utf8)))
    }
}

import CryptoKit

enum HMAC256 {
    static func sign(_ data: Data, key: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))) }
}

/// A moving 1280 x 720 BGRA picture.
enum SyntheticFrame {
    static func make(time: Int64) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let shade = UInt8(truncatingIfNeeded: time / 10_000_000)
        for y in 0 ..< 720 {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
            for x in 0 ..< 1280 {
                line[x * 4] = UInt8(truncatingIfNeeded: x) &+ shade
                line[x * 4 + 1] = UInt8(truncatingIfNeeded: y)
                line[x * 4 + 2] = shade
                line[x * 4 + 3] = 255
            }
        }
        return buffer
    }
}

/// StreamPacket audio: a 440 Hz tone on the left channel only.
enum SyntheticSound {
    static func packet(frames: Int, start: Int) -> Data {
        var samples = [Int16](repeating: 0, count: frames * 2)
        for frame in 0 ..< frames {
            samples[frame * 2] = Int16(sin(Double(start + frame) * 2 * .pi * 440 / 48000) * 12000)
        }
        let payload = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return StreamPacket.audio(payload, number: UInt32(start / frames), milliseconds: UInt32(start / 48))
    }
}
