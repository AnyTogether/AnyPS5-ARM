import Foundation

/// The texts of assist (another device helps player 1) and of gyro aiming, in both languages;
/// kept apart from `T` like `TPow`.
enum TA {
    static func text(_ key: Key) -> String {
        let table = T.language == .turkish ? turkish : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case assist, assistDetail, assistOff, assistControllers, assistOn, assistShare, assistShareDetail, assistHelping
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
    ]
}
