import Foundation

/// Broadcasting's texts, from the language files (l10n).
enum TB {
    enum Key: String, CaseIterable {
        case title = "broadcastTitle", settingsDetail = "broadcastSettingsDetail", service = "broadcastService", serviceCustom = "broadcastServiceCustom", server = "broadcastServer", serverDetail = "broadcastServerDetail", key = "broadcastKey", keyNone = "broadcastKeyNone", keyDetail = "broadcastKeyDetail", keyEnter = "broadcastKeyEnter", keyEnterDetail = "broadcastKeyEnterDetail", keyPaste = "broadcastKeyPaste", keyPasted = "broadcastKeyPasted", keyClipboardEmpty = "broadcastKeyClipboardEmpty"
        case keyPage = "broadcastKeyPage", keyPageDetail = "broadcastKeyPageDetail", quality = "broadcastQuality", qualityDetail = "broadcastQualityDetail", microphone = "broadcastMicrophone", microphoneDetail = "broadcastMicrophoneDetail", microphoneLevel = "broadcastMicrophoneLevel", badge = "broadcastBadge", badgeDetail = "broadcastBadgeDetail", viewerLink = "broadcastViewerLink", viewerLinkDetail = "broadcastViewerLinkDetail", keptPrivately = "broadcastKeptPrivately"
        case goLive = "broadcastGoLive", goLiveDetail = "broadcastGoLiveDetail", goLiveNoGame = "broadcastGoLiveNoGame", setUpFirst = "broadcastSetUpFirst", setUpFirstDetail = "broadcastSetUpFirstDetail", live = "broadcastLive", starting = "broadcastStarting", reconnecting = "broadcastReconnecting", failed = "broadcastFailed", stop = "broadcastStop", stopped = "broadcastStopped", copyLink = "broadcastCopyLink", linkCopied = "broadcastLinkCopied"
        case liveStats = "broadcastLiveStats", dropped = "broadcastDropped", stateLine = "broadcastStateLine", startedNotice = "broadcastStartedNotice", startedDetail = "broadcastStartedDetail", endedNotice = "broadcastEndedNotice", failedNotice = "broadcastFailedNotice", reconnectingNotice = "broadcastReconnectingNotice", reconnectingDetail = "broadcastReconnectingDetail"
        case needsPermission = "broadcastNeedsPermission", needsPermissionDetail = "broadcastNeedsPermissionDetail", noMicrophone = "broadcastNoMicrophone", save = "broadcastSave", cancel = "broadcastCancel", liveBadge = "broadcastLiveBadge"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// 0:42, 12:05 or 1:02:09.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total / 60 % 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// 4.5 Mbit/s, or 850 kbit/s below one.
    static func rate(_ bits: Int) -> String {
        bits >= 1_000_000 ? String(format: "%.1f Mbit/s", Double(bits) / 1_000_000) : "\(bits / 1000) kbit/s"
    }
}
