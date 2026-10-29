import Foundation

/// Captures on AnyTogether (posts of screenshots and clips, their likes and comments): their
/// texts, in both languages.
enum TCap {
    enum Key: String, CaseIterable {
        // Sharing from the gallery
        case shareToTogether = "capturesShareToTogether", shareToTogetherDetail = "capturesShareToTogetherDetail", postTitle = "capturesPostTitle", postSubtitle = "capturesPostSubtitle", caption = "capturesCaption", captionPlaceholder = "capturesCaptionPlaceholder", captionCount = "capturesCaptionCount"
        case visibility = "capturesVisibility", visibilityFriends = "capturesVisibilityFriends", visibilityPublic = "capturesVisibilityPublic", visibilityFriendsDetail = "capturesVisibilityFriendsDetail", visibilityPublicDetail = "capturesVisibilityPublicDetail"
        case post = "capturesPost", posting = "capturesPosting", uploading = "capturesUploading", posted = "capturesPosted", clipTooLong = "capturesClipTooLong", clipTooLongDetail = "capturesClipTooLongDetail", clipTooBig = "capturesClipTooBig", clipLength = "capturesClipLength", hintType = "capturesHintType", hintPost = "capturesHintPost"
        // The feed
        case title = "capturesTitle", subtitle = "capturesSubtitle", row = "capturesRow", rowDetail = "capturesRowDetail", empty = "capturesEmpty", failed = "capturesFailed", loading = "capturesLoading", more = "capturesMore"
        case like = "capturesLike", liked = "capturesLiked", comments = "capturesComments", commentsOff = "capturesCommentsOff", view = "capturesView", delete = "capturesDelete", deleteAgain = "capturesDeleteAgain", deleted = "capturesDeleted", likesCount = "capturesLikesCount", commentsCount = "capturesCommentsCount"
        case friendsOnly = "capturesFriendsOnly", everyone = "capturesEveryone", hintAction = "capturesHintAction", hintAuthor = "capturesHintAuthor"
        // Comments
        case commentsTitle = "capturesCommentsTitle", commentsEmpty = "capturesCommentsEmpty", commentsFailed = "capturesCommentsFailed", commentsLoading = "capturesCommentsLoading", write = "capturesWrite", replyingTo = "capturesReplyingTo", reply = "capturesReply", cancelReply = "capturesCancelReply"
        case commentSent = "capturesCommentSent", commentDeleted = "capturesCommentDeleted", commentDeleteAgain = "capturesCommentDeleteAgain", hintReply = "capturesHintReply", hintDelete = "capturesHintDelete", quickNice = "capturesQuickNice", quickWow = "capturesQuickWow", quickHaha = "capturesQuickHaha"
        // Refusals
        case refusedCommentsOff = "capturesRefusedCommentsOff", refusedLink = "capturesRefusedLink", refusedMuted = "capturesRefusedMuted", refusedFamilyFriends = "capturesRefusedFamilyFriends", refusedRateLimited = "capturesRefusedRateLimited", refusedStorage = "capturesRefusedStorage", refusedBadMedia = "capturesRefusedBadMedia", refusedGone = "capturesRefusedGone"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// The quick comments a controller can send with one press.
    static var quickComments: [String] { ["GG", text(.quickNice), "🔥", text(.quickWow), text(.quickHaha)] }

    static let english: [Key: String] = [
        .shareToTogether: "Share to AnyTogether",
        .shareToTogetherDetail: "A post your friends can like and comment on",
        .postTitle: "Share to AnyTogether",
        .postSubtitle: "Posted to Captures with the game it is from",
        .caption: "Caption",
        .captionPlaceholder: "Say something about it (optional)",
        .captionCount: "%d / %d",
        .visibility: "Who sees it",
        .visibilityFriends: "Friends",
        .visibilityPublic: "Public",
        .visibilityFriendsDetail: "Your friends, and you",
        .visibilityPublicDetail: "Anyone on AnyTogether who is not blocked",
        .post: "Post",
        .posting: "Posting…",
        .uploading: "Uploading…",
        .posted: "Posted to Captures",
        .clipTooLong: "This clip is %@ long",
        .clipTooLongDetail: "A post takes a clip of up to 1:00. Save a shorter one (F12 keeps the last moments) and share that.",
        .clipTooBig: "This clip is %@: it is made smaller to fit %@ before it goes up",
        .clipLength: "Clip · %@",
        .hintType: "Type",
        .hintPost: "Post",
        .title: "Captures",
        .subtitle: "Screenshots and clips from you, your friends and players you met",
        .row: "Captures",
        .rowDetail: "Friends' screenshots and clips: like them, comment",
        .empty: "No captures yet. Share a screenshot or clip from a game's gallery: Share → Share to AnyTogether.",
        .failed: "Captures could not be read. Check the connection and open them again.",
        .loading: "Reading captures…",
        .more: "Older captures load as you go",
        .like: "Like",
        .liked: "Liked",
        .comments: "Comments",
        .commentsOff: "Comments off",
        .view: "View",
        .delete: "Delete",
        .deleteAgain: "Press again to delete",
        .deleted: "Post deleted",
        .likesCount: "%d",
        .commentsCount: "%d",
        .friendsOnly: "Friends",
        .everyone: "Public",
        .hintAction: "Like, comment, view",
        .hintAuthor: "Profile",
        .commentsTitle: "Comments",
        .commentsEmpty: "No comments yet. Be the first.",
        .commentsFailed: "The comments could not be read.",
        .commentsLoading: "Reading comments…",
        .write: "Write a comment…",
        .replyingTo: "Replying to %@",
        .reply: "Reply",
        .cancelReply: "Cancel reply",
        .commentSent: "Comment sent",
        .commentDeleted: "Comment deleted",
        .commentDeleteAgain: "Press △ again to delete",
        .hintReply: "Reply",
        .hintDelete: "Delete",
        .quickNice: "Nice!",
        .quickWow: "Wow",
        .quickHaha: "Haha",
        .refusedCommentsOff: "The author turned comments off for this post",
        .refusedLink: "That link is not allowed on AnyTogether",
        .refusedMuted: "Your account is muted for now: you cannot post or comment",
        .refusedFamilyFriends: "Your family settings keep your posts to friends",
        .refusedRateLimited: "That was a lot at once: wait a moment and try again",
        .refusedStorage: "This AnyTogether server keeps no files, so it takes no captures",
        .refusedBadMedia: "AnyTogether could not take this file",
        .refusedGone: "This post is no longer there",
    ]

