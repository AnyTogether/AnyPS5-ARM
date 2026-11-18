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
        // A PS1 game in the emulator host (RetroHostPlay.swift): its setting, screens and menu.
        case retroHostPs1, retroHostPs1Detail, retroHostUpdating, retroHostCheckFailed
        case retroHostBiosFolder, retroHostBiosFolderDetail, retroHostControlsDetail, retroHostLoading
        case retroHostStopped, retroHostBack, retroHostBiosDetail, retroHostDiscDetail
        case retroHostCoreDetail, retroHostStalledDetail, retroHostDidNotStartDetail, retroHostFrameTooLargeDetail
        case retroHostExitedDetail, retroHostHungDetail, retroHostOtherDetail, retroHostOutdatedDetail
        case retroHostNotStartedDetail, retroHostCardUnreadable, retroHostNoCapture, retroMenuVolume
        case retroMenuMute, retroMenuDiscInsertedDetail, retroMenuDiscChangingDetail, retroMenuDiscFailedDetail
        case retroMenuOptionPendingDetail, retroMenuOptionRestartDetail, retroMenuOptionRestartOnlyDetail, retroMenuAudio
        case retroMenuAudioDetail, retroMenuController, retroMenuControllerDetail, retroMenuConsole
        case retroMenuConsoleDetail, retroMenuAdvanced, retroMenuAdvancedDetail
        // PS2 games in the emulator host, where it has LRPS2 beside it.
        case retroHostPs2, retroHostPs2Detail, retroHostPs2BiosFolder, retroHostPs2BiosFolderDetail
        case retroHostPs2BiosDetail, retroHostNoPs2Detail
        // Save states in the game's menu, where the host lists `saveStates` (RetroHostPlay.swift).
        case retroMenuSaveState, retroMenuSaveStateDetail, retroMenuLoadState, retroMenuLoadStateDetail
        case retroMenuLoadStatePs1Detail, retroMenuNoStatesDetail, retroStateSlot, retroStateEmpty
        case retroStateSaving, retroStateLoading, retroStateCardAfterEnd, retroStateOverwriteTitle
        case retroStateOverwrite, retroStateOverwriteDetail, retroStateSaved, retroStateLoaded
        case retroStateOtherCore, retroStateOtherGame, retroStateBad, retroStateLoadFailed, retroStateSaveFailed
    }
}
