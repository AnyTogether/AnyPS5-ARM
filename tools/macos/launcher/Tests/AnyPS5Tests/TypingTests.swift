@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// Text rows (the sign-in's email and code, names, links): select on the row puts the cursor in
/// it, a click anywhere on the row does too, what is typed arrives, and back or another row
/// gives the keys back to the launcher.
@MainActor
final class TypingTests: XCTestCase {
    /// The first start's last step with the sign-in over it.
    func signingIn() throws -> (AppModel, [PanelRow], Int) {
        let model = try LauncherFixture.model(games: 1) {
            $0.onboarded = false
            $0.libraryFolders = []
        }
        model.onboardingStep = 3
        model.beginSignIn(.firstStart)
        XCTAssertEqual(model.overlay, .signIn)
        let rows = model.signInRows()
        let email = try XCTUnwrap(rows.firstIndex { $0.id == "together-email" }, "no email row")
        return (model, rows, email)
    }

    func testSelectOnATextRowStartsTypingAndBackEndsIt() throws {
        let (model, rows, email) = try signingIn()
        model.focusRow(email, in: rows)
        XCTAssertNil(model.typingRow)
        XCTAssertTrue(model.onboardingCommand(.select))
        XCTAssertEqual(model.typingRow, "together-email", "select on the email row puts the cursor in it")
        XCTAssertTrue(model.onboardingCommand(.back))
        XCTAssertNil(model.typingRow, "back gives the keys back first")
        XCTAssertEqual(model.overlay, .signIn, "and does not leave the sign-in")
        XCTAssertTrue(model.onboardingCommand(.select))
        XCTAssertEqual(model.typingRow, "together-email")
        XCTAssertTrue(model.onboardingCommand(.down))
        XCTAssertNil(model.typingRow, "another row: the cursor is out of the field")
        XCTAssertEqual(model.focusedRow(in: model.signInRows()), email + 1)
    }

    func testSelectOnTheEmailRowPutsTheCursorInAndWhatIsTypedArrives() throws {
        let (model, rows, email) = try signingIn()
        let screen = try LauncherWindow(model)
        defer { screen.close() }
        model.focusRow(email, in: rows)
        screen.wait(0.3)
        XCTAssertFalse(screen.typing)
        XCTAssertTrue(model.onboardingCommand(.select))
        screen.wait(0.5)
        XCTAssertTrue(screen.typing, "after select on the email row the cursor is not in a field (first responder: \(String(describing: screen.window.firstResponder)))")
        screen.type("robin@example.com")
        XCTAssertEqual(model.togetherEmail, "robin@example.com")
        XCTAssertTrue(model.onboardingCommand(.back))
        screen.wait(0.5)
        XCTAssertFalse(screen.typing, "back took the cursor out: the keys are the launcher's again")
        XCTAssertEqual(model.togetherEmail, "robin@example.com", "what was typed is kept")
    }

    func testAClickOnTheEmailRowPutsTheCursorIn() throws {
        let (model, rows, email) = try signingIn()
        let screen = try LauncherWindow(model)
        defer { screen.close() }
        // The row under the email is the focused one: the click has to bring the focus too.
        model.focusRow(email + 1, in: rows)
        screen.wait(0.3)
        let fields = screen.views(NSTextField.self).filter { $0.isEditable }
        let field = try XCTUnwrap(fields.first, "no text field on the sign-in")
        let box = screen.frame(field)
        print("email field in the window: \(box), \(fields.count) editable fields")
        XCTAssertGreaterThanOrEqual(box.width, 200, "a field wide enough to hit and to read an address in")
        // On the field itself.
        screen.click(NSPoint(x: box.midX, y: box.midY))
        XCTAssertTrue(screen.typing, "a click on the field did not put the cursor in it")
        XCTAssertEqual(model.typingRow, "together-email")
        XCTAssertEqual(model.focusedRow(in: model.signInRows()), email, "the focus came with the click")
        screen.type("a")
        XCTAssertEqual(model.togetherEmail, "a")
        // On another row: out of the field.
        XCTAssertTrue(model.onboardingCommand(.down))
        screen.wait(0.5)
        XCTAssertFalse(screen.typing, "moving to another row left the cursor in the field")
        // On the row beside the field (its name): the cursor goes in as well.
        screen.click(NSPoint(x: box.minX - 60, y: box.midY))
        XCTAssertEqual(model.typingRow, "together-email", "a click on the row's name did not start typing")
        XCTAssertTrue(screen.typing, "a click on the row's name did not put the cursor in the field")
        screen.type("b")
        XCTAssertEqual(model.togetherEmail, "ab")
    }

    func testUpFromAddProfilesCardsTypesTheNameAndBackGivesTheKeysBack() throws {
        let model = try LauncherFixture.model()
        model.openAddProfile()
        XCTAssertEqual(model.overlay, .addProfile)
        XCTAssertNil(model.typingRow)
        XCTAssertTrue(model.modeChoiceCommand(.up))
        XCTAssertEqual(model.typingRow, AppModel.profileNameField, "up from the cards puts the cursor in the name")
        XCTAssertTrue(model.modeChoiceCommand(.back))
        XCTAssertNil(model.typingRow, "back gives the keys back first")
        XCTAssertEqual(model.overlay, .addProfile, "and does not leave Add Profile")
        XCTAssertTrue(model.modeChoiceCommand(.up))
        XCTAssertTrue(model.modeChoiceCommand(.down))
        XCTAssertNil(model.typingRow, "down goes back to the cards")
    }

    func testAddProfilesNameTakesTheCursorAndWhatIsTyped() throws {
        let model = try LauncherFixture.model()
        model.openAddProfile()
        let screen = try LauncherWindow(model)
        defer { screen.close() }
        XCTAssertFalse(screen.typing)
        XCTAssertTrue(model.modeChoiceCommand(.up))
        screen.wait(0.5)
        XCTAssertTrue(screen.typing, "up from the cards did not put the cursor in the name")
        screen.type("!")
        XCTAssertTrue(model.profileFlow.name.contains("!"), "what is typed goes into the name: \(model.profileFlow.name)")
        XCTAssertTrue(model.modeChoiceCommand(.back))
        screen.wait(0.5)
        XCTAssertFalse(screen.typing, "back took the cursor out")
        XCTAssertEqual(model.overlay, .addProfile)
    }

    /// A stepper's number being typed is a field too: back leaves it without leaving the screen.
    func testBackEndsANumberBeingTyped() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        model.typingRow = "launcherVolume"
        XCTAssertTrue(model.panelCommand(.back))
        XCTAssertNil(model.typingRow)
        XCTAssertEqual(model.overlay, .settings)
    }
}
