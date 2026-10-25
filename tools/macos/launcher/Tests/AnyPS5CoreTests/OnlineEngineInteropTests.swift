import XCTest
@testable import AnyPS5Core

/// Both ends of the bridge for real: the engine's NpManager, NpWebApi2 and NetCtl libraries in a
/// stand-in game (`online_probe`, built with the engine's tests) against the launcher's own
/// service with an AnyTogether user. Skipped when the probe has not been built; point
/// ANYPS5_ONLINE_PROBE at it, or build it in `<repo>/build-mac` (`ninja -C build-mac online_probe`).
final class OnlineEngineInteropTests: XCTestCase {
    static var probe: URL? {
        if let path = ProcessInfo.processInfo.environment["ANYPS5_ONLINE_PROBE"], !path.isEmpty { return URL(fileURLWithPath: path) }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let built = repository.appendingPathComponent("build-mac/tests/online_probe")
        return FileManager.default.isExecutableFile(atPath: built.path) ? built : nil
    }

    func run(_ probe: URL, environment: [String: String], arguments: [String] = [], whileRunning: () -> Void = {}) throws -> [String: String] {
        let process = Process()
        process.executableURL = probe
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ANYPS5_") }.merging(environment) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        whileRunning()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            XCTFail("the probe did not finish")
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }

    func testAGameSignsInAsTheAnyTogetherUserAndGetsItsFriends() throws {
        guard let probe = OnlineEngineInteropTests.probe else { throw XCTSkip("online_probe is not built") }
        let me = TogetherUser(id: "0190a0b1-0000-7000-8000-00000000000a", handle: "alice", displayName: "Alice", avatar: nil)
        let together = FakeOnlineTogether(friends: [("b-id", "bob", "online"), ("c-id", "carol", "offline")])
        let play = OnlinePlay(service: together, user: me, game: .init(titleId: "PPSA00000", gameVersion: "01.000", engineBuild: "x"),
                              locale: Locale(identifier: "tr_TR"), transport: { _ in OnlineNoTransport() })
        let environment = try play.start()
        defer { play.stop() }

        let seen = try run(probe, environment: environment)
        XCTAssertEqual(seen["state"], "2", "the game sees a signed-in user")
        XCTAssertEqual(seen["online_id"], "alice", "the online ID is the AnyTogether handle")
        XCTAssertEqual(seen["account_id"], String(OnlineIdentity.accountId(forUser: me.id)))
        XCTAssertEqual(seen["country"], "tr")
        XCTAssertEqual(seen["friends_status"], "200")
        let friends = try XCTUnwrap(JSONSerialization.jsonObject(with: Data((seen["friends_body"] ?? "").utf8)) as? [String: Any])
        XCTAssertEqual(friends["friends"] as? [String], [String(OnlineIdentity.accountId(forUser: "b-id")), String(OnlineIdentity.accountId(forUser: "c-id"))],
                       "the friends are the AnyTogether friends")
        XCTAssertEqual(seen["profile_status"], "200")
        XCTAssertTrue(seen["profile_body"]?.contains(#""onlineId":"alice""#) == true)
        XCTAssertEqual(seen["tickets_error"], "0x80553406", "a group nobody offers fails as it does offline")
        XCTAssertEqual(play.router.notOffered["matchmaking GET /v1/tickets"], 1)
        XCTAssertEqual(together.calls.filter { $0.path == "me/friends" }.count, 1)
    }

    /// Host as Human Fall Flat (PPSA02429) does it, through the real NpWebApi2 and NpManager: a
    /// sessionManager push context, a Player Session made with it, news of another player
    /// delivered to the game's push context callback from sceNpCheckCallback, then leaving.
    func testAGameHostsAPlayerSessionWithAPushContext() throws {
        guard let probe = OnlineEngineInteropTests.probe else { throw XCTSkip("online_probe is not built") }
        let me = TogetherUser(id: "0190a0b1-0000-7000-8000-00000000000a", handle: "alice", displayName: "Alice", avatar: nil)
        let together = FakeOnlineTogether()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("online-host-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: log) }
        let play = OnlinePlay(service: together, user: me, game: .init(titleId: "PPSA02429", gameVersion: "01.017", engineBuild: "x"),
                              observationLog: log, transport: { _ in OnlineNoTransport() })
        let environment = try play.start()
        defer { play.stop() }
        let sessions = try XCTUnwrap(play.router.playerSessions)

        let seen = try run(probe, environment: environment, arguments: ["host"]) {
            let deadline = Date().addingTimeInterval(20)
            while sessions.sessionIds.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            guard let id = sessions.sessionIds.first else { return XCTFail("the game made no Player Session") }
            XCTAssertTrue(sessions.playerJoined(sessionId: id, account: 77, onlineId: "bob"))
        }
        XCTAssertEqual(seen["restriction_status"], "200", "the first restriction check is answered")
        XCTAssertEqual(seen["blocks_status"], "200", "the first block list is answered")
        XCTAssertEqual(seen["push_context_result"], "0x00000000", "a push context is made")
        let context = try XCTUnwrap(seen["push_context"])
        XCTAssertEqual(context.count, 36)
        XCTAssertEqual(seen["create_status"], "200", "Host gets its Player Session")
        let sessionId = try XCTUnwrap(seen["session_id"])
        XCTAssertEqual(seen["get_status"], "200")
        XCTAssertEqual(seen["patch_status"], "204")
        XCTAssertEqual(seen["pushed_type"], "psn:sessionManager:ps:m:players:created", "the news reaches the game's push context callback")
        XCTAssertEqual(seen["pushed_context"], context)
        XCTAssertTrue(seen["pushed_data"]?.contains(sessionId) == true)
        XCTAssertEqual(seen["leave_status"], "204")
        XCTAssertEqual(seen["stale_leave_status"], "204", "leaving a session from an earlier lobby does not fail")
        XCTAssertEqual(seen["after_status"], "200", "bob still plays in it")
        XCTAssertTrue(seen["after_body"]?.contains(#""leader":{"accountId":"77","platform":"PS5"}"#) == true, "and leads it once the host left")
        XCTAssertTrue(play.router.notOffered.isEmpty, "\(play.router.notOffered)")
        XCTAssertTrue(together.calls.isEmpty)

        // The observation log shows what Host sent: the filter's data types, the push context
        // and the whole request body, so the next real run tells exactly what the game wants.
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.contains("sceNpWebApi2PushEventCreateFilter") && $0.contains("psn:sessionManager:ps:m:players:created,") })
        XCTAssertTrue(lines.contains { $0.contains("sceNpWebApi2PushEventCreatePushContext") && $0.contains(#""pushContextId":"\#(context)""#) })
        XCTAssertTrue(lines.contains { $0.contains("sceNpWebApi2SendRequest") && $0.contains(#"\"pushContextId\":\"\#(context)\""#) },
                      "the Player Session body is in the log")
        XCTAssertTrue(lines.contains { $0.contains("PushEventDelivered") && $0.contains(#""callbacks":1"#) })
    }

    func testWithoutTheLauncherTheGameStaysSignedOut() throws {
        guard let probe = OnlineEngineInteropTests.probe else { throw XCTSkip("online_probe is not built") }
        let seen = try run(probe, environment: [:])
        XCTAssertEqual(seen["state"], "1")
        XCTAssertEqual(seen["online_id_error"], "0x80550006")
        XCTAssertEqual(seen["friends_error"], "0x80553406")
    }
}
