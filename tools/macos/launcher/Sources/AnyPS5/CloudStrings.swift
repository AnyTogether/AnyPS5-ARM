import Foundation

/// Cloud saves and media on AnyTogether: their texts, in both languages.
enum TCloud {
    enum Key: String, CaseIterable {
        case syncThrough = "cloudSyncThrough", syncThroughFolder = "cloudSyncThroughFolder", syncThroughTogether = "cloudSyncThroughTogether", saveSyncTogetherDetail = "cloudSaveSyncTogetherDetail"
        case storageTitle = "cloudStorageTitle", storageSubtitle = "cloudStorageSubtitle", storageUsed = "cloudStorageUsed", storageLoading = "cloudStorageLoading", storageFailed = "cloudStorageFailed", storageOff = "cloudStorageOff", storageSaves = "cloudStorageSaves", storageMedia = "cloudStorageMedia", storageFree = "cloudStorageFree"
        case storageNoSaves = "cloudStorageNoSaves", storageGameDetail = "cloudStorageGameDetail", storageVersion = "cloudStorageVersion", storageNewest = "cloudStorageNewest", storageRestore = "cloudStorageRestore", storageRestoreDetail = "cloudStorageRestoreDetail", storageDelete = "cloudStorageDelete", storageDeleteGame = "cloudStorageDeleteGame"
        case storagePressAgain = "cloudStoragePressAgain", storageDeleted = "cloudStorageDeleted", storageRestored = "cloudStorageRestored", storageRestoredHere = "cloudStorageRestoredHere", storageMediaTitle = "cloudStorageMediaTitle", storageNoMedia = "cloudStorageNoMedia", storagePinned = "cloudStoragePinned", storageRunning = "cloudStorageRunning"
        case photo = "cloudPhoto", clip, voiceNote = "cloudVoiceNote", removed = "cloudRemoved", unavailable = "cloudUnavailable"
        case savesUploaded = "cloudSavesUploaded", savesDownloaded = "cloudSavesDownloaded", conflictTitle = "cloudConflictTitle", conflictDetail = "cloudConflictDetail", conflictKeepMine = "cloudConflictKeepMine", conflictTakeCloud = "cloudConflictTakeCloud", notNow = "cloudNotNow", conflictCloudUnknown = "cloudConflictCloudUnknown"
        case quotaTitle = "cloudQuotaTitle", quotaReplaceDetail = "cloudQuotaReplaceDetail", replace = "cloudReplace", quotaFull = "cloudQuotaFull", tooBig = "cloudTooBig", badMedia = "cloudBadMedia", notThisKind = "cloudNotThisKind", cloudOff
        case share = "cloudShare", sendToChat = "cloudSendToChat", shareToGallery = "cloudShareToGallery", showInFinder = "cloudShowInFinder", sending = "cloudSending", sentTo = "cloudSentTo", addedToGallery = "cloudAddedToGallery", galleryFull = "cloudGalleryFull", noChats = "cloudNoChats", preparing = "cloudPreparing"
        case profileGallery = "cloudProfileGallery", profileGalleryPrivate = "cloudProfileGalleryPrivate", profileGalleryEmpty = "cloudProfileGalleryEmpty", privacyGallery = "cloudPrivacyGallery", hintShare = "cloudHintShare", hintView = "cloudHintView", close = "cloudClose"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }
    /// Capitals in the launcher's language: "KAYITLAR", "İ" and all.
    static var locale: Locale { T.locale }

