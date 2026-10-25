import CryptoKit
import XCTest
@testable import AnyPS5Core

/// Family calls to AnyTogether: the signed status, the key it is checked with, a child's asks, and
/// the social calls a parent's settings refuse.
final class TogetherFamilyTests: TogetherSignedInCase {
    var cacheFolder: URL!
    var suite: String!
    var defaults: UserDefaults!
    let key = Curve25519.Signing.PrivateKey()

    override func setUp() async throws {
        try await super.setUp()
        cacheFolder = folder.appendingPathComponent("family")
        suite = "together-family-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func serve(_ family: [String: Any]) throws {
        let signed = try FamilyCacheTests.sign(family, with: key)
        var answer = family
        answer["signed"] = signed
        let jwks: [String: Any] = ["keys": [["kty": "OKP", "crv": "Ed25519", "x": FamilyCacheTests.base64URL(key.publicKey.rawRepresentation), "alg": "EdDSA", "use": "sig", "kid": "1"]]]
        FakeTogether.handler = { request, _ in
            switch request.url!.path {
            case "/api/v1/me/family/restrictions": return (200, answer)
            case "/api/v1/.well-known/jwks.json": return (200, jwks)
            default: return (404, ["code": "not_found"])
            }
        }
    }

    func testRefreshingChecksAndKeepsTheStatus() async throws {
        let now = Date()
        try serve(FamilyCacheTests.status(issuedAt: now))
        let cache = FamilyCache(folder: cacheFolder, defaults: defaults)
        let standing = try await cache.refresh(from: client, now: now)
        guard case .limited(let status, false) = standing else { return XCTFail("\(standing)") }
        XCTAssertEqual(status.userId, "u1")
        let paths = FakeTogether.requests.map { "\($0.0.httpMethod!) \($0.0.url!.path)" }
        XCTAssertEqual(Set(paths), ["GET /api/v1/me/family/restrictions", "GET /api/v1/.well-known/jwks.json"])
        XCTAssertNotNil(FakeTogether.requests.first { $0.0.url!.path.hasSuffix("restrictions") }?.0.value(forHTTPHeaderField: "Authorization"))
        guard case .limited = FamilyCache(folder: cacheFolder, defaults: defaults).standing(now: now) else { return XCTFail("kept") }
    }

    func testAnswerAndSignatureMustAgree() async throws {
        let now = Date()
        try serve(FamilyCacheTests.status(issuedAt: now))
        // A proxy changes the plain answer: the signed copy is what counts.
        let jwks: [String: Any] = ["keys": [["kty": "OKP", "crv": "Ed25519", "x": FamilyCacheTests.base64URL(key.publicKey.rawRepresentation), "kid": "1"]]]
        let signed = try FamilyCacheTests.sign(FamilyCacheTests.status(issuedAt: now), with: key)
        var plain = FamilyCacheTests.status(restricted: false, issuedAt: now)
        plain["signed"] = signed
        FakeTogether.handler = { request, _ in request.url!.path.hasSuffix("jwks.json") ? (200, jwks) : (200, plain) }
        let standing = try await FamilyCache(folder: cacheFolder, defaults: defaults).refresh(from: client, now: now)
        guard case .limited = standing else { return XCTFail("the signed status applies") }
    }

    func testAChildAsks() async throws {
        FakeTogether.handler = { _, _ in (201, ["id": "r1", "kind": "more_time", "status": "pending"]) }
        let asked = try await client.askFamily(.moreTime(minutes: 30, titleId: "PPSA01234"))
        XCTAssertTrue(asked, "a new ask")
        XCTAssertEqual(last(), "POST /api/v1/me/family/requests")
        XCTAssertEqual(body() as NSDictionary?, ["kind": "more_time", "minutes": 30, "titleId": "PPSA01234"])
        try await client.askFamily(.playGame(titleId: "PPSA05678", name: "Stray"))
        XCTAssertEqual(body() as NSDictionary?, ["kind": "play_game", "titleId": "PPSA05678", "name": "Stray"])
        try await client.askFamily(.addFriend(handle: "deniz"))
        XCTAssertEqual(body() as NSDictionary?, ["kind": "add_friend", "handle": "deniz"])
        try await client.askFamily(.moreTime(minutes: 1000, titleId: nil))
        XCTAssertEqual(body()?["minutes"] as? Int, 240, "within what the server takes")
        FakeTogether.handler = { _, _ in (200, ["id": "r1", "kind": "more_time", "status": "pending"]) }
        let again = try await client.askFamily(.moreTime(minutes: 30, titleId: nil))
        XCTAssertFalse(again, "the same one waits already")
    }

