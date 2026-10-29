import Foundation

/// The texts of trophy levels, the showcase, comparing trophies and appearing offline, in both
/// languages (the same words the website uses). `TL.text(.key)` reads the launcher's language.
enum TL {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        // Levels
        case trophyLevel = "levelTitle", levelLabel, tierBronze = "levelTierBronze", tierSilver = "levelTierSilver", tierGold = "levelTierGold", tierPlatinum = "levelTierPlatinum", levelNext = "levelNextPoints", levelTop, levelPoints
        case levelUp = "levelUpKicker", levelUpTitle = "levelUp", levelUpDetail, friendLevelUp, notifLevelUp
        // Showcase
        case showcase = "showcaseTitle", showcaseTrophies, showcaseGames, showcaseEmpty, showcasePrivate
        // Compare
        case compareTrophies, compareTitle, compareLead, compareGameLead, compareNoGames, compareBoth, compareNotYet, compareNotPlayed
        case comparePrivate, compareFailed, compareLoading, compareYou, compareGames, compareBothPlay, hintCompare, hintTrophies, compareUnknownGame
        // Appear offline
        case presenceTitle, presenceOnline, presenceOffline = "presenceAppearOffline", presenceHint, appearingOffline = "presenceAppearing", presenceUnavailable
    }
}
