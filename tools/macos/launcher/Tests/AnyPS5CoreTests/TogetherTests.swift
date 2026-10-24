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

/// The socket against a real gateway and API (both from the server's repository, run locally):
/// signing the launcher's session out from another device closes its socket within seconds.
final class TogetherSocketLiveTests: XCTestCase {
    func testSigningOutElsewhereEndsTheSocket() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["ANYTOGETHER_TEST_URL"].flatMap(URL.init(string:)), let log = environment["ANYTOGETHER_TEST_LOG"],
              let realtime = environment["ANYTOGETHER_TEST_RT"].flatMap(URL.init(string:)) else { throw XCTSkip("no AnyTogether server given") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-socket-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let email = "socket-\(UUID().uuidString.prefix(6).lowercased())@example.com"
        func signIn(_ name: String, _ base: URL) async throws -> TogetherClient {
            let client = TogetherClient(base: base, store: TokenStore(file: folder.appendingPathComponent("\(name).json")), clientName: "\(name)/test")
            try await client.startEmail(email)
            try await Task.sleep(for: .milliseconds(200))
            let code = try XCTUnwrap(try String(contentsOfFile: log, encoding: .utf8).components(separatedBy: "\n").last { $0.contains(email) }?.components(separatedBy: ": ").last?.prefix(6))
            _ = try await client.verifyEmail(email, code: String(code))
            return client
        }
        // The launcher talks to the API for tokens and to the gateway for the socket.
        let launcher = try await signIn("launcher-macos", url)
        let web = try await signIn("web", url)
        let socketClient = TogetherClient(base: realtime, store: launcher.store, clientName: "launcher-macos/test")
        let ended = expectation(description: "signed out")
        let socket = TogetherSocket(client: socketClient) { ended.fulfill() }
        socket.start()
        try await Task.sleep(for: .milliseconds(500))
        struct Sessions: Decodable { struct Item: Decodable { let id: String; let client: String }; let sessions: [Item] }
        let list = try JSONDecoder().decode(Sessions.self, from: try await web.authorized("GET", "auth/sessions", nil))
        let mac = try XCTUnwrap(list.sessions.first { $0.client == "launcher-macos" })
        let started = Date()
        _ = try await web.authorized("DELETE", "auth/sessions/\(mac.id)", nil)
        await fulfillment(of: [ended], timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertNil(launcher.user, "the launcher forgot the session")
    }
}

final class TogetherFriendsTests: XCTestCase {
    func testFriendsWithPresenceAndRequests() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-friends-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        let client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: TokenStore(file: folder.appendingPathComponent("s.json")),
                                    session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
        FakeTogether.requests = []
        FakeTogether.handler = { _, _ in (200, TogetherTests.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
        FakeTogether.handler = { request, _ in
            switch (request.httpMethod ?? "", request.url!.path) {
            case ("GET", "/api/v1/me/friends"):
                return (200, ["friends": [["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull(),
                                           "presence": ["state": "in_game", "titleId": "PPSA01234", "since": "2026-10-24T10:00:00Z"]]]])
            case ("GET", "/api/v1/me/friends/requests"):
                return (200, ["incoming": [["userId": "f2", "handle": "kral", "displayName": "Kral", "avatar": NSNull()]], "outgoing": []])
            case ("POST", "/api/v1/me/friends/requests"): return (201, ["state": "pending"])
            case ("POST", "/api/v1/me/friends/requests/f2/accept"): return (204, [:])
            case ("GET", "/api/v1/users/search"): return (200, ["users": [["userId": "f3", "handle": "utkan", "displayName": "Utkan", "avatar": NSNull()]]])
            default: return (404, ["code": "not_found", "status": 404, "title": "x"])
            }
        }
        let friends = try await client.friends()
        XCTAssertEqual(friends.first?.presence?.titleId, "PPSA01234")
        XCTAssertTrue(friends.first?.presence?.playing ?? false)
        let requests = try await client.friendRequests()
        XCTAssertEqual(requests.incoming.map(\.handle), ["kral"])
        let state = try await client.askFriend("@ayse ")
        XCTAssertEqual(state, "pending")
        let asked = FakeTogether.requests.first { $0.0.httpMethod == "POST" && $0.0.url!.path == "/api/v1/me/friends/requests" }
        XCTAssertEqual(try JSONSerialization.jsonObject(with: asked?.1 ?? Data()) as? [String: String], ["handle": "ayse"])
        try await client.answerFriend("f2", accept: true)
        let found = try await client.searchPeople("utk")
        XCTAssertEqual(found.map(\.handle), ["utkan"])
        XCTAssertEqual(FakeTogether.requests.last?.0.url?.query, "q=utk")
    }
}

final class TogetherSyncTests: XCTestCase {
    var folder: URL!
    var client: TogetherClient!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-sync-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: TokenStore(file: folder.appendingPathComponent("s.json")),
                                session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
        FakeTogether.requests = []
        FakeTogether.handler = { _, _ in (200, TogetherTests.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func sync() -> TogetherSync {
        TogetherSync(client: client, file: folder.appendingPathComponent("outbox.json"), deviceName: "Utku's Mac", model: "Mac15,9")
    }

    static let set = TogetherSync.TrophySetRecord(titleId: "PPSA01234", gameName: "Silksong", language: "en", trophies: [
        .init(id: 0, grade: "platinum", hidden: false, name: "All", detail: "Every trophy", earnedAt: nil),
        .init(id: 1, grade: "bronze", hidden: false, name: "Bound", detail: "Bind a skill", earnedAt: Date(timeIntervalSince1970: 1_790_000_000)),
        .init(id: 2, grade: "gold", hidden: true, name: "Secret", detail: "Shh", earnedAt: nil),
    ])

    /// The first time: the computer is registered, the game taught, its trophy set uploaded, then
    /// the session and the earned trophy go up; nothing is sent twice.
    func testAGameAndItsTrophiesGoUpInOrderOnce() async throws {
        var paths: [String] = []
        FakeTogether.handler = { request, _ in
            paths.append("\(request.httpMethod!) \(request.url!.path)")
            if request.url!.path.hasSuffix("/me/sessions") || request.url!.path.hasSuffix("/me/trophies") {
                return (200, ["results": [["index": 0, "status": "stored"]]])
            }
            return (201, [:])
        }
        let sync = sync()
        sync.recordSession(titleId: "PPSA01234", gameName: "Silksong", startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: Date(timeIntervalSince1970: 1_800_003_600), exit: "normal")
        sync.recordTrophies(Self.set)
        try await sync.flush()
        XCTAssertEqual(paths, [
            "POST /api/v1/me/devices",
            "PUT /api/v1/games/PPSA01234",
            "PUT /api/v1/trophy-sets/PPSA01234/\(Self.set.setHash)",
            "POST /api/v1/me/sessions",
            "POST /api/v1/me/trophies",
        ])
        let trophies = try XCTUnwrap(FakeTogether.requests.last?.1).flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let items = trophies?["trophies"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1, "only the earned one")
        XCTAssertEqual(items?.first?["trophyId"] as? Int, 1)
        paths = []
        sync.recordTrophies(Self.set)
        try await sync.flush()
        XCTAssertEqual(paths, [], "nothing new: the set, the game and the trophy were sent")
    }

    /// Offline: everything waits in the outbox, kept on disk, and goes up later.
    func testWhatCouldNotBeSentWaitsForNextTime() async throws {
        FakeTogether.handler = { _, _ in (503, ["code": "internal", "status": 503, "title": "down"]) }
        let first = sync()
        first.recordSession(titleId: "PPSA01234", gameName: "Silksong", startedAt: Date(), endedAt: Date().addingTimeInterval(60), exit: "normal")
        do { try await first.flush() } catch {}
        var sessions = 0
        FakeTogether.handler = { request, body in
            if request.url!.path.hasSuffix("/me/sessions") {
                sessions += (try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: [Any]])?["sessions"]?.count ?? 0
                return (200, ["results": [["index": 0, "status": "stored"]]])
            }
            return (201, [:])
        }
        let later = sync()
        try await later.flush()
        XCTAssertEqual(sessions, 1)
        XCTAssertTrue(later.isEmpty)
    }

    func testTheSetHashFollowsTheTrophiesNotTheirTexts() {
        var other = Self.set
        other.trophies[1].name = "Bağlandı"
        XCTAssertEqual(other.setHash, Self.set.setHash)
        other.trophies[1].grade = "silver"
        XCTAssertNotEqual(other.setHash, Self.set.setHash)
    }
}

/// The sync against a real AnyTogether API: the library and trophies come back as sent.
final class TogetherSyncLiveTests: XCTestCase {
    func testPlayAndTrophiesReachTheLibrary() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["ANYTOGETHER_TEST_URL"].flatMap(URL.init(string:)), let log = environment["ANYTOGETHER_TEST_LOG"] else { throw XCTSkip("no AnyTogether server given") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-sync-live-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let client = TogetherClient(base: url, store: TokenStore(file: folder.appendingPathComponent("s.json")), clientName: "launcher-macos/test")
        let email = "sync-\(UUID().uuidString.prefix(6).lowercased())@example.com"
        try await client.startEmail(email)
        try await Task.sleep(for: .milliseconds(200))
        let code = try XCTUnwrap(try String(contentsOfFile: log, encoding: .utf8).components(separatedBy: "\n").last { $0.contains(email) }?.components(separatedBy: ": ").last?.prefix(6))
        let user = try await client.verifyEmail(email, code: String(code))
        let sync = TogetherSync(client: client, file: folder.appendingPathComponent("outbox.json"), deviceName: "Test Mac", model: "Mac15,9")
        sync.recordSession(titleId: "PPSA01234", gameName: "Silksong", startedAt: Date().addingTimeInterval(-3600), endedAt: Date(), exit: "normal")
        sync.recordTrophies(TogetherSyncTests.set)
        try await sync.flush()
        XCTAssertTrue(sync.isEmpty)
        struct Library: Decodable { struct Game: Decodable { let titleId: String; let secondsPlayed: Int; let trophiesEarned: Int; let points: Int }; let games: [Game] }
        let library = try JSONDecoder().decode(Library.self, from: try await client.authorized("GET", "users/\(user.handle)/library", nil))
        let game = try XCTUnwrap(library.games.first)
        XCTAssertEqual(game.titleId, "PPSA01234")
        XCTAssertEqual(game.secondsPlayed, 3600, accuracy: 2)
        XCTAssertEqual(game.trophiesEarned, 1)
        XCTAssertEqual(game.points, 15)
    }
}
