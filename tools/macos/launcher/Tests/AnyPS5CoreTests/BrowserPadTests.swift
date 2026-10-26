import XCTest
@testable import AnyPS5Core

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { time } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
    var read: @Sendable () -> Date { { [self] in now } }
}

final class BrowserPadAccessTests: XCTestCase {
    let clock = TestClock()
    lazy var access = BrowserPadAccess(clock: clock.read)

    func testATokenIsGoodOnceAndBecomesASession() throws {
        let token = access.currentToken()
        XCTAssertGreaterThanOrEqual(token.value.count, 22)
        XCTAssertEqual(access.currentToken(), token, "the QR code keeps its token while it is good")
        let session = try XCTUnwrap(access.redeem(token.value, deviceName: "iPhone · Web"))
        XCTAssertTrue(session.deviceID.hasPrefix(BrowserPadAccess.devicePrefix))
        XCTAssertNil(session.key)
        XCTAssertNil(access.redeem(token.value, deviceName: "iPhone · Web"), "a second phone with the same link gets nothing")
        XCTAssertNotEqual(access.currentToken(), token, "the QR code shows a new token once it is spent")
    }

    func testATokenExpires() {
        let token = access.currentToken()
        clock.advance(BrowserPadAccess.tokenLifetime + 1)
        XCTAssertNil(access.redeem(token.value, deviceName: "Phone"))
        XCTAssertNotEqual(access.currentToken(), token)
    }

    func testAWrongOrRenewedTokenIsRefused() {
        let token = access.currentToken()
        XCTAssertNil(access.redeem(token.value + "x", deviceName: "Phone"))
        XCTAssertNil(access.redeem("", deviceName: "Phone"))
        access.renewToken()
        XCTAssertNil(access.redeem(token.value, deviceName: "Phone"))
    }

    func testTheCookieIsBoundToTheRedeemedSession() throws {
        let session = try XCTUnwrap(access.redeem(access.currentToken().value, deviceName: "Phone"))
        let cookie = BrowserPadAccess.setCookie(session)
        XCTAssertTrue(cookie.hasPrefix("\(BrowserPadAccess.cookieName)=\(session.id);"))
        XCTAssertTrue(cookie.contains("HttpOnly"))
        XCTAssertTrue(cookie.contains("SameSite=Strict"))
        XCTAssertEqual(access.session(cookieHeader: "theme=dark; \(BrowserPadAccess.cookieName)=\(session.id)")?.deviceID, session.deviceID)
        XCTAssertNil(access.session(cookieHeader: "\(BrowserPadAccess.cookieName)=\(session.id)x"))
        XCTAssertNil(access.session(cookieHeader: nil))
        XCTAssertNil(access.session(cookieHeader: "other=\(session.id)"))
    }

    func testAnIdleSessionEndsButAConnectedOneStays() throws {
        let idle = try XCTUnwrap(access.redeem(access.currentToken().value, deviceName: "A"))
        let playing = try XCTUnwrap(access.redeem(access.currentToken().value, deviceName: "B"))
        access.setConnected(true, for: playing.id)
        clock.advance(BrowserPadAccess.sessionIdle + 1)
        XCTAssertEqual(access.expireIdle().map(\.id), [idle.id])
        XCTAssertNotNil(access.session(id: playing.id))
    }

    func testSessionsAreLimitedAndTheOldestIdleOneGivesWay() throws {
        var first: BrowserPadAccess.Session?
        for index in 0..<BrowserPadAccess.maxSessions {
            let session = try XCTUnwrap(access.redeem(access.currentToken().value, deviceName: "\(index)"))
            if index == 0 { first = session }
            clock.advance(1)
        }
        XCTAssertNotNil(access.redeem(access.currentToken().value, deviceName: "late"))
        XCTAssertNil(access.session(id: first!.id))
        for session in access.all { access.setConnected(true, for: session.id) }
        XCTAssertNil(access.redeem(access.currentToken().value, deviceName: "full"), "with every session playing there is no room")
    }

