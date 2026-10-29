import Foundation

/// Broadcasting's texts, in both languages.
enum TB {
    enum Key: String, CaseIterable {
        case title = "broadcastTitle", settingsDetail = "broadcastSettingsDetail", service = "broadcastService", serviceCustom = "broadcastServiceCustom", server = "broadcastServer", serverDetail = "broadcastServerDetail", key = "broadcastKey", keyNone = "broadcastKeyNone", keyDetail = "broadcastKeyDetail", keyEnter = "broadcastKeyEnter", keyEnterDetail = "broadcastKeyEnterDetail", keyPaste = "broadcastKeyPaste", keyPasted = "broadcastKeyPasted", keyClipboardEmpty = "broadcastKeyClipboardEmpty"
        case keyPage = "broadcastKeyPage", keyPageDetail = "broadcastKeyPageDetail", quality = "broadcastQuality", qualityDetail = "broadcastQualityDetail", microphone = "broadcastMicrophone", microphoneDetail = "broadcastMicrophoneDetail", microphoneLevel = "broadcastMicrophoneLevel", badge = "broadcastBadge", badgeDetail = "broadcastBadgeDetail", viewerLink = "broadcastViewerLink", viewerLinkDetail = "broadcastViewerLinkDetail", keptPrivately = "broadcastKeptPrivately"
        case goLive = "broadcastGoLive", goLiveDetail = "broadcastGoLiveDetail", goLiveNoGame = "broadcastGoLiveNoGame", setUpFirst = "broadcastSetUpFirst", setUpFirstDetail = "broadcastSetUpFirstDetail", live = "broadcastLive", starting = "broadcastStarting", reconnecting = "broadcastReconnecting", failed = "broadcastFailed", stop = "broadcastStop", stopped = "broadcastStopped", copyLink = "broadcastCopyLink", linkCopied = "broadcastLinkCopied"
        case liveStats = "broadcastLiveStats", dropped = "broadcastDropped", stateLine = "broadcastStateLine", startedNotice = "broadcastStartedNotice", startedDetail = "broadcastStartedDetail", endedNotice = "broadcastEndedNotice", failedNotice = "broadcastFailedNotice", reconnectingNotice = "broadcastReconnectingNotice", reconnectingDetail = "broadcastReconnectingDetail"
        case needsPermission = "broadcastNeedsPermission", needsPermissionDetail = "broadcastNeedsPermissionDetail", noMicrophone = "broadcastNoMicrophone", save = "broadcastSave", cancel = "broadcastCancel", liveBadge = "broadcastLiveBadge"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// 0:42, 12:05 or 1:02:09.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total / 60 % 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// 4.5 Mbit/s, or 850 kbit/s below one.
    static func rate(_ bits: Int) -> String {
        bits >= 1_000_000 ? String(format: "%.1f Mbit/s", Double(bits) / 1_000_000) : "\(bits / 1000) kbit/s"
    }

    static let english: [Key: String] = [
        .title: "Broadcasting",
        .settingsDetail: "Stream the game live to Twitch, YouTube or any RTMP server",
        .service: "Service",
        .serviceCustom: "Custom RTMP",
        .server: "Server",
        .serverDetail: "rtmp:// or rtmps:// address; the key can be at its end",
        .key: "Stream key",
        .keyNone: "Not set",
        .keyDetail: "From your channel's dashboard. Never show it on stream",
        .keyEnter: "Stream key for %@",
        .keyEnterDetail: "Paste the key from your channel's stream settings. It is kept on this Mac only.",
        .keyPaste: "Paste key from clipboard",
        .keyPasted: "Stream key saved",
        .keyClipboardEmpty: "There is no text on the clipboard",
        .keyPage: "Get your key",
        .keyPageDetail: "Opens %@ in your browser",
        .quality: "Quality",
        .qualityDetail: "Pick lower if frames drop: your upload needs about 1.5 times this",
        .microphone: "Microphone",
        .microphoneDetail: "Your commentary mixed over the game's sound",
        .microphoneLevel: "Microphone level",
        .badge: "LIVE badge",
        .badgeDetail: "A small badge over the game while you are live; viewers do not see it",
        .viewerLink: "Viewer link",
        .viewerLinkDetail: "Where people watch, like twitch.tv/yourname: shown and copied while live",
        .keptPrivately: "Keys are kept in a file only you can read, not in the Keychain: the launcher is signed ad hoc, so the Keychain would ask again after every update.",
        .goLive: "Broadcast %@",
        .goLiveDetail: "%@ · %@",
        .goLiveNoGame: "Start a game to go live",
        .setUpFirst: "Set up broadcasting",
        .setUpFirstDetail: "Add your stream key in Settings → Broadcasting",
        .live: "LIVE",
        .starting: "Connecting to %@…",
        .reconnecting: "Connection lost · trying again in %d s",
        .failed: "Broadcast stopped: %@",
        .stop: "Stop broadcast",
        .stopped: "Broadcast ended",
        .copyLink: "Copy viewer link",
        .linkCopied: "Viewer link copied",
        .liveStats: "On air for %@",
        .dropped: "%d dropped (%.1f%%)",
        .stateLine: "%@ · %@ · %@",
        .startedNotice: "You are live",
        .startedDetail: "Broadcasting to %@",
        .endedNotice: "Broadcast ended",
        .failedNotice: "The broadcast stopped",
        .reconnectingNotice: "Broadcast reconnecting",
        .reconnectingDetail: "The connection to %@ dropped; trying again",
        .needsPermission: "Broadcasting needs screen recording",
        .needsPermissionDetail: "Allow AnyPS5 in System Settings → Privacy & Security → Screen Recording",
        .noMicrophone: "The microphone is not allowed; the broadcast goes on without it",
        .save: "Save",
        .cancel: "Cancel",
        .liveBadge: "LIVE",
    ]