    func testTheLimitReachedIsTold() async throws {
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.familyLimitReached(titleId: "PPSA01234")
        XCTAssertEqual(last(), "POST /api/v1/me/family/limit-reached")
        XCTAssertEqual(body() as NSDictionary?, ["titleId": "PPSA01234"])
        try await client.familyLimitReached(titleId: nil)
        XCTAssertEqual(body() as NSDictionary?, [:])
    }

    func testARefusalNamesTheFeature() async {
        FakeTogether.handler = { _, _ in (403, ["type": "x", "title": "Not allowed by your family", "status": 403, "code": "restricted_by_family", "feature": "voice_chat"]) }
        do {
            _ = try await client.me()
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "restricted_by_family")
            XCTAssertEqual(problem.feature, "voice_chat")
            XCTAssertEqual(problem.familyFeature, .voiceChat)
            XCTAssertFalse(problem.byOthersFamily, "no side: the asker's own")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testARefusalSaysWhoseFamily() async {
        FakeTogether.handler = { _, _ in (403, ["type": "x", "title": "Not allowed", "status": 403, "code": "restricted_by_family", "feature": "friend_requests", "side": "other"]) }
        do {
            _ = try await client.askFriend("deniz")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.side, "other")
            XCTAssertTrue(problem.byOthersFamily)
            XCTAssertEqual(problem.familyFeature, .friendRequests)
        } catch {
            XCTFail("\(error)")
        }
    }

    /// The catalogue call carries the game's age ratings, sent again once for a game taught before.
    func testTheGamesAgeRatingsAreTaught() async throws {
        var bodies: [String: [String: Any]] = [:]
        FakeTogether.handler = { request, body in
            if request.url!.path.hasSuffix("/me/sessions") { return (200, ["results": [["index": 0, "status": "stored"]]]) }
            if request.url!.path.contains("/games/") { bodies[request.url!.path] = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
            return (201, [:])
        }
        let sync = TogetherSync(client: client, folder: folder.appendingPathComponent("outbox"), deviceName: "Mac", model: "Mac15,3")
        sync.recordSession(titleId: "PPSA01234", gameName: "Silksong", startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: Date(timeIntervalSince1970: 1_800_003_600), exit: "normal")
        try await sync.flush()
        XCTAssertNil(bodies["/api/v1/games/PPSA01234"]?["ageLevels"])
        bodies = [:]
        let id = sync.recordSession(titleId: "PPSA01234", gameName: "Silksong", ageLevels: ["default": 16, "US": 13, "de": 12, "XX": 300], startedAt: Date(timeIntervalSince1970: 1_800_010_000), endedAt: Date(timeIntervalSince1970: 1_800_013_600), exit: "normal")
        XCTAssertEqual(sync.pendingSessionIDs, Set([id].compactMap { $0 }))
        XCTAssertNotNil(id)
        try await sync.flush()
        XCTAssertEqual(bodies["/api/v1/games/PPSA01234"]?["ageLevels"] as? [String: Int], ["default": 16, "US": 13], "only what the server takes")
        XCTAssertEqual(sync.pendingSessionIDs, [])
        bodies = [:]
        sync.recordSession(titleId: "PPSA01234", gameName: "Silksong", ageLevels: ["default": 16, "US": 13], startedAt: Date(timeIntervalSince1970: 1_800_020_000), endedAt: Date(timeIntervalSince1970: 1_800_023_600), exit: "normal")
        try await sync.flush()
        XCTAssertTrue(bodies.isEmpty, "taught once")
    }
}
