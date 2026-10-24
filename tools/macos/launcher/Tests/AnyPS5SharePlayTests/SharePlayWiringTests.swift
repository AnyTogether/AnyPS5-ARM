import AnyPS5Core
import CoreVideo
import WebRTC
import XCTest
@testable import AnyPS5SharePlay

/// Counts the frames a viewer is shown and their size.
final class FrameCounter: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var size = (width: Int32(0), height: Int32(0))

    var count: Int { lock.withLock { frames } }
    var last: (width: Int32, height: Int32) { lock.withLock { size } }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        lock.withLock {
            frames += 1
            size = (frame.width, frame.height)
        }
    }
}

/// The game's bridges, standing in for the remote server.
final class Bridges: SharePadBridges, @unchecked Sendable {
    let sent = Locked<[(Data, Int)]>([])
    func reservePadBridge() -> Int? { 3 }
    func releasePadBridge(_ bridge: Int) {}
    func sendPad(_ data: Data, bridge: Int) { sent.withLock { $0.append((data, bridge)) } }
}

/// A synthetic game picture: 1280 x 720 NV12 with a bar that moves every frame.
func syntheticFrame(_ index: Int) -> CVPixelBuffer {
    var made: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
    CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes as CFDictionary, &made)
    let pixels = made!
    CVPixelBufferLockBaseAddress(pixels, [])
    let luma = CVPixelBufferGetBaseAddressOfPlane(pixels, 0)!.assumingMemoryBound(to: UInt8.self)
    let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
    for row in 0 ..< 720 {
        for column in 0 ..< 1280 { luma[row * lumaStride + column] = UInt8(truncatingIfNeeded: (column + index * 8) / 5 + row / 6) }
    }
    let chroma = CVPixelBufferGetBaseAddressOfPlane(pixels, 1)!.assumingMemoryBound(to: UInt8.self)
    memset(chroma, 128, CVPixelBufferGetBytesPerRowOfPlane(pixels, 1) * 360)
    CVPixelBufferUnlockBaseAddress(pixels, [])
    return pixels
}

/// The host's WebRTC wiring end to end in one process: a viewer joins and asks for an offer, the
/// picture arrives as H.264 at 720p, the sound packets arrive whole, and the viewer's pad reaches
/// the game's bridge only once the host handed them a pad; the game's answer comes back.
@MainActor
final class SharePlayWiringTests: XCTestCase {
    struct TimedOut: Error {}

    func waitUntil(_ seconds: Double = 15, line: UInt = #line, _ condition: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end {
                XCTFail("timed out", line: line)
                throw TimedOut()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testAViewerSeesThePictureHearsTheSoundAndPlaysOnceAllowed() async throws {
        let bridges = Bridges()
        let router = SharePadRouter(bridges: bridges)
        let renderer = FrameCounter()
        let sounds = Locked<[Data]>([])
        let outputs = Locked<[Data]>([])
        var watcher: SharePlayWatcher!
        let host = SharePlayHost(iceServers: [], send: { to, device, signal in
            XCTAssertEqual(to, "viewer")
            XCTAssertEqual(device, "web")
            Task { @MainActor in watcher.receive(signal, from: "host", device: "mac") }
        }, onPad: { userId, packet in router.receive(packet, from: userId) })
        watcher = SharePlayWatcher(hostId: "host", hostDevice: "mac", iceServers: [], renderer: renderer, send: { to, device, signal in
            XCTAssertEqual(to, "host")
            XCTAssertEqual(device, "mac")
            Task { @MainActor in host.receive(signal, from: "viewer", device: "web") }
        }, onSound: { packet in sounds.withLock { $0.append(packet) } }, onPadOutput: { packet in outputs.withLock { $0.append(packet) } })
        defer {
            watcher.close()
            host.close()
        }

        // The game runs at 60 frames a second on its own thread (a loop of pictures made first).
        let pictures = (0 ..< 24).map(syntheticFrame)
        let pump = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "frames", qos: .userInteractive))
        let frameIndex = Locked(0)
        pump.schedule(deadline: .now(), repeating: .milliseconds(16))
        pump.setEventHandler {
            let index = frameIndex.withLock { value -> Int in
                value += 1
                return value
            }
            host.push(pictures[index % pictures.count], timeNs: Int64(DispatchTime.now().uptimeNanoseconds))
        }
        pump.resume()
        defer { pump.cancel() }

