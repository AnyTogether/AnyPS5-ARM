import Foundation

/// The texts of an unlock's Pause, Resume and Cancel, and of the question before quitting while
/// games are unlocked or removed, from the language files (l10n); kept apart from `T` like `TPrep`.
enum TUnlock {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case unlockPause, unlockResume, unlockCancelling, unlockPausedState, cancelUnlock, keepGoing
        case cancelUnlockAskTitle, cancelUnlockAskDetail
        case quitUnlocksTitle, quitRemovingTitle, quitGoBack, quitCancelAndQuit, quitAnyway, quitUnlocksDetail, quitRemovingNote
    }
}
