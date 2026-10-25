import CoreVideo
import XCTest
@testable import AnyPS5Core

final class BroadcastMediaTests: XCTestCase {
    /// 10 ms of a sine in both channels, interleaved.
    func sine(_ frames: Int, from start: Int, frequency: Double = 440, amplitude: Float = 0.5) -> [Float] {
        (0 ..< frames).flatMap { index -> [Float] in
            let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(start + index) / 48000))
            return [value, value]
        }
    }

    func pixels(_ width: Int, _ height: Int, frame: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        let base = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(buffer!)
        // A moving gradient, so the encoder has something to do.
        for y in 0 ..< height {
            for x in 0 ..< width {
                let pixel = base + y * row + x * 4
                pixel[0] = UInt8((x + frame * 4) & 0xFF)
                pixel[1] = UInt8((y + frame * 2) & 0xFF)
                pixel[2] = UInt8((x + y) & 0xFF)
                pixel[3] = 0xFF
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        return buffer!
    }

    // MARK: Mixer

    /// The game's sound in 10 ms pieces comes out as 1024-frame blocks, one after the other.
    func testTheGamesSoundIsCutIntoAACBlocks() {
        var mixer = BroadcastAudioMixer()
        var blocks: [BroadcastAudioMixer.Block] = []
        for piece in 0 ..< 100 {
            blocks += mixer.addGame(sine(480, from: piece * 480), at: 10 + Double(piece) * 0.01)
        }
        XCTAssertEqual(blocks.count, 48000 / 1024)
        XCTAssertTrue(blocks.allSatisfy { $0.samples.count == 2048 })
        for (index, block) in blocks.enumerated() {
            XCTAssertEqual(block.seconds, 10 + Double(index) * 1024 / 48000, accuracy: 1e-9)
        }
        XCTAssertEqual(blocks[1].samples, sine(1024, from: 1024), "the sound is passed on as it is")
    }

    /// The microphone is mixed over the game at its level, never past full scale.
    func testTheMicrophoneIsMixedAtItsLevel() {
        var mixer = BroadcastAudioMixer()
        mixer.microphoneLevel = 0.5
        XCTAssertEqual(mixer.addGame([Float](repeating: 0.2, count: 2048), at: 0).first?.samples[0], 0.2)
        XCTAssertEqual(mixer.addMicrophone([Float](repeating: 0.4, count: 2048), at: 0.02), [], "kept for the game's next block")
        let blocks = mixer.addGame([Float](repeating: 0.2, count: 2048), at: 1024 / 48000)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].samples[0], 0.4, accuracy: 1e-6)
        mixer.microphoneLevel = 1
        _ = mixer.addMicrophone([Float](repeating: 0.9, count: 2048), at: 0.05)
        XCTAssertEqual(mixer.addGame([Float](repeating: 0.9, count: 2048), at: 2048 / 48000).first?.samples[5], 1, "clipped, not wrapped")
        // Off: the microphone is not kept.
        mixer.microphoneLevel = 0
        XCTAssertEqual(mixer.addMicrophone([Float](repeating: 0.9, count: 2048), at: 0.07), [])
        XCTAssertEqual(mixer.addGame([Float](repeating: 0.1, count: 2048), at: 3072 / 48000).first?.samples[0], 0.1)
    }

    /// With the game silent the commentary still goes out, on its own clock.
    func testTheMicrophoneSpeaksWhileTheGameIsSilent() {
        var mixer = BroadcastAudioMixer()
        mixer.microphoneLevel = 1
        _ = mixer.addGame(sine(1024, from: 0), at: 5)
        var blocks: [BroadcastAudioMixer.Block] = []
        for piece in 0 ..< 50 {
            blocks += mixer.addMicrophone([Float](repeating: 0.25, count: 960), at: 6 + Double(piece) * 0.01)
        }
        XCTAssertGreaterThan(blocks.count, 18)
        XCTAssertEqual(blocks[0].samples[0], 0.25)
        XCTAssertEqual(blocks[0].seconds, 6, accuracy: 0.03)
        XCTAssertGreaterThan(blocks[1].seconds, blocks[0].seconds)
    }

    /// Sound that jumps (the game paused, the capture restarted) starts the clock again.
    func testAJumpInTheSoundRestartsTheClock() {
        var mixer = BroadcastAudioMixer()
        _ = mixer.addGame(sine(1500, from: 0), at: 1)
        let blocks = mixer.addGame(sine(1024, from: 0), at: 9)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].seconds, 9)
    }

    // MARK: Encoders

    /// AAC-LC at 160 kbit/s: one frame a block once the encoder is primed, each about 430 bytes,
    /// timed by the sound it holds.
    func testAACFramesComeOutTimedByTheirSound() throws {
        let encoder = try AACEncoder(sampleRate: 48000, channels: 2, bitRate: 160_000)
        XCTAssertEqual([UInt8](encoder.audioSpecificConfig), [0x11, 0x90])
        var frames: [AACEncoder.Frame] = []
        // Noise, which needs every bit it gets, as a game's sound does.
        var generator = SystemRandomNumberGenerator()
        for block in 0 ..< 94 {
            let noise = (0 ..< 2048).map { _ in Float.random(in: -0.5 ... 0.5, using: &generator) }
            frames += encoder.encode(noise, at: 3 + Double(block) * 1024 / 48000)
        }
        XCTAssertGreaterThanOrEqual(frames.count, 90)
        XCTAssertLessThanOrEqual(frames.count, 94)
        // 160 kbit/s is 427 bytes a frame.
        let average = frames.dropFirst(4).map(\.data.count).reduce(0, +) / (frames.count - 4)
        XCTAssertGreaterThan(average, 380)
        XCTAssertLessThan(average, 470)
        for (earlier, later) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(later.seconds - earlier.seconds, 1024.0 / 48000, accuracy: 1e-6)
        }
        XCTAssertLessThanOrEqual(frames[0].seconds, 3, "the primed start comes before the first block")
        XCTAssertNotEqual(frames[0].data.first, 0xFF, "raw frames, no ADTS header")
    }

    /// High profile, no B-frames, a key frame every two seconds with its parameter sets.
    func testTheVideoIsEncodedAsServicesAskForIt() {
        let frames = Locked<[BroadcastVideoEncoder.Frame]>([])
        let encoder = BroadcastVideoEncoder(bitRate: 3_000_000, frameRate: 60) { frame in frames.withLock { $0.append(frame) } }
        let shared = pixels(640, 360, frame: 0)
        for index in 0 ..< 130 {
            encoder.encode(index % 10 == 0 ? pixels(640, 360, frame: index) : shared, at: 100 + Double(index) / 60)
        }
        encoder.flush()
        let made = frames.value
        XCTAssertEqual(made.count, 130)
        XCTAssertEqual(made.indices.filter { made[$0].key }, [0, 120])
        XCTAssertEqual(made[0].parameterSets.count, 2)
        XCTAssertEqual(made[0].parameterSets[0][1], 100, "profile_idc 100: High")
        XCTAssertEqual(made[0].parameterSets[0][0] & 0x1F, 7)
        XCTAssertEqual(made[0].parameterSets[1][0] & 0x1F, 8)
        XCTAssertTrue(made[1].parameterSets.isEmpty)
        for (index, frame) in made.enumerated() {
            XCTAssertEqual(frame.seconds, 100 + Double(index) / 60, accuracy: 1e-4, "in the order given: nothing reordered")
        }
        // AVCC: the first unit's length then the unit.
        let units = [UInt8](made[0].units)
        let length = Int(units[0]) << 24 | Int(units[1]) << 16 | Int(units[2]) << 8 | Int(units[3])
        XCTAssertLessThanOrEqual(length + 4, units.count)
        XCTAssertNotEqual(Array(units.prefix(4)), [0, 0, 0, 1], "not a start code")
    }

    /// A 60 Hz capture for a 30 fps preset: every other frame is left out.
    func testFramesBeyondThePresetsRateAreLeftOut() {
        let count = Locked(0)
        let encoder = BroadcastVideoEncoder(bitRate: 4_500_000, frameRate: 30) { _ in count.withLock { $0 += 1 } }
        let frame = pixels(320, 180, frame: 0)
        for index in 0 ..< 60 { encoder.encode(frame, at: Double(index) / 60) }
        encoder.flush()
        XCTAssertEqual(count.value, 30)
        XCTAssertEqual(encoder.framesSkipped, 30)
    }

    // MARK: End to end

    /// Three seconds of a game broadcast to the local server, as a file ffprobe reads back as
    /// H.264 High at 1280 x 720 and AAC at 48 kHz stereo.
    func testABroadcastReachesTheServerAsAPlayableStream() throws {
        let server = try FakeRTMPServer()
        let states = Locked<[RTMPPublisher.State]>([])
        let session = BroadcastSession(endpoint: RTMPEndpoint(tls: false, host: "127.0.0.1", port: server.port, app: "live", streamKey: "key"),
                                       quality: .hd720p60, onState: { state in states.withLock { $0.append(state) } })
        session.start()
        let deadline = Date().addingTimeInterval(10)
        while !states.value.contains(.live), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(states.value.contains(.live))
        let still = pixels(1280, 720, frame: 0)
        for index in 0 ..< 180 {
            let time = 50 + Double(index) / 60
            session.video(index % 6 == 0 ? pixels(1280, 720, frame: index) : still, at: time)
            // 800 frames of sound a video frame: 48 kHz at 60 frames a second.
            session.gameAudio(sine(800, from: index * 800), at: time)
        }
        XCTAssertTrue(server.wait(15) { ($0.first?.media.filter { $0.kind == .video }.count ?? 0) >= 170 && ($0.first?.media.filter { $0.kind == .audio }.count ?? 0) >= 130 })
        let stats = session.stats()
        XCTAssertEqual(stats.state, .live)
        XCTAssertGreaterThanOrEqual(stats.framesSent, 170)
        XCTAssertEqual(stats.framesDropped, 0)
        let stopped = expectation(description: "stopped")
        session.stop { stopped.fulfill() }
        wait(for: [stopped], timeout: 5)

        let received = try XCTUnwrap(server.sessions.first)
        XCTAssertEqual(received.problems, [])
        let video = received.media.filter { $0.kind == .video }
        XCTAssertEqual(Array(video[0].payload.prefix(2)), [0x17, 0x00])
        XCTAssertEqual(Array(video[1].payload.prefix(2)), [0x17, 0x01])
        XCTAssertTrue(zip(video.dropFirst(), video.dropFirst(2)).allSatisfy { $0.timestamp <= $1.timestamp })
        let audio = received.media.filter { $0.kind == .audio }
        XCTAssertEqual([UInt8](audio[0].payload), [0xAF, 0x00, 0x11, 0x90])
        XCTAssertTrue(zip(audio.dropFirst(), audio.dropFirst(2)).allSatisfy { $1.timestamp > $0.timestamp })

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("anyps5-broadcast-\(UUID().uuidString).flv")
        try server.flv(received).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let ffprobe = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("no ffprobe to read the stream back")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = ["-v", "error", "-count_packets", "-show_entries", "stream=codec_name,profile,width,height,sample_rate,channels,nb_read_packets", "-of", "json", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let json = try JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [String: Any]
        let streams = try XCTUnwrap(json?["streams"] as? [[String: Any]])
        let h264 = try XCTUnwrap(streams.first { $0["codec_name"] as? String == "h264" })
        XCTAssertEqual(h264["profile"] as? String, "High")
        XCTAssertEqual(h264["width"] as? Int, 1280)
        XCTAssertEqual(h264["height"] as? Int, 720)
        XCTAssertGreaterThanOrEqual(Int(h264["nb_read_packets"] as? String ?? "") ?? 0, 170)
        let aac = try XCTUnwrap(streams.first { $0["codec_name"] as? String == "aac" })
        XCTAssertEqual(aac["profile"] as? String, "LC")
        XCTAssertEqual(aac["sample_rate"] as? String, "48000")
        XCTAssertEqual(aac["channels"] as? Int, 2)
    }

    /// The same broadcast to ffmpeg's own RTMP server (`ffmpeg -listen 1`), a real implementation
    /// rather than the test's: run with ANYPS5_INTEROP=1 where ffmpeg is installed.
    func testFFmpegsRTMPServerTakesTheBroadcast() throws {
        guard ProcessInfo.processInfo.environment["ANYPS5_INTEROP"] == "1",
              let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("set ANYPS5_INTEROP=1 with ffmpeg installed")
        }
        let port = UInt16.random(in: 20000 ... 40000)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("anyps5-interop-\(UUID().uuidString).flv")
        defer { try? FileManager.default.removeItem(at: file) }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: ffmpeg)
        server.arguments = ["-v", "error", "-listen", "1", "-timeout", "10", "-i", "rtmp://127.0.0.1:\(port)/live/key", "-c", "copy", "-f", "flv", file.path]
        try server.run()
        defer { if server.isRunning { server.terminate() } }
        Thread.sleep(forTimeInterval: 1)
        let states = Locked<[RTMPPublisher.State]>([])
        let session = BroadcastSession(endpoint: RTMPEndpoint(tls: false, host: "127.0.0.1", port: port, app: "live", streamKey: "key"),
                                       quality: .hd720p60, onState: { state in states.withLock { $0.append(state) } })
        session.start()
        let deadline = Date().addingTimeInterval(10)
        while !states.value.contains(.live), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(states.value.contains(.live), "\(states.value)")
        let still = pixels(1280, 720, frame: 0)
        for index in 0 ..< 120 {
            let time = 7 + Double(index) / 60
            session.video(index % 6 == 0 ? pixels(1280, 720, frame: index) : still, at: time)
            session.gameAudio(sine(800, from: index * 800), at: time)
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let stopped = expectation(description: "stopped")
        session.stop { stopped.fulfill() }
        wait(for: [stopped], timeout: 5)
        let end = Date().addingTimeInterval(10)
        while server.isRunning, Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertFalse(server.isRunning, "ffmpeg ends with the stream")
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: ffmpeg.replacingOccurrences(of: "ffmpeg", with: "ffprobe"))
        probe.arguments = ["-v", "error", "-count_packets", "-show_entries", "stream=codec_name,nb_read_packets", "-of", "csv=p=0", file.path]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try probe.run()
        probe.waitUntilExit()
        let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
        let video = lines.first { $0.hasPrefix("h264,") }.flatMap { Int($0.split(separator: ",")[1]) } ?? 0
        let audio = lines.first { $0.hasPrefix("aac,") }.flatMap { Int($0.split(separator: ",")[1]) } ?? 0
        XCTAssertGreaterThanOrEqual(video, 110, "\(lines)")
        XCTAssertGreaterThanOrEqual(audio, 80, "\(lines)")
    }
}
