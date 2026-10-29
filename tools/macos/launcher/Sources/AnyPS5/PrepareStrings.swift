import Foundation

/// The texts of the free-space check before an unlock and of new games prepared in the
/// background, from the language files (l10n); kept apart from `T` like `TSteam`.
enum TPrep {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case prepareNewGames, prepareNewGamesDetail
        case newGamePreparing, newGamesPreparing, newGameWaiting, newGamesWaiting, newGameNotPreparedBattery, newGameNotPreparedSpace
        case preparing, preparingStep, preparingPaused, waitingToPrepare, playWhenReady, startsWhenReady, readyToPlay, readyToPlayDetail
        case notPreparedBattery, notPreparedSpace
        case noSpaceTitle, noSpaceSubtitle, noSpaceAmount = "noSpaceAmountOnDrive", noSpaceNothingWritten, noSpaceWhy
        case noSpaceFolder, noSpaceFolderDetail, noSpaceStorage, noSpaceStorageDetail, noSpaceRetry, noSpaceRetryDetail
    }
}
