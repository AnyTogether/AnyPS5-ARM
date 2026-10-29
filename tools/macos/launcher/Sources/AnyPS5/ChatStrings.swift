import AnyPS5Core
import Foundation

/// The texts of reactions, replies, editing and unsending, receipts, pinned and muted
/// conversations and the read receipts setting, from the language files (l10n) (the same words the website
/// uses). `TChat.text(.key)` reads the launcher's language.
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
