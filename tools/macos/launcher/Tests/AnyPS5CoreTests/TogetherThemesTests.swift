import XCTest
@testable import AnyPS5Core

final class TogetherThemesTests: TogetherSignedInCase {
    static let id = "01928c3e-7a4b-7c3d-9e2f-0a1b2c3d4e5f"

    static func index(_ names: [String]) -> [String: Any] {
        ["themes": names.map { name in
            ["id": name.lowercased(), "name": name, "author": "Ada", "version": 2, "style": 1, "deep": "#0A0014", "middle": "#4A0E6B", "bright": "#FF5EDB",
             "accent": "#FF4FD8", "package": "https://anytogether.test/api/v1/themes/\(name.lowercased())/download", "preview": "https://anytogether.test/api/v1/themes/x/thumb.webp"]
        }]
    }

    static func detail(version: Int = 1) -> [String: Any] {
        ["id": id, "name": "Neon Nights", "maker": ["userId": "u1", "handle": "utku", "displayName": "Utku", "avatar": NSNull()], "version": version, "style": 0,
         "colors": ["deep": "#0A0014", "middle": "#4A0E6B", "bright": "#FF5EDB", "accent": "#FF4FD8"], "background": "picture", "music": false,
         "downloads": 12, "likes": 3, "preview": "https://anytogether.test/api/v1/themes/\(id)/preview.webp?v=1", "thumb": "https://anytogether.test/api/v1/themes/\(id)/thumb.webp?v=1",
         "download": "https://anytogether.test/api/v1/themes/\(id)/download", "open": "anyps5://theme/\(id)", "size": 4096, "createdAt": "2026-10-24T10:00:00.000Z",
         "updatedAt": "2026-10-24T10:00:00.000Z", "description": NSNull(), "sha256": "ab", "status": "published", "liked": false, "mine": true]
    }

    let github = URL(string: "https://raw.example.test/hub/")!

    func testTheHubListsTheServersThemes() async throws {
        FakeTogether.handler = { request, _ in request.url!.host == "anytogether.test" ? (200, Self.index(["Neon"])) : (200, Self.index(["Old"])) }
        let base = ThemeHub.base(onServer: client.base)
        XCTAssertEqual(base.absoluteString, "https://anytogether.test/api/v1/hub/")
        let themes = try await ThemeHub.themes(from: [base, github], session: client.session)
        XCTAssertEqual(themes.map(\.name), ["Neon"])
        XCTAssertEqual(themes.first?.design.version, 2)
        XCTAssertEqual(last(), "GET /api/v1/hub/themes.json")
    }

    /// No themes on the server yet, or no server: the GitHub folder's.
    func testTheOldHubStandsIn() async throws {
        FakeTogether.handler = { request, _ in request.url!.host == "anytogether.test" ? (200, ["themes": []]) : (200, Self.index(["Old"])) }
        var themes = try await ThemeHub.themes(from: [ThemeHub.base(onServer: client.base), github], session: client.session)
        XCTAssertEqual(themes.map(\.name), ["Old"])
        FakeTogether.handler = { request, _ in request.url!.host == "anytogether.test" ? (502, ["code": "internal"]) : (200, Self.index(["Old"])) }
        themes = try await ThemeHub.themes(from: [ThemeHub.base(onServer: client.base), github], session: client.session)
        XCTAssertEqual(themes.map(\.name), ["Old"])
        FakeTogether.handler = { _, _ in (200, ["themes": []]) }
        themes = try await ThemeHub.themes(from: [ThemeHub.base(onServer: client.base), github], session: client.session)
        XCTAssertTrue(themes.isEmpty)
        FakeTogether.handler = { _, _ in (500, ["code": "internal"]) }
        do {
            _ = try await ThemeHub.themes(from: [ThemeHub.base(onServer: client.base), github], session: client.session)
            XCTFail("no error")
        } catch {}
    }

    func testSharingSendsTheFileAndItsStill() async throws {
        let file = folder.appendingPathComponent("Neon Nights.anyps5theme")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("PK-zip-bytes".utf8).write(to: file)
        FakeTogether.handler = { _, _ in (201, Self.detail()) }
        let shared = try await client.shareTheme(file, preview: Data("PNG-bytes".utf8))
        XCTAssertEqual(last(), "POST /api/v1/themes")
        let request = try XCTUnwrap(FakeTogether.requests.last)
        XCTAssertTrue(request.0.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let sent = String(decoding: request.1 ?? Data(), as: UTF8.self)
        XCTAssertTrue(sent.contains("name=\"theme\"; filename=\"Neon Nights.anyps5theme\""))
        XCTAssertTrue(sent.contains("PK-zip-bytes"))
        XCTAssertTrue(sent.contains("name=\"preview\"; filename=\"preview.png\""))
        XCTAssertTrue(sent.contains("PNG-bytes"))
        XCTAssertEqual(shared.open, "anyps5://theme/\(Self.id)")
        XCTAssertEqual(shared.mine, true)
        XCTAssertEqual(shared.hubTheme?.design.author, "Utku")
        XCTAssertEqual(shared.hubTheme?.package.absoluteString, "https://anytogether.test/api/v1/themes/\(Self.id)/download")
    }

    /// Shared before from the same design: it goes up again as the next version.
    func testSharingAgainMakesANewVersion() async throws {
        let file = folder.appendingPathComponent("t.anyps5theme")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("zip".utf8).write(to: file)
        FakeTogether.handler = { request, _ in
            request.url!.path.hasSuffix("/versions")
                ? (200, Self.detail(version: 2))
                : (409, ["code": "conflict", "status": 409, "title": "You shared this theme already", "themeId": Self.id])
        }
        let shared = try await client.shareTheme(file, preview: nil)
        XCTAssertEqual(last(), "POST /api/v1/themes/\(Self.id)/versions")
        XCTAssertEqual(shared.version, 2)
        XCTAssertFalse(String(decoding: FakeTogether.requests.last?.1 ?? Data(), as: UTF8.self).contains("name=\"preview\""))
    }

    func testOneThemeForALink() async throws {
        FakeTogether.handler = { _, _ in (200, Self.detail()) }
        let theme = try await client.hubTheme(Self.id)
        XCTAssertEqual(last(), "GET /api/v1/themes/\(Self.id)")
        XCTAssertEqual(theme.name, "Neon Nights")
        XCTAssertEqual(theme.background, "picture")
    }

    func testThemeLinks() {
        XCTAssertEqual(URL(string: "anyps5://theme/\(Self.id.uppercased())").flatMap(DeepLink.init), .theme(Self.id))
        XCTAssertEqual(DeepLink.theme(Self.id).url.absoluteString, "anyps5://theme/\(Self.id)")
        XCTAssertNil(URL(string: "anyps5://theme/../etc").flatMap(DeepLink.init))
        XCTAssertNil(URL(string: "anyps5://theme/neon").flatMap(DeepLink.init))
    }
}
