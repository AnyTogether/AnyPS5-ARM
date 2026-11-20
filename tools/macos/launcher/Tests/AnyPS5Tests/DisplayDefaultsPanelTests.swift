@testable import AnyPS5
import AnyPS5Core
import XCTest

/// Settings › Default Display and the Default options in a game's settings.
@MainActor
final class DisplayDefaultsPanelTests: XCTestCase {
    func row(_ rows: [PanelRow], _ id: String) throws -> PanelRow { try XCTUnwrap(rows.first { $0.id == id }, "no row \(id)") }

    func choice(_ row: PanelRow) -> (options: [String], selected: Int, set: (Int) -> Void)? {
        if case .choice(let options, let selected, let set) = row.kind { return (options, selected, set) }
        return nil
    }

    func testSettingsHasDefaultDisplayBeforeGamePresets() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        let ids = model.panelCategories().map(\.id)
        let display = try XCTUnwrap(ids.firstIndex(of: "display"))
        XCTAssertEqual(ids[display + 1], "presets")
        let rows = model.displayDefaultRows()
        XCTAssertEqual(rows.map(\.id), ["displayDefaultsIntro", "defaultDisplay", "defaultStartAnimation", "defaultVsync"], "Full Screen by default: no window size")
        XCTAssertEqual(try XCTUnwrap(choice(try row(rows, "defaultDisplay"))).selected, 1)
        try XCTUnwrap(choice(try row(rows, "defaultDisplay"))).set(0)
        XCTAssertEqual(model.preferences.displayDefaults?.fullscreen, false)
        XCTAssertEqual(model.displayDefaultRows().map(\.id), ["displayDefaultsIntro", "defaultDisplay", "defaultStartAnimation", "defaultSize", "defaultVsync"])
        try XCTUnwrap(choice(try row(model.displayDefaultRows(), "defaultDisplay"))).set(1)
        XCTAssertNil(model.preferences.displayDefaults, "back to the built-in values: nothing kept")
    }

    func testAGameShowsTheDefaultAndFollowsIt() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        XCTAssertNil(model.preferences.displayDefaults, "the built-in defaults")
        let display = try XCTUnwrap(choice(try row(model.gameDisplayRows(game, model.settings(for: game)), "display")))
        XCTAssertEqual(display.options, ["Default (Full Screen)", "Window", "Full Screen"])
        XCTAssertEqual(display.selected, 0)
        XCTAssertTrue(model.launchSettings(for: game).fullscreen, "the game starts full screen")
        XCTAssertFalse(model.gameDisplayRows(game, model.settings(for: game)).contains { $0.id == "useDisplayDefaults" }, "nothing of its own to put back")
    }

    /// Slick Daddy's report of 7 November 2026 (a per-game "start full screen, borderless"): the
    /// row was there as Display, so it says what it is and that full screen is borderless.
    func testAGamesRowSaysWindowOrFullScreenAndThatFullScreenIsBorderless() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        let display = try row(model.gameDisplayRows(game, model.settings(for: game)), "display")
        XCTAssertEqual(display.title, "Window or full screen")
        XCTAssertEqual(display.detail, T.text(.displayBorderless))
        XCTAssertTrue(display.detail?.contains("borderless") == true)
    }

    func testAGamesOwnChoiceWinsAndUseDefaultDisplayPutsItBack() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        model.updateDisplayDefaults { $0.fullscreen = true }
        try XCTUnwrap(choice(try row(model.gameDisplayRows(game, model.settings(for: game)), "display"))).set(1)
        XCTAssertFalse(model.launchSettings(for: game).fullscreen, "Window chosen for the game")
        let rows = model.gameDisplayRows(game, model.settings(for: game))
        XCTAssertNotNil(rows.first { $0.id == "size" }, "windowed: its size")
        guard case .action(_, let run) = try row(rows, "useDisplayDefaults").kind else { return XCTFail("not an action") }
        run()
        XCTAssertTrue(model.settings(for: game).followsDisplayDefaults)
        XCTAssertTrue(model.launchSettings(for: game).fullscreen)
    }

    func testTheWindowSizeReadsDefaultUntilTheGamePicksOne() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        model.updateDisplayDefaults { $0.fullscreen = false }
        guard case .stepper(let value, _, _, let format, let set) = try row(model.gameDisplayRows(game, model.settings(for: game)), "size").kind else { return XCTFail("not a stepper") }
        XCTAssertEqual(format(value), "Default (75%)")
        set(80)
        guard case .stepper(let now, _, _, let formatNow, _) = try row(model.gameDisplayRows(game, model.settings(for: game)), "size").kind else { return XCTFail("not a stepper") }
        XCTAssertEqual(formatNow(now), "80%")
    }

    func testVerticalSyncHasADefaultToo() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        model.updateDisplayDefaults { $0.vsync = false }
        let vsync = try XCTUnwrap(choice(try row(model.gameDisplayRows(game, model.settings(for: game)), "vsync")))
        XCTAssertEqual(vsync.options, ["Default (Off)", "On", "Off"])
        XCTAssertEqual(model.launchSettings(for: game).environment(launcherLanguage: 1)["ANYPS5_PRESENT_MODE"], "immediate")
        vsync.set(1)
        XCTAssertEqual(model.launchSettings(for: game).environment(launcherLanguage: 1)["ANYPS5_PRESENT_MODE"], "fifo")
    }

    func testAChoiceMadeBeforeTheUpdateIsKept() throws {
        let older = #"{"fullscreen":true,"windowSize":75,"vsync":true,"overlay":"off"}"#
        let saved = try JSONDecoder().decode(GameSettings.self, from: Data(older.utf8))
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        model.update(game) { $0 = saved }
        model.updateDisplayDefaults { $0.fullscreen = false; $0.vsync = false }
        let started = model.launchSettings(for: game)
        XCTAssertTrue(started.fullscreen, "full screen was chosen")
        XCTAssertFalse(started.vsync, "vertical sync on was the old default: it follows")
    }

    /// A preferences file as an older launcher wrote it: no preferencesVersion, and Default
    /// Display only when changed.
    func olderFile(_ displayDefaults: [String: Any]?) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Preferences())) as? [String: Any])
        json["preferencesVersion"] = nil
        json["displayDefaults"] = displayDefaults
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Lenny4250gh's AnyTogether/AnyPS5-Desktop#179, on the Mac: games start in Full Screen unless
    /// Window was chosen, in Default Display or for the game.
    func testAnOlderLaunchersPreferencesFollowFullScreenUnlessWindowWasChosen() throws {
        let untouched = try XCTUnwrap(Preferences.read(try olderFile(nil)))
        XCTAssertNil(untouched.displayDefaults, "never changed: the built-in Full Screen")
        XCTAssertEqual(untouched.preferencesVersion, Preferences.version)
        let tearing = try XCTUnwrap(Preferences.read(try olderFile(["fullscreen": false, "windowSize": 75, "vsync": false, "startAnimation": false])))
        XCTAssertEqual(tearing.displayDefaults, DisplayDefaults(fullscreen: true, windowSize: 75, vsync: false, startAnimation: false),
                       "Window at 75 % was the old default: Full Screen, vsync and the start animation stay off")
        let window = try XCTUnwrap(Preferences.read(try olderFile(["fullscreen": false, "windowSize": 60, "vsync": true])))
        XCTAssertEqual(window.displayDefaults, DisplayDefaults(fullscreen: false, windowSize: 60), "Window at 60 % was chosen and stays")

        let model = try LauncherFixture.model { $0.displayDefaults = untouched.displayDefaults; $0.preferencesVersion = untouched.preferencesVersion }
        let game = try XCTUnwrap(model.selectedGame)
        let other = try XCTUnwrap(model.games.first { $0.id != game.id })
        XCTAssertEqual(model.launchSettings(for: game).environment(launcherLanguage: 1)["ANYPS5_FULLSCREEN"], "1")
        XCTAssertTrue(model.launchSettings(for: game).fadesCover, "the cover fades over the game")
        model.update(game) { $0.ownFullscreen = false }
        XCTAssertEqual(model.launchSettings(for: game).environment(launcherLanguage: 1)["ANYPS5_FULLSCREEN"], "0", "the game's own Window wins")
        XCTAssertTrue(model.launchSettings(for: other).fullscreen)
    }

    func testTheFirstSaveKeepsWhatTheOlderFileMeant() throws {
        let untouched = try XCTUnwrap(Preferences.read(try olderFile(nil)))
        let saved = try XCTUnwrap(untouched.encoded())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(json["preferencesVersion"] as? Int, Preferences.version)
        XCTAssertNil(json["displayDefaults"], "no Default Display written for the built-in one")
        let again = try XCTUnwrap(Preferences.read(saved))
        XCTAssertNil(again.displayDefaults, "still Full Screen")
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(again.encoded())) as? [String: Any])["displayDefaults"])

        var chosen = Preferences()
        chosen.displayDefaults = DisplayDefaults.formerBuiltIn
        let read = try XCTUnwrap(Preferences.read(try XCTUnwrap(chosen.encoded())))
        XCTAssertEqual(read.displayDefaults, DisplayDefaults.formerBuiltIn, "Window at 75 % chosen in this launcher is read as written")
        XCTAssertEqual(Preferences.firstStart(preferred: []).preferencesVersion, Preferences.version)
    }
}
