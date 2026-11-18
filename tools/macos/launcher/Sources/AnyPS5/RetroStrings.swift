import Foundation

/// The texts of the emulator games (Settings › Library › Emulator games, Settings › Emulators and
/// the home screen's console folders), from the language files (l10n); the same keys and wording
/// as AnyPS5 Desktop, kept apart from `T` like `TPrep`.
enum TRetro {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case retroLibrary, retroLibraryDetail
        case retroEmulators, retroSelectExecutable, retroChooseExecutable, retroEmulatorPickerFailed, retroShowFolders
        case retroGames, retroChooseEmulator, retroEmulatorNeeded
        case retroDiscMoved, retroEmulatorStartFailed, retroEmulatorExited
        // The PS1 emulator host (RetroHostDownload.swift), Settings › Emulators.
        case retroHostUnchecked, retroHostUncheckedDetail, retroHostDownload, retroHostDownloadDetail, retroHostInstalled
        case retroHostInstalledDetail, retroHostBrokenDetail, retroHostDownloading, retroHostProgress, retroHostLooking
        case retroHostChecking, retroHostNotYet, retroHostDownloadFailed, retroHostReady, retroHostUpToDate
        case retroHostDownloadCloseGame
    }
}
