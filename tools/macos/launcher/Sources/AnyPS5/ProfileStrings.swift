import Foundation

/// Profiles (the picker, adding one, online and offline, Settings → Profiles) and the
/// friends-only name and picture: their texts, from the language files (l10n).
enum TPro {
    enum Key: String, CaseIterable {
        case profilesCategory, pickerKicker = "profileKicker", whoIsPlaying = "profileWhoIsPlaying", pickerSubtitle = "profilePickerSubtitle", pickerSubtitleLaunch = "profilePickerSubtitleLaunch", hintPlay = "profileHintPlay", playingNow = "profilePlayingNow", online = "profileOnline", offline = "profileOffline"
        case howToPlay = "profileHowToPlay", howToPlaySubtitle = "profileHowToPlaySubtitle", profileNamePlaceholder = "profileNameHint", playerNumber = "profilePlayerNumber", continueStep = "profileContinueStep"
        case offlineTitle = "profileOfflineTitle", offlineLead = "profileOfflineLead", offlineFact1 = "profileOfflineFact1", offlineFact2 = "profileOfflineFact2", offlineFact3 = "profileOfflineFact3", offlineTag = "profileOfflineTag"
        case onlineTitle = "profileOnlineTitle", onlineLead = "profileOnlineLead", onlineFact1 = "profileOnlineFact1", onlineFact2 = "profileOnlineFact2", onlineFact3 = "profileOnlineFact3", onlineTag = "profileOnlineTag"
        case signInTitleNew = "profileSignInNew", signInTitleOnline = "profileSignInOnline", signInTitleAgain = "profileSignInAgain", signInSubtitle = "profileSignInSubtitle"
        case menuKicker = "profileMenuTitle", otherProfiles = "profileOtherProfiles", otherProfile = "profileOtherProfile", addSomeone = "profileAddSomeone", goOffline = "profileGoOffline", goOnline = "profileGoOnline", goOfflineDetail = "profileGoOfflineDetail", goOnlineDetail = "profileGoOnlineDetail", manageProfiles = "profileManage"
        case closeGameFirst = "profileCloseGameFirst", waitForSync = "profileWaitForSync", welcomeBack = "profileWelcomeBack", nowOffline = "profileNowOffline", savesNotSwapped = "profileSavesNotSwapped"
        case onlineAs = "profileOnlineAs", onlineSignedOut = "profileOnlineSignedOut", offlineDetail = "profileOfflineDetail", tileColour = "profileColour", tileColourDetail = "profileTileColourDetail", askEveryTime = "profileAskEveryTime", askEveryTimeDetail = "profileAskEveryTimeDetail"
        case otherProfilesTitle = "profileOtherTitle", switchTo = "profileSwitchTo", deleteProfile = "profileDelete", deleteQuestion = "profileDeleteQuestion", addProfile = "profileAdd", addProfileDetail = "profileAddProfileDetail", backupFolder = "profileBackupFolder", cannotDelete = "profileCannotDelete", deleted = "profileDeleted"
        case offlineTogether = "profileOfflineTogether", offlineTogetherDetail = "profileOfflineTogetherDetail"
        case friendsOnlyTitle = "privateTitle", friendsOnlyDetail = "privateDetail", friendsOnlyName = "privateName", friendsOnlyNameDetail = "profileFriendsOnlyNameDetail", friendsOnlyNameSave = "privateNameSave", friendsOnlyNameClear = "privateNameClear"
        case friendsOnlyNameSaved = "privateNameSaved", friendsOnlyNameCleared = "privateNameCleared", friendsOnlyPicture = "profileFriendsOnlyPicture", friendsOnlyPictureDetail = "profileFriendsOnlyPictureDetail", friendsOnlyPictureRemove = "privatePictureRemove"
        case friendsOnlyPictureSaved = "privatePictureSaved", friendsOnlyPictureRemoved = "privatePictureRemoved", friendsOnlyBadge = "privateBadge"
        case colourIndigo, colourTeal, colourCoral, colourAmber, colourViolet, colourGreen, colourPink, colourSky
    }

    /// "1 other profile", "3 other profiles", or the way to add one when there is none.
    static func others(_ count: Int) -> String {
        count > 1 ? format(.otherProfiles, count) : count == 1 ? text(.otherProfile) : text(.addSomeone)
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    /// The tile colours, in AppModel.profilePalette's order.
    static var colourNames: [String] {
        [.colourIndigo, .colourTeal, .colourCoral, .colourAmber, .colourViolet, .colourGreen, .colourPink, .colourSky].map(text)
    }
}
