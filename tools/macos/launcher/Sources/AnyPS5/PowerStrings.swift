import Foundation

/// The texts of Settings → Battery & Heat, the quick menu's power line and the heat note over a
/// game, from the language files (l10n); kept apart from `T` like `TF`.
enum TPow {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case title = "powerTitle", intro = "powerIntro", pluggedIn = "powerPluggedIn", onBattery = "powerOnBattery", onBatteryPercent = "powerOnBatteryPercent", noBattery = "powerNoBattery", timeLeft = "powerTimeLeft", estimating = "powerEstimating", hoursMinutes = "powerHoursMinutes", minutes = "powerMinutes"
        case thermalNominal = "powerThermalNominal", thermalFair = "powerThermalFair", thermalSerious = "powerThermalSerious", thermalCritical = "powerThermalCritical", lowPowerMode = "powerLowPowerMode"
        case profileNone = "powerProfileNone", profileBattery = "powerProfileBattery", profileHot = "powerProfileHot", profileUndone = "powerProfileUndone", capSummary = "powerCapSummary", inForce = "powerInForce", inForceNothing = "powerInForceNothing"
        case sectionBattery = "powerSectionBattery", sectionHot = "powerSectionHot", batteryProfile = "powerBatteryProfile", batteryProfileDetail = "powerBatteryProfileDetail", hotProfile = "powerHotProfile", hotProfileDetail = "powerHotProfileDetail"
        case frameCap = "powerFrameCap", frameCapDetail = "powerFrameCapDetail", fps = "powerFps", lowerResolution = "powerLowerResolution", lowerResolutionDetail = "powerLowerResolutionDetail", pauseFrameGeneration = "powerPauseFrameGeneration", pauseFrameGenerationDetail = "powerPauseFrameGenerationDetail"
        case dimEffects = "powerDimEffects", dimEffectsDetail = "powerDimEffectsDetail", undo = "powerUndo", undoDetail = "powerUndoDetail", undone = "powerUndone"
        case hotTitle = "powerHotTitle", hotLowered = "powerHotLowered", hotEased = "powerHotEased", hotDetail = "powerHotDetail", quickUndoHot = "powerQuickUndoHot", quickUndoBattery = "powerQuickUndoBattery", quickUndoDetail = "powerQuickUndoDetail"
    }
}