    /// "25 Eki 2026 21:15" in the launcher's language.
    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    /// 1.2 MB, 640 KB: sizes the way the quota counts them (1 MB = 1,048,576 bytes).
    static func size(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 10 { return String(format: "%.0f MB", mb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return "\(max(bytes > 0 ? 1 : 0, Int((Double(bytes) / 1024).rounded()))) KB"
    }

    /// "Photo", "Clip" or "Voice note" for a media kind.
    static func kind(_ kind: String) -> String {
        switch kind {
        case "clip": return text(.clip)
        case "voice": return text(.voiceNote)
        default: return text(.photo)
        }
    }

    static let english: [Key: String] = [
        .syncThrough: "Sync Through",
        .syncThroughFolder: "A Folder",
        .syncThroughTogether: "AnyTogether",
        .saveSyncTogetherDetail: "Saves and trophies stay the same on your other Macs through your AnyTogether cloud",
        .storageTitle: "Cloud Storage",
        .storageSubtitle: "Saves and media on AnyTogether",
        .storageUsed: "%@ of %@ used",
        .storageLoading: "Reading your cloud…",
        .storageFailed: "Your cloud could not be read",
        .storageOff: "This AnyTogether server keeps no files",
        .storageSaves: "Saves",
        .storageMedia: "Media",
        .storageFree: "Free",
        .storageNoSaves: "No saves in your cloud yet. Turn on Save Sync through AnyTogether and play.",
        .storageGameDetail: "%d versions · %@",
        .storageVersion: "Version %d",
        .storageNewest: "Newest",
        .storageRestore: "Restore This Version",
        .storageRestoreDetail: "It becomes the newest again; this Mac takes it, its own saves backed up first",
        .storageDelete: "Delete This Version",
        .storageDeleteGame: "Delete This Game's Cloud Saves",
        .storagePressAgain: "Press again to delete",
        .storageDeleted: "Deleted from your cloud",
        .storageRestored: "Version %d is the newest again",
        .storageRestoredHere: "Version %d restored on this Mac",
        .storageMediaTitle: "Photos, clips and voice notes",
        .storageNoMedia: "Nothing sent or shared yet",
        .storagePinned: "In your gallery",
        .storageRunning: "Close the game first",
        .photo: "Photo",
        .clip: "Clip",
        .voiceNote: "Voice note",
        .removed: "Removed",
        .unavailable: "Not available",
        .savesUploaded: "Saves are in your cloud",
        .savesDownloaded: "Saves from %@ are on this Mac",
        .conflictTitle: "Saves changed on this Mac and in your cloud",
        .conflictDetail: "Your cloud has newer saves of %@ from %@ (%@). The ones you do not keep stay as a backup.",
        .conflictKeepMine: "Keep This Mac's",
        .conflictTakeCloud: "Take the Newer One",
        .notNow: "Not Now",
        .conflictCloudUnknown: "another device",
        .quotaTitle: "Your cloud storage is full",
        .quotaReplaceDetail: "There is room for %@ only if its newest cloud save (%@) is replaced by this Mac's. Replace it?",
        .replace: "Replace",
        .quotaFull: "Your cloud storage is full: free some room in Settings → Cloud Storage",
        .tooBig: "That is too big to send",
        .badMedia: "That file cannot be sent",
        .notThisKind: "Only PNG, JPEG and WebP pictures and MP4 clips can be sent",
        .cloudOff: "This AnyTogether server keeps no files",
        .share: "Share",
        .sendToChat: "Send to %@",
        .shareToGallery: "Share to My Gallery",
        .showInFinder: "Show in Finder",
        .sending: "Sending…",
        .sentTo: "Sent to %@",
        .addedToGallery: "Added to your gallery",
        .galleryFull: "Your gallery is full (%d): unpin something first",
        .noChats: "No conversations yet: write to a friend in Messages first",
        .preparing: "Getting it ready…",
        .profileGallery: "Gallery",
        .profileGalleryPrivate: "This gallery is private",
        .profileGalleryEmpty: "Nothing pinned yet: share a screenshot or a clip from a game's gallery",
        .privacyGallery: "Gallery",
        .hintShare: "Share",
        .hintView: "View",
        .close: "Close",
    ]

    static let turkish: [Key: String] = [
        .syncThrough: "Senkron Yolu",
        .syncThroughFolder: "Bir Klasör",
        .syncThroughTogether: "AnyTogether",
        .saveSyncTogetherDetail: "Kayıtlar ve kupalar AnyTogether bulutun üzerinden diğer Mac'lerle aynı kalır",
        .storageTitle: "Bulut Depolama",
        .storageSubtitle: "AnyTogether'daki kayıtlar ve medya",
        .storageUsed: "%@ / %@ kullanılıyor",
        .storageLoading: "Bulutun okunuyor…",
        .storageFailed: "Bulutun okunamadı",
        .storageOff: "Bu AnyTogether sunucusu dosya saklamıyor",
        .storageSaves: "Kayıtlar",
        .storageMedia: "Medya",
        .storageFree: "Boş",
        .storageNoSaves: "Bulutunda henüz kayıt yok. Kayıt Senkronu'nu AnyTogether üzerinden aç ve oyna.",
        .storageGameDetail: "%d sürüm · %@",
        .storageVersion: "Sürüm %d",
        .storageNewest: "En yeni",
        .storageRestore: "Bu Sürümü Geri Yükle",
        .storageRestoreDetail: "Yeniden en yeni olur; bu Mac onu alır, kendi kayıtları önce yedeklenir",
        .storageDelete: "Bu Sürümü Sil",
        .storageDeleteGame: "Bu Oyunun Buluttaki Kayıtlarını Sil",
        .storagePressAgain: "Silmek için tekrar bas",
        .storageDeleted: "Bulutundan silindi",
        .storageRestored: "Sürüm %d yeniden en yeni",
        .storageRestoredHere: "Sürüm %d bu Mac'e geri yüklendi",
        .storageMediaTitle: "Fotoğraflar, klipler ve sesli notlar",
        .storageNoMedia: "Henüz bir şey gönderilmedi ya da paylaşılmadı",
        .storagePinned: "Galerinde",
        .storageRunning: "Önce oyunu kapat",
        .photo: "Fotoğraf",
        .clip: "Klip",
        .voiceNote: "Sesli not",
        .removed: "Kaldırıldı",
        .unavailable: "Kullanılamıyor",
        .savesUploaded: "Kayıtlar bulutunda",
        .savesDownloaded: "%@ cihazındaki kayıtlar bu Mac'te",
        .conflictTitle: "Kayıtlar hem bu Mac'te hem bulutunda değişti",
        .conflictDetail: "Bulutunda %@ için %@ cihazından daha yeni kayıtlar var (%@). Tutmadığın yedek olarak kalır.",
        .conflictKeepMine: "Bu Mac'tekini Tut",
        .conflictTakeCloud: "Yeni Olanı Al",
        .notNow: "Şimdi Değil",
        .conflictCloudUnknown: "başka bir cihaz",
        .quotaTitle: "Bulut depolaman dolu",
        .quotaReplaceDetail: "%@ için yer ancak buluttaki en yeni kaydı (%@) bu Mac'tekiyle değiştirilirse açılır. Değiştirilsin mi?",
        .replace: "Değiştir",
        .quotaFull: "Bulut depolaman dolu: Ayarlar → Bulut Depolama'dan yer aç",
        .tooBig: "Bu, gönderilemeyecek kadar büyük",
        .badMedia: "Bu dosya gönderilemiyor",
        .notThisKind: "Yalnızca PNG, JPEG, WebP resimler ve MP4 klipler gönderilebilir",
        .cloudOff: "Bu AnyTogether sunucusu dosya saklamıyor",
        .share: "Paylaş",
        .sendToChat: "%@ sohbetine gönder",
        .shareToGallery: "Galerime Ekle",
        .showInFinder: "Finder'da Göster",
        .sending: "Gönderiliyor…",
        .sentTo: "%@ sohbetine gönderildi",
        .addedToGallery: "Galerine eklendi",
        .galleryFull: "Galerin dolu (%d): önce birini kaldır",
        .noChats: "Henüz sohbet yok: önce Mesajlar'dan bir arkadaşına yaz",
        .preparing: "Hazırlanıyor…",
        .profileGallery: "Galeri",
        .profileGalleryPrivate: "Bu galeri gizli",
        .profileGalleryEmpty: "Henüz sabitlenen bir şey yok: bir oyunun galerisinden ekran görüntüsü ya da klip paylaş",
        .privacyGallery: "Galeri",
        .hintShare: "Paylaş",
        .hintView: "Görüntüle",
        .close: "Kapat",
    ]
}
