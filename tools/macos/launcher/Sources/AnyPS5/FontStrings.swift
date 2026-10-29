import Foundation

/// The texts of the system fonts games get (Settings → Fonts, the download before a start), in
/// both languages; kept apart from `T` like `TE`. `TF.text(.key)` reads the launcher's language.
enum TF {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case title = "fonts", intro = "fontsIntro", latin = "fontsLatin", italic = "fontsItalic", typewriter = "fontsTypewriter", thai = "fontsThai", arabic = "fontsArabic", cjk = "fontsCjk"
        case builtIn = "fontsSourceBuiltIn", downloaded = "fontsSourceDownloaded", yourFolder = "fontsSourceYourFolder", console = "fontsConsole", none = "fontsNone"
        case cjkOnNeed = "fontsCjkOnNeed", cjkNotYet = "fontsCjkNotYet", cjkDownloading = "fontsCjkDownloading", cjkDownloadNow = "fontsCjkDownloadNow", cjkDownloadNowDetail = "fontsCjkDownloadNowDetail", cjkRemove = "fontsCjkRemove", cjkRemoveDetail = "fontsCjkRemoveDetail", cjkRemoved = "fontsCjkRemoved"
        case userFolder = "fontsOwnFolder", userFolderNone = "fontsUserFolderNone", userFolderReset = "fontsUserFolderReset", hint = "fontsFolderHint"
        case getting = "fontsGetting", gettingText = "fontsGettingText", gettingProgress = "fontsGettingProgress", ready = "fontsCjkReady", readyRestart = "fontsReadyRestart", neededDownloading = "fontsNeededDownloading", failed = "fontsFailed"
    }

    static let english: [Key: String] = [
        .title: "Fonts",
        .intro: "What games get when they ask for the console's system fonts. Some games stop at start without them.",
        .latin: "Latin, Vietnamese",
        .italic: "Latin Italic",
        .typewriter: "Typewriter",
        .thai: "Thai",
        .arabic: "Arabic",
        .cjk: "Japanese, Chinese, Korean",
        .builtIn: "%@ · Built in",
        .downloaded: "%@ · Downloaded",
        .yourFolder: "%@ · Your folder",
        .console: "%@ (console)",
        .none: "None",
        .cjkOnNeed: "Downloads the first time a game needs them: %@, once",
        .cjkNotYet: "Not yet",
        .cjkDownloading: "Downloading… %d%%",
        .cjkDownloadNow: "Download Japanese, Chinese and Korean Now",
        .cjkDownloadNowDetail: "Noto Sans CJK from Noto's own release, %@; checked before games get it",
        .cjkRemove: "Remove Japanese, Chinese and Korean Fonts",
        .cjkRemoveDetail: "Frees %@. They download again when a game needs them.",
        .cjkRemoved: "Japanese, Chinese and Korean fonts removed",
        .userFolder: "Your Fonts Folder",
        .userFolderNone: "None. For the console's own fonts, if you have them",
        .userFolderReset: "Stop Using Your Folder",
        .hint: "Your folder's files come first; the launcher's fonts fill in what it lacks. Noto fonts: SIL Open Font License 1.1.",
        .getting: "Getting Fonts",
        .gettingText: "%@ needs the Japanese, Chinese and Korean fonts (%@, once). It starts as soon as they are checked.",
        .gettingProgress: "%d%%",
        .ready: "Japanese, Chinese and Korean fonts are ready",
        .readyRestart: "Japanese, Chinese and Korean fonts are ready: start %@ again to use them",
        .neededDownloading: "%@ asked for Japanese, Chinese or Korean fonts: downloading them",
        .failed: "The fonts could not be downloaded: %@",
    ]

    static let turkish: [Key: String] = [
        .title: "Fontlar",
        .intro: "Oyunlar konsolun sistem fontlarını istediğinde bunları alır. Bazı oyunlar bunlar olmadan açılışta durur.",
        .latin: "Latin, Vietnamca",
        .italic: "Latin İtalik",
        .typewriter: "Daktilo",
        .thai: "Tayca",
        .arabic: "Arapça",
        .cjk: "Japonca, Çince, Korece",
        .builtIn: "%@ · Yerleşik",
        .downloaded: "%@ · İndirildi",
        .yourFolder: "%@ · Klasörün",
        .console: "%@ (konsol)",
        .none: "Yok",
        .cjkOnNeed: "Bir oyun ilk istediğinde iner: %@, bir kez",
        .cjkNotYet: "Henüz yok",
        .cjkDownloading: "İniyor… %%%d",
        .cjkDownloadNow: "Japonca, Çince ve Korece Fontları Şimdi İndir",
        .cjkDownloadNowDetail: "Noto'nun kendi sürümünden Noto Sans CJK, %@; oyunlara verilmeden önce denetlenir",
        .cjkRemove: "Japonca, Çince ve Korece Fontları Kaldır",
        .cjkRemoveDetail: "%@ yer açar. Bir oyun istediğinde yeniden iner.",
        .cjkRemoved: "Japonca, Çince ve Korece fontlar kaldırıldı",
        .userFolder: "Font Klasörün",
        .userFolderNone: "Yok. Elinde varsa konsolun kendi fontları için",
        .userFolderReset: "Klasörünü Kullanmayı Bırak",
        .hint: "Önce klasöründeki dosyalar kullanılır; eksik kalanı AnyPS5'in fontları tamamlar. Noto fontları: SIL Open Font License 1.1.",
        .getting: "Fontlar Alınıyor",
        .gettingText: "%@ Japonca, Çince ve Korece fontları istiyor (%@, bir kez). Denetlenir denetlenmez başlar.",
        .gettingProgress: "%%%d",
        .ready: "Japonca, Çince ve Korece fontlar hazır",
        .readyRestart: "Japonca, Çince ve Korece fontlar hazır: kullanmak için %@ oyununu yeniden başlat",
        .neededDownloading: "%@ Japonca, Çince veya Korece font istedi: indiriliyor",
        .failed: "Fontlar indirilemedi: %@",
    ]
}
