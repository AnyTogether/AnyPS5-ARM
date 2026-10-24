import AnyPS5Core
import WebRTC
import XCTest
@testable import AnyPS5SharePlay

/// A test signal standing in for the game's sound: a different tone on each side, fed in real
/// time as the capture does (5 ms StreamPacket audio), and the decoded side pulled the same way.
final class SoundLoop: @unchecked Sendable {
    let leftHz = 440.0, rightHz = 1000.0, leftLevel = 0.5, rightLevel = 0.25
    private var start = DispatchTime.now()
    private var pushed = 0
    private var pulled = 0
    private var chunker = SoundChunker()
    private let heard = Locked<[Int16]>([])

    /// The last second the viewer's side played, interleaved.
    var lastSecond: [Int16] { heard.withLock { Array($0.suffix(96000)) } }

    func run(push: @escaping (Data) -> Void, pull: ((UnsafeMutablePointer<Int16>, Int) -> Void)?) {
        start = DispatchTime.now()
        running.value = true
        // A real-time thread of its own, as an audio device's: a busy Mac's timers wait too long.
        let thread = Thread { [self] in
            SoundLoop.makeRealTime()
            let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: 960)
            defer { scratch.deallocate() }
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            let period = UInt64(2_000_000) * UInt64(info.denom) / UInt64(info.numer)
            var next = mach_absolute_time()
            while running.value {
                tick(push: push, pull: pull, scratch: scratch)
                next += period
                mach_wait_until(next)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private let running = Locked(false)

    static func makeRealTime() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        func ticks(_ ms: Double) -> UInt32 { UInt32(ms * 1_000_000 * Double(info.denom) / Double(info.numer)) }
        var policy = thread_time_constraint_policy_data_t(period: ticks(2), computation: ticks(0.5), constraint: ticks(1), preemptible: 1)
        _ = withUnsafeMutablePointer(to: &policy) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: 4) {
                thread_policy_set(pthread_mach_thread_np(pthread_self()), thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0,
                                  mach_msg_type_number_t(4))
            }
        }
    }

    private func tick(push: (Data) -> Void, pull: ((UnsafeMutablePointer<Int16>, Int) -> Void)?, scratch: UnsafeMutablePointer<Int16>) {
        let now = DispatchTime.now().uptimeNanoseconds
        if lastTick > 0 { let ms = Double(now - lastTick) / 1e6; gap.withLock { $0 = max($0, ms) } }
        lastTick = now
        let due = Int(Double(now - start.uptimeNanoseconds) / 1e9 * 48000)
        while pushed + 240 <= due {
            var samples = [Int16](repeating: 0, count: 480)
            for frame in 0 ..< 240 {
                let t = Double(pushed + frame) / 48000
                samples[frame * 2] = Int16(sin(2 * .pi * leftHz * t) * leftLevel * 32767)
                samples[frame * 2 + 1] = Int16(sin(2 * .pi * rightHz * t) * rightLevel * 32767)
            }
            for packet in chunker.add(samples, at: Double(pushed) / 48000) { push(packet) }
            pushed += 240
        }
        guard let pull else { return }
        while pulled + 480 <= due {
            pull(scratch, 480)
            let block = Array(UnsafeBufferPointer(start: scratch, count: 960))
            heard.withLock { $0.append(contentsOf: block); if $0.count > 480000 { $0.removeFirst($0.count - 96000) } }
            pulled += 480
        }
    }

    func stop() { running.value = false }

    private let gap = Locked<Double>(0)
    private var lastTick: UInt64 = 0
    /// The longest wait between two ticks since asked last, milliseconds.
    func maxGap() -> Double { gap.withLock { value in defer { value = 0 }; return value } }

    /// Level and crossings a second of one side, to tell the tones apart.
    static func measure(_ samples: [Int16], side: Int) -> (rms: Double, hz: Double) {
        let values = stride(from: side, to: samples.count, by: 2).map { Double(samples[$0]) / 32768 }
        guard values.count > 1 else { return (0, 0) }
        let rms = (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
        var crossings = 0
        for index in 1 ..< values.count where (values[index - 1] < 0) != (values[index] < 0) { crossings += 1 }
        return (rms, Double(crossings) / 2 / (Double(values.count) / 48000))
    }
}

/// The game's sound end to end as Opus: a viewer that says hello gets the track (stereo, ~128
/// kbit/s, WebRTC's jitter buffer) and the PCM stops; one that does not stays on PCM.
@MainActor
final class SharePlayOpusTests: XCTestCase {
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

    private func connect(codecs: [ShareAudioCodec], sounds: Locked<Int>) -> (SharePlayHost, SharePlayWatcher) {
        var watcher: SharePlayWatcher!
        let host = SharePlayHost(iceServers: [], send: { _, _, signal in
            Task { @MainActor in watcher.receive(signal, from: "host", device: "mac") }
        }, onPad: { _, _ in })
        watcher = SharePlayWatcher(hostId: "host", hostDevice: "mac", iceServers: [], renderer: FrameCounter(), send: { _, _, signal in
            Task { @MainActor in host.receive(signal, from: "viewer", device: "web") }
        }, onSound: { _ in sounds.withLock { $0 += 1 } }, audio: codecs)
        return (host, watcher)
    }

