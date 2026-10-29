import Foundation

/// The texts of assist (another device helps player 1) and of gyro aiming, from the language files (l10n);
/// kept apart from `T` like `TPow`.
enum TA {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case assist = "padAssist", assistDetail = "padAssistDetail", assistOff = "padAssistOff", assistControllers = "padAssistControllers", assistOn = "padAssistOn", assistShare, assistShareDetail, assistHelping
        case gyroSection, gyro, gyroDetail, gyroSensitivity, gyroSensitivityDetail, gyroInvert, gyroInvertNone = "gyroInvert_none", gyroInvertX = "gyroInvert_x", gyroInvertY = "gyroInvert_y", gyroInvertBoth = "gyroInvert_xy"
        case gyroActivation, gyroActivationDetail, gyroAlways = "gyro_always", gyroL2 = "gyro_l2", gyroTouch = "gyro_touch", gyroDeadzone, gyroDeadzoneDetail, degreesPerSecond
    }
}
