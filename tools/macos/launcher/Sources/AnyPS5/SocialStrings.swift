import Foundation

/// The texts of AnyTogether's social screens (activity, leaderboards, notifications, community
/// compatibility), from the language files (l10n); kept apart from `T`.
/// `TS.text(.key)` reads the launcher's current language.
enum TS {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        // Activity
        case feedTitle = "socialFeedTitle", feedSubtitle = "socialFeedSubtitle", feedRow = "socialFeedRow", feedRowDetail = "socialFeedRowDetail", feedEmpty = "socialFeedEmpty", feedFailed = "socialFeedFailed", feedLoading = "socialFeedLoading", feedMore = "socialFeedMore"
        case feedTrophy = "socialFeedTrophy", feedTrophies = "socialFeedTrophies", feedPlatinum = "socialFeedPlatinum", feedFirstPlay = "socialFeedFirstPlay", feedLongSession = "socialFeedLongSession", feedFriendship = "socialFeedFriendship", feedOther = "socialFeedOther"
        case feedMilestoneTrophies = "socialFeedMilestoneTrophies", feedMilestonePlatinums = "socialFeedMilestonePlatinums", feedMilestoneGames = "socialFeedMilestoneGames", feedMilestoneHours = "socialFeedMilestoneHours"
        case feedAndMore = "socialFeedAndMore", feedRare = "socialFeedRare", hintReact = "socialHintReact", hintProfile = "socialHintProfile"
        case profileActivity = "socialProfileActivity", profileNoActivity = "socialProfileNoActivity"
        // Leaderboards
        case boardTitle = "socialBoardTitle", boardOverall = "socialBoardOverall", boardPoints = "socialBoardPoints", boardTime = "socialBoardTime", boardCompletion = "socialBoardCompletion", scopeFriends = "socialScopeFriends", scopeGlobal = "socialScopeGlobal", boardYourRank = "socialBoardYourRank", boardOf = "socialBoardOf", boardPointsValue = "socialBoardPointsValue"
        case boardEmpty = "socialBoardEmpty", boardFailed = "socialBoardFailed", boardLoading = "socialBoardLoading", boardNoGame = "socialBoardNoGame", boardUnlisted = "socialBoardUnlisted", boardWouldBe = "socialBoardWouldBe", boardNothing = "socialBoardNothing", boardRowDetail = "socialBoardRowDetail", boardGameRowDetail = "socialBoardGameRowDetail"
        case hintBoard = "socialHintBoard", hintScope = "socialHintScope", boardYou = "socialBoardYou", boardPlayers = "socialBoardPlayers"
        // Notifications
        case notifTitle = "socialNotifTitle", notifEmpty = "socialNotifEmpty", notifMarkAll = "socialNotifMarkAll", notifMore = "socialNotifMore", notifFailed = "socialNotifFailed", notifLoading = "socialNotifLoading", notifUnread = "socialNotifUnread", notifSignIn = "socialNotifSignIn"
        case notifFriendRequest = "socialNotifFriendRequest", notifFriendAccepted = "socialNotifFriendAccepted", notifMessage = "socialNotifMessage", notifMessages = "socialNotifMessages", notifPartyInvite = "socialNotifPartyInvite", notifGameInvite = "socialNotifGameInvite", notifMissedCall = "socialNotifMissedCall", notifWarning = "socialNotifWarning", notifOther = "socialNotifOther"
        // Theme Hub
        case hubSharing = "socialHubSharing", hubShared = "socialHubShared", hubSharedVersion = "socialHubSharedVersion", hubShareDetail = "socialHubShareDetail", hubTooLarge = "socialHubTooLarge", hubBadTheme = "socialHubBadTheme", hubNoPreview = "socialHubNoPreview", hubNoTheme = "socialHubNoTheme"
        // Compatibility
        case compatAsk = "socialCompatAsk", compatSubtitle = "socialCompatSubtitle", compatNothing = "socialCompatNothing", compatBoots = "socialCompatBoots", compatMenus = "socialCompatMenus", compatIngame = "socialCompatIngame", compatPlayable = "socialCompatPlayable"
        case compatNothingDetail = "socialCompatNothingDetail", compatBootsDetail = "socialCompatBootsDetail", compatMenusDetail = "socialCompatMenusDetail", compatIngameDetail = "socialCompatIngameDetail", compatPlayableDetail = "socialCompatPlayableDetail"
        case compatLater = "socialCompatLater", compatNever = "socialCompatNever", compatNeverDetail = "socialCompatNeverDetail", compatWhat = "socialCompatWhat", compatThanks = "socialCompatThanks", compatCommunity = "socialCompatCommunity", compatReports = "socialCompatReports", compatReportRow = "socialCompatReportRow", compatNone = "socialCompatNone"
    }
}