    func testAViewerSayingHelloHearsStereoOpus() async throws {
        let sounds = Locked(0)
        let (host, watcher) = connect(codecs: [.opus, .pcm], sounds: sounds)
        let loop = SoundLoop()
        defer {
            loop.stop()
            watcher.close()
            host.close()
        }
        // Host and viewer share the one audio device in this process: what is pushed goes in as
        // the host's track, what is pulled is what the viewer's connection decoded.
        loop.run(push: { host.push(sound: $0) }, pull: { ShareWebRTC.audioDevice.pull($0, frames: UInt32($1)) })
        watcher.start()
        try await waitUntil { watcher.state == .connected }
        try await waitUntil { host.links["viewer"]?.audio == .opus }
        // PCM stops once the track is taken.
        try await Task.sleep(for: .milliseconds(500))
        let pcmThen = sounds.value
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(sounds.value, pcmThen, "PCM still arriving next to the track")

        let heard = loop.lastSecond
        let left = SoundLoop.measure(heard, side: 0), right = SoundLoop.measure(heard, side: 1)
        print("opus decoded: left", left, "right", right)
        // Each side its own tone at its own level: stereo, untouched by voice processing.
        XCTAssertEqual(left.hz, loop.leftHz, accuracy: 25)
        XCTAssertEqual(right.hz, loop.rightHz, accuracy: 40)
        XCTAssertEqual(left.rms, loop.leftLevel / 2.squareRoot(), accuracy: 0.06)
        XCTAssertEqual(right.rms, loop.rightLevel / 2.squareRoot(), accuracy: 0.04)

        let stats = Locked<SharePlayWatcher.AudioStatistics?>(nil)
        watcher.audioStatistics { stats.value = $0 }
        try await waitUntil { stats.value != nil }
        let first = try XCTUnwrap(stats.value)
        var previous = first
        var windows: [Double] = []
        for _ in 0 ..< 6 {
            try await Task.sleep(for: .seconds(1))
            stats.value = nil
            watcher.audioStatistics { stats.value = $0 }
            try await waitUntil { stats.value != nil }
            let window = stats.value!.bufferMs(since: previous) ?? 1000
            windows.append(window)
            print("window buffer ms:", window, "max tick gap ms:", loop.maxGap())
            previous = stats.value!
        }
        watcher.audioStatistics { stats.value = $0 }
        try await waitUntil { stats.value != first }
        let now = try XCTUnwrap(stats.value)
        let seconds = now.time - first.time
        let kbps = (now.bytes - first.bytes) * 8 / seconds / 1000
        let packetsPerSecond = (now.packets - first.packets) / seconds
        let buffer = now.bufferMs(since: first) ?? 1000
        let concealed = (now.concealed - first.concealed) / max(1, now.samples - first.samples)
        print("opus codec:", now.codec ?? "-", "channels:", now.channels ?? 0, "kbit/s:", kbps, "packets/s:", packetsPerSecond, "jitter buffer ms:", buffer,
              "since start:", now.bufferMs() ?? -1, "concealed:", concealed)
        XCTAssertEqual(now.codec?.lowercased(), "audio/opus")
        XCTAssertEqual(now.channels, 2)
        XCTAssertEqual(kbps, 128, accuracy: 30)
        // 10 ms frames, as the host's answer asks.
        XCTAssertEqual(packetsPerSecond, 100, accuracy: 15)
        // The jitter buffer's hold, second by second: under 60 ms most of the time (a busy Mac's
        // stall raises it for a while, as it would on a bad network).
        XCTAssertLessThan(windows.sorted()[windows.count / 2], 60, "per second: \(windows), overall \(buffer)")
        XCTAssertLessThan(concealed, 0.02)
        try await waitUntil { host.links["viewer"]?.audioRate != nil }
        print("host's audio rate:", host.links["viewer"]?.audioRate ?? 0)
    }

    func testAViewerWithoutHelloStaysOnPcm() async throws {
        let sounds = Locked(0)
        let (host, watcher) = connect(codecs: [], sounds: sounds)
        let loop = SoundLoop()
        defer {
            loop.stop()
            watcher.close()
            host.close()
        }
        loop.run(push: { host.push(sound: $0) }, pull: nil)
        watcher.start()
        try await waitUntil { watcher.state == .connected }
        try await waitUntil { sounds.value > 100 }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(host.links["viewer"]?.audio, .pcm)
        // 5 ms packets: about 200 a second.
        let before = sounds.value
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThan(sounds.value - before, 150)
        let stats = Locked<SharePlayWatcher.AudioStatistics??>(.none)
        watcher.audioStatistics { stats.value = .some($0) }
        try await waitUntil { stats.value != nil }
        XCTAssertNil(stats.value!, "an audio track without a hello")
    }
}
