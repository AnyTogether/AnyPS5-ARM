import AnyPS5Core
import CoreVideo
import WebRTC
import XCTest
@testable import AnyPS5SharePlay

/// The launcher's host against a real AnyTogether (API and gateway behind one address) and a real
/// viewer, such as the website in a browser: it signs in, starts share play, writes the share
/// play's ID for the viewer's side, sends a synthetic 60 fps picture and a tone, hands the first
/// viewer pad 2 once their link is up, keeps the pad packets that reach the game's bridge, takes
/// the pad back, and stops. Runs only when SHAREPLAY_INTEROP_BASE is set:
///   SHAREPLAY_INTEROP_BASE=http://127.0.0.1:8090 SHAREPLAY_INTEROP_EMAIL=utku@example.com
///   SHAREPLAY_INTEROP_LOG=<api log with the sign-in codes> SHAREPLAY_INTEROP_OUT=<folder>
@MainActor
final class SharePlayInteropTests: XCTestCase {
    struct TimedOut: Error { let what: String }

    func waitUntil(_ what: String, _ seconds: Double = 30, _ condition: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { throw TimedOut(what: what) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testTheHostAgainstARealServerAndViewer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let base = environment["SHAREPLAY_INTEROP_BASE"].flatMap(URL.init(string:)), let email = environment["SHAREPLAY_INTEROP_EMAIL"],
              let log = environment["SHAREPLAY_INTEROP_LOG"], let out = environment["SHAREPLAY_INTEROP_OUT"].map(URL.init(fileURLWithPath:)) else {
            throw XCTSkip("set SHAREPLAY_INTEROP_BASE, _EMAIL, _LOG and _OUT to run against a real server")
        }
        let note = { (line: String) in
            print("[host] \(line)")
            if let data = (line + "\n").data(using: .utf8), let handle = try? FileHandle(forWritingTo: out.appendingPathComponent("host.log")) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
        FileManager.default.createFile(atPath: out.appendingPathComponent("host.log").path, contents: Data())

        // Signed in with the code the API printed.
        let store = TokenStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("interop-\(UUID().uuidString).json"))
        let client = TogetherClient(base: base, store: store, clientName: "launcher-macos/interop")
        try await client.startEmail(email)
        try await Task.sleep(for: .milliseconds(500))
        let codes = try String(contentsOfFile: log, encoding: .utf8).matches(of: try Regex("code for \(email): (\\d{6})"))
        guard let code = codes.last.flatMap({ $0.output[1].substring }) else { return XCTFail("no sign-in code in the log") }
        let me = try await client.verifyEmail(email, code: String(code))
        note("signed in as \(me.handle)")

        // The bridge the viewer's pad would reach.
        final class Bridges: SharePadBridges, @unchecked Sendable {
            let sent = Locked<[Data]>([])
            func reservePadBridge() -> Int? { 3 }
            func releasePadBridge(_ bridge: Int) {}
            func sendPad(_ data: Data, bridge: Int) { sent.withLock { $0.append(data) } }
        }
        let bridges = Bridges()
        let router = SharePadRouter(bridges: bridges)
        let events = Locked<[TogetherSocket.Event]>([])
        let socket = TogetherSocket(client: client, onEvent: { event in events.withLock { $0.append(event) } }, onSignedOut: {})
        socket.start()
        defer { socket.stop() }
        try await Task.sleep(for: .seconds(1))

        let joined = try await client.startSharePlay(titleId: "PPSA01234", title: "Interop Quest", open: true, maxViewers: 2)
        let id = joined.sharePlay.id
        note("share play \(id) on device \(joined.sharePlay.hostDevice)")
        try JSONSerialization.data(withJSONObject: ["sharePlayId": id, "hostId": me.id]).write(to: out.appendingPathComponent("share.json"))

        let host = SharePlayHost(iceServers: joined.iceServers, send: { to, device, signal in
            note("→ \(signal.kind.rawValue) to \(to.prefix(8))")
            socket.signal(to: to, device: device, share: id, kind: signal.kind, data: signal.data)
        }, onPad: { userId, packet in router.receive(packet, from: userId) })
        defer { host.close() }

        // The game: a moving picture at 60 fps and a 440 Hz tone in 5 ms packets.
        let pictures = (0 ..< 24).map(syntheticFrame)
        let frameIndex = Locked(0)
        let pump = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "frames", qos: .userInteractive))
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
        var chunker = SoundChunker()
        var phase = 0.0
        let tone = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "tone", qos: .userInteractive))
        tone.schedule(deadline: .now(), repeating: .milliseconds(10))
        let started = Date()
        tone.setEventHandler {
            var samples = [Int16](repeating: 0, count: 480 * 2)
            for frame in 0 ..< 480 {
                let value = Int16(sin(phase) * 8000)
                samples[frame * 2] = value
                samples[frame * 2 + 1] = value
                phase += 2 * .pi * 440 / 48000
            }
            for packet in chunker.add(samples, at: Date().timeIntervalSince(started)) { host.push(sound: packet) }
        }
        tone.resume()
        defer { tone.cancel() }

        // Viewers as the server says: called when they come; signals handed to the host.
        var viewers: [TogetherSharePlay.Viewer] = []
        var handled = 0
        var granted: String?
        func drain() {
            let now = events.value
            for event in now.dropFirst(handled) {
                switch event.type {
                case "share_play.updated":
                    guard let sharePlay = event.decode(TogetherSharePlay.self), sharePlay.id == id else { continue }
                    let plan = SharePlayRoster.plan(from: viewers, to: sharePlay.viewers)
                    for userId in plan.hangUp { host.hangUp(userId, sayBye: false) }
                    for viewer in plan.call {
                        note("calling \(viewer.user.handle) on \(viewer.device.prefix(8))")
                        host.call(viewer.user.userId, device: viewer.device)
                    }
                    router.update(pads: SharePlayRoster.pads(sharePlay.viewers))
                    viewers = sharePlay.viewers
                case "share_play.signal":
                    guard let raw = event.decode(TogetherShareSignal.self), raw.sharePlayId == id, let signal = ShareSignal(raw) else { continue }
                    note("← \(raw.kind.rawValue) from \(raw.from.prefix(8))")
                    host.receive(signal, from: raw.from, device: raw.device)
                default:
                    break
                }
            }
            handled = now.count
        }

        try await waitUntil("a viewer connected", 90) {
            drain()
            return host.links.values.contains { $0.state == .connected }
        }
        let viewer = try XCTUnwrap(host.links.first { $0.value.state == .connected }?.key)
        note("viewer \(viewer.prefix(8)) connected")
        try await Task.sleep(for: .seconds(3))
        drain()
        XCTAssertTrue(bridges.sent.value.isEmpty, "no pad reaches the game before the host hands one over")
        _ = try await client.setSharePad(viewer, slot: 2, in: id)
        granted = viewer
        note("pad 2 handed to \(viewer.prefix(8))")
        try await waitUntil("pad packets from the viewer", 20) {
            drain()
            return bridges.sent.value.count >= 20
        }
        let packets = bridges.sent.value
        note("pad packets: \(packets.count); first bytes 32-41 \([UInt8](packets[0][32 ..< 42]))")
        try JSONSerialization.data(withJSONObject: ["count": packets.count, "packets": packets.prefix(240).map { $0.base64EncodedString() }])
            .write(to: out.appendingPathComponent("pads.json"))
        // A second of sending to measure the rate.
        let before = bridges.sent.value.count
        try await Task.sleep(for: .seconds(1))
        drain()
        let rate = bridges.sent.value.count - before
        note("pad packets in a second: \(rate)")
        try JSONSerialization.data(withJSONObject: ["rate": rate]).write(to: out.appendingPathComponent("pad-rate.json"))

        _ = try await client.setSharePad(viewer, slot: nil, in: id)
        try await Task.sleep(for: .milliseconds(800))
        drain()
        let afterRevoke = bridges.sent.value.count
        try await Task.sleep(for: .seconds(1))
        drain()
        let late = bridges.sent.value.count - afterRevoke
        note("pad packets reaching the game after the pad was taken back: \(late)")
        XCTAssertEqual(late, 0)
        try JSONSerialization.data(withJSONObject: ["late": late, "done": true]).write(to: out.appendingPathComponent("revoked.json"))
        _ = granted

        // Let the viewer's side look a little longer, then stop.
        try await Task.sleep(for: .seconds(Double(environment["SHAREPLAY_INTEROP_LINGER"] ?? "4") ?? 4))
        drain()
        if let link = host.links[viewer] { note("link: rtt \(link.roundTrip ?? -1) ms, \(link.frameHeight ?? 0)p\(Int(link.framesPerSecond ?? 0)), relayed \(link.relayed ?? false)") }
        try await client.endSharePlay(id)
        note("stopped")
    }
}
