import XCTest
@testable import AnyPS5Core

final class GameSettingsTests: XCTestCase {
    func testTheOverlayIsTheMinimalLineUnlessTheDetailedPanelIsChosen() throws {
        var settings = GameSettings()
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_OVERLAY"])
        settings.overlay = .topRight
        let minimal = settings.environment(launcherLanguage: 1)
        XCTAssertEqual(minimal["ANYPS5_OVERLAY"], "1")
        XCTAssertEqual(minimal["ANYPS5_OVERLAY_POS"], "tr")
        XCTAssertEqual(minimal["ANYPS5_OVERLAY_STYLE"], "minimal")
        settings.overlayStyle = .detailed
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_OVERLAY_STYLE"], "detailed")
    }

    func testTheGameReadsThePadOnlyWhileItsWindowIsInFront() {
        XCTAssertEqual(GameSettings().environment(launcherLanguage: 1)["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"], "0",
                       "with the launcher over the game (PS), the game leaves the pad alone")
        var traced = GameSettings()
        traced.trace = true
        XCTAssertEqual(traced.environment(launcherLanguage: 1, trace: true)["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"], "0")
    }

    func testFrameGenerationTurnsOnVerticalSync() {
        var settings = GameSettings()
        settings.vsync = false
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_FRAME_GEN"])
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_PRESENT_MODE"], "immediate")
        settings.frameGeneration = true
        let environment = settings.environment(launcherLanguage: 1)
        XCTAssertEqual(environment["ANYPS5_FRAME_GEN"], "1")
        XCTAssertEqual(environment["ANYPS5_PRESENT_MODE"], "fifo", "the generated frame needs presents a refresh apart")
    }

    func testSettingsSavedBeforeTheStyleStillRead() throws {
        let older = #"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"topLeft"}"#
        let settings = try JSONDecoder().decode(GameSettings.self, from: Data(older.utf8))
        XCTAssertEqual(settings.overlay, .topLeft)
        XCTAssertEqual(settings.style, .minimal)
    }
}
