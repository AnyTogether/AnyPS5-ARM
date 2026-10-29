@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// Players' feedback, as in AnyPS5 Desktop: Esc on the home screen asks before quitting, and the
/// mouse's side buttons are Back (Circle) and Forward.
@MainActor
final class EscapeOnHomeTests: XCTestCase {
    func testEscapeOnTheHomeScreenAsksQuitWithCancelFirst() throws {
        let model = try LauncherFixture.model()
        XCTAssertTrue(model.escape())
        XCTAssertEqual(model.overlay, .confirmQuit)
        XCTAssertEqual(model.menuIndex, 0, "Cancel has the focus, so a second Enter does not quit")
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay, "Cancel closes the question")
    }

    func testEscapeCircleAndTheBackdropAnswerCancel() throws {
        let model = try LauncherFixture.model()
        for answer in [Command.back, .options] {
            XCTAssertTrue(model.escape())
            XCTAssertEqual(model.overlay, .confirmQuit)
            XCTAssertTrue(model.handle(answer))
            XCTAssertNil(model.overlay)
        }
        XCTAssertTrue(model.escape())
        XCTAssertTrue(model.escape(), "Esc on the question is its Cancel")
        XCTAssertNil(model.overlay)
    }

    func testThePadMovesToQuit() throws {
        let model = try LauncherFixture.model()
        _ = model.escape()
        XCTAssertTrue(model.handle(.down))
        XCTAssertEqual(model.menuIndex, 1)
        XCTAssertTrue(model.handle(.up))
        XCTAssertEqual(model.menuIndex, 0)
    }

    func testEverywhereElseEscapeKeepsItsMeaning() throws {
        let model = try LauncherFixture.model()
        model.focus = .top(1)
        XCTAssertFalse(model.escape(), "from the top bar Esc is Back: to the games")
        model.focus = .actions(0)
        XCTAssertFalse(model.escape())
        model.focus = .tiles
        model.open(.settings)
        XCTAssertFalse(model.escape(), "a panel is closed by Back as before")
        model.overlay = nil
        XCTAssertTrue(model.handle(.back), "Circle on the home screen")
        XCTAssertNil(model.overlay, "asks nothing")
    }
}

@MainActor
final class MouseSideButtonTests: XCTestCase {
    func testBackClosesAPanelAndForwardOpensItAgain() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        model.mouseBack()
        XCTAssertNil(model.overlay)
        model.mouseForward()
        XCTAssertEqual(model.overlay, .settings)
    }

    func testBackStepsOutOfASubPanelAndForwardGoesBackIn() throws {
        let model = try LauncherFixture.model()
        model.open(.gameSettings)
        model.open(.controls)
        model.mouseBack()
        XCTAssertEqual(model.overlay, .gameSettings, "the controls back to the game settings")
        model.mouseBack()
        XCTAssertNil(model.overlay)
        model.mouseForward()
        XCTAssertEqual(model.overlay, .gameSettings)
        model.mouseForward()
        XCTAssertEqual(model.overlay, .gameSettings, "only the screen Back just closed")
    }

    func testForwardDoesNothingOnceTheUserMovedOn() throws {
        let model = try LauncherFixture.model()
        model.open(.library)
        model.mouseBack()
        model.moveSelection(1)
        model.mouseForward()
        XCTAssertNil(model.overlay, "another game chosen")
        model.open(.library)
        model.mouseBack()
        model.open(.settings)
        model.mouseForward()
        XCTAssertEqual(model.overlay, .settings, "somewhere else since")
    }

    func testForwardNeverReopensAQuestion() throws {
        let model = try LauncherFixture.model()
        _ = model.escape()
        model.mouseBack()
        XCTAssertNil(model.overlay, "Back answers Cancel")
        model.mouseForward()
        XCTAssertNil(model.overlay)
    }

    func testBackOnTheHomeScreenIsCircleAndAsksNothing() throws {
        let model = try LauncherFixture.model()
        model.focus = .top(2)
        model.mouseBack()
        XCTAssertEqual(model.focus, .tiles)
        model.mouseBack()
        XCTAssertNil(model.overlay)
    }

    func testBackInTheGalleryLeavesThePictureForTheGridFirst() throws {
        let model = try LauncherFixture.model()
        model.open(.gallery)
        model.galleryViewing = true
        model.mouseBack()
        XCTAssertEqual(model.overlay, .gallery)
        XCTAssertFalse(model.galleryViewing)
        model.mouseBack()
        XCTAssertNil(model.overlay)
    }

    func testTheSideButtonsAreButtonsThreeAndFour() {
        XCTAssertEqual(Input.sideButton(3), .back)
        XCTAssertEqual(Input.sideButton(4), .forward)
        XCTAssertNil(Input.sideButton(2), "the middle button stays the middle button")
    }
}
