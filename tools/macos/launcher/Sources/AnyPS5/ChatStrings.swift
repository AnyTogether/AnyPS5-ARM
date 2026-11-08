import AnyPS5Core
import Foundation

/// The texts of reactions, replies, editing and unsending, receipts, pinned and muted
/// conversations, the read receipts setting, end-to-end encryption, reporting and the party's chat, from the language files (l10n) (the same words the website
/// uses). `TChat.text(.key)` reads the launcher's language.
enum TChat {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case retry = "messagesRetry"
        case react = "messagesReact", reactionLike, reactionLove, reactionLaugh, reactionWow, reactionSad, reactionFire, reactionGg, reactedBy = "chatReactedBy"
        case reply = "messagesReply", replyingTo = "messagesReplyingTo", earlierMessage = "messagesEarlier", edit = "messagesEdit", editing = "chatEditing", editLimit = "messagesEditLimit", unsend = "messagesUnsend", unsendConfirm = "messagesUnsendConfirm"
        case receiptSent, receiptDelivered, receiptRead, seenBy = "chatSeenBy", seenByEveryone = "receiptSeenByEveryone"
        case sendPhoto = "messagesSendPhoto"
        case pin = "conversationPin", unpin = "conversationUnpin", pinned = "conversationPinned", pinFull = "chatPinFull", mute = "conversationMute", unmute = "conversationUnmute", muted = "conversationMuted"
        case readReceipts, readReceiptsHint, hintActions = "chatHintActions"
        // End-to-end encrypted direct messages (AnyTogether's docs/e2ee.md, its table of texts).
        case e2eeOn, e2eeOnDetail, e2eeOff, e2eeOffDetail, e2eeNoDevice, e2eeSafetyNumber, e2eeSafetyHow, e2eeMarkCompared, e2eeCompared
        case e2eeDevicesChanged, e2eeMyDevicesChanged, e2eeCompare, e2eeDismiss, e2eeDevices, e2eeYou, e2eeNewDeviceNote
        case e2eeDeviceAdded, e2eeDeviceWindows, e2eeDeviceMac, e2eeDeviceLinux, e2eeDeviceIphone, e2eeDeviceIpad, e2eeDeviceAndroid, e2eeDeviceBrowser, e2eeDeviceOther
        case e2eeBeforeDevice, e2eeUndecryptable, e2eePreview, e2eeNotification, e2eeReportNote
        // Reporting a message (the website's words).
        case report = "messagesReport", reportLead = "messagesReportLead", reported = "messagesReported"
        case reasonSpam = "reportReasonSpam", reasonHarassment = "reportReasonHarassment", reasonHate = "reportReasonHate", reasonSexual = "reportReasonSexual", reasonOther = "reportReasonOther"
        // The party's chat beside its voice.
        case partyChat = "partyChatTitle", partyChatPlaceholder, partyChatEmpty, formerMember = "messagesFormerMember"
    }

    /// The reasons a message can be reported for, as the server names them.
    static let reportReasons: [(reason: String, key: Key)] = [("spam", .reasonSpam), ("harassment", .reasonHarassment), ("hate", .reasonHate), ("sexual", .reasonSexual), ("other", .reasonOther)]

    /// What a device is, in words: "Windows PC", "iPhone", "Device".
    static func name(_ kind: TogetherE2EE.DeviceKind) -> String {
        switch kind {
        case .windows: return text(.e2eeDeviceWindows)
        case .mac: return text(.e2eeDeviceMac)
        case .linux: return text(.e2eeDeviceLinux)
        case .iphone: return text(.e2eeDeviceIphone)
        case .ipad: return text(.e2eeDeviceIpad)
        case .android: return text(.e2eeDeviceAndroid)
        case .browser: return text(.e2eeDeviceBrowser)
        case .device: return text(.e2eeDeviceOther)
        }
    }

    static func name(_ reaction: TogetherMessageReaction) -> String {
        switch reaction {
        case .like: return text(.reactionLike)
        case .love: return text(.reactionLove)
        case .laugh: return text(.reactionLaugh)
        case .wow: return text(.reactionWow)
        case .sad: return text(.reactionSad)
        case .fire: return text(.reactionFire)
        case .gg: return text(.reactionGg)
        }
    }
}
