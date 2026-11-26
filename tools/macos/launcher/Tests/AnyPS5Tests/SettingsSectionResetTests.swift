@testable import AnyPS5
import AnyPS5Core
import XCTest

/// Settings › Restore All: the last row of each section with preferences of its own puts that
/// section back to its defaults and leaves every other section, the games folders, the language,
/// the profile name and AnyTogether as they are. AnyPS5 Desktop's settings_section_reset_test.dart.
@MainActor
final class SettingsSectionResetTests: XCTestCase {
    func category(_ model: AppModel, _ id: String) throws -> PanelCategory {
        model.open(.settings)
        return try XCTUnwrap(model.panelCategories().first { $0.id == id }, "no category \(id)")
    }

    /// Restore All chosen in `id`, as the pad or the mouse chooses it.
    func restore(_ model: AppModel, _ id: String) throws {
        model.open(.settings)
        let categories = model.panelCategories()
        let index = try XCTUnwrap(categories.firstIndex { $0.id == id }, "no category \(id)")
        model.panelCategory = index
        let row = try XCTUnwrap(categories[index].rows.last)
        XCTAssertEqual(row.id, "reset-" + id)
        guard case .action(_, let run) = row.kind else { return XCTFail("Restore All is an action") }
        run()
    }

    func focused(_ model: AppModel) -> String? {
        let rows = model.panelCategories()[model.panelCategory].rows
        return rows.indices.contains(model.panelRow) ? rows[model.panelRow].id : nil
    }

    func testEachSectionWithPreferencesOfItsOwnEndsInRestoreAll() throws {
        let model = try LauncherFixture.model { $0.retroLibrary = true }
        model.open(.settings)
        let categories = model.panelCategories()
        XCTAssertEqual(Set(categories.map(\.id)).intersection(AppModel.settingsSectionsWithReset), AppModel.settingsSectionsWithReset, "every one of them is in Settings")
        for category in categories {
            let resets = category.rows.filter { $0.id.hasPrefix("reset-") }
            if AppModel.settingsSectionsWithReset.contains(category.id) {
                let last = try XCTUnwrap(category.rows.last)
                XCTAssertEqual(last.id, "reset-" + category.id)
                XCTAssertEqual(last.title, "Restore All")
                XCTAssertEqual(last.detail, "Put every setting in this section back to its default.")
                guard case .action(let destructive, _) = last.kind else { return XCTFail("\(category.id): an action") }
                XCTAssertTrue(destructive, "\(category.id): as on Windows and Linux")
            } else {
                XCTAssertEqual(resets.map(\.id), [], category.id)
            }
        }
        // Shortcuts and Game Presets keep their own reset rows.
        XCTAssertTrue(try category(model, "shortcuts").rows.contains { $0.id == "shortcutsReset" })
    }

    func testBehaviourComesBackToItsDefaultsAndLeavesTheRestAlone() throws {
        let model = try LauncherFixture.model {
            $0.sounds = false
            $0.soundVolume = 40
            $0.musicVolume = 20
            $0.launcherVolume = 50
            $0.controllerVibration = false
            $0.hideWhilePlaying = true
            $0.alwaysShowHiddenTrophies = true
            $0.discordPresence = false
            $0.discordJoin = false
            $0.nowPlayingCard = false
            $0.nowPlayingShare = true
            $0.clips = true
            $0.clipLength = 60
            $0.pauseOnMenu = false
            // Other sections' settings, and what Restore All never touches.
            $0.friendsJoin = false
            $0.saveSync = true
            $0.confirmCircle = true
            $0.screenshotsFolder = "/somewhere/else"
        }
        let folders = model.preferences.libraryFolders
        let name = model.preferences.profileName

        try restore(model, "behaviour")
        let preferences = model.preferences
        XCTAssertTrue(preferences.sounds)
        XCTAssertNil(preferences.soundVolume)
        XCTAssertNil(preferences.musicVolume)
        XCTAssertNil(preferences.launcherVolume)
        XCTAssertNil(preferences.controllerVibration)
        XCTAssertFalse(preferences.hideWhilePlaying)
        XCTAssertNil(preferences.alwaysShowHiddenTrophies)
        XCTAssertNil(preferences.discordPresence)
        XCTAssertNil(preferences.discordJoin)
        XCTAssertNil(preferences.nowPlayingCard)
        XCTAssertNil(preferences.nowPlayingShare)
        XCTAssertNil(preferences.clips)
        XCTAssertNil(preferences.clipLength)
        XCTAssertNil(preferences.pauseOnMenu)

        XCTAssertEqual(preferences.language, .english)
        XCTAssertEqual(preferences.libraryFolders, folders)
        XCTAssertEqual(preferences.profileName, name)
        XCTAssertEqual(preferences.saveSync, true, "Save Sync is left as it is")
        XCTAssertEqual(preferences.friendsJoin, false, "Settings › AnyTogether owns it")
        XCTAssertEqual(preferences.confirmCircle, true)
        XCTAssertEqual(preferences.screenshotsFolder, "/somewhere/else")
        XCTAssertEqual(model.toast?.text, TH.text(.settingsResetSectionDone))
        XCTAssertEqual(focused(model), "reset-behaviour")
    }

