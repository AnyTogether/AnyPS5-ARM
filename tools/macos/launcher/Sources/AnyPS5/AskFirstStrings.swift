import Foundation

/// The questions social steps ask before they happen, and the Update Required screen: their
/// texts, in both languages.
enum TK {
    enum Key: String, CaseIterable {
        case askLeaveParty, askKick, askEndTogether, askLeaveTogether, askRemoveViewer, askStopShare, askClosePost
        case updateRequiredTitle = "requiredTitle", updateRequiredSubtitle, updateRequiredTooOld = "requiredTooOld", updateRequiredTooOldVersion = "requiredTooOldVersion", updateRequiredDetail, updateRequiredUpdate, updateRequiredUpdateDetail
        case updateRequiredRestart, updateRequiredRestartDetail, updateRequiredDownloading, updateRequiredLooking, updateRequiredDownload = "requiredDownload"
        case updateRequiredDownloadDetail = "requiredDownloadDetail", updateRequiredLater = "requiredLater", updateRequiredToast
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    static let english: [Key: String] = [
        .askLeaveParty: "Leave the party? Voice ends for you, and an invite-only party takes a new invite to get back in.",
        .askKick: "Remove %@ from the party? They need a new invite to come back.",
        .askEndTogether: "End Play Together for everyone? The others stay in their game, alone.",
        .askLeaveTogether: "Leave the game? Your game keeps running, without the others.",
        .askRemoveViewer: "Take %@ out? They need a new invite to watch again.",
        .askStopShare: "Stop share play? Everyone watching is let go.",
        .askClosePost: "Close this post? Its requests go with it.",
        .updateRequiredTitle: "Update Required",
        .updateRequiredSubtitle: "AnyTogether needs AnyPS5 %@ or newer",
        .updateRequiredTooOld: "This AnyPS5 is too old for AnyTogether",
        .updateRequiredTooOldVersion: "AnyPS5 %@ is too old for AnyTogether",
        .updateRequiredDetail: "Friends, parties, messages and cloud saves wait for the update. Your games still play.",
        .updateRequiredUpdate: "Update to %@",
        .updateRequiredUpdateDetail: "Downloads it, checks its signature, then asks to restart",
        .updateRequiredRestart: "Restart Now",
        .updateRequiredRestartDetail: "AnyPS5 %@ is ready; with a game running, it restarts after it",
        .updateRequiredDownloading: "Downloading the update… %d%%",
        .updateRequiredLooking: "Looking for the update…",
        .updateRequiredDownload: "Get the Update",
        .updateRequiredDownloadDetail: "Opens the downloads page in your browser",
        .updateRequiredLater: "Later",
        .updateRequiredToast: "AnyTogether needs AnyPS5 %@ or newer: Settings → About",
    ]

    static let turkish: [Key: String] = [
        .askLeaveParty: "Partiden ayrılınsın mı? Sesli sohbet senin için biter; yalnızca davetle girilen partiye dönmek için yeni davet gerekir.",
        .askKick: "%@ partiden çıkarılsın mı? Geri gelmek için yeni bir davet gerekir.",
        .askEndTogether: "Birlikte Oyna herkes için bitsin mi? Diğerleri oyunlarında yalnız kalır.",
        .askLeaveTogether: "Oyundan ayrılınsın mı? Oyunun diğerleri olmadan çalışmaya devam eder.",
        .askRemoveViewer: "%@ çıkarılsın mı? Yeniden izlemek için yeni bir davet gerekir.",
        .askStopShare: "Paylaşım durdurulsun mu? İzleyen herkesin bağlantısı kesilir.",
        .askClosePost: "Bu ilan kapatılsın mı? İstekleri de gider.",
        .updateRequiredTitle: "Güncelleme Gerekli",
        .updateRequiredSubtitle: "AnyTogether için AnyPS5 %@ ya da daha yenisi gerekiyor",
        .updateRequiredTooOld: "Bu AnyPS5, AnyTogether için çok eski",
        .updateRequiredTooOldVersion: "AnyPS5 %@, AnyTogether için çok eski",
        .updateRequiredDetail: "Arkadaşlar, partiler, mesajlar ve bulut kayıtları güncellemeyi bekliyor. Oyunların yine oynanır.",
        .updateRequiredUpdate: "%@ sürümüne güncelle",
        .updateRequiredUpdateDetail: "İndirir, imzasını denetler, sonra yeniden başlatmayı sorar",
        .updateRequiredRestart: "Şimdi Yeniden Başlat",
        .updateRequiredRestartDetail: "AnyPS5 %@ hazır; bir oyun açıksa oyundan sonra yeniden başlar",
        .updateRequiredDownloading: "Güncelleme indiriliyor… %%%d",
        .updateRequiredLooking: "Güncelleme aranıyor…",
        .updateRequiredDownload: "Güncellemeyi İndir",
        .updateRequiredDownloadDetail: "İndirme sayfasını tarayıcında açar",
        .updateRequiredLater: "Sonra",
        .updateRequiredToast: "AnyTogether için AnyPS5 %@ ya da daha yenisi gerekiyor: Ayarlar → Hakkında",
    ]
}
