import Darwin
import XCTest
@testable import AnyPS5Core

/// Discord's side of its local socket, for the tests: it reads frames and answers each one.
final class FakeDiscord: @unchecked Sendable {
    let directory: URL
    private let listener: Int32
    private let lock = NSLock()
    private var received: [(UInt32, [String: Any])] = []

    init() throws {
        directory = URL(fileURLWithPath: "/tmp/anyps5-discord-\(UInt32.random(in: 0...UInt32.max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = directory.appendingPathComponent("discord-ipc-0").path
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            _ = path.utf8CString.withUnsafeBytes { raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(raw.count))) }
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(listener, 1) == 0 else { throw URLError(.cannotOpenFile) }
        Thread.detachNewThread { [self] in serve() }
    }

    deinit {
        close(listener)
        try? FileManager.default.removeItem(at: directory)
    }

    var frames: [(UInt32, [String: Any])] { lock.withLock { received } }

    private func serve() {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        while true {
            var header = [UInt8](repeating: 0, count: 8)
            guard recv(client, &header, 8, MSG_WAITALL) == 8 else { break }
            let op = UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24
            let length = Int(UInt32(header[4]) | UInt32(header[5]) << 8 | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
            var body = [UInt8](repeating: 0, count: length)
            guard recv(client, &body, length, MSG_WAITALL) == length else { break }
            let json = (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any] ?? [:]
            lock.withLock { received.append((op, json)) }
            let answer = op == 0 ? #"{"cmd":"DISPATCH","evt":"READY","data":{}}"# : #"{"cmd":"SET_ACTIVITY","evt":null,"data":{}}"#
            let frame = DiscordFrame.encode(op: 1, json: Data(answer.utf8))
            _ = frame.withUnsafeBytes { send(client, $0.baseAddress, frame.count, 0) }
        }
        close(client)
    }

    func waitFor(_ count: Int) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if frames.count >= count { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }
}

final class DiscordPresenceTests: XCTestCase {
    func testFrameRoundTrip() {
        let frame = DiscordFrame.encode(op: 1, json: Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(Array(frame.prefix(8)), [1, 0, 0, 0, 7, 0, 0, 0])
        XCTAssertEqual(DiscordFrame.decode(frame)?.op, 1)
        XCTAssertEqual(DiscordFrame.decode(frame).map { String(decoding: $0.json, as: UTF8.self) }, #"{"a":1}"#)
        XCTAssertNil(DiscordFrame.decode(frame.prefix(9)))
    }

    func testHandshakeThenActivity() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        presence.playing("Hollow Knight: Silksong", since: started)
        XCTAssertTrue(discord.waitFor(2))
        let (handshakeOp, handshake) = discord.frames[0]
        XCTAssertEqual(handshakeOp, 0)
        XCTAssertEqual(handshake["client_id"] as? String, "1234")
        XCTAssertEqual(handshake["v"] as? Int, 1)
        let (activityOp, command) = discord.frames[1]
        XCTAssertEqual(activityOp, 1)
        XCTAssertEqual(command["cmd"] as? String, "SET_ACTIVITY")
        let arguments = command["args"] as? [String: Any]
        XCTAssertEqual(arguments?["pid"] as? Int, Int(ProcessInfo.processInfo.processIdentifier))
        let activity = arguments?["activity"] as? [String: Any]
        XCTAssertEqual(activity?["details"] as? String, "Hollow Knight: Silksong")
        XCTAssertEqual((activity?["timestamps"] as? [String: Any])?["start"] as? Int, 1_800_000_000)
        XCTAssertEqual((activity?["assets"] as? [String: Any])?["large_image"] as? String, "anyps5")
        presence.close()
    }

    func testClearRemovesTheActivity() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "1234", directory: discord.directory)
        presence.playing("Stray", since: Date())
        presence.clear()
        XCTAssertTrue(discord.waitFor(3))
        let arguments = discord.frames[2].1["args"] as? [String: Any]
        XCTAssertEqual(discord.frames[2].1["cmd"] as? String, "SET_ACTIVITY")
        XCTAssertTrue(arguments?["activity"] is NSNull)
        XCTAssertEqual(discord.frames.filter { $0.0 == 0 }.count, 1, "one handshake per connection")
        presence.close()
    }

    func testWithoutDiscordNothingHappens() {
        let empty = URL(fileURLWithPath: "/tmp/anyps5-no-discord-\(UInt32.random(in: 0...UInt32.max))")
        let presence = DiscordPresence(applicationID: "1234", directory: empty)
        presence.playing("Stray", since: Date())
        presence.clear()
        presence.close()
    }

    func testNoApplicationIDIsOff() throws {
        let discord = try FakeDiscord()
        let presence = DiscordPresence(applicationID: "", directory: discord.directory)
        presence.playing("Stray", since: Date())
        XCTAssertFalse(discord.waitFor(1))
        presence.close()
    }
}
