import AnyPS5Core
import Foundation

/// Family limits: play time, age ratings, asking a parent and what a parent turned off: the
/// texts, from the language files (l10n).
enum FS {
    enum Key: String, CaseIterable {
        case family = "familyTitle", leftToday = "familyLeftToday", noLimitToday = "familyNoLimitToday", timeUp = "familyTimeUp", outsideHours = "familyOutsideHours", playedToday = "familyPlayedToday", limitToday = "familyLimitToday"
        case stale = "familyStaleConnect", staleDetail = "familyStaleDetail", locked = "familyLocked", lockedDetail = "familyLockedDetail", signInToAsk = "familySignInToAsk"
        case askParent = "familyAskParent", askedTooMany = "familyAskedTooMany", askMoreTime = "familyAskMoreTime", askMinutes = "familyAskMinutesFor", askMinutesDetail = "familyAskTimeDetail", asked = "familyAsked", askedAlready = "familyAskedAlready", askedGame = "familyAskedToPlay", askedFriend = "familyAskedFriend", askFriend = "familyAskFriend", askFailed = "familyAskFailed"
        case ratedAbove = "familyRatedAbove", ratedUnknown = "familyRatedUnknown", startLimit = "familyStartLimit", startWindow = "familyStartWindow"
        case warnMinutes = "familyWarnMinutes", warnOne = "familyWarnOne", warnDetail = "familyWarnDetail", noticeTitle = "familyNoticeTitle", noticeCloses = "familyNoticeCloses", noticeClosing = "familyNoticeClosing", noticeNotify = "familyNoticeNotify", noticeAsk = "familyNoticeAsk", moreTime = "familyMoreTime"
        case hoursMinutes = "familyHoursMinutes", minutes = "familyMinutes"
        case refusedVoice = "familyRefusedVoice", refusedShare = "familyRefusedShare", refusedPublic = "familyRefusedPublic", refusedMessages = "familyRefusedMessages", refusedFriends = "familyRefusedFriends", refusedDiscovery = "familyRefusedDiscovery", refusedMedia = "familyRefusedMedia", refusedProfile = "familyRefusedProfile", refusedCommunities = "familyRefusedCommunities", refusedAge = "familyRefusedAge", refusedFamily = "familyRefusedFamily"
        case refusedOther = "familyOtherSide", otherServer = "familyOtherServer"
        case notifAsksTime = "familyNotifAsksTime", notifAsksGame = "familyNotifAsksGame", notifAsksFriend = "familyNotifAsksFriend", notifSaidNo = "familyNotifSaidNo", notifGaveTime = "familyNotifGaveTime", notifGameYes = "familyNotifGameYes", notifFriendYes = "familyNotifFriendYes"
        case notifReachedLimit = "familyNotifReachedLimit", notifJoinedFamily = "familyNotifJoinedFamily", notifDeclinedFamily = "familyNotifDeclinedFamily", notifFamilyInvite = "familyNotifFamilyInvite", notifSummary = "familyNotifSummary"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// "1 h 20 min", "45 min"; a started minute counts.
    static func duration(_ seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60).rounded(.up))
        return minutes >= 60 ? format(.hoursMinutes, minutes / 60, minutes % 60) : format(.minutes, minutes)
    }

    /// What a parent's settings refused, as a 403 names it.
    static func refusal(_ feature: FamilyFeature) -> String {
        switch feature {
        case .voiceChat: return text(.refusedVoice)
        case .sharePlay: return text(.refusedShare)
        case .publicMatchmaking: return text(.refusedPublic)
        case .messages: return text(.refusedMessages)
        case .friendRequests: return text(.refusedFriends)
        case .discovery: return text(.refusedDiscovery)
        case .mediaSharing: return text(.refusedMedia)
        case .profileVisibility: return text(.refusedProfile)
        case .communities: return text(.refusedCommunities)
        case .ageRating: return text(.refusedAge)
        case .family: return text(.refusedFamily)
        }
    }
}
