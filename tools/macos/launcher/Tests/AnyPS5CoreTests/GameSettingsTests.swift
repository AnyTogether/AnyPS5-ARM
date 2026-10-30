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

    func testFsr1PassesTheUpscalerAndItsSharpness() {
        var settings = GameSettings()
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_UPSCALER"], "bilinear is the engine's default: nothing is passed")
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_FSR_SHARPNESS"])
        settings.upscaler = .fsr1
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_UPSCALER"], "fsr1")
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_FSR_SHARPNESS"], "0.2", "AMD's default sharpness")
        settings.fsrSharpness = 1.26
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_FSR_SHARPNESS"], "1.3", "a tenth of a stop, with a point in every language")
        settings.fsrSharpness = 7
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_FSR_SHARPNESS"], "2.0", "the engine refuses more than 2 stops")
        settings.fsrSharpness = -1
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_FSR_SHARPNESS"], "0.0")
        settings.upscaler = .bilinear
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_UPSCALER"])
    }

    func testUpscalingIsSavedWithTheGamesSettings() throws {
        var settings = GameSettings()
        settings.upscaler = .fsr1
        settings.fsrSharpness = 0.5
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["upscaler"] as? String, "fsr1")
        XCTAssertEqual(object["fsrSharpness"] as? Double, 0.5)
        let read = try JSONDecoder().decode(GameSettings.self, from: data)
        XCTAssertEqual(read.upscaler, .fsr1)
        XCTAssertEqual(read.fsrSharpness, 0.5)
        let unknown = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"overlay":"off","upscaler":"fsr9","fsrSharpness":"x"}"#.utf8))
        XCTAssertNil(unknown.upscaler, "an upscaler this launcher does not know is bilinear, and the rest still reads")
        XCTAssertNil(unknown.fsrSharpness)
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(GameSettings())) as? [String: Any])
        XCTAssertNil(plain["upscaler"], "bilinear is not written")
        XCTAssertNil(plain["fsrSharpness"])
    }

    func testSettingsSavedBeforeTheStyleStillRead() throws {
        let older = #"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"topLeft"}"#
        let settings = try JSONDecoder().decode(GameSettings.self, from: Data(older.utf8))
        XCTAssertEqual(settings.overlay, .topLeft)
        XCTAssertEqual(settings.style, .minimal)
    }
}
