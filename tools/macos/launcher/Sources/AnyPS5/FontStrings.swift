import Foundation

/// The texts of the system fonts games get (Settings → Fonts, the download before a start),
/// from the language files (l10n); kept apart from `T` like `TE`. `TF.text(.key)` reads the launcher's language.
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
}
