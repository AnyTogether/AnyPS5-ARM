import AnyPS5Core
import Foundation

/// Controller vibration and the launcher's own update notice: their texts, in both languages.
enum TU {
    enum Key: String, CaseIterable {
        case controllerVibration, controllerVibrationDetail
        case noticeReady = "desktopNoticeReady", noticeReadyDetail, restartNow = "desktopRestartNow", later = "desktopLater", noticeWaiting = "desktopRestartWaiting", cancelRestart = "desktopCancelRestart"
        case stateIdle = "noticeStateIdle", stateChecking = "noticeStateChecking", stateUpToDate = "noticeStateUpToDate", stateFailed = "desktopUpdateNoAnswer", stateAvailableDetail = "noticeStateAvailableDetail", stateDownloading = "noticeStateDownloading"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// About's line for the check: where it stands.
    static func checkLine(_ state: LauncherUpdateState) -> String {
        switch state {
        case .idle: return text(.stateIdle)
        case .checking: return text(.stateChecking)
        case .failed: return text(.stateFailed)
        case .upToDate(let checked): return format(.stateUpToDate, checked.formatted(date: .omitted, time: .shortened))
        case .available(let version): return T.format(.launcherUpdateAvailable, version)
        case .downloading(let version, _): return format(.stateDownloading, version, state.percent ?? 0)
        case .ready(let version): return format(.noticeReady, version)
        }
    }

    static let english: [Key: String] = [
        .controllerVibration: "Controller Vibration",
        .controllerVibrationDetail: "Soft pulses for select, back, errors, trophies, calls and the end of a row; never while a game is in front",
        .noticeReady: "AnyPS5 %@ is ready",
        .noticeReadyDetail: "Restart now, or it goes in when you quit",
        .restartNow: "Restart Now",
        .later: "Later",
        .noticeWaiting: "Restarts when your game closes",
        .cancelRestart: "Cancel Restart",
        .stateIdle: "Not checked yet",
        .stateChecking: "Checking…",
        .stateUpToDate: "Up to date · checked %@",
        .stateFailed: "No answer from GitHub: it asks again in a while",
        .stateAvailableDetail: "Downloads in the background with its signature checked; you choose when to restart",
        .stateDownloading: "Downloading AnyPS5 %@ · %d%%",
    ]

    static let turkish: [Key: String] = [
        .controllerVibration: "Kumanda Titreşimi",
        .controllerVibrationDetail: "Seçme, geri, hata, kupa, arama ve satır sonunda hafif titreşim; oyun öndeyken asla",
        .noticeReady: "AnyPS5 %@ hazır",
        .noticeReadyDetail: "Şimdi yeniden başlat ya da çıkarken kurulsun",
        .restartNow: "Şimdi Yeniden Başlat",
        .later: "Sonra",
        .noticeWaiting: "Oyun kapanınca yeniden başlar",
        .cancelRestart: "İptal Et",
        .stateIdle: "Henüz denetlenmedi",
        .stateChecking: "Denetleniyor…",
        .stateUpToDate: "Güncel · %@ denetlendi",
        .stateFailed: "GitHub yanıt vermedi: bir süre sonra yeniden sorar",
        .stateAvailableDetail: "Arka planda iner, imzası denetlenir; ne zaman yeniden başlatacağını sen seçersin",
        .stateDownloading: "AnyPS5 %@ indiriliyor · %%%d",
    ]
}
