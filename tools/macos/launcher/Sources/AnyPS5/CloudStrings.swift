import Foundation

/// Cloud saves and media on AnyTogether: their texts, from the language files (l10n).
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
}
