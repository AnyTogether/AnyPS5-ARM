import XCTest
@testable import AnyPS5Core

/// A pretend AnyTogether API: answers by path, keeps what was asked.
final class FakeTogether: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest, Data?) -> (Int, Any))?
    nonisolated(unsafe) static var requests: [(URLRequest, Data?)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        FakeTogether.requests.append((request, body))
        let (status, json) = FakeTogether.handler?(request, body) ?? (404, ["code": "not_found"])
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let type = status >= 400 ? "application/problem+json" : "application/json"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["content-type": type])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class TogetherTests: XCTestCase {
    var folder: URL!
    var client: TogetherClient!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        FakeTogether.requests = []
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: TokenStore(file: folder.appendingPathComponent("session.json")),
                                session: URLSession(configuration: configuration), clientName: "launcher-macos/0.2.13 (macOS 26.6)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    static func tokens(access: String = "access-1", refresh: String = "refresh-1") -> [String: Any] {
        ["accessToken": access, "expiresIn": 900, "refreshToken": refresh,
         "user": ["id": "u1", "handle": "utku", "displayName": "Utku", "avatar": NSNull(), "created": true]]
    }

    func testAnEmailCodeSignsInAndTheSessionIsKept() async throws {
        FakeTogether.handler = { request, _ in
            switch request.url!.path {
            case "/api/v1/auth/email/start": return (202, [:])
            case "/api/v1/auth/email/verify": return (200, Self.tokens())
            default: return (404, ["code": "not_found"])
            }
        }
        try await client.startEmail("utku@example.com")
        let user = try await client.verifyEmail("utku@example.com", code: "123456")
        XCTAssertEqual(user.handle, "utku")
        XCTAssertEqual(FakeTogether.requests.first?.0.value(forHTTPHeaderField: "AnyTogether-Client"), "launcher-macos/0.2.13 (macOS 26.6)")
        let verify = try JSONSerialization.jsonObject(with: FakeTogether.requests[1].1 ?? Data()) as? [String: String]
        XCTAssertEqual(verify, ["email": "utku@example.com", "code": "123456"])
        let again = TogetherClient(base: client.base, store: TokenStore(file: folder.appendingPathComponent("session.json")), session: .shared, clientName: "x")
        XCTAssertEqual(again.user?.handle, "utku", "kept for the next start")
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("session.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, "only the user may read it")
    }

    func testAProblemComesBackWithItsCode() async {
        FakeTogether.handler = { _, _ in (400, ["type": "x", "title": "That code is not right", "status": 400, "code": "code_invalid"]) }
        do {
            _ = try await client.verifyEmail("a@example.com", code: "000000")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "code_invalid")
        } catch {
            XCTFail("\(error)")
        }
    }

    /// An access token that expired is turned in once for a new one, and the call goes again.
    func testAnExpiredAccessTokenIsRefreshedOnce() async throws {
        FakeTogether.handler = { _, _ in (200, Self.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
        var meCalls = 0
        FakeTogether.handler = { request, _ in
            switch request.url!.path {
            case "/api/v1/me":
                meCalls += 1
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                    ? (200, ["account": ["id": "u1", "email": "u@example.com"], "profile": ["handle": "utku", "displayName": "Utku"]])
                    : (401, ["code": "unauthorized", "title": "expired", "status": 401])
            case "/api/v1/auth/token": return (200, Self.tokens(access: "access-2", refresh: "refresh-2"))
            default: return (404, [:])
            }
        }
        let me = try await client.me()
        XCTAssertEqual(me.profile.handle, "utku")
        XCTAssertEqual(meCalls, 2)
        let refresh = FakeTogether.requests.first { $0.0.url!.path == "/api/v1/auth/token" }
        let body = try JSONSerialization.jsonObject(with: refresh?.1 ?? Data()) as? [String: String]
        XCTAssertEqual(body, ["grantType": "refresh_token", "refreshToken": "refresh-1"])
    }

    func testARefusedRefreshSignsOut() async throws {
        FakeTogether.handler = { _, _ in (200, Self.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
        FakeTogether.handler = { request, _ in
            request.url!.path == "/api/v1/auth/token" ? (401, ["code": "refresh_reused", "status": 401, "title": "ended"]) : (401, ["code": "unauthorized", "status": 401, "title": "x"])
        }
        do { _ = try await client.me() } catch {}
        XCTAssertNil(client.user)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("session.json").path))
    }

    /// The phone signs this launcher in: the launcher waits until the phone approves.
    func testAHandOffWaitsForThePhone() async throws {
        var polls = 0
        FakeTogether.handler = { request, _ in
            switch request.url!.path {
            case "/api/v1/auth/handoff/start": return (201, ["handoffId": "0192f000-0000-7000-8000-000000000001", "secret": String(repeating: "s", count: 43), "expiresIn": 300])
            case "/api/v1/auth/token":
                polls += 1
                return polls < 3 ? (400, ["code": "authorization_pending", "status": 400, "title": "wait"]) : (200, Self.tokens())
            default: return (404, [:])
            }
        }
        let handoff = try await client.startHandoff(deviceName: "Utku's MacBook")
        let user = try await client.waitForApproval(handoff, every: .milliseconds(10), until: Date().addingTimeInterval(5))
        XCTAssertEqual(user.handle, "utku")
        XCTAssertEqual(polls, 3)
    }

    func testADeviceCodeWaitsForApproval() async throws {
        var polls = 0
        FakeTogether.handler = { request, _ in
            switch request.url!.path {
            case "/api/v1/auth/device": return (201, ["deviceCode": String(repeating: "d", count: 43), "userCode": "K7QM-2XZP", "verificationUri": "https://anytogether.test/link", "expiresIn": 600, "interval": 5])
            case "/api/v1/auth/token":
                polls += 1
                return polls < 2 ? (400, ["code": "authorization_pending", "status": 400, "title": "wait"]) : (200, Self.tokens())
            default: return (404, [:])
            }
        }
        let device = try await client.startDeviceCode(deviceName: "Mac")
        XCTAssertEqual(device.userCode, "K7QM-2XZP")
        _ = try await client.waitForApproval(device, every: .milliseconds(10), until: Date().addingTimeInterval(5))
        XCTAssertEqual(polls, 2)
    }

    func testSigningOutTellsTheServerAndForgets() async throws {
        FakeTogether.handler = { _, _ in (200, Self.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
        FakeTogether.handler = { _, _ in (204, [:]) }
        await client.signOut()
        XCTAssertNil(client.user)
        XCTAssertTrue(FakeTogether.requests.contains { $0.0.url!.path == "/api/v1/auth/logout" })
    }
}

/// Against a real AnyTogether API (the server's own repository, run locally): set
/// ANYTOGETHER_TEST_URL and ANYTOGETHER_TEST_LOG (the API's log, where development mail lands).
final class TogetherLiveTests: XCTestCase {
    func testSignInWithAnEmailCodeOnARealServer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["ANYTOGETHER_TEST_URL"].flatMap(URL.init(string:)), let log = environment["ANYTOGETHER_TEST_LOG"] else {
            throw XCTSkip("no AnyTogether server given")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-live-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let client = TogetherClient(base: url, store: TokenStore(file: folder.appendingPathComponent("session.json")), clientName: "launcher-macos/test")
        let email = "live-\(UUID().uuidString.prefix(6).lowercased())@example.com"
        try await client.startEmail(email)
        try await Task.sleep(for: .milliseconds(200))
        let text = try String(contentsOfFile: log, encoding: .utf8)
        let code = try XCTUnwrap(text.components(separatedBy: "\n").last { $0.contains(email) }?.components(separatedBy: ": ").last?.prefix(6))
        let user = try await client.verifyEmail(email, code: String(code))
        XCTAssertTrue(user.handle.hasPrefix("live"))
        let me = try await client.me()
        XCTAssertEqual(me.account.email, email)
        await client.signOut()
        XCTAssertNil(client.user)
    }
}
