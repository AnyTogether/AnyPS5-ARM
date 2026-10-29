import AnyPS5Core
import Foundation

/// A launcher language: one file in the l10n folder (or the user's Languages folder) named by its
/// locale code, de.json for German, its own name the text "languageName" and its console language
/// found from the code. The same files as AnyLauncher-Port's; see l10n/TRANSLATING.md.
struct Language: Hashable, Identifiable, Codable {
    let code: String

    init(code: String) { self.code = code }

    /// The language of [rawValue] when there is a file for it.
    init?(rawValue: String) {
        guard T.languages.contains(where: { $0.code == rawValue }) else { return nil }
        code = rawValue
    }

    init(from decoder: Decoder) throws { code = try decoder.singleValueContainer().decode(String.self) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }

    /// English, there even when en.json is not; and Turkish, for the previews.
    static let english = Language(code: LanguageFiles.english)
    static let turkish = Language(code: "tr")

    /// Every language with a file, English first, then by name.
    static var allCases: [Language] { T.languages }

    var rawValue: String { code }
    var id: String { code }

    /// The language's name in itself, as Settings lists it.
    var displayName: String { T.texts.language(code)?.name ?? (code == LanguageFiles.english ? "English" : code) }

    /// The console language a game starts in when its own setting follows the launcher.
    var consoleLanguage: Int { T.texts.language(code)?.consoleLanguage ?? 1 }

    /// The locale dates, numbers and capitals follow: tr_TR and en_US for the first two, as before.
    var locale: Locale {
        switch code {
        case "tr": return Locale(identifier: "tr_TR")
        case "en": return Locale(identifier: "en_US")
        default: return Locale(identifier: code.replacingOccurrences(of: "-", with: "_"))
        }
    }
}

/// Every user-facing text, read from the language files (l10n/en.json, tr.json, …). `T.text(.key)`
/// reads the current language; a text it does not have is the English one.
enum T {
    nonisolated(unsafe) static var language: Language = .english

    /// Where a translator tries a file in a released launcher; one there comes before the built-in
    /// file of its code.
    static let userFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Languages")

