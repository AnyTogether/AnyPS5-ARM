import Foundation

/// The questions social steps ask before they happen, and the Update Required screen: their
/// texts, from the language files (l10n).
enum TK {
    enum Key: String, CaseIterable {
        case askLeaveParty, askKick, askEndTogether, askLeaveTogether, askRemoveViewer, askStopShare, askClosePost
        case updateRequiredTitle = "requiredTitle", updateRequiredSubtitle, updateRequiredTooOld = "requiredTooOld", updateRequiredTooOldVersion = "requiredTooOldVersion", updateRequiredDetail, updateRequiredUpdate, updateRequiredUpdateDetail
        case updateRequiredRestart, updateRequiredRestartDetail, updateRequiredDownloading, updateRequiredLooking, updateRequiredDownload = "requiredDownload"
        case updateRequiredDownloadDetail = "requiredDownloadDetail", updateRequiredLater = "requiredLater", updateRequiredToast
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }
}
