import Foundation

/// Find players, Live now, public parties and share plays, discovery and game hubs: the texts,
/// from the language files (l10n).
enum FP {
    enum Key: String, CaseIterable {
        case findPlayers = "discoverFindPlayers", findPlayersDetail = "discoverFindPlayersDetail", board = "discoverBoard", myPosts = "discoverMyPosts", liveAndParties = "discoverLiveAndParties", people = "discoverPeople", overview = "discoverOverview"
        case game = "discoverGame", allGames = "discoverAllGames", purpose = "discoverPurpose", anyPurpose = "discoverAnyPurpose", language = "discoverLanguage", anyLanguage = "discoverAnyLanguage", startingSoon = "discoverStartingSoon", startingSoonDetail = "discoverStartingSoonDetail"
        case purposeCoop = "discoverPurposeCoop", purposeOnline = "discoverPurposeOnline", purposeParty = "discoverPurposeParty", purposeTrophies = "discoverPurposeTrophies"
        case findFor = "discoverFindFor", findForDetail = "discoverFindForDetail", hubOf = "discoverHubOf", hubDetail = "discoverHubDetail", loading = "discoverLoading", noPosts = "discoverNoPosts", noPostsDetail = "discoverNoPostsDetail", more = "discoverMore"
        case now = "discoverNow", inMinutes = "discoverInMinutes", inHours = "discoverInHours", filled = "discoverFilled", selectImIn = "discoverSelectImIn", waitingFor = "discoverWaitingFor", inSharePlay = "discoverInSharePlay", inParty = "discoverInParty", saidNo = "discoverSaidNo", closed = "discoverClosed", full = "discoverFull", waitingCount = "discoverWaitingCount"
        case noMine = "discoverNoMine", noMineDetail = "discoverNoMineDetail", letIn = "discoverLetIn", letInCoop = "discoverLetInCoop", letInParty = "discoverLetInParty", notNow = "discoverNotNow", theyShare = "discoverTheyShare", theyParty = "discoverTheyParty", closePost = "discoverClosePost", askedTitle = "discoverAskedTitle"
        case liveNow = "discoverLiveNow", liveDetail = "discoverLiveDetail", noLive = "discoverNoLive", publicParties = "discoverPublicParties", publicPartiesDetail = "discoverPublicPartiesDetail", noParties = "discoverNoParties", viewers = "discoverViewers"
        case askToWatch = "discoverAskToWatch", askedToWatch = "discoverAskedToWatch", askedToWatchToast = "discoverAskedToWatchToast", askParty = "discoverAskParty", askedParty = "discoverAskedParty", askedPartyToast = "discoverAskedPartyToast", selectTakeBack = "discoverSelectTakeBack", yourParty = "discoverYourParty"
        case discoverySettings, discoveryDetail, youShow = "discoverYouShow", youHide = "discoverYouHide", noSuggestions = "discoverNoSuggestions", noSuggestionsDetail = "discoverNoSuggestionsDetail", addFriend = "discoverAddFriend", alreadyFriends = "discoverAlreadyFriends"
        case bothPlay = "discoverBothPlay", friendsInCommon = "discoverFriendsInCommon", speaks = "discoverSpeaks"
        case playingNow = "discoverPlayingNow", players = "discoverPlayers", forMinutes = "discoverForMinutes", noGroups = "discoverNoGroups", noPlayers = "discoverNoPlayers", noPlayersDetail = "discoverNoPlayersDetail", played = "discoverPlayed"
        case slots = "discoverSlots", slotsCount = "discoverSlotsCount", coopDetail = "discoverCoopDetail", partyDetail = "discoverPartyDetail", alsoIn = "discoverAlsoIn", noOther = "discoverNoOther", starts = "discoverStarts", staysUp = "discoverStaysUp", staysUpDetail = "discoverStaysUpDetail", hours = "discoverHours", note = "discoverNote", noteDetail = "discoverNoteDetail"
        case post = "discoverPost", postDetail = "discoverPostDetail", posting = "discoverPosting", posted = "discoverPosted", toldThem = "discoverToldThem", letInDone = "discoverLetInDone", letInDoneCoop = "discoverLetInDoneCoop"
        case slowDown = "discoverSlowDown", tooManyPosts = "discoverTooManyPosts"
        case wantsIn = "discoverWantsIn", youreInParty = "discoverYoureInParty", youreInShare = "discoverYoureInShare", notThisTime = "discoverNotThisTime", asksParty = "discoverAsksParty", partyLetYouIn = "discoverPartyLetYouIn", asksWatch = "discoverAsksWatch"
        case listPublic = "discoverListPublic", listPublicDetail = "discoverListPublicDetail", listOff = "discoverListOff", listAsk = "discoverListAsk", listOpen = "discoverListOpen", listOpenWatch = "discoverListOpenWatch", listGame = "discoverListGame", listNoGame = "discoverListNoGame", listLanguage = "discoverListLanguage", liveToggle = "discoverLiveToggle", liveToggleDetail = "discoverLiveToggleDetail"
        case letWatch = "discoverLetWatch", findParty = "discoverFindParty", findPartyDetail = "discoverFindPartyDetail"
        case discoveryTitle, showMe = "discoverShowMe", showMeDetail = "discoverShowMeDetail", followLibrary = "discoverFollowLibrary", on = "discoverOn", off = "discoverOff", languagesTitle = "discoverLanguagesTitle", languagesDetail = "discoverLanguagesDetail", languagesFull = "discoverLanguagesFull"
        case notifLfgRequest = "discoverNotifLfgRequest", notifLfgAccepted = "discoverNotifLfgAccepted"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }
}
