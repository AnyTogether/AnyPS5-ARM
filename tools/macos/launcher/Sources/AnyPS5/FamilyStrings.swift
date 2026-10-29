import AnyPS5Core
import Foundation

/// Family limits: play time, age ratings, asking a parent and what a parent turned off: the
/// texts, in both languages.
enum FS {
    enum Key: String, CaseIterable {
        case family = "familyTitle", leftToday = "familyLeftToday", noLimitToday = "familyNoLimitToday", timeUp = "familyTimeUp", outsideHours = "familyOutsideHours", playedToday = "familyPlayedToday", limitToday = "familyLimitToday"
        case stale = "familyStaleConnect", staleDetail = "familyStaleDetail", locked = "familyLocked", lockedDetail = "familyLockedDetail", signInToAsk = "familySignInToAsk"
        case askParent = "familyAskParent", askedTooMany = "familyAskedTooMany", askMoreTime = "familyAskMoreTime", askMinutes = "familyAskMinutesFor", askMinutesDetail = "familyAskTimeDetail", asked = "familyAsked", askedAlready = "familyAskedAlready", askedGame = "familyAskedToPlay", askedFriend = "familyAskedFriend", askFriend = "familyAskFriend", askFailed = "familyAskFailed"
        case ratedAbove = "familyRatedAbove", ratedUnknown = "familyRatedUnknown", startLimit = "familyStartLimit", startWindow = "familyStartWindow"
        case warnMinutes = "familyWarnMinutes", warnOne = "familyWarnOne", warnDetail = "familyWarnDetail", noticeTitle = "familyNoticeTitle", noticeCloses = "familyNoticeCloses", noticeClosing = "familyNoticeClosing", noticeNotify = "familyNoticeNotify", noticeAsk = "familyNoticeAsk", moreTime = "familyMoreTime"
        case hoursMinutes = "familyHoursMinutes", minutes = "familyMinutes"
        case refusedVoice = "familyRefusedVoice", refusedShare = "familyRefusedShare", refusedPublic = "familyRefusedPublic", refusedMessages = "familyRefusedMessages", refusedFriends = "familyRefusedFriends", refusedDiscovery = "familyRefusedDiscovery", refusedMedia = "familyRefusedMedia", refusedProfile = "familyRefusedProfile", refusedCommunities = "familyRefusedCommunities", refusedAge = "familyRefusedAge", refusedFamily = "familyRefusedFamily"
        case refusedOther = "familyOtherSide", otherServer = "familyOtherServer"
        case notifAsksTime = "familyNotifAsksTime", notifAsksGame = "familyNotifAsksGame", notifAsksFriend = "familyNotifAsksFriend", notifSaidNo = "familyNotifSaidNo", notifGaveTime = "familyNotifGaveTime", notifGameYes = "familyNotifGameYes", notifFriendYes = "familyNotifFriendYes"
        case notifReachedLimit = "familyNotifReachedLimit", notifJoinedFamily = "familyNotifJoinedFamily", notifDeclinedFamily = "familyNotifDeclinedFamily", notifFamilyInvite = "familyNotifFamilyInvite", notifSummary = "familyNotifSummary"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// "1 h 20 min", "45 min"; a started minute counts.
    static func duration(_ seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60).rounded(.up))
        return minutes >= 60 ? format(.hoursMinutes, minutes / 60, minutes % 60) : format(.minutes, minutes)
    }

    /// What a parent's settings refused, as a 403 names it.
    static func refusal(_ feature: FamilyFeature) -> String {
        switch feature {
        case .voiceChat: return text(.refusedVoice)
        case .sharePlay: return text(.refusedShare)
        case .publicMatchmaking: return text(.refusedPublic)
        case .messages: return text(.refusedMessages)
        case .friendRequests: return text(.refusedFriends)
        case .discovery: return text(.refusedDiscovery)
        case .mediaSharing: return text(.refusedMedia)
        case .profileVisibility: return text(.refusedProfile)
        case .communities: return text(.refusedCommunities)
        case .ageRating: return text(.refusedAge)
        case .family: return text(.refusedFamily)
        }
    }

    static let english: [Key: String] = [
        .family: "Family",
        .leftToday: "%@ left to play today",
        .noLimitToday: "No play-time limit today",
        .timeUp: "Today's play time is over",
        .outsideHours: "You can play between %@ and %@",
        .playedToday: "Played today: %@",
        .limitToday: "Today's limit: %@ · played %@",
        .stale: "Connect to refresh your family's limits",
        .staleDetail: "Last checked %@: the limits from then still apply",
        .locked: "Your family's limits need checking",
        .lockedDetail: "Sign in to AnyTogether while online: games stay closed until then",
        .signInToAsk: "Sign in to AnyTogether to ask a parent",
        .askParent: "Ask a parent",
        .askMoreTime: "Ask for more time",
        .askMinutes: "Ask for %d more minutes",
        .askMinutesDetail: "A parent answers on the AnyTogether website",
        .asked: "Asked. A parent can answer on the AnyTogether website",
        .askedAlready: "Already asked: waiting for a parent",
        .askedTooMany: "That's a lot of asks today: try again tomorrow",
        .askedGame: "Asked a parent to let you play %@",
        .askedFriend: "Asked a parent to add @%@",
        .askFriend: "Ask a parent to add them",
        .askFailed: "Could not ask: check the connection",
        .ratedAbove: "Rated %d+: above what your family allows",
        .ratedUnknown: "No age rating: your family wants you to ask first",
        .startLimit: "Today's play time is over. Ask a parent for more time",
        .startWindow: "Play time today is %@–%@. Ask a parent for more time",
        .warnMinutes: "%d minutes left",
        .warnOne: "1 minute left",
        .warnDetail: "Today's play time is nearly over: a good moment to save",
        .noticeTitle: "Time's up for today",
        .noticeCloses: "The game closes in %@. Save your game now.",
        .noticeClosing: "Closing the game…",
        .noticeNotify: "Your parents have been told.",
        .noticeAsk: "Ask a parent for more time in the launcher: Settings → AnyTogether.",
        .moreTime: "More time: %@ left",
        .hoursMinutes: "%d h %d min",
        .minutes: "%d min",
        .refusedVoice: "Voice chat is turned off by your family",
        .refusedShare: "Share play is turned off by your family",
        .refusedPublic: "Public groups and Find players are turned off by your family",
        .refusedMessages: "Messages are turned off by your family",
        .refusedFriends: "Your family approves new friends: ask a parent",
        .refusedDiscovery: "Discovery is turned off by your family",
        .refusedMedia: "Sharing clips and screenshots is turned off by your family",
        .refusedProfile: "Your family keeps your profile private",
        .refusedCommunities: "Communities are turned off by your family",
        .refusedAge: "This game's age rating is above what your family allows",
        .refusedFamily: "Your family's settings don't allow this",
        .refusedOther: "This person's family settings don't allow it",
        .notifAsksTime: "%@ asks for %d more minutes",
        .notifAsksGame: "%@ asks to play %@",
        .notifAsksFriend: "%@ asks to add a friend",
        .notifSaidNo: "A parent said no this time",
        .notifGaveTime: "A parent gave you %d more minutes",
        .notifGameYes: "A parent said yes: the game is open",
        .notifFriendYes: "A parent said yes to your new friend",
        .notifReachedLimit: "%@ reached today's play time",
        .notifJoinedFamily: "%@ joined your family",
        .notifDeclinedFamily: "%@ did not join your family",
        .notifFamilyInvite: "%@ invites you to the family %@",
        .notifSummary: "Your family's week in games",
        .otherServer: "Your family's limits come from %@: a parent signs in there to change them",
    ]

    static let turkish: [Key: String] = [
        .family: "Aile",
        .leftToday: "Bugün %@ daha oynayabilirsin",
        .noLimitToday: "Bugün oyun süresi sınırı yok",
        .timeUp: "Bugünkü oyun süren doldu",
        .outsideHours: "%@ ile %@ arasında oynayabilirsin",
        .playedToday: "Bugün oynadığın: %@",
        .limitToday: "Bugünkü sınır: %@ · oynanan %@",
        .stale: "Ailenin sınırlarını yenilemek için bağlan",
        .staleDetail: "Son denetim %@: o günkü sınırlar geçerli",
        .locked: "Ailenin sınırlarının denetlenmesi gerekiyor",
        .lockedDetail: "İnternete bağlıyken AnyTogether'a giriş yap: o zamana kadar oyunlar kapalı",
        .signInToAsk: "Ebeveynine sormak için AnyTogether'a giriş yap",
        .askParent: "Ebeveynine sor",
        .askMoreTime: "Daha fazla süre iste",
        .askMinutes: "%d dakika daha iste",
        .askMinutesDetail: "Ebeveynin AnyTogether sitesinden yanıtlar",
        .asked: "Soruldu. Ebeveynin AnyTogether sitesinden yanıtlayabilir",
        .askedAlready: "Zaten soruldu: ebeveynin bekleniyor",
        .askedTooMany: "Bugün çok fazla soru soruldu: yarın yeniden dene",
        .askedGame: "%@ oynamak için ebeveynine soruldu",
        .askedFriend: "@%@ kişisini eklemek için ebeveynine soruldu",
        .askFriend: "Eklemek için ebeveynine sor",
        .askFailed: "Sorulamadı: bağlantını kontrol et",
        .ratedAbove: "%d+ yaş: ailenin izin verdiğinin üstünde",
        .ratedUnknown: "Yaş sınırı yok: ailen önce sormanı istiyor",
        .startLimit: "Bugünkü oyun süren doldu. Ebeveyninden daha fazla süre iste",
        .startWindow: "Bugün oyun saati %@–%@. Ebeveyninden daha fazla süre iste",
        .warnMinutes: "%d dakika kaldı",
        .warnOne: "1 dakika kaldı",
        .warnDetail: "Bugünkü oyun süren bitmek üzere: kaydetmek için iyi bir an",
        .noticeTitle: "Bugünlük süre doldu",
        .noticeCloses: "Oyun %@ sonra kapanacak. Oyununu şimdi kaydet.",
        .noticeClosing: "Oyun kapatılıyor…",
        .noticeNotify: "Ebeveynlerine haber verildi.",
        .noticeAsk: "Başlatıcıdan daha fazla süre iste: Ayarlar → AnyTogether.",
        .moreTime: "Ek süre: %@ kaldı",
        .hoursMinutes: "%d sa %d dk",
        .minutes: "%d dk",
        .refusedVoice: "Sesli sohbet ailen tarafından kapatıldı",
        .refusedShare: "Birlikte oyna ailen tarafından kapatıldı",
        .refusedPublic: "Herkese açık gruplar ve Oyuncu bul ailen tarafından kapatıldı",
        .refusedMessages: "Mesajlar ailen tarafından kapatıldı",
        .refusedFriends: "Yeni arkadaşları ailen onaylıyor: ebeveynine sor",
        .refusedDiscovery: "Keşif ailen tarafından kapatıldı",
        .refusedMedia: "Klip ve ekran görüntüsü paylaşmak ailen tarafından kapatıldı",
        .refusedProfile: "Ailen profilini gizli tutuyor",
        .refusedCommunities: "Topluluklar ailen tarafından kapatıldı",
        .refusedAge: "Bu oyunun yaş sınırı ailenin izin verdiğinin üstünde",
        .refusedFamily: "Ailenin ayarları buna izin vermiyor",
        .refusedOther: "Bu kişinin aile ayarları buna izin vermiyor",
        .notifAsksTime: "%@ %d dakika daha istiyor",
        .notifAsksGame: "%@, %@ oynamak istiyor",
        .notifAsksFriend: "%@ bir arkadaş eklemek istiyor",
        .notifSaidNo: "Ebeveynin bu sefer hayır dedi",
        .notifGaveTime: "Ebeveynin sana %d dakika daha verdi",
        .notifGameYes: "Ebeveynin evet dedi: oyun açıldı",
        .notifFriendYes: "Ebeveynin yeni arkadaşına evet dedi",
        .notifReachedLimit: "%@ bugünkü oyun süresini doldurdu",
        .notifJoinedFamily: "%@ ailene katıldı",
        .notifDeclinedFamily: "%@ ailene katılmadı",
        .notifFamilyInvite: "%@ seni %@ ailesine davet ediyor",
        .notifSummary: "Ailenin oyun haftası",
        .otherServer: "Ailenin sınırları %@ sunucusundan geliyor: değiştirmek için bir ebeveyn orada giriş yapar",
    ]
}
