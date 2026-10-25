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

    func run(_ probe: URL, environment: [String: String]) throws -> [String: String] {
        let process = Process()
        process.executableURL = probe
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ANYPS5_") }.merging(environment) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
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
        XCTAssertEqual(seen["sessions_error"], "0x80553406", "a group nobody offers fails as it does offline")
        XCTAssertEqual(play.router.notOffered["sessionManager GET /v1/playerSessions"], 1)
        XCTAssertEqual(together.calls.filter { $0.path == "me/friends" }.count, 1)
    }

    func testWithoutTheLauncherTheGameStaysSignedOut() throws {
        guard let probe = OnlineEngineInteropTests.probe else { throw XCTSkip("online_probe is not built") }
        let seen = try run(probe, environment: [:])
        XCTAssertEqual(seen["state"], "1")
        XCTAssertEqual(seen["online_id_error"], "0x80550006")
        XCTAssertEqual(seen["friends_error"], "0x80553406")
    }
}