    /// The built-in files: Contents/Resources/l10n in the app (build_launcher_app.sh copies them),
    /// else the source tree's for `swift run` and the previews.
    static var builtInFolder: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("l10n"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("en.json").path) { return bundled }
        return sourceFolder
    }

    static let sourceFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../l10n").standardized

    nonisolated(unsafe) static var texts = load()

    static func load(_ folders: [URL] = [userFolder, builtInFolder]) -> LanguageTexts {
        LanguageTexts(LanguageFiles.load(folders) { NSLog("[anyps5-launcher] %@", $0) })
    }

    /// Every language with a file, English first even without one.
    static var languages: [Language] {
        let found = texts.languages.map { Language(code: $0.code) }
        return found.first == .english ? found : [.english] + found.filter { $0 != .english }
    }

    static var locale: Locale { language.locale }

    /// The text of the JSON key [key] in the current language.
    static func string(_ key: String) -> String { texts.text(key, in: language.code) }

    static func text(_ key: Key) -> String { string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    /// Every JSON key the code reads, from each texts enum (`T.Key`, `TPrep.Key`, …): the check
    /// in Tests/AnyPS5Tests has en.json hold them all, and nothing else.
    static var codeKeys: [String] {
        [
            T.Key.allCases.map(\.rawValue),
            TAddons.Key.allCases.map(\.rawValue),
            TK.Key.allCases.map(\.rawValue),
            TA.Key.allCases.map(\.rawValue),
            TB.Key.allCases.map(\.rawValue),
            TW.Key.allCases.map(\.rawValue),
            TCap.Key.allCases.map(\.rawValue),
            TChat.Key.allCases.map(\.rawValue),
            TCloud.Key.allCases.map(\.rawValue),
            TP.Key.allCases.map(\.rawValue),
            FP.Key.allCases.map(\.rawValue),
            TE.Key.allCases.map(\.rawValue),
            FS.Key.allCases.map(\.rawValue),
            TU.Key.allCases.map(\.rawValue),
            TF.Key.allCases.map(\.rawValue),
            TPresets.Key.allCases.map(\.rawValue),
            TG.Key.allCases.map(\.rawValue),
            TH.Key.allCases.map(\.rawValue),
            JS.Key.allCases.map(\.rawValue),
            TL.Key.allCases.map(\.rawValue),
            PT.Key.allCases.map(\.rawValue),
            TPow.Key.allCases.map(\.rawValue),
            TPrep.Key.allCases.map(\.rawValue),
            TPro.Key.allCases.map(\.rawValue),
            TC.Key.allCases.map(\.rawValue),
            SP.Key.allCases.map(\.rawValue),
            TS.Key.allCases.map(\.rawValue),
            TSteam.Key.allCases.map(\.rawValue),
        ].flatMap { $0 }
    }

    enum Key: String, CaseIterable {
        case welcome, welcomeSubtitle, chooseLanguage, chooseTheme, chooseThemeSubtitle, chooseFolder, chooseFolderSubtitle
        case pickFolder, changeFolder, gamesFound, noGamesFound, continueAction, back, start, skip
        case games, library, settings, play, unlock, unlocking, cancel, queued, update, retry, options
        case locked, ready, updateAvailable, failed, starting, startingText, running
        case stepUnwrap, stepRelink, stepCopy, stepBundle, stepFinish
        case titleID, version, size, status, folder
        case gameSettings, resolution, resolutionDefault, display, windowed, fullscreen, windowSize, vsync, on, off
        case displayDefaults, displayDefaultsDetail, followDefault, useDisplayDefaults, useDisplayDefaultsDetail
        case overlay, overlayOff, overlayTopLeft, overlayTopRight, overlayBottomLeft, overlayBottomRight, overlayStyle, overlayMinimal, overlayDetailed, frameGeneration, frameGenerationDetail, frameGenerationLowPower, linkNoGame, folderNoGames, useGamesFolder, useGamesFolderDetail, useGamesFolderConfirm, addFolder, addFolderDetail, removeFolder, removeFolderAsk, folderRemoved, folderNotConnected, folderGames, folderOneGame, copyLink, linkCopied, saveSync, saveSyncDetail, saveSyncNoFolder, syncFolder, syncFolderICloud, syncFolderNone, savesSyncedFrom, saveSyncFailed, clips, clipsDetail, clipLength, seconds, clipsNeedPermission, clipsNeedPermissionDetail, clipsOff, clipsOffDetail, clipSaved = "clipSavedTitle", clipSavedDetail, clipFailed, lowPowerTitle, lowPowerFrameGeneration, lowPowerRefresh, gameLanguage, followLauncher
        case newGame, newGames, newGameDetail
        case reinstall, showInFinder, openLog, uninstall, clearShaderCache, uninstallConfirm, uninstallDone, cacheCleared
        case appearance, theme, accent, background, backgroundTheme, backgroundImage, backgroundVideo, chooseFile, gameArtwork
        case motion, motionFull, motionReduced, sounds, language, storage, rescan, installedSize, about, aboutText, toolkitVersion
        case profileName, behaviour, hideWhilePlaying, rosettaMissing, rosettaInstall, rosettaInstalled
        case moveToApplications, moveToApplicationsText, moveNow, later, noToolkit
        case emptyLibraryTitle, emptyLibraryText, scanning, allGames, sortName, playTime
        case themeCosmic, themeAurora, themeSunset, themeGlass, hintMove, hintGame, hintSelect, hintBack, hintOptions
        case unlockFailed, startFailed, gameEnded, logTitle, close, quit, confirm
        case unreadableDump
        case togetherIntro, togetherIntroDetail, togetherEmail, togetherSendCode, togetherWithWebsite, togetherWithWebsiteDetail, togetherCodeSent, togetherCode, togetherSignIn, togetherOtherEmail, togetherTypeCode, togetherOpenWebsite, togetherWelcome, togetherSignOut, togetherOnline, togetherConnected, togetherConnecting, togetherSignedOutElsewhere, togetherEmailInvalid, togetherCodeWrong, togetherCodeExpired, togetherCodeLocked, togetherTooMany, togetherUnreachable
        case togetherWithPhone, togetherWithPhoneDetail, togetherOnPhone, togetherPhoneDeclined, togetherPhoneSignedIn
        case profileTitle, profileMine, profileMineDetail, profileGames, profileHours, profileTrophies, profilePoints, profileGamesTitle, profileRecentTrophies, profilePrivate, profileFriendsOnly, profileDetailsPrivate, profileFailed, profileNoGames, profileNoTrophies, profileLoading, profileHoursMinutes, profileHoursOnly, profileMinutes, profileLastPlayed, profileYou, profileFriend
        case rarityCommon, rarityUncommon, rarityRare, rarityVeryRare, rarityUltraRare
        case togetherEditProfile, togetherName, togetherBio, togetherCountry, togetherCountryDetail, togetherSaveProfile, togetherProfileSaved, togetherHandle, togetherHandleDetail, togetherHandleAgain, togetherChangeHandle, togetherHandleChanged, togetherHandleTaken, togetherHandleReserved, togetherHandleInvalid, togetherNoLinks, togetherPrivacyTitle, privacyLibrary, privacyTrophies, privacyFriends, privacyPresence, privacySearch, visibilityEveryone, visibilityFriends, visibilityNobody, visibilityNoOne
        case messagesTitle, messagesNone, messagesStart, messagesSayHello, messagesYou, messagesDeleted, messagesWrite, messagesFrom, messagesPick, messagesEmptyThread, messagesFailed, messagesEdited, messagesSend, quickHello, quickOnMyWay, quickJoinMe, quickOneSec
        case partyTitle, partyStart, partyStartDetail, partyOpen, partyOpenDetail, partyJoinOf, partySize, partyDecline, partyNone, partyMembers, partyLeader, partyInVoice, partyInviteFriends, partyInvite, partyInvited, partyLeave, partyInvites, partyInvitedYou, partyJoined, partyLeft, partyKicked, partyEnded, partyFull, friendsInParty
        case togetherServer, togetherServerDetail, togetherServerForced, togetherServerUse, togetherServerInvalid, togetherServerNow
        case gameJoinable, gameJoin, gameInvitedDetail, gameDecline, gameInviteTitle, gamePlayers, gameInvited, gameInvitedYou, gameNotHere, gameUnlockFirst, gameVersionMismatch, gameEngineMismatch, gameSessionFull, gameCloseFirst, sessionEnded, gameJoined, togetherFriendsJoin, togetherFriendsJoinDetail
        case voiceJoin, voiceJoinDetail, voiceInCall, voiceMic, voicePushToTalk, voicePushToTalkOn = "voicePushToTalkOnMac", voicePushToTalkOff = "voicePushToTalkOffMac", voiceLeave, voiceNoMic, voiceJoined
        case togetherLinkBlocked
        case togetherOnlinePlay, togetherOnlinePlayDetail
        case messagesTyping, messagesTypingMany
        case callRinging, callAnswer, callDecline, callKeys, callWith, callCalling, callFriend, callHangUp, callMissed, callDeclined, callEnded, callNoAnswer, callAnsweredElsewhere, voiceMuted, voiceSpeaking
        case messagesNewGroup, messagesNewGroupDetail, messagesGroupName, messagesGroupPicked, messagesGroupCreate, messagesGroupPick, messagesGroupMade
        case partyMakeLeader, partyRemove = "partyKick", partyNowLeads, partyRemoved, partyYouLead
        case friendsTitle, friendsSignIn, friendsAccept, friendsDecline, friendsWantsToBe, friendsAddByHandle, friendsSendRequest, friendsNone, friendsYourHandle, friendsWaiting, friendsOffline, friendsOnline, friendsAway, friendsPlaying, friendsPlayingFor, friendsRequestSent, friendsNowFriends, friendsNoOne, friendsAsked, friendsOnlineCount
        case remotePlayNeedsPermission, remotePlayPermissionTitle, themes, themesDetail, themeStudio, themeStudioDetail, themeStudioSubtitle, themesOnMac, themesHub, hubLoading, hubFailed, hubEmpty, installThemeFile, themeBy, themeActive, themeInstalled, themeDownloading, themeInstallFailed, themeSaveFailed, themeSaved, themeName, themeAuthor, themeMotion, themeHue, themeHighlight, themeDepth, themeAccent, themeBackground, themeNoFile, themeRemoveBackground, themeMusic, themeMusicDetail, themeRemoveMusic, exportTheme, exportThemeDetail, shareTheme, shareThemeDetail, shareThemeHint, themeShareNext, deleteTheme, newThemeName
        case controls, controlsHint, controlsFromGame, pressKey, resetControls, noKey, dpad, leftStick, rightStick, touchpadLeft, touchpadRight
        case directionUp, directionDown, directionLeft, directionRight, keySpace, keyEnter
        case mouseLeft, mouseRight, mouseMiddle, mouseBack, mouseForward, wheelUp, wheelDown
        case trophies, trophyHidden, trophyHiddenDetail, trophyShow, trophyHide, alwaysShowHiddenTrophies = "showHiddenTrophies", alwaysShowHiddenTrophiesDetail, trophyLocked, gradePlatinum, gradeGold, gradeSilver, gradeBronze
        case phonePairingTitle, phonePairingText, phoneAllow, phoneDeny, phoneConnected, phones, phonesNone, phoneRemove, phoneOpenLauncher, phoneServerFailed, phoneConnecting, phoneNone, phoneConnectedDetail, phoneOnline, phonesConnectedCount, phonePlayer, phoneWaiting
        case madeBy, builtOn
        case updateChoiceText, updateAndPlay, updateAndPlayDetail, playNow, playNowDetail
        case discordPresence, discordPresenceDetail, gameMusic, gameMusicDetail, checkUpdates, checkUpdatesDetail, screenshots, screenshotsNone, backUpSaves, backUpSavesDetail, lastBackup, restoreSaves, restoreSavesDetail, savesBackedUp, savesRestored, backupFailed, closeGameFirst, launcherUpdateAvailable, launcherUpToDate, updateCheckFailed, checkForUpdatesNow, checkForUpdatesDetail, checkingUpdates, lastChecked, updateTo, updateDetail, updateDownloading, whatsNew, updateFailed, updateCloseGame, updateNotWritable
        case advanced, advancedDetail, advancedTitle, makeReport, makeReportDetail, screenshotsFolder, showScreenshots, screenshotsHint, sectionSticks, leftDeadzone, rightDeadzone, deadzoneDetail, sectionMouse, mouseSensitivity, mouseSensitivityDetail, mouseVertical, mouseVerticalDetail, mouseCurve, mouseCurveDetail, mouseMinimum, mouseMinimumDetail, mouseMaxSpeed, mouseMaxSpeedDetail, mouseSmoothing, mouseSmoothingDetail, mouseDecay, mouseDecayDetail, sectionKeyboard, stickModifierScale, stickModifierScaleDetail, keyboardRamp, keyboardRampDetail, triggerRamp, triggerRampDetail, sectionGraphics, shaderCache, shaderCacheDetail, sectionShare, exportSettings, exportSettingsDetail, importSettings, importSettingsDetail, resetAdvanced, reportSaved, reportFailed, settingsExported, settingsImported, settingsImportedOther, settingsFileFailed, stickModifier, diagnosisMissingModule, diagnosisUnsupported, diagnosisGpuLost, diagnosisOutOfMemory, diagnosisEngineError, diagnosisCrashed, trophyEarned
        case updateChannel, channelStable, channelNightly, channelNightlyShort, updateChannelStableDetail, updateChannelNightlyDetail, updateChannelStays
        case profilePicture, profilePictureDetail, profilePictureNone, profilePictureRemove, profilePictureUpload, profilePictureUploadDetail, profilePictureFromTogether, profilePictureFromTogetherDetail
        case profilePictureUploaded, profilePictureUploadFailed = "privatePictureFailed", profilePictureSaved, profilePictureUnreadable, profilePictureTooSmall, profilePictureDownloadFailed, profilePictureRemoved
        case cropTitle, cropZoom, cropHint, cropSave
        case accentBlue, accentMint, accentCoral, accentViolet, accentGold, accentWhite, accentIce
    }
}