    func testControllersAndDefaultDisplayRestoreOnlyThemselves() throws {
        let model = try LauncherFixture.model {
            $0.controllerLight = "red"
            $0.confirmCircle = true
            $0.stickDeadzone = 10
            $0.assistPlayerOne = "controllers"
            $0.displayDefaults = DisplayDefaults(fullscreen: false, windowSize: 50, vsync: false)
            $0.sounds = false
        }

        try restore(model, "controllers")
        XCTAssertNil(model.preferences.controllerLight)
        XCTAssertNil(model.preferences.confirmCircle)
        XCTAssertNil(model.preferences.stickDeadzone)
        XCTAssertNil(model.preferences.assistPlayerOne)
        XCTAssertFalse(Input.shared.circleConfirms, "at once")
        XCTAssertEqual(model.preferences.displayDefaults?.fullscreen, false, "Default Display has its own row")
        XCTAssertFalse(model.preferences.sounds)
        XCTAssertEqual(focused(model), "reset-controllers")

        try restore(model, "display")
        XCTAssertNil(model.preferences.displayDefaults)
        XCTAssertEqual(model.displayDefaults, DisplayDefaults())
        XCTAssertEqual(focused(model), "reset-display")
    }

    func testAppearanceGoesBackToCosmicAndGlasssRowsGoWithIt() throws {
        let model = try LauncherFixture.model {
            $0.theme = .glass
            $0.accent = .coral
            $0.reducedMotion = true
            $0.gameArtwork = false
            $0.glassTransparency = 40
            $0.glassArtwork = true
        }
        XCTAssertTrue(try category(model, "appearance").rows.contains { $0.id == "transparency" })

        try restore(model, "appearance")
        XCTAssertEqual(model.preferences.theme, .cosmic)
        XCTAssertNil(model.preferences.accent)
        XCTAssertFalse(model.preferences.reducedMotion)
        XCTAssertTrue(model.preferences.gameArtwork)
        XCTAssertNil(model.preferences.glassTransparency)
        XCTAssertNil(model.preferences.glassArtwork)
        XCTAssertNil(model.preferences.fullScreen)
        XCTAssertFalse(try category(model, "appearance").rows.contains { $0.id == "transparency" })
        XCTAssertEqual(focused(model), "reset-appearance")
    }

    func testBatteryAndHeatHandTheBuiltInProfilesToThePolicyAtOnce() throws {
        let model = try LauncherFixture.model()
        model.setPowerProfiles { $0.hot.on = false }
        XCTAssertFalse(model.power.profiles.hot.on)

        try restore(model, "power")
        XCTAssertNil(model.preferences.powerProfiles)
        XCTAssertEqual(model.power.profiles, PowerProfiles())
    }

    func testAdvancedPutsThePhoneServerAndTheScreenshotsFolderBack() throws {
        let model = try LauncherFixture.model {
            $0.phoneServer = false
            $0.browserPlay = false
            $0.browserPlayAlways = true
            $0.screenshotsFolder = "/somewhere/else"
            $0.stickDeadzone = 10
        }

        try restore(model, "advanced")
        XCTAssertNil(model.preferences.phoneServer)
        XCTAssertTrue(model.phoneServerOn)
        XCTAssertNil(model.preferences.browserPlay)
        XCTAssertNil(model.preferences.browserPlayAlways)
        XCTAssertNil(model.preferences.screenshotsFolder)
        XCTAssertEqual(model.preferences.stickDeadzone, 10)
    }

    func testEmulatorsRestoreTheirSwitchesAndKeepTheEmulatorsChosen() throws {
        let model = try LauncherFixture.model {
            $0.retroLibrary = true
            $0.showRetroFolders = true
            $0.retroEmulators = ["ps1": "/Applications/DuckStation.app"]
        }

        try restore(model, "emulators")
        XCTAssertNil(model.preferences.showRetroFolders)
        XCTAssertNil(model.preferences.retroHostPs1)
        XCTAssertNil(model.preferences.retroHostPs2)
        XCTAssertEqual(model.preferences.retroEmulators, ["ps1": "/Applications/DuckStation.app"])
        XCTAssertEqual(model.preferences.retroLibrary, true, "Settings › Game Library owns it")
    }

    func testSteamRestoresItsOwnThreeSettings() throws {
        let model = try LauncherFixture.model {
            $0.steamUser = "/steam|1234"
            $0.steamGames = true
            $0.steamFullscreen = false
        }

        model.resetSettingsSection("steam")
        XCTAssertNil(model.preferences.steamUser)
        XCTAssertNil(model.preferences.steamGames)
        XCTAssertNil(model.preferences.steamFullscreen)
    }
}
