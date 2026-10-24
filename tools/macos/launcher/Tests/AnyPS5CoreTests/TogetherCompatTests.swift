import XCTest
@testable import AnyPS5Core

final class TogetherCompatTests: TogetherSignedInCase {
    static let summary: [String: Any] = ["status": "ingame", "version": "0.2.14", "testedAt": "2026-10-24T10:00:00.000Z", "reports": 7]

    func testAReportAfterASession() async throws {
        FakeTogether.handler = { _, _ in (201, ["id": "r1", "summary": Self.summary]) }
        let report = TogetherCompatReport(titleId: "PPSA01234", name: " Stray ", status: .ingame, launcherVersion: "0.2.14", engineVersion: "0.2.14-arm (build 7)",
                                          machine: "Mac15,8", os: "macOS 26.1", gameVersion: "01.001.002")
        let summary = try await client.reportCompat(report)
        XCTAssertEqual(last(), "POST /api/v1/compat/reports")
        let sent = try XCTUnwrap(body())
        XCTAssertEqual(sent["titleId"] as? String, "PPSA01234")
        XCTAssertEqual(sent["platform"] as? String, "macos")
        XCTAssertEqual(sent["status"] as? String, "ingame")
        XCTAssertEqual(sent["name"] as? String, "Stray")
        XCTAssertEqual(sent["launcherVersion"] as? String, "0.2.14")
        XCTAssertEqual(sent["engineVersion"] as? String, "0.2.14-armbuild7", "only what a version may hold")
        XCTAssertEqual(sent["machine"] as? String, "Mac15,8")
        XCTAssertEqual(sent["os"] as? String, "macOS 26.1")
        XCTAssertEqual(sent["gameVersion"] as? String, "01.001.002")
        XCTAssertNil(sent["fpsAvg"])
        XCTAssertNil(sent["note"])
        XCTAssertEqual(summary?.status, .ingame)
        XCTAssertEqual(summary?.reports, 7)
    }

    func testTheCommunityStatusOfAGame() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["titleId": "PPSA01234", "name": "Stray", "names": ["en": "Stray"], "iconUrl": NSNull(), "platforms": ["macos": Self.summary, "windows": ["status": "boots", "version": "0.1", "testedAt": "2026-10-20T10:00:00.000Z", "reports": 1]],
                   "reports": []])
        }
        let game = try await client.compat("PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/compat/PPSA01234")
        XCTAssertEqual(game?.mac?.status, .ingame)
        XCTAssertEqual(game?.mac?.version, "0.2.14")
        XCTAssertEqual(game?.platforms["windows"]?.status, .boots)
        FakeTogether.handler = { _, _ in (404, ["code": "not_found", "status": 404, "title": "No such game"]) }
        let unknown = try await client.compat("PPSA09999")
        XCTAssertNil(unknown)
    }

    /// Once per game and launcher version, after a session long enough to tell.
    func testWhenToAsk() {
        XCTAssertFalse(TogetherCompatPrompt.shouldAsk(titleId: "PPSA01234", played: 20, launcherVersion: "0.2.14", asked: [:]))
        XCTAssertTrue(TogetherCompatPrompt.shouldAsk(titleId: "PPSA01234", played: 600, launcherVersion: "0.2.14", asked: [:]))
        XCTAssertFalse(TogetherCompatPrompt.shouldAsk(titleId: "PPSA01234", played: 600, launcherVersion: "0.2.14", asked: ["PPSA01234": "0.2.14"]))
        XCTAssertTrue(TogetherCompatPrompt.shouldAsk(titleId: "PPSA01234", played: 600, launcherVersion: "0.2.15", asked: ["PPSA01234": "0.2.14"]))
    }

    func testStatusesWorstToBest() {
        XCTAssertEqual(TogetherCompatStatus.allCases.map(\.rawValue), ["nothing", "boots", "menus", "ingame", "playable"])
        XCTAssertNil(TogetherCompatReport.version("  "))
        XCTAssertEqual(TogetherCompatReport.version(String(repeating: "9", count: 50))?.count, 40)
    }
}
