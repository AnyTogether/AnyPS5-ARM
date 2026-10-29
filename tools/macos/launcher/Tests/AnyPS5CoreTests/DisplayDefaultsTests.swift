import XCTest
@testable import AnyPS5Core

/// A player: "option to make default display settings for all apps in settings, useful for people
/// wanting fullscreen/windowed in all games". Settings › Default Display, as in AnyPS5 Desktop
/// (game_settings.dart): a game's own choice wins, and a settings file from before keeps the
/// choices that were really made.
final class DisplayDefaultsTests: XCTestCase {
    let custom = DisplayDefaults(fullscreen: true, windowSize: 60, vsync: false)

    func decode(_ json: String) throws -> GameSettings {
        try JSONDecoder().decode(GameSettings.self, from: Data(json.utf8))
    }

    func object(_ settings: GameSettings, legacy: Bool = false) throws -> [String: Any] {
        let encoder = JSONEncoder()
        if legacy { encoder.userInfo[GameSettings.legacyDisplayKeys] = true }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(settings)) as? [String: Any])
    }

    func testAGameWithoutChoicesOfItsOwnStartsWithTheDefaults() {
        let settings = GameSettings()
        XCTAssertTrue(settings.followsDisplayDefaults)
        let environment = settings.withDefaults(custom).environment(launcherLanguage: 1)
        XCTAssertEqual(environment["ANYPS5_FULLSCREEN"], "1")
        XCTAssertEqual(environment["ANYPS5_WINDOW_SIZE"], "60")
        XCTAssertEqual(environment["ANYPS5_PRESENT_MODE"], "immediate")
        XCTAssertEqual(GameSettings().environment(launcherLanguage: 1)["ANYPS5_FULLSCREEN"], "0", "the built-in defaults, as before")
    }

    func testTheGamesOwnChoiceWins() {
        var settings = GameSettings()
        settings.fullscreen = false
        settings.vsync = true
        XCTAssertFalse(settings.followsDisplayDefaults)
        let started = settings.withDefaults(custom)
        XCTAssertFalse(started.fullscreen)
        XCTAssertTrue(started.vsync)
        XCTAssertEqual(started.windowSize, 60, "the size it did not choose follows the default")
    }

    func testFollowingTheDefaultsAgain() {
        var settings = GameSettings()
        settings.fullscreen = true
        settings.windowSize = 90
        settings.vsync = false
        settings.overlay = .topLeft
        let back = settings.followingDisplayDefaults()
        XCTAssertTrue(back.followsDisplayDefaults)
        XCTAssertNil(back.ownFullscreen)
        XCTAssertNil(back.ownWindowSize)
        XCTAssertNil(back.ownVsync)
        XCTAssertEqual(back.overlay, .topLeft, "the other settings stay")
    }

    func testAFileWritesOnlyTheGamesOwnDisplayChoices() throws {
        var settings = GameSettings()
        settings.vsync = false
        let json = try object(settings)
        XCTAssertEqual(json["settingsVersion"] as? Int, GameSettings.version)
        XCTAssertEqual(json["vsync"] as? Bool, false)
        XCTAssertNil(json["fullscreen"])
        XCTAssertNil(json["windowSize"])
        XCTAssertEqual(try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertEqual(try decode(#"{"settingsVersion":2,"windowSize":75,"overlay":"off"}"#).ownWindowSize, 75, "a newer file's 75 % is a choice")
    }

    func testAnOlderFileKeepsTheChoicesThatWereMade() throws {
        // Before the defaults every file had every display key, changed or not.
        let untouched = try decode(#"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"off"}"#)
        XCTAssertTrue(untouched.followsDisplayDefaults, "the old built-in values follow the defaults")
        let full = try decode(#"{"fullscreen":true,"windowSize":75,"vsync":true,"overlay":"off"}"#)
        XCTAssertEqual(full.ownFullscreen, true)
        XCTAssertNil(full.ownWindowSize)
        XCTAssertNil(full.ownVsync)
        let sized = try decode(#"{"fullscreen":false,"windowSize":60,"vsync":true,"overlay":"off"}"#)
        XCTAssertEqual(sized.ownWindowSize, 60)
        XCTAssertEqual(sized.ownFullscreen, false, "windowed with a size of its own was chosen")
        let tearing = try decode(#"{"fullscreen":false,"windowSize":75,"vsync":false,"overlay":"off"}"#)
        XCTAssertEqual(tearing.ownVsync, false)
        XCTAssertNil(tearing.ownFullscreen)
        XCTAssertEqual(try decode(#"{"overlay":"bottomLeft"}"#).overlay, .bottomLeft)
    }

    func testThePreferencesFileStillReadsInAnOlderLauncher() throws {
        // An older launcher decodes fullscreen, windowSize and vsync as required keys: the
        // launcher's own preferences keep them, with which of them are the game's own.
        struct Older: Decodable {
            let fullscreen: Bool
            let windowSize: Int
            let vsync: Bool
        }
        var settings = GameSettings()
        settings.vsync = false
        let encoder = JSONEncoder()
        encoder.userInfo[GameSettings.legacyDisplayKeys] = true
        let data = try encoder.encode(settings)
        let older = try JSONDecoder().decode(Older.self, from: data)
        XCTAssertEqual([older.fullscreen, older.vsync], [false, false])
        XCTAssertEqual(older.windowSize, 75)
        let again = try JSONDecoder().decode(GameSettings.self, from: data)
        XCTAssertEqual(again, settings, "only vsync is the game's own")
        XCTAssertEqual(try object(settings, legacy: true)["ownDisplay"] as? [String], ["vsync"])
    }

    func testTheDefaultsReadLeniently() throws {
        XCTAssertTrue(DisplayDefaults().isBuiltIn)
        XCTAssertEqual(DisplayDefaults(), DisplayDefaults(fullscreen: false, windowSize: 75, vsync: true))
        let read = try JSONDecoder().decode(DisplayDefaults.self, from: Data(#"{"fullscreen":true,"windowSize":10,"vsync":"yes"}"#.utf8))
        XCTAssertEqual(read, DisplayDefaults(fullscreen: true, windowSize: DisplayDefaults.minimumWindowSize, vsync: true))
        XCTAssertEqual(try JSONDecoder().decode(DisplayDefaults.self, from: JSONEncoder().encode(custom)), custom)
    }

    func testTheCrashReportSaysHowTheGameStarted() {
        XCTAssertTrue(GameSettings().withDefaults(custom).reportSummary.contains("Fullscreen"))
    }
}
