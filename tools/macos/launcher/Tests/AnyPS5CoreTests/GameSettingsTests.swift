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

    func testSettingsSavedBeforeTheStyleStillRead() throws {
        let older = #"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"topLeft"}"#
        let settings = try JSONDecoder().decode(GameSettings.self, from: Data(older.utf8))
        XCTAssertEqual(settings.overlay, .topLeft)
        XCTAssertEqual(settings.style, .minimal)
    }
}
