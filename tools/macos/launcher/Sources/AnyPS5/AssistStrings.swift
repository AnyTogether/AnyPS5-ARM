import Foundation

/// The texts of assist (another device helps player 1) and of gyro aiming, in both languages;
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

    static let english: [Key: String] = [
        .assist: "Assist Player 1",
        .assistDetail: "Another device plays player 1 together with you: its buttons and sticks join yours. Good for helping with a hard part, or for anyone who plays better with a second pair of hands",
        .assistOff: "Off",
        .assistControllers: "Other controllers",
        .assistOn: "%@ helps player 1",
        .assistShare: "Assist Player 1",
        .assistShareDetail: "%@ helps you play player 1 instead of playing their own",
        .assistHelping: "Helping player 1",
        .gyroSection: "Gyro Aiming",
        .gyro: "Aim with the Gyro",
        .gyroDetail: "Turn the controller or the phone to move the right stick",
        .gyroSensitivity: "Sensitivity",
        .gyroSensitivityDetail: "At 1.0, a full stick at 90°/s",
        .gyroInvert: "Invert",
        .gyroInvertNone: "Off",
        .gyroInvertX: "Left and right",
        .gyroInvertY: "Up and down",
        .gyroInvertBoth: "Both",
        .gyroActivation: "Aim",
        .gyroActivationDetail: "L2 suits aiming down the sights",
        .gyroAlways: "Always",
        .gyroL2: "While L2 is held",
        .gyroTouch: "While touching the touchpad",
        .gyroDeadzone: "Dead Zone",
        .gyroDeadzoneDetail: "A hand held still moves nothing; turns slower than this are ignored",
        .degreesPerSecond: "%d°/s",
    ]

    static let turkish: [Key: String] = [
        .assist: "1. Oyuncuya Yardım",
        .assistDetail: "Başka bir cihaz 1. oyuncuyu seninle birlikte oynar: onun tuşları ve çubukları seninkilere eklenir. Zor bir yerde yardım için, ya da ikinci bir el ile daha rahat oynayanlar için",
        .assistOff: "Kapalı",
        .assistControllers: "Diğer kumandalar",
        .assistOn: "%@ 1. oyuncuya yardım ediyor",
        .assistShare: "1. Oyuncuya Yardım",
        .assistShareDetail: "%@ kendi oyuncusu yerine 1. oyuncuyu seninle birlikte oynar",
        .assistHelping: "1. oyuncuya yardım ediyor",
        .gyroSection: "Jiroskopla Nişan",
        .gyro: "Jiroskopla Nişan Al",
        .gyroDetail: "Kumandayı ya da telefonu çevirince sağ çubuk oynar",
        .gyroSensitivity: "Hassasiyet",
        .gyroSensitivityDetail: "1.0'da 90°/s tam çubuktur",
        .gyroInvert: "Ters Çevir",
        .gyroInvertNone: "Kapalı",
        .gyroInvertX: "Sağ ve sol",
        .gyroInvertY: "Yukarı ve aşağı",
        .gyroInvertBoth: "İkisi de",
        .gyroActivation: "Nişan",
        .gyroActivationDetail: "L2, nişangâhla nişan almaya uyar",
        .gyroAlways: "Her zaman",
        .gyroL2: "L2 basılıyken",
        .gyroTouch: "Dokunmatik yüzeye dokunurken",
        .gyroDeadzone: "Ölü Bölge",
        .gyroDeadzoneDetail: "Sabit tutulan el hiçbir şeyi oynatmaz; bundan yavaş dönüşler yok sayılır",
        .degreesPerSecond: "%d°/s",
    ]
}
