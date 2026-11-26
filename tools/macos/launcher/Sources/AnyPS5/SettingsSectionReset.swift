import AnyPS5Core
import Foundation

// Settings › Restore All: the last row of each section with preferences of its own puts that
// section back to its defaults, at once where they act on something running, as AnyPS5 Desktop's
// resetSettingsSection does. Games folders, emulator programs, language, profile name, Save Sync,
// sign-in and installed engines are left alone; Game Presets and Shortcuts have their own reset rows.
// The Mac's sections hold the same settings as Windows and Linux in other places: its Advanced is
// their Phones with Captures' screenshots folder, and its Behaviour has the clips of their Captures.

extension AppModel {
    /// The sections Restore All puts back. The others show accounts, engines and status (About,
    /// AnyTogether, Profiles, …) or have a reset of their own (Game Presets, Shortcuts).
    static let settingsSectionsWithReset: Set<String> = [
        "appearance", "library", "emulators", "behaviour", "power", "controllers", "display", "advanced", "steam",
    ]

    func settingsSectionResetRow(_ section: String) -> PanelRow {
        PanelRow(id: "reset-" + section, title: TH.text(.settingsResetSection), detail: TH.text(.settingsResetSectionDetail), symbol: "arrow.counterclockwise",
                 kind: .action(destructive: true) { [weak self] in self?.resetSettingsSection(section) })
    }

    /// `section`'s preferences back to their defaults; nothing for a section without a Restore All.
    func resetSettingsSection(_ section: String) {
        guard Self.settingsSectionsWithReset.contains(section) else { return }
        var restored = preferences
        switch section {
        case "appearance":
            restored.theme = .cosmic
            restored.accent = nil
            restored.customTheme = nil
            restored.backdrop = .theme
            restored.backdropFile = nil
            restored.menuMusicFile = nil
            restored.gameArtwork = true
            restored.reduceTransparency = nil
            restored.glassTransparency = nil
            restored.glassArtwork = nil
            restored.reducedMotion = false
            restored.fullScreen = nil
            preferences = restored
            // Full screen, as the launcher starts the first time.
            if mainWindow != nil, !isFullScreen { toggleFullScreen() }
        case "library":
            // The games folders stay: restoring those would empty the library.
            restored.prepareNewGames = nil
            preferences = restored
            // As its switch does it; Settings › Emulators keeps its own settings.
            setRetroLibrary(false)
        case "emulators":
            // The emulator programs chosen and the host's downloads stay.
            setShowRetroFolders(false)
            setRetroHostPs1(false)
            setRetroHostPs2(false)
        case "behaviour":
            let checked = preferences.checkUpdates ?? true
            restored.launcherVolume = nil
            restored.sounds = true
            restored.soundVolume = nil
            restored.musicVolume = nil
            restored.controllerVibration = nil
            restored.hideWhilePlaying = false
            restored.alwaysShowHiddenTrophies = nil
            restored.discordPresence = nil
            restored.discordJoin = nil
            restored.nowPlayingCard = nil
            restored.nowPlayingShare = nil
            restored.clipLength = nil
            restored.pauseOnMenu = nil
            restored.checkUpdates = nil
            preferences = restored
            clipsChanged(false)
            preferences.clips = nil
            updateDiscord()
            followNowPlaying()
            if !checked { checkForUpdate() }
        case "power":
            restored.powerProfiles = nil
            preferences = restored
        case "controllers":
            restored.controllerLight = nil
            restored.confirmCircle = nil
            restored.stickDeadzone = nil
            restored.assistPlayerOne = nil
            preferences = restored
        case "display":
            restored.displayDefaults = nil
            preferences = restored
        case "advanced":
            restored.screenshotsFolder = nil
            restored.browserPlay = nil
            restored.browserPlayAlways = nil
            preferences = restored
            setPhoneServer(true)
            if persists { updateBrowserPlay() }
        case "steam":
            restoreSteamDefaults()
        default:
            return
        }
        // Rows that went with the old values (Glass's, a folder's): the focus stays on Restore All.
        let categories = panelCategories()
        if categories.indices.contains(panelCategory), let at = categories[panelCategory].rows.firstIndex(where: { $0.id == "reset-" + section }) {
            panelRow = at
        }
        show(TH.text(.settingsResetSectionDone), symbol: "arrow.counterclockwise")
    }
}
