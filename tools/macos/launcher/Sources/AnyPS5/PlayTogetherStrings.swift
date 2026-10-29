import Foundation

/// Play Together: its texts, from the language files (l10n).
enum PT {
    enum Key: String, CaseIterable {
        case start = "togetherStart", startDetail = "togetherStartDetail", pickGame = "togetherPick", pickGameDetail = "togetherPickDetail", starting = "togetherStarting", started = "togetherStarted", startFailed = "togetherStartFailed", alreadyRunning = "togetherAlready"
        case title = "togetherTitle", titleDetail = "togetherTitleDetail", joinRow = "togetherJoinRow", joinDetail = "togetherJoinDetail", offer = "togetherOffer", offerDetail = "togetherOfferDetail", leave = "togetherLeave", end = "togetherEnd", ended = "togetherEnded", endedYours = "togetherEndedYours", joined = "togetherJoining"
        case you = "togetherYou", host = "togetherHost", inGame = "togetherInGame", notYet = "playTogetherNotYet", connecting = "playTogetherConnecting", direct = "playTogetherDirect", relay = "playTogetherRelay", unreachable = "playTogetherUnreachable", ms = "playTogetherMs"
        case signIn = "togetherSignInFirst", missing = "togetherMissing", versionYou = "togetherVersionYou", versionHost = "togetherVersionHost", engineYou = "togetherEngineYou", engineHost = "togetherEngineHost", closeFirst = "togetherCloseFirst", full = "togetherFull", unlockAndPlay = "togetherUnlockAndPlay", updateAndPlay = "togetherUpdateAndPlay", unlockingFirst = "togetherUnlockingFirst", updatingFirst = "togetherUpdatingFirst"
        case code = "playTogetherCode", codeDetail = "playTogetherCodeDetail", codeCopied = "playTogetherCodeCopied", presence = "togetherPresence"
        case tryAnyway = "togetherTryAnyway", tryAnywayDetail = "togetherTryAnywayDetail", triedAnyway = "togetherTriedAnyway", tryingAnyway = "togetherTryingAnyway"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }
}
