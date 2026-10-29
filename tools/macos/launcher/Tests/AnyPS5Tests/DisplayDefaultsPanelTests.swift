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
        XCTAssertEqual(rows.map(\.id), ["displayDefaultsIntro", "defaultDisplay", "defaultSize", "defaultVsync"])
        try XCTUnwrap(choice(try row(rows, "defaultDisplay"))).set(1)
        XCTAssertEqual(model.preferences.displayDefaults?.fullscreen, true)
        XCTAssertFalse(model.displayDefaultRows().contains { $0.id == "defaultSize" }, "no window size in full screen")
        try XCTUnwrap(choice(try row(model.displayDefaultRows(), "defaultDisplay"))).set(0)
        XCTAssertNil(model.preferences.displayDefaults, "back to the built-in values: nothing kept")
    }

    func testAGameShowsTheDefaultAndFollowsIt() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        model.updateDisplayDefaults { $0.fullscreen = true }
        let display = try XCTUnwrap(choice(try row(model.gameDisplayRows(game, model.settings(for: game)), "display")))
        XCTAssertEqual(display.options, ["Default (Full Screen)", "Window", "Full Screen"])
        XCTAssertEqual(display.selected, 0)
        XCTAssertTrue(model.launchSettings(for: game).fullscreen, "the game starts full screen")
        XCTAssertFalse(model.gameDisplayRows(game, model.settings(for: game)).contains { $0.id == "useDisplayDefaults" }, "nothing of its own to put back")
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
}
