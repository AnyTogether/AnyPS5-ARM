import XCTest
@testable import AnyPS5Core

final class GamePresetsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-presets-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testNothingSetPassesNothingSoGamesStartAsOnAFreshConsole() {
        let presets = GamePresets()
        XCTAssertTrue(presets.isEmpty)
        XCTAssertEqual(presets.environment, [:])
    }

    func testEverySettingReachesTheEngineInOneVariable() {
        var presets = GamePresets()
        presets.difficulty = .hard
        presets.priority = .performance
        presets.invertVerticalFirstPerson = true
        presets.invertHorizontalThirdPerson = true
        presets.subtitles = .on
        presets.audioLanguage = 19
        XCTAssertFalse(presets.isEmpty)
        XCTAssertEqual(presets.environment, [
            "ANYPS5_GAME_PRESETS": "difficulty=hard,priority=performance,invert_1st_v=1,invert_1st_h=0,invert_3rd_v=0,invert_3rd_h=1,subtitles=on,audio_language=19",
        ])
        var other = GamePresets()
        other.priority = .resolution
        other.subtitles = .off
        XCTAssertEqual(other.engineValue, "difficulty=default,priority=resolution,invert_1st_v=0,invert_1st_h=0,invert_3rd_v=0,invert_3rd_h=0,subtitles=off,audio_language=default")
    }

    func testTheStoreKeepsThemInAFileOfTheirOwn() throws {
        let store = GamePresetsStore(file: folder.appendingPathComponent("GamePresets.json"))
        XCTAssertEqual(store.load(), GamePresets(), "no file is nothing set")
        var presets = GamePresets()
        presets.difficulty = .easiest
        presets.invertVerticalThirdPerson = true
        presets.audioLanguage = 0
        try store.save(presets)
        XCTAssertEqual(store.load(), presets)
        XCTAssertEqual(GamePresetsStore(file: store.file).load().audioLanguage, 0, "Japanese is a language, not the default")
    }

    func testAFileFromAnotherVersionStillLoads() throws {
        let file = folder.appendingPathComponent("GamePresets.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"difficulty":"hard","priority":"turbo","future":true}"#.utf8).write(to: file)
        let presets = GamePresetsStore(file: file).load()
        XCTAssertEqual(presets.difficulty, .hard)
        XCTAssertEqual(presets.priority, .gameDefault, "a value this version does not know is the default")
        try Data("not json".utf8).write(to: file)
        XCTAssertEqual(GamePresetsStore(file: file).load(), GamePresets())
    }
}