    static let turkish: [Key: String] = [
        .title: "Yayın",
        .settingsDetail: "Oyunu Twitch'e, YouTube'a ya da herhangi bir RTMP sunucusuna canlı yayınla",
        .service: "Servis",
        .serviceCustom: "Özel RTMP",
        .server: "Sunucu",
        .serverDetail: "rtmp:// ya da rtmps:// adresi; anahtar sonunda olabilir",
        .key: "Yayın anahtarı",
        .keyNone: "Ayarlanmadı",
        .keyDetail: "Kanal panelinden alınır. Yayında asla gösterme",
        .keyEnter: "%@ yayın anahtarı",
        .keyEnterDetail: "Anahtarı kanalının yayın ayarlarından yapıştır. Yalnızca bu Mac'te tutulur.",
        .keyPaste: "Anahtarı panodan yapıştır",
        .keyPasted: "Yayın anahtarı kaydedildi",
        .keyClipboardEmpty: "Panoda metin yok",
        .keyPage: "Anahtarını al",
        .keyPageDetail: "%@ tarayıcıda açılır",
        .quality: "Kalite",
        .qualityDetail: "Kare düşerse daha düşüğünü seç: yükleme hızın bunun 1,5 katı olmalı",
        .microphone: "Mikrofon",
        .microphoneDetail: "Anlatımın oyunun sesinin üstüne karışır",
        .microphoneLevel: "Mikrofon seviyesi",
        .badge: "CANLI rozeti",
        .badgeDetail: "Yayındayken oyunun üstünde küçük bir rozet; izleyiciler görmez",
        .viewerLink: "İzleyici bağlantısı",
        .viewerLinkDetail: "İzlenen adres, ör. twitch.tv/adın: yayındayken gösterilir ve kopyalanır",
        .keptPrivately: "Anahtarlar Anahtar Zinciri'nde değil, yalnızca senin okuyabildiğin bir dosyada tutulur: başlatıcı ad hoc imzalı, Anahtar Zinciri her güncellemeden sonra yeniden sorardı.",
        .goLive: "%@ yayınla",
        .goLiveDetail: "%@ · %@",
        .goLiveNoGame: "Yayına başlamak için bir oyun aç",
        .setUpFirst: "Yayını ayarla",
        .setUpFirstDetail: "Yayın anahtarını Ayarlar → Yayın'dan ekle",
        .live: "CANLI",
        .starting: "%@ bağlantısı kuruluyor…",
        .reconnecting: "Bağlantı koptu · %d sn sonra yeniden denenecek",
        .failed: "Yayın durdu: %@",
        .stop: "Yayını durdur",
        .stopped: "Yayın bitti",
        .copyLink: "İzleyici bağlantısını kopyala",
        .linkCopied: "İzleyici bağlantısı kopyalandı",
        .liveStats: "%@ süredir yayında",
        .dropped: "%d kare düştü (%%%.1f)",
        .stateLine: "%@ · %@ · %@",
        .startedNotice: "Yayındasın",
        .startedDetail: "%@ üzerinde yayın yapılıyor",
        .endedNotice: "Yayın bitti",
        .failedNotice: "Yayın durdu",
        .reconnectingNotice: "Yayın yeniden bağlanıyor",
        .reconnectingDetail: "%@ bağlantısı koptu; yeniden deneniyor",
        .needsPermission: "Yayın için ekran kaydı izni gerekli",
        .needsPermissionDetail: "Sistem Ayarları → Gizlilik ve Güvenlik → Ekran Kaydı'ndan AnyPS5'e izin ver",
        .noMicrophone: "Mikrofona izin yok; yayın mikrofonsuz sürüyor",
        .save: "Kaydet",
        .cancel: "Vazgeç",
        .liveBadge: "CANLI",
    ]
}
