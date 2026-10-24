import XCTest
@testable import AnyPS5Core

final class GameLogTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("game-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Logs

    func testTheUnlockOutputIsKeptForTheReport() throws {
        try GameLog.writeUnlockLog(["unwrap eboot.bin", "relink 12 modules"], failure: nil, titleID: "PPSA01234", in: folder)
        XCTAssertEqual(GameLog.readUnlockLog(titleID: "PPSA01234", in: folder), "unwrap eboot.bin\nrelink 12 modules\n")
        try GameLog.writeUnlockLog(["unwrap"], failure: "relinker failed", titleID: "PPSA01234", in: folder)
        XCTAssertEqual(GameLog.readUnlockLog(titleID: "PPSA01234", in: folder), "unwrap\nrelinker failed\n")
        XCTAssertNil(GameLog.readUnlockLog(titleID: "PPSA99999", in: folder))
    }

    func testABigLogIsSetAsideBeforeAStart() throws {
        let log = GameLog.file(titleID: "PPSA01234", in: folder)
        try Data(repeating: 65, count: 2000).write(to: log)
        XCTAssertFalse(GameLog.rollForStart(log, limit: 4000))
        XCTAssertTrue(GameLog.rollForStart(log, limit: 1000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("PPSA01234.previous.log")).count, 2000)
    }

    func testATraceLogOverItsCapStartsAgainAndKeepsOnePart() throws {
        let log = GameLog.file(titleID: "PPSA01234", in: folder)
        try Data("first part\n".utf8 + Data(repeating: 66, count: 3000)).write(to: log)
        // The game writes with O_APPEND, so it carries on at the new end.
        let writer = try FileHandle(forWritingTo: log)
        XCTAssertFalse(GameLog.trim(log, cap: 10_000))
        XCTAssertTrue(GameLog.trim(log, cap: 1000))
        let part = folder.appendingPathComponent("PPSA01234.trace-1.log")
        XCTAssertTrue(try String(contentsOf: part, encoding: .utf8).hasPrefix("first part"))
        let restarted = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(restarted.contains("[anyps5-launcher] log rotated"))
        XCTAssertLessThan(restarted.utf8.count, 300)
        try writer.close()
    }

    // MARK: Trace mode

    func testDetailedLoggingTurnsOnTheEnginesTraceSwitches() throws {
        var settings = GameSettings()
        for key in TraceMode.environment.keys { XCTAssertNil(settings.environment(launcherLanguage: 1)[key]) }
        settings.trace = true
        let environment = settings.environment(launcherLanguage: 1)
        XCTAssertEqual(environment["APS5_LOG_SYNC"], "1")
        XCTAssertEqual(environment["APS5_TRACE_EXIT"], "1")
        XCTAssertEqual(environment["APS5_LOG_TIMESTAMPS"], "1")
        XCTAssertEqual(GameSettings().environment(launcherLanguage: 1, trace: true)["APS5_LOG_SYNC"], "1", "the one-shot start")
        let older = #"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"off"}"#
        XCTAssertNil(try JSONDecoder().decode(GameSettings.self, from: Data(older.utf8)).trace)
    }
}
