import Foundation

/// The texts of AnyTogether's social screens (activity, leaderboards, notifications, community
/// compatibility), in both languages; kept apart from `T` so they grow without touching its table.
/// `TS.text(.key)` reads the launcher's current language.
enum TS {
    static func text(_ key: Key) -> String {
        let table = T.language == .turkish ? turkish : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String {
        // Activity
        case feedTitle, feedSubtitle, feedRow, feedRowDetail, feedEmpty, feedFailed, feedLoading, feedMore
        case feedTrophy, feedTrophies, feedPlatinum, feedFirstPlay, feedLongSession, feedFriendship, feedOther
        case feedMilestoneTrophies, feedMilestonePlatinums, feedMilestoneGames, feedMilestoneHours
        case feedAndMore, feedRare, hintReact, hintProfile
        case profileActivity, profileNoActivity
    }

    static let english: [Key: String] = [
        .feedTitle: "Activity",
        .feedSubtitle: "What your friends have been playing",
        .feedRow: "Activity",
        .feedRowDetail: "Friends' trophies, first plays and milestones",
        .feedEmpty: "Nothing from your friends yet. Trophies, first plays and long sessions show up here.",
        .feedFailed: "Couldn't read the activity",
        .feedLoading: "Reading the activity…",
        .feedMore: "Older activity…",
        .feedTrophy: "earned a trophy in %@",
        .feedTrophies: "earned %2$d trophies in %1$@",
        .feedPlatinum: "earned the platinum in %@",
        .feedFirstPlay: "played %@ for the first time",
        .feedLongSession: "played %1$@ for %2$@",
        .feedFriendship: "is now friends with %@",
        .feedOther: "did something new",
        .feedMilestoneTrophies: "reached %d trophies",
        .feedMilestonePlatinums: "reached %d platinums",
        .feedMilestoneGames: "has played %d games",
        .feedMilestoneHours: "has played for %d hours",
        .feedAndMore: "+%d more",
        .feedRare: "Rare",
        .hintReact: "React",
        .hintProfile: "Profile",
        .profileActivity: "Recent activity",
        .profileNoActivity: "No activity yet",
    ]

    static let turkish: [Key: String] = [
        .feedTitle: "Etkinlikler",
        .feedSubtitle: "Arkadaşların neler oynuyor",
        .feedRow: "Etkinlikler",
        .feedRowDetail: "Arkadaşlarının kupaları, ilk oyunları ve dönüm noktaları",
        .feedEmpty: "Arkadaşlarından henüz bir şey yok. Kupalar, ilk oyunlar ve uzun oturumlar burada görünür.",
        .feedFailed: "Etkinlikler okunamadı",
        .feedLoading: "Etkinlikler okunuyor…",
        .feedMore: "Daha eski etkinlikler…",
        .feedTrophy: "%@ oyununda bir kupa kazandı",
        .feedTrophies: "%1$@ oyununda %2$d kupa kazandı",
        .feedPlatinum: "%@ oyununda platini aldı",
        .feedFirstPlay: "%@ oyununu ilk kez oynadı",
        .feedLongSession: "%1$@ oyununu %2$@ oynadı",
        .feedFriendship: "%@ ile arkadaş oldu",
        .feedOther: "yeni bir şey yaptı",
        .feedMilestoneTrophies: "%d kupaya ulaştı",
        .feedMilestonePlatinums: "%d platine ulaştı",
        .feedMilestoneGames: "%d oyun oynadı",
        .feedMilestoneHours: "%d saat oynadı",
        .feedAndMore: "+%d tane daha",
        .feedRare: "Nadir",
        .hintReact: "Tepki ver",
        .hintProfile: "Profil",
        .profileActivity: "Son etkinlikler",
        .profileNoActivity: "Henüz etkinlik yok",
    ]
}
