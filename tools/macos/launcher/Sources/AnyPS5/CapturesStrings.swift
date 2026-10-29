import Foundation

/// Captures on AnyTogether (posts of screenshots and clips, their likes and comments): their
/// texts, from the language files (l10n).
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
}
