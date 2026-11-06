import Foundation

/// The texts of challenges (the strip on the leaderboard, a challenge's page, its notifications),
/// from the language files (l10n), the same words the website uses. `TChal.text(.key)` reads the
/// launcher's current language.
enum TChal {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case title = "challengesTitle", kicker = "challengeKicker"
        case metricPoints = "challengeMetricPoints", metricTrophies = "challengeMetricTrophies", metricTime = "challengeMetricTime", metricOther = "challengeMetricOther"
        case trophiesValue = "challengeTrophiesValue", trophyValue = "challengeTrophyValue"
        case endsIn = "challengeEndsIn", startsIn = "challengeStartsIn", finishing = "challengeFinishing", ended = "challengeEnded", cancelled = "challengeCancelled"
        case entrants = "challengeEntrants", leading = "challengeLeading", winner = "challengeWinner", yourPlace = "challengeYourPlace", notIn = "challengeNotIn", noLeader = "challengeNoLeader"
        case hidden = "challengeHidden", join = "challengeJoin", leave = "challengeLeave", joinNote = "challengeJoinNote", makeOnWeb = "challengeMakeOnWeb"
        case forFriends = "challengeForFriends", forCommunity = "challengeForCommunity", forEveryone = "challengeForEveryone", by = "challengeBy", byYou = "challengeByYou"
        case loading = "challengeLoading", failed = "challengeFailed", gone = "challengeGone", noScores = "challengeNoScores", notStarted = "challengeNotStarted", finalStandings = "challengeFinalStandings", standings = "challengeStandings"
        case full = "challengeFull", over = "challengeOver", youMadeIt = "challengeYouMadeIt", family = "challengeFamily", joined = "challengeJoined", left = "challengeLeft", actionFailed = "challengeActionFailed"
        case hintChallenges = "challengeHintChallenges", hintJoin = "challengeHintJoin"
        case notifInvite = "socialNotifChallengeInvite", notifStarted = "socialNotifChallengeStarted", notifEnded = "socialNotifChallengeEnded", notifWon = "socialNotifChallengeWon", notifPlace = "socialNotifChallengePlace", notifWinner = "socialNotifChallengeWinner"
    }
}
