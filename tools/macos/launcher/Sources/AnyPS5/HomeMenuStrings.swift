import AnyPS5Core
import Foundation

/// Full screen, the PS button's menus, the replay buffer's cost and the Shortcuts page: their
/// texts, from the language files (l10n).
enum TH {
    enum Key: String, CaseIterable {
        case fullScreen = "launcherFullscreen", fullScreenDetail = "menuFullScreenDetail"
        case pauseOnMenu, pauseOnMenuDetail
        case resume = "quickResume", closeGame = "quickCloseGame", paused = "quickPaused", stillRunning = "menuStillRunning", quickMenuKicker = "menuQuickMenuKicker"
        case closeGameTitle, closeGameText = "menuCloseGameText"
        case homeMenuKicker = "menuHomeMenuKicker", switchProfile, quitApp = "quitLauncher", quitWithGame = "menuQuitWithGame"
        case shortcuts, shortcutsIntro = "menuShortcutsIntro", keyboard = "menuKeyboard", controller = "menuController", held = "shortcutHeld", notSet = "menuNotSet", pressButtons = "menuPressButtons", inGameToo = "menuInGameToo"
        case actionHome = "menuActionHome", actionQuickMenu = "shortcutQuickMenu", actionScreenshot = "shortcutScreenshot", actionClip = "menuActionClip", actionFullScreen = "shortcutFullscreen", actionPrevious = "shortcutPreviousSection", actionNext = "shortcutNextSection"
        case conflictSame = "menuConflictSame", conflictNavigationKey = "menuConflictNavigationKey", conflictNavigationButton = "menuConflictNavigationButton", conflictReservedKey = "menuConflictReservedKey", conflictNeedsModifier = "menuConflictNeedsModifier", refused = "menuRefused", cleared = "menuCleared"
        case resetShortcuts = "shortcutsReset", resetShortcutsDetail = "menuResetShortcutsDetail", shortcutsReset = "shortcutsResetDone", gameButtons = "shortcutsGameButtons", gameButtonsDetail = "shortcutsGameButtonsDetail", gameButtonsNoGame = "menuGameButtonsNoGame"
        case screenshotSaved, screenshotFailed, minutes = "menuMinutes", clipsCost = "menuClipsCost"
        case hintChange = "menuHintChange", hintDone = "menuHintDone", hintClear = "menuHintClear"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    static func name(_ action: ShortcutAction) -> String {
        switch action {
        case .home: return text(.actionHome)
        case .quickMenu: return text(.actionQuickMenu)
        case .screenshot: return text(.actionScreenshot)
        case .clip: return text(.actionClip)
        case .fullScreen: return text(.actionFullScreen)
        case .previousSection: return text(.actionPrevious)
        case .nextSection: return text(.actionNext)
        }
    }

    /// A pad chord as the row shows it: "L1 + R1", "Create (hold)".
    static func chord(_ chord: PadChord) -> String {
        let buttons = chord.buttons.map(\.glyph).joined(separator: " + ")
        return chord.hold ? format(.held, buttons) : buttons
    }

    /// Why a binding clashes, from `action`'s side.
    static func conflict(_ conflict: ShortcutConflict, for action: ShortcutAction) -> String {
        switch conflict {
        case .sameKey(let a, let b), .samePad(let a, let b): return format(.conflictSame, name(a == action ? b : a))
        case .navigationKey: return text(.conflictNavigationKey)
        case .navigationButton: return text(.conflictNavigationButton)
        case .reservedKey: return text(.conflictReservedKey)
        case .needsModifier: return text(.conflictNeedsModifier)
        }
    }

    /// 30 s, 1 min, 3 min, 5 min.
    static func length(_ seconds: Int) -> String {
        seconds < 60 ? T.format(.seconds, seconds) : format(.minutes, seconds / 60)
    }
}
