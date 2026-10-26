import XCTest
@testable import AnyPS5Core

/// Gyro aiming as a game's setting and the ANYPS5_GYRO_AIM the engine reads (GyroAim::Parse).
final class GyroAimingTests: XCTestCase {
    func testOffPassesNothing() {
        XCTAssertNil(GyroAiming().environment)
        XCTAssertNil(GameSettings().environment(launcherLanguage: 1)["ANYPS5_GYRO_AIM"])
        var settings = GameSettings()
        settings.gyro = GyroAiming()
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_GYRO_AIM"], "kept but off")
    }

    func testOnPassesEverySetting() {
        var aim = GyroAiming()
        aim.enabled = true
        XCTAssertEqual(aim.environment, "sensitivity=1.0,invert=none,activate=always,deadzone=2")
        aim.sensitivity = 25
        aim.invert = .y
        aim.activation = .l2
        aim.deadzone = 6
        var settings = GameSettings()
        settings.gyro = aim
        XCTAssertEqual(settings.environment(launcherLanguage: 1)["ANYPS5_GYRO_AIM"], "sensitivity=2.5,invert=y,activate=l2,deadzone=6")
        aim.activation = .touch
        aim.invert = .xy
        XCTAssertEqual(aim.environment, "sensitivity=2.5,invert=xy,activate=touch,deadzone=6")
    }

    func testValuesAreKeptToWhatTheEngineTakes() {
        var aim = GyroAiming()
        aim.enabled = true
        aim.sensitivity = 0
        aim.deadzone = 99
        XCTAssertEqual(aim.environment, "sensitivity=0.1,invert=none,activate=always,deadzone=45")
        aim.sensitivity = 500
        aim.deadzone = -3
        XCTAssertEqual(aim.environment, "sensitivity=10.0,invert=none,activate=always,deadzone=0")
    }

    func testSavedSettingsRoundTripAndOlderOnesStillRead() throws {
        var aim = GyroAiming()
        aim.enabled = true
        aim.sensitivity = 15
        aim.activation = .touch
        var settings = GameSettings()
        settings.gyro = aim
        let again = try JSONDecoder().decode(GameSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(again.gyro, aim)
        let older = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"off"}"#.utf8))
        XCTAssertNil(older.gyro)
        let partial = try JSONDecoder().decode(GyroAiming.self, from: Data(#"{"enabled":true,"activation":"sideways"}"#.utf8))
        XCTAssertTrue(partial.enabled)
        XCTAssertEqual(partial.activation, .always, "an unknown value keeps the default")
        XCTAssertEqual(partial.sensitivity, 10)
    }
}
