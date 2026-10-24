import XCTest
@testable import AnyPS5Core

/// A client signed in against FakeTogether, for the social tests.
class TogetherSignedInCase: XCTestCase {
    var folder: URL!
    var client: TogetherClient!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-social-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: TokenStore(file: folder.appendingPathComponent("s.json")),
                                session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
        FakeTogether.requests = []
        FakeTogether.handler = { _, _ in (200, TogetherTests.tokens()) }
        _ = try await client.verifyEmail("u@example.com", code: "111111")
        FakeTogether.requests = []
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func body(_ index: Int = -1) -> [String: Any]? {
        let request = index < 0 ? FakeTogether.requests.last : FakeTogether.requests[index]
        return (request?.1).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func last() -> String {
        guard let request = FakeTogether.requests.last?.0 else { return "" }
        return "\(request.httpMethod ?? "") \(request.url!.path)" + (request.url!.query.map { "?\($0)" } ?? "")
    }
}

final class TogetherAccountTests: TogetherSignedInCase {
    static func own(handle: String = "utku", name: String = "Utku", bio: Any = NSNull(), changeAt: Any = NSNull()) -> [String: Any] {
        ["handle": handle, "displayName": name, "bio": bio, "avatar": "https://cdn.test/u.webp", "country": "TR", "handleChangedAt": NSNull(), "handleChangeAt": changeAt,
         "privacy": ["library": "friends", "trophies": "everyone", "friends": "friends", "presence": "nobody", "search": "everyone"]]
    }

    func testMyProfileWithItsPrivacy() async throws {
        FakeTogether.handler = { _, _ in (200, ["account": ["id": "u1", "email": "u@example.com", "createdAt": "2026-10-01T10:00:00.000Z"], "profile": Self.own()]) }
        let mine = try await client.myProfile()
        XCTAssertEqual(mine.handle, "utku")
        XCTAssertEqual(mine.country, "TR")
        XCTAssertNil(mine.handleChangeAt)
        XCTAssertEqual(mine.privacy[.trophies], .everyone)
        XCTAssertEqual(mine.privacy[.presence], .nobody)
        XCTAssertEqual(last(), "GET /api/v1/me")
    }

    /// Only what changed goes up; the name the launcher keeps for the session follows.
    func testEditingTheProfileSendsWhatChanged() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(name: "Utku H.", bio: "Platinum hunter")) }
        let mine = try await client.updateProfile(displayName: "Utku H.", bio: "Platinum hunter")
        XCTAssertEqual(mine.displayName, "Utku H.")
        XCTAssertEqual(last(), "PATCH /api/v1/me/profile")
        XCTAssertEqual(body()?.keys.sorted(), ["bio", "displayName"])
        XCTAssertEqual(client.user?.displayName, "Utku H.")
        _ = try await client.updateProfile(bio: "")
        XCTAssertTrue(body()?["bio"] is NSNull, "an empty bio clears it")
    }

    func testANewHandleAndItsRefusals() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(handle: "utkuh")) }
        let mine = try await client.changeHandle("@UtkuH ")
        XCTAssertEqual(mine.handle, "utkuh")
        XCTAssertEqual(body()?["handle"] as? String, "utkuh")
        XCTAssertEqual(client.user?.handle, "utkuh", "the session's user follows")
        FakeTogether.handler = { _, _ in (429, ["code": "handle_cooldown", "status": 429, "title": "The handle can change again on 2026-11-20", "handleChangeAt": "2026-11-20T09:00:00.000Z"]) }
        do {
            _ = try await client.changeHandle("other")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "handle_cooldown")
            XCTAssertEqual(problem.handleChangeAt, ISO8601DateFormatter().date(from: "2026-11-20T09:00:00Z"))
        }
    }

    func testPrivacyChangesOneSection() async throws {
        FakeTogether.handler = { _, _ in (200, ["library": "nobody", "trophies": "friends", "friends": "friends", "presence": "friends", "search": "everyone"]) }
        let privacy = try await client.updatePrivacy(.library, to: .nobody)
        XCTAssertEqual(last(), "PATCH /api/v1/me/privacy")
        XCTAssertEqual(body() as? [String: String], ["library": "nobody"])
        XCTAssertEqual(privacy[.library], .nobody)
        XCTAssertEqual(privacy[.search], .everyone)
    }

    /// A 403 for a private section names it, for the launchers that read it.
    func testAPrivateSectionIsNamed() async throws {
        FakeTogether.handler = { _, _ in (403, ["code": "forbidden", "status": 403, "title": "This is private", "section": "library"]) }
        do {
            _ = try await client.authorized("GET", "users/ayse/library", nil)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.section, "library")
        }
    }
}
