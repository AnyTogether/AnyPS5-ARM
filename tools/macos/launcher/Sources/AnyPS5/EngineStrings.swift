import Foundation

/// The texts of the engine picker (Settings → Engine and a game's engine), in both languages;
/// kept apart from `T` like `TS`. `TE.text(.key)` reads the launcher's current language.
enum TE {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case engineTitle, engineDefault, engineDefaultDetail, engineBuiltIn, engineCustomName, engineFollow
        case engineGameDetail, engineUnlockedWith, engineNotUnlocked, engineSwitch
        case engineDownloadedSection, engineAvailableSection, engineCustomSection
        case engineInUse, engineDeleteHint, engineDeleted = "engineVersionDeleted", engineInUseNoDelete, engineDeleteUnused, engineDeleteUnusedDetail, engineNothingUnused
        case engineDownloadHint, engineDownloading = "engineDownloadingPercent", engineReady, engineDownloadFailed, enginePrerelease, engineBuilt
        case engineSigned, engineUnsignedOlder, engineUnsignedOlderDetail, engineUnsignedReady, engineUnsignedRefused, engineUnsignedRefusedDetail
        case engineRefresh, engineChecked, engineChecking, engineOffline = "engineOfflineList", engineNeverChecked, engineNoneYet, engineCheckFailed
        case engineFolder, engineFolderNone, engineFolderReset, engineFolderInvalid, engineFolderPick, engineFolderUsed
        case engineHint
    }

    static let english: [Key: String] = [
        .engineTitle: "Engine",
        .engineDefault: "Default Engine",
        .engineDefaultDetail: "Unlocks every game that has no engine of its own",
        .engineBuiltIn: "Built in, %@",
        .engineCustomName: "Your folder, %@",
        .engineFollow: "Default (%@)",
        .engineGameDetail: "The AnyPS5 build that unlocks this game",
        .engineUnlockedWith: "Unlocked with %@",
        .engineNotUnlocked: "Used when you unlock it",
        .engineSwitch: "Engine %@ → %@",
        .engineDownloadedSection: "Downloaded",
        .engineAvailableSection: "On GitHub",
        .engineCustomSection: "Your Own Build",
        .engineInUse: "In use",
        .engineDeleteHint: "Select to delete",
        .engineDeleted: "Engine %@ deleted",
        .engineInUseNoDelete: "This engine is in use. Choose another one first.",
        .engineDeleteUnused: "Delete Unused Engines",
        .engineDeleteUnusedDetail: "%d downloaded, not chosen anywhere",
        .engineNothingUnused: "Every downloaded engine is in use",
        .engineDownloadHint: "Select to download",
        .engineDownloading: "Downloading… %d%%",
        .engineReady: "Engine %@ is ready",
        .engineDownloadFailed: "The engine could not be downloaded",
        .enginePrerelease: "Pre-release",
        .engineSigned: "Signed",
        .engineUnsignedOlder: "Unsigned (older release)",
        .engineUnsignedOlderDetail: "Came out before releases were signed: only GitHub's checksum checks it. Select to download anyway",
        .engineUnsignedReady: "Engine %@ is ready (unsigned, older release)",
        .engineUnsignedRefused: "Not signed",
        .engineUnsignedRefusedDetail: "Releases are signed now, and this one is not: it is not downloaded",
        .engineBuilt: "Built %@",
        .engineRefresh: "Check for Engines",
        .engineChecked: "Last checked %@",
        .engineChecking: "Asking GitHub…",
        .engineOffline: "GitHub could not be reached; this list is from %@",
        .engineNeverChecked: "Lists the engines attached to AnyPS5's releases",
        .engineNoneYet: "No engine downloads on the releases yet",
        .engineCheckFailed: "GitHub could not be reached",
        .engineFolder: "Engine Folder",
        .engineFolderNone: "None. For an engine you build yourself",
        .engineFolderReset: "Stop Using the Folder",
        .engineFolderInvalid: "Not an engine folder: %@",
        .engineFolderPick: "Use as Engine",
        .engineFolderUsed: "Engine folder set: %@",
        .engineHint: "A game unlocked with another engine than its own offers Update and Play: it is unlocked again with the chosen one, and its saves and trophies stay.",
    ]

    static let turkish: [Key: String] = [
        .engineTitle: "Motor",
        .engineDefault: "Varsayılan Motor",
        .engineDefaultDetail: "Kendi motoru seçilmemiş her oyunun kilidini bununla açar",
        .engineBuiltIn: "Yerleşik, %@",
        .engineCustomName: "Senin klasörün, %@",
        .engineFollow: "Varsayılan (%@)",
        .engineGameDetail: "Bu oyunun kilidini açan AnyPS5 sürümü",
        .engineUnlockedWith: "%@ ile açıldı",
        .engineNotUnlocked: "Kilidini açtığında kullanılır",
        .engineSwitch: "Motor %@ → %@",
        .engineDownloadedSection: "İndirilenler",
        .engineAvailableSection: "GitHub'da",
        .engineCustomSection: "Kendi Derlemen",
        .engineInUse: "Kullanımda",
        .engineDeleteHint: "Silmek için seç",
        .engineDeleted: "%@ motoru silindi",
        .engineInUseNoDelete: "Bu motor kullanımda. Önce başka birini seç.",
        .engineDeleteUnused: "Kullanılmayan Motorları Sil",
        .engineDeleteUnusedDetail: "%d motor indirildi, hiçbir yerde seçili değil",
        .engineNothingUnused: "İndirilen her motor kullanımda",
        .engineDownloadHint: "İndirmek için seç",
        .engineDownloading: "İndiriliyor… %%%d",
        .engineReady: "%@ motoru hazır",
        .engineDownloadFailed: "Motor indirilemedi",
        .enginePrerelease: "Ön sürüm",
        .engineSigned: "İmzalı",
        .engineUnsignedOlder: "İmzasız (eski sürüm)",
        .engineUnsignedOlderDetail: "Sürümler imzalanmadan önce çıktı: yalnızca GitHub'ın sağlama toplamı denetler. Yine de indirmek için seç",
        .engineUnsignedReady: "%@ motoru hazır (imzasız, eski sürüm)",
        .engineUnsignedRefused: "İmzasız",
        .engineUnsignedRefusedDetail: "Sürümler artık imzalanıyor, bu imzasız: indirilmez",
        .engineBuilt: "%@ derlendi",
        .engineRefresh: "Motorları Denetle",
        .engineChecked: "Son denetim %@",
        .engineChecking: "GitHub'a soruluyor…",
        .engineOffline: "GitHub'a ulaşılamadı; bu liste %@ tarihli",
        .engineNeverChecked: "AnyPS5 sürümlerine eklenen motorları listeler",
        .engineNoneYet: "Sürümlerde henüz indirilebilir motor yok",
        .engineCheckFailed: "GitHub'a ulaşılamadı",
        .engineFolder: "Motor Klasörü",
        .engineFolderNone: "Yok. Kendi derlediğin motor için",
        .engineFolderReset: "Klasörü Kullanmayı Bırak",
        .engineFolderInvalid: "Motor klasörü değil: %@",
        .engineFolderPick: "Motor Olarak Kullan",
        .engineFolderUsed: "Motor klasörü seçildi: %@",
        .engineHint: "Seçili motorundan başka bir motorla açılmış oyun Güncelle ve Oyna'yı önerir: kilidi seçilen motorla yeniden açılır, kayıtları ve kupaları korunur.",
    ]
}