        watcher.start()
        try await waitUntil { watcher.state == .connected }
        try await waitUntil { renderer.count >= 30 }
        XCTAssertEqual(host.links["viewer"]?.state, .connected)
        // The game's 60 frames a second arrive at (nearly) that rate.
        let before = renderer.count
        try await Task.sleep(for: .seconds(1))
        let rate = renderer.count - before
        print("frames shown in a second:", rate, "size:", renderer.last)
        XCTAssertGreaterThanOrEqual(rate, 45)
        XCTAssertGreaterThanOrEqual(renderer.last.height, 360)
        XCTAssertEqual(Double(renderer.last.width) / Double(renderer.last.height), 16.0 / 9.0, accuracy: 0.02)
        let codec = Locked<String?>(nil)
        watcher.videoCodec { codec.value = $0 }
        try await waitUntil { codec.value != nil }
        XCTAssertEqual(codec.value?.lowercased(), "video/h264")

        // Sound: 5 ms packets, whole and as sent.
        let samples = Data((0 ..< 960).map { UInt8(truncatingIfNeeded: $0 * 7) })
        let packet = StreamPacket.audio(samples, number: 1, milliseconds: 5)
        try await waitUntil {
            host.push(sound: packet)
            return !sounds.value.isEmpty
        }
        XCTAssertEqual(sounds.value.first, packet)
        XCTAssertEqual(StreamPacket.Audio(sounds.value.first!)?.payload, samples)

        // The pad: nothing reaches the game until the host hands this viewer one.
        var input = Data(count: 80)
        for (offset, value) in [(0, UInt32(RemotePacket.inputMagic)), (8, 1), (32, 0x4000)] {
            input.replaceSubrange(offset ..< offset + 4, with: withUnsafeBytes(of: value.littleEndian) { Data($0) })
        }
        input.replaceSubrange(4 ..< 8, with: Data([1, 0, 80, 0]))
        input.replaceSubrange(24 ..< 32, with: withUnsafeBytes(of: UInt64(0xABCDEF).littleEndian) { Data($0) })
        input.replaceSubrange(36 ..< 42, with: Data([0, 255, 128, 128, 255, 10]))
        try await waitUntil { watcher.padOpen }
        for _ in 0 ..< 5 { watcher.sendPad(input) }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(bridges.sent.value.isEmpty)
        router.update(pads: ["viewer": 2])
        try await waitUntil {
            watcher.sendPad(input)
            return !bridges.sent.value.isEmpty
        }
        // As the viewer sent it, naming the pad the host gave.
        var seated = input
        seated[SharePadRouter.seatByte] = 2
        XCTAssertEqual(bridges.sent.value.first?.0, seated)
        XCTAssertEqual(bridges.sent.value.first?.1, 3)

        // The game's answer on that bridge goes back to the viewer.
        let output = Data([0x41, 0x50, 0x52, 0x4F, 1, 0, 32, 0] + [UInt8](repeating: 9, count: 24))
        try await waitUntil {
            host.sendPadOutput(output, to: "viewer")
            return !outputs.value.isEmpty
        }
        XCTAssertEqual(outputs.value.first, output)

        // Hanging up closes the viewer's side too.
        host.hangUp("viewer")
        try await waitUntil { watcher.state != .connected }
    }
}

/// A viewer asking for an offer while one waits for its answer gets the same one again; asking
/// once connected (a viewer that started over) gets a fresh connection.
@MainActor
final class SharePlayRenegotiateTests: XCTestCase {
    func testAskingAgainResendsThePendingOfferThenStartsOver() async throws {
        let offers = Locked<[String]>([])
        let host = SharePlayHost(iceServers: [], send: { _, _, signal in
            if case .offer(let sdp) = signal { offers.withLock { $0.append(sdp) } }
        }, onPad: { _, _ in })
        defer { host.close() }
        host.call("viewer", device: "web")
        let end = Date().addingTimeInterval(5)
        while offers.value.isEmpty, Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        host.receive(.renegotiate, from: "viewer", device: "web")
        while offers.value.count < 2, Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(offers.value.count, 2)
        // The same offer (its ICE credentials), now with the candidates gathered since.
        func ufrag(_ sdp: String) -> String? { sdp.components(separatedBy: "\r\n").first { $0.hasPrefix("a=ice-ufrag:") } }
        XCTAssertNotNil(ufrag(offers.value[0]))
        XCTAssertEqual(ufrag(offers.value[0]), ufrag(offers.value[1]))
        // Another device of the same viewer: a new connection, a new offer.
        host.receive(.renegotiate, from: "viewer", device: "phone")
        while offers.value.count < 3, Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(offers.value.count, 3)
        XCTAssertNotEqual(ufrag(offers.value[2]), ufrag(offers.value[0]))
    }
}
