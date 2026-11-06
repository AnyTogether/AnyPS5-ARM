import AnyPS5Core
import Foundation

/// The texts of reactions, replies, editing and unsending, receipts, pinned and muted
/// conversations, the read receipts setting, the party's chat and reporting a message, from the language
/// files (l10n) (the same words the website uses). `TChat.text(.key)` reads the launcher's language.
enum TChat {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case react = "messagesReact", reactionLike, reactionLove, reactionLaugh, reactionWow, reactionSad, reactionFire, reactionGg, reactedBy = "chatReactedBy"
        case reply = "messagesReply", replyingTo = "messagesReplyingTo", earlierMessage = "messagesEarlier", edit = "messagesEdit", editing = "chatEditing", editLimit = "messagesEditLimit", unsend = "messagesUnsend", unsendConfirm = "messagesUnsendConfirm"
        case receiptSent, receiptDelivered, receiptRead, seenBy = "chatSeenBy", seenByEveryone = "receiptSeenByEveryone"
        case pin = "conversationPin", unpin = "conversationUnpin", pinned = "conversationPinned", pinFull = "chatPinFull", mute = "conversationMute", unmute = "conversationUnmute", muted = "conversationMuted"
        case readReceipts, readReceiptsHint, hintActions = "chatHintActions"
        case partyChat = "partyChatTitle", partyChatPlaceholder, partyChatEmpty, formerMember = "messagesFormerMember"
        case report = "messagesReport", reportTitle = "messagesReportTitle", reportLead = "messagesReportLead", reportSent = "messagesReportSent"
        case reasonSpam = "reportReasonSpam", reasonHarassment = "reportReasonHarassment", reasonHate = "reportReasonHate", reasonSexual = "reportReasonSexual"
        case reasonImpersonation = "reportReasonImpersonation", reasonCheating = "reportReasonCheating", reasonPiracy = "reportReasonPiracy", reasonOther = "reportReasonOther"
    }

    static func name(_ reason: TogetherReportReason) -> String {
        switch reason {
        case .spam: return text(.reasonSpam)
        case .harassment: return text(.reasonHarassment)
        case .hate: return text(.reasonHate)
        case .sexual: return text(.reasonSexual)
        case .impersonation: return text(.reasonImpersonation)
        case .cheating: return text(.reasonCheating)
        case .piracy: return text(.reasonPiracy)
        case .other: return text(.reasonOther)
        }
    }

    static func symbol(_ reason: TogetherReportReason) -> String {
        switch reason {
        case .spam: return "envelope.badge"
        case .harassment: return "hand.raised"
        case .hate: return "exclamationmark.bubble"
        case .sexual: return "eye.slash"
        case .impersonation: return "person.crop.circle.badge.questionmark"
        case .cheating: return "gamecontroller"
        case .piracy: return "externaldrive.badge.xmark"
        case .other: return "ellipsis.circle"
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