    func testOnlyThisSiteIsAllowed() {
        let host = "192.168.1.20"
        XCTAssertTrue(BrowserPadAccess.allowed(origin: "http://192.168.1.20:47710", host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: true))
        XCTAssertTrue(BrowserPadAccess.allowed(origin: nil, host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: false), "a plain page load has no Origin")
        XCTAssertFalse(BrowserPadAccess.allowed(origin: nil, host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: true), "a WebSocket without Origin")
        XCTAssertFalse(BrowserPadAccess.allowed(origin: "http://evil.example", host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: true))
        XCTAssertFalse(BrowserPadAccess.allowed(origin: "https://192.168.1.20:47710", host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: true))
        XCTAssertFalse(BrowserPadAccess.allowed(origin: "http://192.168.1.20:47711", host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: true))
        XCTAssertFalse(BrowserPadAccess.allowed(origin: "null", host: "192.168.1.20:47710", serverHost: host, port: 47710, requireOrigin: true))
        XCTAssertFalse(BrowserPadAccess.allowed(origin: "http://rebound.example:47710", host: "rebound.example:47710", serverHost: host, port: 47710, requireOrigin: true), "DNS rebinding")
        XCTAssertFalse(BrowserPadAccess.allowed(origin: nil, host: nil, serverHost: host, port: 47710, requireOrigin: false))
    }

    func testOnlyLocalPeersAreLocal() {
        for address in ["192.168.0.4", "10.1.2.3", "172.16.0.1", "172.31.255.1", "169.254.3.3", "127.0.0.1", "::ffff:192.168.1.9", "fe80::1%en0", "fd12::4", "::1"] {
            XCTAssertTrue(BrowserPadAccess.isLocal(address), address)
        }
        for address in ["8.8.8.8", "172.32.0.1", "100.64.1.1", "2001:db8::1", "::ffff:1.1.1.1", "nonsense"] {
            XCTAssertFalse(BrowserPadAccess.isLocal(address), address)
        }
    }

