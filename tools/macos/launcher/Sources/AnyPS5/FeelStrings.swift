import AnyPS5Core
import Foundation

/// Controller vibration and the launcher's own update notice: their texts, from the language files (l10n).
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
}
