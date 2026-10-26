import Darwin
import XCTest
@testable import AnyPS5Core

/// A headless browser for the tests: plain HTTP requests, and a WebSocket that masks its
/// frames as a browser does.
final class RawBrowser {
    let fd: Int32
    private var buffer = Data()

    init(port: UInt16) {
        fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    }

    deinit { close(fd) }

    func write(_ data: Data) { _ = data.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, data.count, 0) } }

    /// Reads more into the buffer; false once the socket closed (or after `seconds`).
    @discardableResult
    func fill(seconds: Double = 2) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while Date() < deadline {
            let got = recv(fd, &chunk, chunk.count, 0)
            if got > 0 {
                buffer.append(contentsOf: chunk.prefix(got))
                return true
            }
            if got == 0 { return false }
        }
        return false
    }

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    /// One whole request and its response (the server closes after each).
    static func get(_ port: UInt16, _ target: String, headers: [String: String] = [:], host: String? = nil) -> Response {
        let browser = RawBrowser(port: port)
        var head = "GET \(target) HTTP/1.1\r\nHost: \(host ?? "127.0.0.1:\(port)")\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        browser.write(Data((head + "\r\n").utf8))
        while browser.fill() {}
        return browser.response() ?? Response(status: 0, headers: [:], body: Data())
    }

    func response() -> Response? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)), let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let status = Int(lines.removeFirst().split(separator: " ")[1]) ?? 0
        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        let body = buffer[end.upperBound...]
        buffer = Data()
        return Response(status: status, headers: headers, body: Data(body))
    }

    /// Opens the page's WebSocket; the status the server answered with.
    func open(port: UInt16, origin: String?, cookie: String?) -> Int {
        var head = "GET /ws HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
        if let origin { head += "Origin: \(origin)\r\n" }
        if let cookie { head += "Cookie: \(cookie)\r\n" }
        write(Data((head + "\r\n").utf8))
        while buffer.range(of: Data("\r\n\r\n".utf8)) == nil { if !fill() { break } }
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)), let line = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { return 0 }
        buffer.removeSubrange(..<end.upperBound)
        return Int(line.split(separator: " ")[1]) ?? 0
    }

    func send(_ text: String) { write(WebSocketFrame.text(text).encoded(mask: [0x12, 0x34, 0x56, 0x78])) }

    /// The next text frame's JSON; nil when the socket closed or nothing came in `seconds`.
    func receive(seconds: Double = 3) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let (frame, used) = try? WebSocketFrame.decode(buffer, requireMask: false) {
                buffer.removeFirst(used)
                if frame.opcode == .close { return nil }
                if frame.opcode == .text { return try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] }
                continue
            }
            if !fill(seconds: max(0.01, deadline.timeIntervalSinceNow)) && (try? WebSocketFrame.decode(buffer, requireMask: false)) == nil {
                if Date() >= deadline { return nil }
            }
        }
        return nil
    }

    /// Waits for the page to be told it is player `number`.
    func becomes(player number: Int, seconds: Double = 4) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            guard let message = next("player", seconds: deadline.timeIntervalSinceNow) else { return false }
            if message["n"] as? Int == number { return true }
        }
        return false
    }

    /// Skips to the next message of `type`.
    func next(_ type: String, seconds: Double = 4) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            guard let message = receive(seconds: deadline.timeIntervalSinceNow) else { return nil }
            if message["t"] as? String == type { return message }
        }
        return nil
    }
}