    func testDeviceNamesFromTheUserAgent() {
        XCTAssertEqual(BrowserPadAccess.deviceName(userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"), "iPhone · Web")
        XCTAssertEqual(BrowserPadAccess.deviceName(userAgent: "Mozilla/5.0 (Linux; Android 15; Pixel 9) Chrome/130 Mobile"), "Android · Web")
        XCTAssertEqual(BrowserPadAccess.deviceName(userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Mobile/15E148"), "iPad · Web")
        XCTAssertEqual(BrowserPadAccess.deviceName(userAgent: nil), "Phone · Web")
    }

    func testTheRateLimiterRefills() {
        let limiter = RateLimiter(capacity: 3, perSecond: 1, clock: clock.read)
        XCTAssertTrue(limiter.allow("a"))
        XCTAssertTrue(limiter.allow("a"))
        XCTAssertTrue(limiter.allow("a"))
        XCTAssertFalse(limiter.allow("a"))
        XCTAssertTrue(limiter.allow("b"), "another peer has its own bucket")
        clock.advance(1)
        XCTAssertTrue(limiter.allow("a"))
        XCTAssertFalse(limiter.allow("a"))
    }
}

final class BrowserPadInputTests: XCTestCase {
    typealias B = SharePadState.Button

    func pad(_ text: String) -> SharePadState? {
        guard case .pad(let state)? = BrowserPadMessage.parse(text) else { return nil }
        return state
    }

    func testAPadMessageBecomesThePadState() throws {
        let state = try XCTUnwrap(pad(#"{"t":"pad","b":\#(B.cross | B.up | B.l1),"s":[0,255,128,64],"l2":0,"r2":0}"#))
        XCTAssertEqual(state.buttons, B.cross | B.up | B.l1)
        XCTAssertEqual(state.sticks, [0, 255, 128, 64])
        XCTAssertEqual(state.l2, 0)
        XCTAssertEqual(state.r2, 0)
        XCTAssertEqual(state.touches, [])
    }

    func testValuesAreClampedAndForeignBitsDropped() throws {
        let state = try XCTUnwrap(pad(#"{"t":"pad","b":\#(0xFFFF_FFFF),"s":[-40,999,127.6,12],"l2":300,"r2":-3}"#))
        XCTAssertEqual(state.buttons, BrowserPadMessage.buttonMask)
        XCTAssertEqual(state.sticks, [0, 255, 128, 12])
        XCTAssertEqual(state.l2, 255)
        XCTAssertEqual(state.r2, 255, "R2's button held is a full pull")
    }

    func testTriggersAndTheirButtonsAgree() throws {
        let pulled = try XCTUnwrap(pad(#"{"t":"pad","b":0,"l2":90}"#))
        XCTAssertEqual(pulled.buttons, B.l2)
        XCTAssertEqual(pulled.l2, 90)
        XCTAssertEqual(pulled.sticks, [128, 128, 128, 128], "sticks left out are centred")
        let pressed = try XCTUnwrap(pad(#"{"t":"pad","b":\#(B.r2)}"#))
        XCTAssertEqual(pressed.r2, 255)
    }

    func testTouchpadFingers() throws {
        let state = try XCTUnwrap(pad(#"{"t":"pad","b":\#(B.touchPad),"tp":[[3,100,2000],[4,5000,-1],[5,1,1]]}"#))
        XCTAssertEqual(state.touches, [.init(id: 3, x: 100, y: 1079), .init(id: 4, x: 1919, y: 0)])
        let packet = state.packet(sequence: 1, sentMicros: 2, session: 3)
        XCTAssertEqual(packet[44], 1)
        XCTAssertEqual(packet[45], 3)
        XCTAssertEqual(UInt16(packet[46]) | UInt16(packet[47]) << 8, 100)
        XCTAssertEqual(UInt16(packet[48]) | UInt16(packet[49]) << 8, 1079)
        XCTAssertEqual(packet[50], 1)
        XCTAssertEqual(packet[51], 4)
    }

    func testThePadStateIsTheEnginesPacket() throws {
        let state = try XCTUnwrap(pad(#"{"t":"pad","b":\#(B.options),"s":[1,2,3,4],"l2":5,"r2":6}"#))
        let packet = state.packet(sequence: 7, sentMicros: 8, session: 0xDEAD_BEEF_0102_0304)
        XCTAssertEqual(RemotePacket.inputSession(packet), 0xDEAD_BEEF_0102_0304)
        XCTAssertEqual(UInt32(packet[32]) | UInt32(packet[33]) << 8, B.options | B.l2 | B.r2)
        XCTAssertEqual([UInt8](packet[36..<42]), [1, 2, 3, 4, 5, 6])
    }

    func testOtherMessages() {
        XCTAssertEqual(BrowserPadMessage.parse(#"{"t":"btn","n":"ps"}"#), .button("ps"))
        XCTAssertEqual(BrowserPadMessage.parse(#"{"t":"btn","n":"create"}"#), .button("create"))
        XCTAssertNil(BrowserPadMessage.parse(#"{"t":"btn","n":"launch"}"#))
        XCTAssertEqual(BrowserPadMessage.parse(#"{"t":"ping","at":12.5}"#), .ping(12.5))
        XCTAssertEqual(BrowserPadMessage.parse(#"{"t":"lat","ms":14}"#), .latency(14))
        XCTAssertNil(BrowserPadMessage.parse(#"{"t":"lat","ms":-1}"#))
    }

    func testBrokenMessagesAreDropped() {
        for text in ["", "nope", "[]", #"{"t":"pad"}"#, #"{"t":"pad","b":"1"}"#, #"{"t":"pad","b":true}"#, #"{"t":"pad","b":1,"s":[1,2,3]}"#,
                     #"{"t":"pad","b":1,"s":[1,2,3,"x"]}"#, #"{"t":"what"}"#, #"{"b":1}"#, #"{"t":"pad","b":-1}"#,
                     #"{"t":"pad","b":1,"pad":""# + String(repeating: "x", count: 5000) + #""}"#] {
            XCTAssertNil(BrowserPadMessage.parse(text), text)
        }
    }

    func testTheGamesOutputForThePage() {
        var bytes = [UInt8](repeating: 0, count: RemotePacket.outputSize)
        withUnsafeBytes(of: RemotePacket.outputMagic.littleEndian) { bytes.replaceSubrange(0..<4, with: $0) }
        bytes[4] = 1
        bytes[6] = UInt8(RemotePacket.outputSize)
        bytes[24] = 200
        bytes[25] = 30
        XCTAssertEqual(BrowserPadReply.output(Data(bytes))?.text, #"{"big":200,"small":30,"t":"out"}"#)
        bytes[26] = 1
        bytes[27] = 0x10
        bytes[28] = 0x80
        bytes[29] = 0xFF
        XCTAssertEqual(BrowserPadReply.output(Data(bytes))?.text, ##"{"big":200,"rgb":"#1080ff","small":30,"t":"out"}"##)
        XCTAssertNil(BrowserPadReply.output(Data(bytes.prefix(20))))
    }
}

final class BrowserPadWireTests: XCTestCase {
    func testARequestHead() throws {
        let raw = Data("GET /?t=abc HTTP/1.1\r\nHost: 10.0.0.2:47710\r\nCookie: a=1\r\nCookie: b=2\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\nrest".utf8)
        let (request, used) = try XCTUnwrap(HTTPRequest.parse(raw))
        XCTAssertEqual(used, raw.count - 4)
        XCTAssertEqual(request.path, "/")
        XCTAssertEqual(BrowserPadAccess.query("t", in: request.target), "abc")
        XCTAssertEqual(request.header("HOST"), "10.0.0.2:47710")
        XCTAssertEqual(request.header("cookie"), "a=1; b=2")
        XCTAssertTrue(request.isUpgrade)
        XCTAssertEqual(HTTPRequest.acceptKey("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "RFC 6455's example")
        XCTAssertNil(try HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data("NOT HTTP\r\n\r\n".utf8)))
        XCTAssertThrowsError(try HTTPRequest.parse(Data(repeating: 0x41, count: HTTPRequest.maxHead + 1)))
    }

    func testFramesBothWays() throws {
        let frame = WebSocketFrame.text(#"{"t":"pad","b":1}"#)
        let masked = frame.encoded(mask: [1, 2, 3, 4])
        let (decoded, used) = try XCTUnwrap(WebSocketFrame.decode(masked + Data([0x81])))
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(used, masked.count)
        XCTAssertNil(try WebSocketFrame.decode(masked.prefix(masked.count - 1)), "half a frame waits for the rest")
        let long = WebSocketFrame(opcode: .binary, payload: Data(repeating: 7, count: 300))
        XCTAssertEqual(try WebSocketFrame.decode(long.encoded(mask: [9, 9, 9, 9]))?.0, long)
        XCTAssertEqual(try WebSocketFrame.decode(long.encoded(), requireMask: false)?.0, long)
    }

    func testFramesThatBreakTheRules() {
        XCTAssertThrowsError(try WebSocketFrame.decode(WebSocketFrame.text("x").encoded()), "a browser's frame is masked")
        XCTAssertThrowsError(try WebSocketFrame.decode(WebSocketFrame(opcode: .binary, payload: Data(count: WebSocketFrame.maxPayload + 1)).encoded(mask: [0, 0, 0, 0])))
        XCTAssertThrowsError(try WebSocketFrame.decode(Data([0x83, 0x80, 0, 0, 0, 0])), "opcode 3 is reserved")
        XCTAssertThrowsError(try WebSocketFrame.decode(WebSocketFrame(fin: false, opcode: .ping, payload: Data()).encoded(mask: [0, 0, 0, 0])))
    }
}
