import Foundation

/// The texts of Settings → Steam (AnyPS5 as a non-Steam game, and its games), from the language files (l10n);
/// kept apart from `T` like `TF`.
enum TSteam {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case title = "steam", looking = "steamLooking", notFound = "steamNotFound", notFoundDetail = "steamNotFoundDetail", account = "steamAccount", add = "steamAdd", addDetail = "steamAddDetail", update = "steamUpdate", inSteam = "steamInSteam", inSteamLauncher = "steamInSteamLauncher", inSteamGames = "steamInSteamGames"
        case notInSteam = "steamNotInSteam", games = "steamGames", gamesDetail = "steamGamesDetail", fullscreen = "steamFullscreen", remove = "steamRemove", removeDetail = "steamRemoveDetail", running = "steamRunning", runningDetail = "steamRunningDetail", closeAndAdd = "steamCloseAndAdd", closeAndRemove = "steamCloseAndRemove"
        case closing = "steamClosing", working = "steamWorking", added = "steamAdded", removed = "steamRemoved", nothing = "steamNothing", failed = "steamFailed", wouldNotClose = "steamWouldNotClose", fromSteam = "steamFromSteam", open = "steamOpen", playMissing = "steamPlayMissing"
    }
}
