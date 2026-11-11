@testable import AnyPS5
import AnyPS5Core
import XCTest

/// A game's Advanced page: Custom Relinker Options under Rebuild Options and Launch Options under
/// Launch, saved as they are typed only while they pass their check, with the reason under the
/// row when they do not. As on Windows and Linux.
@MainActor
final class CustomOptionsPanelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        T.language = .english
    }

    func advanced(_ model: AppModel) throws -> [PanelRow] {
        model.open(.advanced)
        return try XCTUnwrap(model.panelCategories().first { $0.id == "advanced" }, "no advanced page").rows
    }

    func row(_ rows: [PanelRow], _ id: String) throws -> PanelRow { try XCTUnwrap(rows.first { $0.id == id }, "no row \(id)") }

    func type(_ row: PanelRow, _ text: String) {
        guard case .text(_, let set) = row.kind else { return XCTFail("\(row.id) is not a text field") }
        set(text)
    }

    func value(_ row: PanelRow) -> String? {
        guard case .text(let value, _) = row.kind else { return nil }
        return value
    }

    func testTheFieldsSitUnderTheirSections() throws {
        let model = try LauncherFixture.model()
        let ids = try advanced(model).map(\.id)
        let relinker = try XCTUnwrap(ids.firstIndex(of: "relinkerSection"))
        let custom = try XCTUnwrap(ids.firstIndex(of: "relinkerCustomOptions"))
        let launch = try XCTUnwrap(ids.firstIndex(of: "launchSection"))
        let options = try XCTUnwrap(ids.firstIndex(of: "launchOptions"))
        let share = try XCTUnwrap(ids.firstIndex(of: "shareSection"))
        XCTAssertTrue(relinker < custom && custom < launch && launch < options && options < share, "\(ids)")
        let rows = try advanced(model)
        XCTAssertEqual(try row(rows, "relinkerCustomOptions").detail, T.text(.relinkerCustomOptionsDetail) + "\n" + T.text(.customOptionsWarning))
        XCTAssertEqual(try row(rows, "launchOptions").detail, T.text(.launchOptionsDetail) + "\n" + T.text(.customOptionsWarning))
    }

    func testAValidTextIsSavedAndAnInvalidOneIsNotAndSaysWhy() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        type(try row(try advanced(model), "relinkerCustomOptions"), "--lazy-binding")
        XCTAssertEqual(model.settings(for: game).customRelinkerOptions, "--lazy-binding")

        type(try row(try advanced(model), "relinkerCustomOptions"), "--lazy-binding --macos")
        XCTAssertEqual(model.settings(for: game).customRelinkerOptions, "--lazy-binding", "nothing saved")
        let refused = try row(try advanced(model), "relinkerCustomOptions")
        XCTAssertEqual(value(refused), "--lazy-binding --macos", "what was typed stays in the field")
        XCTAssertEqual(refused.detail, T.format(.optionsNotSaved, T.format(.relinkerOptionLauncher, "--macos")))
        XCTAssertEqual(refused.detail, "--macos is left to the launcher. Not saved.")

        type(refused, "")
        XCTAssertNil(model.settings(for: game).customRelinkerOptions, "cleared")
        XCTAssertEqual(try row(try advanced(model), "relinkerCustomOptions").detail, T.text(.relinkerCustomOptionsDetail) + "\n" + T.text(.customOptionsWarning))

        type(try row(try advanced(model), "launchOptions"), "APS5_REPORT=0 --aps5-report=off")
        XCTAssertEqual(model.settings(for: game).launchOptions, "APS5_REPORT=0 --aps5-report=off")
        type(try row(try advanced(model), "launchOptions"), "A='open")
        XCTAssertEqual(model.settings(for: game).launchOptions, "APS5_REPORT=0 --aps5-report=off")
        XCTAssertEqual(try row(try advanced(model), "launchOptions").detail, "A quote is not closed. Not saved.")
    }

    func testResetTakesThemOff() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.selectedGame)
        type(try row(try advanced(model), "relinkerCustomOptions"), "--registry")
        type(try row(try advanced(model), "launchOptions"), "--x")
        type(try row(try advanced(model), "launchOptions"), "'")
        guard case .action(_, let reset) = try row(try advanced(model), "resetAdvanced").kind else { return XCTFail("not an action") }
        reset()
        XCTAssertNil(model.settings(for: game).customRelinkerOptions)
        XCTAssertNil(model.settings(for: game).launchOptions)
        XCTAssertEqual(value(try row(try advanced(model), "launchOptions")), "", "the unsaved draft goes too")
    }

    func testEveryProblemHasItsText() {
        let words: [OptionsProblem] = [.launcherOption("--a"), .breaksGame("--a"), .hasSwitch("--a"), .unknown("--a"), .needsValue("--a"), .positional("--a")]
        for problem in words { XCTAssertTrue(AppModel.optionsProblemText(problem).contains("--a"), "\(problem)") }
        XCTAssertEqual(AppModel.optionsProblemText(.openQuote), T.text(.optionsQuoteOpen))
    }

    func testTheLogSaysWhatTheGameStartedWith() throws {
        let options = try LaunchOptions.parse("ANYPS5_FULLSCREEN=0 MINE=1 --x").get()
        XCTAssertEqual(AppModel.launchNotes("ANYPS5_FULLSCREEN=0 MINE=1 --x", options, ["ANYPS5_FULLSCREEN": "1"]),
                       ["launch options: ANYPS5_FULLSCREEN=0 MINE=1 --x", "launch options: the launcher's own value is used for ANYPS5_FULLSCREEN"])
        XCTAssertEqual(AppModel.launchNotes("MINE=1", try LaunchOptions.parse("MINE=1").get(), [:]), ["launch options: MINE=1"])
        XCTAssertEqual(AppModel.launchNotes(nil, LaunchOptions(), [:]), [])
    }
}
