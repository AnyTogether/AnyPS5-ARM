import AnyPS5Core
import Foundation

/// The texts of reactions, replies, editing and unsending, receipts, pinned and muted
/// conversations and the read receipts setting, in both languages (the same words the website
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

    static let english: [Key: String] = [
        .react: "React",
        .reactionLike: "Like",
        .reactionLove: "Love",
        .reactionLaugh: "Haha",
        .reactionWow: "Wow",
        .reactionSad: "Sad",
        .reactionFire: "Fire",
        .reactionGg: "GG",
        .reactedBy: "%1$@: %2$@",
        .reply: "Reply",
        .replyingTo: "Replying to %@",
        .earlierMessage: "An earlier message",
        .edit: "Edit",
        .editing: "Editing your message",
        .editLimit: "This message can't be edited any more.",
        .unsend: "Unsend",
        .unsendConfirm: "Unsend this message for everyone? It can't be undone.",
        .receiptSent: "Sent",
        .receiptDelivered: "Delivered",
        .receiptRead: "Read",
        .seenBy: "Seen by %d",
        .seenByEveryone: "Seen by everyone",
        .pin: "Pin to top",
        .unpin: "Unpin",
        .pinned: "Pinned",
        .pinFull: "You can pin up to %d conversations.",
        .mute: "Mute notifications",
        .unmute: "Unmute",
        .muted: "Muted",
        .readReceipts: "Send read receipts",
        .readReceiptsHint: "When off, people don't see when you've read their messages, and you don't see theirs. Delivered still shows.",
        .hintActions: "Actions",
    ]

    static let turkish: [Key: String] = [
        .react: "Tepki ver",
        .reactionLike: "Beğen",
        .reactionLove: "Sevgi",
        .reactionLaugh: "Haha",
        .reactionWow: "Vay",
        .reactionSad: "Üzgün",
        .reactionFire: "Ateş",
        .reactionGg: "GG",
        .reactedBy: "%1$@: %2$@",
        .reply: "Yanıtla",
        .replyingTo: "%@ kişisine yanıt",
        .earlierMessage: "Önceki bir mesaj",
        .edit: "Düzenle",
        .editing: "Mesajını düzenliyorsun",
        .editLimit: "Bu mesaj artık düzenlenemez.",
        .unsend: "Geri al",
        .unsendConfirm: "Bu mesaj herkesten geri alınsın mı? Bu geri döndürülemez.",
        .receiptSent: "Gönderildi",
        .receiptDelivered: "İletildi",
        .receiptRead: "Okundu",
        .seenBy: "%d kişi gördü",
        .seenByEveryone: "Herkes gördü",
        .pin: "En üste sabitle",
        .unpin: "Sabitlemeyi kaldır",
        .pinned: "Sabitlendi",
        .pinFull: "En fazla %d konuşma sabitleyebilirsin.",
        .mute: "Bildirimleri sessize al",
        .unmute: "Sesi aç",
        .muted: "Sessizde",
        .readReceipts: "Okundu bilgisi gönder",
        .readReceiptsHint: "Kapalıyken mesajlarını okuduğunu kimse görmez, sen de onlarınkini görmezsin. İletildi bilgisi yine görünür.",
        .hintActions: "Seçenekler",
    ]
}