final class BrowserPadServerTests: XCTestCase {
    var file: URL!
    var devices: PairedDevices!
    var log: EventLog!
    var remote: RemoteServer!
    var pads: BrowserPadServer!
    let page = Data("<!doctype html><title>pad</title>".utf8)

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("browser-\(UUID().uuidString).json")
        devices = PairedDevices(file: file)
        log = EventLog()
        remote = RemoteServer(name: "Test Mac", devices: devices, events: log.events, advertise: false)
        try remote.start()
        let remote = remote!
        pads = BrowserPadServer(host: "127.0.0.1", page: page, controlPort: remote.controlPort!, devices: devices, players: { remote.phonePlayers })
        try pads.start()
    }

    override func tearDown() async throws {
        pads.stop()
        remote.stop()
        try? FileManager.default.removeItem(at: file)
    }

    var port: UInt16 { pads.port! }
    var origin: String { "http://127.0.0.1:\(port)" }

    /// Scans the QR code: the cookie the token turns into.
    func scan() throws -> String {
        let url = try XCTUnwrap(pads.pairingURL)
        XCTAssertEqual(url.host, "127.0.0.1")
        let response = RawBrowser.get(port, "/?" + (url.query ?? ""), headers: ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)"])
        XCTAssertEqual(response.status, 303)
        XCTAssertEqual(response.headers["location"], "/")
        let cookie = try XCTUnwrap(response.headers["set-cookie"])
        return String(cookie.split(separator: ";")[0])
    }

    /// A browser through pairing to the welcome, the Mac's user allowing it.
    func joined(_ cookie: String, allow: Bool = true) throws -> RawBrowser {
        let browser = RawBrowser(port: port)
        XCTAssertEqual(browser.open(port: port, origin: origin, cookie: cookie), 101)
        let pairing = try XCTUnwrap(browser.next("pairing"))
        let code = try XCTUnwrap(pairing["code"] as? String)
        XCTAssertEqual(code.count, 4)
        let asked = expectation(description: "asked")
        Task {
            while !(self.log.pairings.contains { $0.code == code }) { try await Task.sleep(for: .milliseconds(10)) }
            asked.fulfill()
        }
        wait(for: [asked], timeout: 3)
        let request = try XCTUnwrap(log.pairings.last { $0.code == code })
        XCTAssertEqual(request.deviceName, "iPhone · Web", "the Mac's pairing card names the browser")
        remote.respond(to: request.id, allow: allow)
        return browser
    }

    func gameHello(player: UInt8) -> Data { Data([0x41, 0x50, 0x52, 0x48, 1, 0, 16, 0, player] + [UInt8](repeating: 0, count: 7)) }

    // MARK: End to end

    func testABrowserScansPairsAndDrivesTheGame() throws {
        let cookie = try scan()
        let pageLoad = RawBrowser.get(port, "/", headers: ["Cookie": cookie])
        XCTAssertEqual(pageLoad.status, 200)
        XCTAssertEqual(pageLoad.body, page)
        XCTAssertTrue(pageLoad.headers["content-security-policy"]?.contains("connect-src ws://127.0.0.1:\(port)") ?? false)
        XCTAssertEqual(pageLoad.headers["referrer-policy"], "no-referrer")

        let browser = try joined(cookie)
        XCTAssertEqual(try XCTUnwrap(browser.next("welcome"))["host"] as? String, "Test Mac")
        XCTAssertEqual(pads.connected.map(\.allowed), [true])
        XCTAssertTrue(devices.all.contains { $0.id.hasPrefix(BrowserPadAccess.devicePrefix) && $0.name == "iPhone · Web" })

        // The game on the first bridge: the browser is its phone.
        let game = UDPPeer()
        game.send(gameHello(player: 1), to: remote.bridgePorts[0])
        Thread.sleep(forTimeInterval: 0.1)
        browser.send(#"{"t":"pad","b":\#(SharePadState.Button.cross),"s":[10,20,30,40],"l2":0,"r2":200}"#)
        var packet: Data?
        for _ in 0..<10 {
            if let got = game.receive(), RemotePacket.inputSession(got) != nil {
                packet = got
                break
            }
        }
        let input = try XCTUnwrap(packet, "the pad reached the game")
        XCTAssertEqual(UInt32(input[32]) | UInt32(input[33]) << 8, SharePadState.Button.cross | SharePadState.Button.r2)
        XCTAssertEqual([UInt8](input[36..<42]), [10, 20, 30, 40, 0, 200])
        XCTAssertTrue(browser.becomes(player: 1))

        // The game's vibration and light bar come back to the page.
        var output = [UInt8](RemoteRelayTests.output)
        output[24] = 180
        output[25] = 0
        output[26] = 1
        output[27] = 0
        output[28] = 0x60
        output[29] = 0xFF
        let gameAddress = remote.bridgePorts[0]
        game.send(Data(output), to: gameAddress)
        let out = try XCTUnwrap(browser.next("out"))
        XCTAssertEqual(out["big"] as? Int, 180)
        XCTAssertEqual(out["rgb"] as? String, "#0060ff")

        // PS and Create are the launcher's, as on the phone app.
        browser.send(#"{"t":"btn","n":"ps"}"#)
        browser.send(#"{"t":"btn","n":"create"}"#)
        let heard = expectation(description: "requests")
        Task {
            while self.log.requests.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
            heard.fulfill()
        }
        wait(for: [heard], timeout: 3)
        XCTAssertEqual(log.requests, [.home, .command(name: "capture")])

        // Quiet page, held keys: the keep-alive repeats the pad, then lets go.
        var repeats = 0
        var released = false
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, !released {
            guard let got = game.receive(), RemotePacket.inputSession(got) != nil else { continue }
            if got[32] == 0 && got[33] == 0 { released = true } else { repeats += 1 }
        }
        XCTAssertGreaterThanOrEqual(repeats, 2)
        XCTAssertTrue(released, "a page gone quiet lets the buttons go")

        browser.send(#"{"t":"ping","at":123.5}"#)
        XCTAssertEqual(try XCTUnwrap(browser.next("pong"))["at"] as? Double, 123.5)
    }

    func testAReloadComesBackWithoutAskingAgain() throws {
        let cookie = try scan()
        let first = try joined(cookie)
        XCTAssertNotNil(first.next("welcome"))
        let again = RawBrowser(port: port)
        XCTAssertEqual(again.open(port: port, origin: origin, cookie: cookie), 101)
        XCTAssertNotNil(again.next("welcome"))
        XCTAssertEqual(log.pairings.count, 1, "the session's key let it straight in")
        XCTAssertNil(first.receive(seconds: 1), "the page it replaced is let go")
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(remote.connectedDeviceIDs.count, 1)
    }

    func testDeniedEndsTheSession() throws {
        let cookie = try scan()
        let browser = try joined(cookie, allow: false)
        XCTAssertEqual(try XCTUnwrap(browser.next("rejected"))["reason"] as? String, "denied")
        let again = RawBrowser(port: port)
        XCTAssertEqual(again.open(port: port, origin: origin, cookie: cookie), 403, "a refused browser scans again")
        XCTAssertFalse(devices.all.contains { $0.id.hasPrefix(BrowserPadAccess.devicePrefix) })
    }

    // MARK: Seats

    func testBrowsersTakeTheNextSeatsAfterThePhoneApp() throws {
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let phone = FakePhone(port: remote.controlPort!)
        let phoneWelcomed = expectation(description: "phone")
        Task {
            try await phone.hello(key: known.key)
            if case .welcome = try await phone.receive() { phoneWelcomed.fulfill() }
        }
        wait(for: [phoneWelcomed], timeout: 3)

        let first = try joined(try scan())
        XCTAssertNotNil(first.next("welcome"))
        // A second browser while nobody is being asked about: the next seat.
        let second = try joined(try scan())
        XCTAssertNotNil(second.next("welcome"))
        XCTAssertEqual(remote.phoneSlots, [0, 1, 2])

        // The game's third phone channel answers to the second browser alone.
        let games = (0..<3).map { _ in UDPPeer() }
        for (slot, game) in games.enumerated() { game.send(gameHello(player: UInt8(slot + 1)), to: remote.bridgePorts[slot]) }
        Thread.sleep(forTimeInterval: 0.1)
        second.send(#"{"t":"pad","b":\#(SharePadState.Button.triangle)}"#)
        var reached: Data?
        for _ in 0..<10 {
            if let got = games[2].receive(), RemotePacket.inputSession(got) != nil, got[33] != 0 || got[32] != 0 {
                reached = got
                break
            }
        }
        XCTAssertEqual(try XCTUnwrap(reached)[33], UInt8(SharePadState.Button.triangle >> 8))
        XCTAssertTrue(second.becomes(player: 3))
        phone.close()
    }

    func testABrowserWaitsWhileAnotherIsAskedAbout() throws {
        let firstCookie = try scan()
        let first = RawBrowser(port: port)
        XCTAssertEqual(first.open(port: port, origin: origin, cookie: firstCookie), 101)
        XCTAssertNotNil(first.next("pairing"))
        let second = RawBrowser(port: port)
        XCTAssertEqual(second.open(port: port, origin: origin, cookie: try scan()), 101)
        XCTAssertNotNil(second.next("busy"), "one new device is asked about at a time")
        remote.respond(to: log.pairings[0].id, allow: true)
        XCTAssertNotNil(first.next("welcome"))
        XCTAssertNotNil(second.next("pairing", seconds: 6), "then it is its turn")
    }

    func testEverySeatTaken() throws {
        var browsers: [RawBrowser] = []
        for _ in 0..<RemoteServer.maxPhones {
            let browser = try joined(try scan())
            XCTAssertNotNil(browser.next("welcome"))
            browsers.append(browser)
        }
        let late = RawBrowser(port: port)
        XCTAssertEqual(late.open(port: port, origin: origin, cookie: try scan()), 101)
        XCTAssertNotNil(late.next("busy"))
    }

    // MARK: Refused

    func testOtherOriginsAndHostsAreRefused() throws {
        let cookie = try scan()
        XCTAssertEqual(RawBrowser(port: port).open(port: port, origin: "http://evil.example", cookie: cookie), 403)
        XCTAssertEqual(RawBrowser(port: port).open(port: port, origin: nil, cookie: cookie), 403)
        XCTAssertEqual(RawBrowser(port: port).open(port: port, origin: origin, cookie: nil), 403)
        XCTAssertEqual(RawBrowser(port: port).open(port: port, origin: origin, cookie: "\(BrowserPadAccess.cookieName)=forged"), 403)
        XCTAssertEqual(RawBrowser.get(port, "/", host: "rebound.example:\(port)").status, 403)
        XCTAssertEqual(RawBrowser.get(port, "/", headers: ["Origin": "http://evil.example"]).status, 403)
        XCTAssertEqual(RawBrowser.get(port, "/admin").status, 404)
    }

    func testASpentOrWrongTokenGivesNoCookie() throws {
        let url = try XCTUnwrap(pads.pairingURL)
        XCTAssertEqual(RawBrowser.get(port, "/?" + url.query!).status, 303)
        let again = RawBrowser.get(port, "/?" + url.query!)
        XCTAssertEqual(again.status, 200, "the page, which then says to scan again")
        XCTAssertNil(again.headers["set-cookie"])
        XCTAssertNil(RawBrowser.get(port, "/?t=guess").headers["set-cookie"])
    }

    func testTokenGuessingIsSlowedDown() {
        let statuses = (0..<8).map { _ in RawBrowser.get(port, "/?t=guess\(Int.random(in: 0...999))").status }
        XCTAssertEqual(statuses.prefix(5), [200, 200, 200, 200, 200])
        XCTAssertEqual(statuses.last, 429)
    }

    func testRequestFloodsAreSlowedDown() {
        let statuses = (0..<40).map { _ in RawBrowser.get(port, "/").status }
        XCTAssertTrue(statuses.contains(429))
        XCTAssertEqual(statuses.first, 200)
    }

    func testStoppingEndsSessionsAndForgetsTheBrowsers() throws {
        let cookie = try scan()
        let browser = try joined(cookie)
        XCTAssertNotNil(browser.next("welcome"))
        pads.stop()
        XCTAssertNil(browser.receive(seconds: 1))
        XCTAssertFalse(devices.all.contains { $0.id.hasPrefix(BrowserPadAccess.devicePrefix) })
        XCTAssertTrue(pads.access.all.isEmpty)
        try pads.start()
        XCTAssertEqual(RawBrowser(port: port).open(port: port, origin: origin, cookie: cookie), 403)
    }

    func testTheLANAddressIsPrivate() {
        guard let address = BrowserPadServer.lanAddress() else { return }
        XCTAssertTrue(BrowserPadAccess.isLocal(address))
        XCTAssertFalse(address.hasPrefix("127."))
    }
}
