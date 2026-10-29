import AnyPS5Core
import Foundation

/// Full screen, the PS button's menus, the replay buffer's cost and the Shortcuts page: their
/// texts, in both languages.
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

    static let english: [Key: String] = [
        .fullScreen: "Full Screen",
        .fullScreenDetail: "F11 or ⌃⌘F switches it; AnyPS5 starts the way you left it",
        .pauseOnMenu: "Pause Game When Opening the Menu",
        .pauseOnMenuDetail: "PS in a game presses Options once first, on player 1's controller, keyboard or phone",
        .resume: "Resume",
        .closeGame: "Close Game",
        .paused: "Paused",
        .stillRunning: "Still running · pause it in the game",
        .quickMenuKicker: "Quick Menu",
        .closeGameTitle: "Close %@?",
        .closeGameText: "Anything since your last save is lost.",
        .homeMenuKicker: "AnyPS5",
        .switchProfile: "Switch Profile",
        .quitApp: "Quit AnyPS5",
        .quitWithGame: "Closes %@ first",
        .shortcuts: "Shortcuts",
        .shortcutsIntro: "Choose a row and press the new key or buttons. Hold buttons to bind a hold; Esc or ○ cancels, △ clears a row.",
        .keyboard: "Keyboard",
        .controller: "Controller",
        .held: "%@ (hold)",
        .notSet: "Not set",
        .pressButtons: "Press buttons…",
        .inGameToo: "Works in games too",
        .actionHome: "Home",
        .actionQuickMenu: "Quick Menu",
        .actionScreenshot: "Screenshot",
        .actionClip: "Save Clip",
        .actionFullScreen: "Full Screen",
        .actionPrevious: "Previous Section",
        .actionNext: "Next Section",
        .conflictSame: "Also set for %@",
        .conflictNavigationKey: "That key moves around the launcher",
        .conflictNavigationButton: "That button moves around the launcher; use it in a chord",
        .conflictReservedKey: "AnyPS5 or the menus use that key (⌥V talks, ⌥A and ⌥D answer calls, ⌘ is the menus')",
        .conflictNeedsModifier: "Needs ⌃, ⌥ or ⌘ (or an F key) to work in games",
        .refused: "Not set · %@",
        .cleared: "%@ cleared",
        .resetShortcuts: "Reset to Defaults",
        .resetShortcutsDetail: "Every shortcut back as AnyPS5 came",
        .shortcutsReset: "Shortcuts back to their defaults",
        .gameButtons: "Game Buttons",
        .gameButtonsDetail: "A game's own buttons and keys are in its Game Settings → Controls",
        .gameButtonsNoGame: "Choose a game first: its Game Settings → Controls has its buttons",
        .screenshotSaved: "Screenshot saved",
        .screenshotFailed: "No screenshot",
        .minutes: "%d min",
        .clipsCost: "Kept in memory only, about %d MB while a game plays, and let go unless you press Create. Encoding runs on the Mac's media engine, so the CPU barely notices",
        .hintChange: "Change",
        .hintDone: "Done",
        .hintClear: "Clear",
    ]

    static let turkish: [Key: String] = [
        .fullScreen: "Tam Ekran",
        .fullScreenDetail: "F11 ya da ⌃⌘F ile değişir; AnyPS5 bıraktığın gibi açılır",
        .pauseOnMenu: "Menü Açılınca Oyunu Duraklat",
        .pauseOnMenuDetail: "Oyunda PS önce bir kez Options'a basar; 1. oyuncunun kumandasında, klavyesinde ya da telefonunda",
        .resume: "Devam Et",
        .closeGame: "Oyunu Kapat",
        .paused: "Duraklatıldı",
        .stillRunning: "Hâlâ çalışıyor · oyunun içinden duraklat",
        .quickMenuKicker: "Hızlı Menü",
        .closeGameTitle: "%@ kapatılsın mı?",
        .closeGameText: "Son kayıttan sonraki her şey kaybolur.",
        .homeMenuKicker: "AnyPS5",
        .switchProfile: "Profil Değiştir",
        .quitApp: "AnyPS5'ten Çık",
        .quitWithGame: "Önce %@ kapanır",
        .shortcuts: "Kısayollar",
        .shortcutsIntro: "Bir satır seç ve yeni tuşa ya da tuşlara bas. Basılı tutma atamak için tuşları basılı tut; Esc ya da ○ vazgeçer, △ satırı temizler.",
        .keyboard: "Klavye",
        .controller: "Kumanda",
        .held: "%@ (basılı)",
        .notSet: "Atanmadı",
        .pressButtons: "Tuşlara bas…",
        .inGameToo: "Oyunlarda da çalışır",
        .actionHome: "Ana Ekran",
        .actionQuickMenu: "Hızlı Menü",
        .actionScreenshot: "Ekran Görüntüsü",
        .actionClip: "Klip Kaydet",
        .actionFullScreen: "Tam Ekran",
        .actionPrevious: "Önceki Bölüm",
        .actionNext: "Sonraki Bölüm",
        .conflictSame: "%@ için de atanmış",
        .conflictNavigationKey: "Bu tuş başlatıcıda gezinmek için",
        .conflictNavigationButton: "Bu tuş başlatıcıda gezinmek için; bir kombinasyonda kullan",
        .conflictReservedKey: "Bu tuşu AnyPS5 ya da menüler kullanıyor (⌥V konuşma, ⌥A ve ⌥D aramalar, ⌘ menüler)",
        .conflictNeedsModifier: "Oyunlarda çalışması için ⌃, ⌥ ya da ⌘ (veya bir F tuşu) gerekir",
        .refused: "Atanmadı · %@",
        .cleared: "%@ temizlendi",
        .resetShortcuts: "Varsayılanlara Dön",
        .resetShortcutsDetail: "Bütün kısayollar AnyPS5'in geldiği gibi",
        .shortcutsReset: "Kısayollar varsayılana döndü",
        .gameButtons: "Oyun Tuşları",
        .gameButtonsDetail: "Bir oyunun kendi tuşları Oyun Ayarları → Kontroller'inde",
        .gameButtonsNoGame: "Önce bir oyun seç: tuşları Oyun Ayarları → Kontroller'inde",
        .screenshotSaved: "Ekran görüntüsü kaydedildi",
        .screenshotFailed: "Ekran görüntüsü alınamadı",
        .minutes: "%d dk",
        .clipsCost: "Yalnız bellekte tutulur, oyun sürerken yaklaşık %d MB; Create'e basmazsan bırakılır. Kodlamayı Mac'in medya motoru yapar, işlemci neredeyse fark etmez",
        .hintChange: "Değiştir",
        .hintDone: "Tamam",
        .hintClear: "Temizle",
    ]
}
