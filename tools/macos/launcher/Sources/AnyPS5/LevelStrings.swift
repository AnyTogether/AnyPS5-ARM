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

    static let english: [Key: String] = [
        .trophyLevel: "Trophy level",
        .levelLabel: "Trophy level %d",
        .tierBronze: "Bronze",
        .tierSilver: "Silver",
        .tierGold: "Gold",
        .tierPlatinum: "Platinum",
        .levelNext: "%1$@ points to level %2$d",
        .levelTop: "The highest level there is",
        .levelPoints: "%@ points",
        .levelUp: "Level up",
        .levelUpTitle: "Trophy level %d",
        .levelUpDetail: "You reached a new trophy level",
        .friendLevelUp: "%1$@ reached trophy level %2$d",
        .notifLevelUp: "You reached trophy level %d",
        .showcase: "Showcase",
        .showcaseTrophies: "Pinned trophies",
        .showcaseGames: "Favourite games",
        .showcaseEmpty: "Nothing pinned yet.",
        .showcasePrivate: "%@ keeps the showcase private",
        .compareTrophies: "Compare trophies",
        .compareTitle: "You and %@",
        .compareLead: "Games either of you has trophies in, the ones you both play first.",
        .compareGameLead: "Who earned what, and when.",
        .compareNoGames: "Neither of you has trophies yet.",
        .compareBoth: "%d earned by both",
        .compareNotYet: "Not yet",
        .compareNotPlayed: "Not played",
        .comparePrivate: "%@ keeps their trophies to themselves.",
        .compareFailed: "Couldn't compare trophies",
        .compareLoading: "Comparing trophies…",
        .compareYou: "You",
        .compareGames: "All games",
        .compareBothPlay: "You both play it",
        .hintCompare: "Compare",
        .hintTrophies: "Trophies",
        .compareUnknownGame: "This game has no trophies on AnyTogether yet.",
        .presenceTitle: "Show me as",
        .presenceOnline: "Online",
        .presenceOffline: "Appear offline",
        .presenceHint: "Friends see you as offline. Messages, parties and cloud saves keep working.",
        .appearingOffline: "Appearing offline",
        .presenceUnavailable: "Appearing offline isn't available on this server yet",
    ]

    static let turkish: [Key: String] = [
        .trophyLevel: "Kupa seviyesi",
        .levelLabel: "Kupa seviyesi %d",
        .tierBronze: "Bronz",
        .tierSilver: "Gümüş",
        .tierGold: "Altın",
        .tierPlatinum: "Platin",
        .levelNext: "%2$d. seviyeye %1$@ puan",
        .levelTop: "Ulaşılabilecek en yüksek seviye",
        .levelPoints: "%@ puan",
        .levelUp: "Seviye atladın",
        .levelUpTitle: "Kupa seviyesi %d",
        .levelUpDetail: "Yeni bir kupa seviyesine ulaştın",
        .friendLevelUp: "%1$@ %2$d. kupa seviyesine ulaştı",
        .notifLevelUp: "Kupa seviyen %d oldu",
        .showcase: "Vitrin",
        .showcaseTrophies: "Sabitlenen kupalar",
        .showcaseGames: "Sevdiği oyunlar",
        .showcaseEmpty: "Henüz sabitlenen bir şey yok.",
        .showcasePrivate: "%@ vitrinini gizli tutuyor",
        .compareTrophies: "Kupaları karşılaştır",
        .compareTitle: "Sen ve %@",
        .compareLead: "İkinizden birinin kupası olan oyunlar; ikinizin de oynadıkları önce.",
        .compareGameLead: "Kim neyi ne zaman kazandı.",
        .compareNoGames: "İkinizin de henüz kupası yok.",
        .compareBoth: "%d tanesini ikiniz de kazandınız",
        .compareNotYet: "Henüz değil",
        .compareNotPlayed: "Oynamadı",
        .comparePrivate: "%@ kupalarını kendine saklıyor.",
        .compareFailed: "Kupalar karşılaştırılamadı",
        .compareLoading: "Kupalar karşılaştırılıyor…",
        .compareYou: "Sen",
        .compareGames: "Tüm oyunlar",
        .compareBothPlay: "İkiniz de oynuyorsunuz",
        .hintCompare: "Karşılaştır",
        .hintTrophies: "Kupalar",
        .compareUnknownGame: "Bu oyunun AnyTogether'da henüz kupası yok.",
        .presenceTitle: "Beni şöyle göster",
        .presenceOnline: "Çevrimiçi",
        .presenceOffline: "Çevrimdışı görün",
        .presenceHint: "Arkadaşların seni çevrimdışı görür. Mesajlar, partiler ve bulut kayıtları çalışmaya devam eder.",
        .appearingOffline: "Çevrimdışı görünüyorsun",
        .presenceUnavailable: "Çevrimdışı görünme bu sunucuda henüz yok",
    ]
}
