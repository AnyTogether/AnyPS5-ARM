import Foundation

/// The texts of the engine picker (Settings → Engine and a game's engine), from the language files (l10n);
/// kept apart from `T` like `TS`. `TE.text(.key)` reads the launcher's current language.
enum TE {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case engineUpstreamNotOnMac, engineUpstreamNotOnMacDetail
        case engineTitle, engineDefault, engineDefaultDetail, engineBuiltIn, engineCustomName, engineFollow
        case engineGameDetail, engineUnlockedWith, engineNotUnlocked, engineSwitch
        case engineDownloadedSection, engineAvailableSection, engineCustomSection
        case engineInUse, engineDeleteHint, engineDeleted = "engineVersionDeleted", engineInUseNoDelete, engineDeleteUnused, engineDeleteUnusedDetail, engineNothingUnused
        case engineDownloadHint, engineDownloading = "engineDownloadingPercent", engineReady, engineDownloadFailed, enginePrerelease, engineBuilt
        case engineSigned, engineUnsignedOlder, engineUnsignedOlderDetail, engineUnsignedReady, engineUnsignedRefused, engineUnsignedRefusedDetail
        case engineRefresh, engineChecked, engineChecking, engineOffline = "engineOfflineList", engineNeverChecked, engineNoneYet, engineCheckFailed
        case engineFolder, engineFolderNone, engineFolderReset, engineFolderInvalid, engineFolderPick, engineFolderUsed
        case engineHint
        case engineNeedsNewerMac, engineGameNeedsNewerMac
        case engineGitUpdate, engineGitUpdateDetail, engineGitNoBuild, engineGitRunning, engineGitStepChecking, engineGitStepPulling, engineGitStepSubmodules, engineGitStepConfiguring, engineGitStepBuilding, engineGitStepAssembling
        case engineGitDone, engineGitBuiltAt, engineGitFailed, engineGitStopped, engineGitNotGit, engineGitDirty, engineGitNoBuildReason, engineGitPullFailed, engineGitSubmodulesFailed, engineGitBuildFailed
        case engineGitToolkitFailed, engineGitNeeds, engineGitNeedsReason, engineGitCopy, engineGitCopied, engineGitStop, engineGitRelinkAll, engineGitRelinkAllDetail, engineGitRelinking, engineGitWaitUnlock, engineGitBeforePlay, engineGitBeforePlayDetail, engineGitBeforePlayStart, engineGitChecking, engineGitPlayAnyway = "engineGitPlayAnywayMac"
        case engineGitSetUpDetail = "engineGitSetUpDetailMac", engineGitConfigureFailed, engineGitGuideMac
    }
}