    static let turkish: [Key: String] = [
        .shareToTogether: "AnyTogether'da Paylaş",
        .shareToTogetherDetail: "Arkadaşlarının beğenip yorum yapabileceği bir gönderi",
        .postTitle: "AnyTogether'da Paylaş",
        .postSubtitle: "Oyunuyla birlikte Anlar'a eklenir",
        .caption: "Açıklama",
        .captionPlaceholder: "Bir şey yaz (isteğe bağlı)",
        .captionCount: "%d / %d",
        .visibility: "Kimler görür",
        .visibilityFriends: "Arkadaşlar",
        .visibilityPublic: "Herkese Açık",
        .visibilityFriendsDetail: "Arkadaşların ve sen",
        .visibilityPublicDetail: "AnyTogether'da seni engellemeyen herkes",
        .post: "Paylaş",
        .posting: "Paylaşılıyor…",
        .uploading: "Yükleniyor…",
        .posted: "Anlar'da paylaşıldı",
        .clipTooLong: "Bu klip %@ uzunluğunda",
        .clipTooLongDetail: "Bir gönderi en fazla 1:00'lık klip alır. Daha kısa bir klip kaydet (F12 son anları saklar) ve onu paylaş.",
        .clipTooBig: "Bu klip %@: yüklenmeden önce %@ sınırına sığacak kadar küçültülür",
        .clipLength: "Klip · %@",
        .hintType: "Yaz",
        .hintPost: "Paylaş",
        .title: "Anlar",
        .subtitle: "Senin, arkadaşlarının ve birlikte oynadıklarının ekran görüntüleri ve klipleri",
        .row: "Anlar",
        .rowDetail: "Arkadaşlarının ekran görüntüleri ve klipleri: beğen, yorum yap",
        .empty: "Henüz bir an yok. Bir oyunun galerisinden ekran görüntüsü ya da klip paylaş: Paylaş → AnyTogether'da Paylaş.",
        .failed: "Anlar okunamadı. Bağlantını kontrol edip yeniden aç.",
        .loading: "Anlar okunuyor…",
        .more: "Daha eskiler sen indikçe gelir",
        .like: "Beğen",
        .liked: "Beğenildi",
        .comments: "Yorumlar",
        .commentsOff: "Yorumlar kapalı",
        .view: "Görüntüle",
        .delete: "Sil",
        .deleteAgain: "Silmek için yeniden bas",
        .deleted: "Gönderi silindi",
        .likesCount: "%d",
        .commentsCount: "%d",
        .friendsOnly: "Arkadaşlar",
        .everyone: "Herkese Açık",
        .hintAction: "Beğen, yorum, bak",
        .hintAuthor: "Profil",
        .commentsTitle: "Yorumlar",
        .commentsEmpty: "Henüz yorum yok. İlk sen yaz.",
        .commentsFailed: "Yorumlar okunamadı.",
        .commentsLoading: "Yorumlar okunuyor…",
        .write: "Yorum yaz…",
        .replyingTo: "%@ kişisine yanıt",
        .reply: "Yanıtla",
        .cancelReply: "Yanıtı bırak",
        .commentSent: "Yorum gönderildi",
        .commentDeleted: "Yorum silindi",
        .commentDeleteAgain: "Silmek için △'ya yeniden bas",
        .hintReply: "Yanıtla",
        .hintDelete: "Sil",
        .quickNice: "Harika!",
        .quickWow: "Vay",
        .quickHaha: "Haha",
        .refusedCommentsOff: "Gönderinin sahibi bu gönderide yorumları kapattı",
        .refusedLink: "Bu bağlantıya AnyTogether'da izin verilmiyor",
        .refusedMuted: "Hesabın şimdilik susturuldu: paylaşamaz ve yorum yapamazsın",
        .refusedFamilyFriends: "Aile ayarların gönderilerini arkadaşlarınla sınırlıyor",
        .refusedRateLimited: "Bir anda çok fazla oldu: biraz bekleyip yeniden dene",
        .refusedStorage: "Bu AnyTogether sunucusu dosya saklamıyor, bu yüzden an paylaşılamıyor",
        .refusedBadMedia: "AnyTogether bu dosyayı alamadı",
        .refusedGone: "Bu gönderi artık yok",
    ]
}
