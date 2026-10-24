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
        // Leaderboards
        case boardTitle, boardOverall, boardPoints, boardTime, boardCompletion, scopeFriends, scopeGlobal, boardYourRank, boardOf, boardPointsValue
        case boardEmpty, boardFailed, boardLoading, boardNoGame, boardUnlisted, boardWouldBe, boardNothing, boardRowDetail, boardGameRowDetail
        case hintBoard, hintScope, boardYou, boardPlayers
        // Notifications
        case notifTitle, notifEmpty, notifMarkAll, notifMore, notifFailed, notifLoading, notifUnread, notifSignIn
        case notifFriendRequest, notifFriendAccepted, notifMessage, notifMessages, notifPartyInvite, notifGameInvite, notifMissedCall, notifWarning, notifOther
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
        .boardTitle: "Leaderboard",
        .boardOverall: "Trophy points",
        .boardPoints: "Points",
        .boardTime: "Play time",
        .boardCompletion: "Completion",
        .scopeFriends: "Friends",
        .scopeGlobal: "Everyone",
        .boardYourRank: "Your rank",
        .boardOf: "of %d",
        .boardPointsValue: "%@ pts",
        .boardEmpty: "No one to rank yet",
        .boardFailed: "Couldn't read the leaderboard",
        .boardLoading: "Reading the leaderboard…",
        .boardNoGame: "No one has played this on AnyTogether yet",
        .boardUnlisted: "You're not on this board: it only lists people whose trophies and library are public",
        .boardWouldBe: "You'd be #%d",
        .boardNothing: "Nothing to rank yet: play and earn trophies to get on the board",
        .boardRowDetail: "Trophy points among friends or everyone",
        .boardGameRowDetail: "Points, play time and completion, among friends or everyone",
        .hintBoard: "Board",
        .hintScope: "Friends / Everyone",
        .boardYou: "You",
        .boardPlayers: "%d players",
        .notifTitle: "Notifications",
        .notifEmpty: "You're all caught up",
        .notifMarkAll: "Mark all as read",
        .notifMore: "Older notifications",
        .notifFailed: "Couldn't read the notifications",
        .notifLoading: "Reading the notifications…",
        .notifUnread: "%d unread",
        .notifSignIn: "Sign in to AnyTogether to get notifications",
        .notifFriendRequest: "%@ wants to be friends",
        .notifFriendAccepted: "%@ accepted your friend request",
        .notifMessage: "%@ wrote to you",
        .notifMessages: "%1$@ sent you %2$d messages",
        .notifPartyInvite: "%@ invited you to their party",
        .notifGameInvite: "%1$@ invited you to play %2$@",
        .notifMissedCall: "Missed call from %@",
        .notifWarning: "A moderator warned you",
        .notifOther: "Something new on AnyTogether",
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
        .boardTitle: "Sıralama",
        .boardOverall: "Kupa puanları",
        .boardPoints: "Puan",
        .boardTime: "Oynama süresi",
        .boardCompletion: "Tamamlama",
        .scopeFriends: "Arkadaşlar",
        .scopeGlobal: "Herkes",
        .boardYourRank: "Sıran",
        .boardOf: "%d kişi içinde",
        .boardPointsValue: "%@ puan",
        .boardEmpty: "Henüz sıralanacak kimse yok",
        .boardFailed: "Sıralama okunamadı",
        .boardLoading: "Sıralama okunuyor…",
        .boardNoGame: "Bunu AnyTogether'da henüz kimse oynamadı",
        .boardUnlisted: "Bu sıralamada değilsin: yalnızca kupaları ve kütüphanesi herkese açık olanlar listelenir",
        .boardWouldBe: "#%d olurdun",
        .boardNothing: "Henüz sıralanacak bir şeyin yok: oyna ve kupa kazan, sıralamaya gir",
        .boardRowDetail: "Arkadaşlar ya da herkes arasında kupa puanları",
        .boardGameRowDetail: "Arkadaşlar ya da herkes arasında puan, oynama süresi ve tamamlama",
        .hintBoard: "Tablo",
        .hintScope: "Arkadaşlar / Herkes",
        .boardYou: "Sen",
        .boardPlayers: "%d oyuncu",
        .notifTitle: "Bildirimler",
        .notifEmpty: "Hepsini gördün",
        .notifMarkAll: "Tümünü okundu say",
        .notifMore: "Daha eski bildirimler",
        .notifFailed: "Bildirimler okunamadı",
        .notifLoading: "Bildirimler okunuyor…",
        .notifUnread: "%d okunmamış",
        .notifSignIn: "Bildirim almak için AnyTogether'a giriş yap",
        .notifFriendRequest: "%@ arkadaş olmak istiyor",
        .notifFriendAccepted: "%@ arkadaşlık isteğini kabul etti",
        .notifMessage: "%@ sana yazdı",
        .notifMessages: "%1$@ sana %2$d mesaj gönderdi",
        .notifPartyInvite: "%@ seni partisine davet etti",
        .notifGameInvite: "%1$@ seni %2$@ oynamaya davet etti",
        .notifMissedCall: "Cevapsız arama: %@",
        .notifWarning: "Bir moderatör seni uyardı",
        .notifOther: "AnyTogether'da yeni bir şey var",
    ]
}
