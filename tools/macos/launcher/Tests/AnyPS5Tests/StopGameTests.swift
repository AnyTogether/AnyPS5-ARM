@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import XCTest

/// Close Game and Stop Game, as on Windows and Linux: the game is asked to close so it can save,
/// and ended only if it is still there after the grace.
@MainActor
final class StopGameTests: XCTestCase {
    private var asked = 0
    private var ended = 0
    private var answersAsk = true

    /// A launcher with a "running" game whose close and end only count (the test's own process
    /// stands in for it, and is left alone).
    private func model() throws -> (AppModel, Game) {
        let model = try LauncherFixture.model()
        model.gameStopGrace = .milliseconds(50)
        model.askGameToClose = { [unowned self] _ in asked += 1; return answersAsk }
        model.endGame = { [unowned self] _ in ended += 1 }
        let game = try XCTUnwrap(model.games.first)
        model.selected = 0
        model.previewRunning(game, app: .current)
        return (model, game)
    }

    func testClosingAGameAsksItFirstAndEndsItAfterTheGraceOnlyIfStillThere() async throws {
        let (model, game) = try model()
        // The quick menu's Close, then the question's answer: a real path through the menus.
        model.overlay = .quickMenu
        model.menuIndex = model.quickMenuRows().count - 1
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.overlay, .closeGame)
        XCTAssertTrue(model.handle(.right))
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertEqual(asked, 1, "the game was asked to close")
        XCTAssertEqual(ended, 0, "and is not ended at once")
        XCTAssertEqual(model.state(of: game), .stopping)
        XCTAssertTrue(model.stopping)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(ended, 1, "a game that does not answer is stopped all the same")
    }

    func testAGameThatClosesInTimeIsNotEnded() async throws {
        let (model, game) = try model()
        model.stopRunningGame()
        XCTAssertEqual(model.state(of: game), .stopping)
        // What the game ending does: nothing is left to stop.
        model.gameStopped()
        XCTAssertFalse(model.stopping)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(ended, 0, "ended only when still running after the grace")
    }

    func testAskingTwiceAsksOnce() throws {
        let (model, _) = try model()
        model.stopRunningGame()
        model.stopRunningGame()
        XCTAssertEqual(asked, 1)
    }

    func testTheGameSettingsHaveStopGameWhileItPlays() throws {
        let (model, game) = try model()
        XCTAssertEqual(model.state(of: game), .running)
        model.overlay = .gameSettings
        let row = try XCTUnwrap(model.panelCategories().flatMap(\.rows).first { $0.id == "stopGame" })
        XCTAssertEqual(row.title, "Stop game")
        guard case .action(let destructive, let run) = row.kind else { return XCTFail("an action row") }
        XCTAssertTrue(destructive)
        run()
        XCTAssertEqual(asked, 1)
    }
}

/// The quick menu has Broadcast and Share play for the game playing, as on Windows and Linux.
@MainActor
final class QuickMenuMediaTests: XCTestCase {
    private func signedIn(_ model: AppModel) {
        model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
    }

    func testResumeSettingsTheGamesRowsAndCloseAreThereInOrder() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        model.previewRunning(game, app: .current)
        signedIn(model)
        let titles = model.quickMenuRows().map(\.title)
        XCTAssertEqual(titles.first, TH.text(.resume))
        XCTAssertEqual(titles[1], T.text(.gameSettings))
        XCTAssertEqual(titles.last, TH.text(.closeGame))
        XCTAssertEqual(model.quickMenuRows().last?.destructive, true)
        XCTAssertEqual(titles[2], TB.text(.setUpFirst), "no stream key yet: Set up broadcasting")
        XCTAssertEqual(titles[3], SP.format(.start, game.name), "and Share play")
    }

    func testTheSharePlayAndBroadcastRowsCanBeChosen() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        model.previewRunning(game, app: .current)
        signedIn(model)
        let rows = model.quickMenuRows()
        XCTAssertNotNil(rows.first { $0.title == SP.format(.start, game.name) }?.run, "Enter on it starts the share play")
        XCTAssertNotNil(rows.first { $0.title == TB.text(.setUpFirst) }?.run, "Enter on it opens Settings > Broadcasting")
    }

    func testSignedOutThereIsNoSharePlayRow() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        model.previewRunning(game, app: .current)
        XCTAssertFalse(model.quickMenuRows().contains { $0.title == SP.format(.start, game.name) })
    }

    func testTheMenuMovesOverEveryRowOfTheGameMenu() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        model.previewRunning(game, app: .current)
        model.overlay = .quickMenu
        model.menuIndex = 0
        let count = model.quickMenuRows().count
        for step in 1..<count {
            XCTAssertTrue(model.handle(.down))
            XCTAssertEqual(model.menuIndex, step)
        }
        XCTAssertTrue(model.handle(.down))
        XCTAssertEqual(model.menuIndex, count - 1, "stops at Close")
    }
}

/// A trophy's picture opens from the trophy; going back returns to the list.
@MainActor
final class TrophyShotTests: XCTestCase {
    private func set(_ game: Game, trophies count: Int) -> TrophySet {
        let list = (0..<count).map { number in
            TrophySet.Trophy(serviceLabel: 0, number: number, grade: .bronze, hidden: false, name: "T\(number)", detail: "", icon: nil, unlocked: Date(), progress: nil)
        }
        return TrophySet(title: game.name, icon: nil, trophies: list)
    }

    func testEnterOnATrophyWithAPictureOpensItAndBackReturnsToTheList() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("anyps5-shots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = try LauncherFixture.model { $0.screenshotsFolder = folder.path }
        let game = try XCTUnwrap(model.games.first)
        model.selected = 0
        model.previewTrophies(game, set(game, trophies: 3))
        let shot = Screenshots.trophyFile(in: folder, titleID: game.titleID, trophyID: "0/1", stamp: "20261108-120000")
        try Data([0x89]).write(to: shot)
        model.open(.trophies)
        model.trophyIndex = 1
        XCTAssertEqual(model.trophyShots["0/1"]?.lastPathComponent, shot.lastPathComponent)
        XCTAssertEqual(model.focusedTrophyShot?.lastPathComponent, shot.lastPathComponent)
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.overlay, .gallery)
        XCTAssertEqual(model.galleryShots[model.galleryIndex].lastPathComponent, shot.lastPathComponent)
        XCTAssertTrue(model.galleryViewing)
        XCTAssertTrue(model.handle(.back))
        XCTAssertFalse(model.galleryViewing)
        XCTAssertTrue(model.handle(.back))
        XCTAssertEqual(model.overlay, .trophies, "back to the list the picture opened from")
        XCTAssertEqual(model.trophyIndex, 1)
    }

    func testATrophyWithoutAPictureHasNoPictureToOpen() throws {
        let model = try LauncherFixture.model()
        let game = try XCTUnwrap(model.games.first)
        model.selected = 0
        model.previewTrophies(game, set(game, trophies: 1))
        model.open(.trophies)
        XCTAssertNil(model.focusedTrophyShot)
    }
}
