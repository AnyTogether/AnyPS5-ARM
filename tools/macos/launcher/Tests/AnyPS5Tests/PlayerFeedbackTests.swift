@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// Players' feedback of 3 November 2026, as AnyPS5 Desktop got it too: the way back from one's
/// profile, the Theme Studio's numbers, taking back a friend request, Fonts lower in Settings and
/// one "all caught up" in the notifications.
@MainActor
final class PlayerFeedbackTests: XCTestCase {
    private func index(of id: String, in model: AppModel) -> Int? {
        model.panelCategories().firstIndex { $0.id == id }
    }

    func testBackFromMyProfileReturnsToAnyTogether() throws {
        let model = try LauncherFixture.model()
        PreviewRenderer.signedIn(model)
        model.togetherConnected = false
        model.openTogetherSettings()
        let together = try XCTUnwrap(index(of: "together", in: model))
        let row = try XCTUnwrap(model.panelCategories()[together].rows.firstIndex { $0.id == "together-profile" })
        model.panelRow = row
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.overlay, .profile)
        model.mouseBack()
        XCTAssertEqual(model.overlay, .settings)
        XCTAssertEqual(model.panelCategory, together, "back on AnyTogether, not on the first category")
        XCTAssertEqual(model.panelRow, row)
        XCTAssertTrue(model.panelInRows)
    }

    // MARK: Theme Studio

    private func stepper(cycle: Int? = 360, range: ClosedRange<Int> = 0...359, step: Int = 15, value: Int, set: @escaping (Int) -> Void = { _ in }) -> PanelRow {
        PanelRow(id: "hue", title: "Hue", kind: .stepper(value: value, range: range, step: step, format: { "\($0)°" }, set: set), cycle: cycle, typable: true)
    }

    func testTheColourWheelGoesRound() {
        XCTAssertEqual(stepper(value: 350).stepped(350, by: 1), 5)
        XCTAssertEqual(stepper(value: 10).stepped(10, by: -1), 355)
        XCTAssertEqual(stepper(value: 300).stepped(300, by: 1), 315)
        // From 300° to around 50°: eight presses, not fifty.
        let row = stepper(value: 300)
        XCTAssertEqual((0..<8).reduce(300) { value, _ in row.stepped(value, by: 1) }, 60)
        let held = stepper(cycle: nil, range: -90...90, step: 10, value: 85)
        XCTAssertEqual(held.stepped(85, by: 1), 90, "a value without a cycle stops at its end")
    }

    func testANumberCanBeTyped() {
        let hue = stepper(value: 300)
        XCTAssertEqual(hue.typed("50"), 50)
        XCTAssertEqual(hue.typed(" 164° "), 164)
        XCTAssertEqual(hue.typed("400"), 40, "round the wheel")
        XCTAssertEqual(hue.typed("-20"), 340)
        XCTAssertNil(hue.typed("abc"))
        XCTAssertNil(hue.typed(""))
        let highlight = stepper(cycle: nil, range: -90...90, step: 10, value: 0)
        XCTAssertEqual(highlight.typed("-120"), -90, "held in the range")
    }

    func testTypingOpensAtTheKeyboardAndKeepsTheNumber() throws {
        let model = try LauncherFixture.model()
        InputModeState.shared.preview(.keyboard)
        var set: [Int] = []
        let row = stepper(value: 300) { set.append($0) }
        model.activate(row)
        XCTAssertEqual(model.typingRow, "hue")
        model.typeStepper(row, "50")
        XCTAssertEqual(set, [50])
        XCTAssertNil(model.typingRow)
        model.typeStepper(row, "60")
        XCTAssertEqual(set, [50], "nothing once the field is closed")
        model.activate(row)
        model.typingRow = nil
        model.typeStepper(row, "70")
        XCTAssertEqual(set, [50], "Esc leaves the number as it was")
    }

    func testThePadStillStepsTheNumber() throws {
        let model = try LauncherFixture.model()
        InputModeState.shared.preview(.pad)
        defer { InputModeState.shared.preview(.keyboard) }
        var set: [Int] = []
        model.activate(stepper(value: 350) { set.append($0) })
        XCTAssertNil(model.typingRow, "no field to type in with a controller")
        XCTAssertEqual(set, [5])
    }

    func testTheStudiosNumbersStepFurtherAndCanBeTyped() throws {
        let model = try LauncherFixture.model()
        let neon = ThemeDesign(id: "neon", name: "Neon", author: "Robin", style: 0, deep: "#050510", middle: "#1A1040", bright: "#FF4FD8", accent: "#00E5FF")
        model.previewThemes([neon], active: neon, hub: [])
        let rows = model.studioRows()
        for id in ["hue", "highlight", "depth", "accent"] {
            let row = try XCTUnwrap(rows.first { $0.id == id }, id)
            XCTAssertTrue(row.typable, id)
        }
        let hue = try XCTUnwrap(rows.first { $0.id == "hue" })
        XCTAssertEqual(hue.cycle, 360)
        guard case .stepper(_, _, let step, _, _) = hue.kind else { return XCTFail("not a stepper") }
        XCTAssertEqual(step, 15)
    }

    // MARK: Friends, Settings, notifications

    func testASentFriendRequestCanBeTakenBack() throws {
        let model = try LauncherFixture.model()
        PreviewRenderer.signedIn(model)
        model.togetherRequests = TogetherRequests(incoming: [], outgoing: [TogetherPerson(userId: "f9", handle: "ada", displayName: "Ada", avatar: nil)])
        let rows = model.friendRows()
        let waiting = try XCTUnwrap(rows.firstIndex { $0.id == "waiting-f9" })
        let cancel = try XCTUnwrap(rows.firstIndex { $0.id == "cancel-f9" })
        XCTAssertEqual(cancel, waiting + 1, "right below the request")
        XCTAssertEqual(rows[cancel].title, T.format(.friendsCancelRequest, "Ada"))
        guard case .action(let destructive, _) = rows[cancel].kind else { return XCTFail("not an action") }
        XCTAssertTrue(destructive)
    }

    func testFontsComeLastBeforeAbout() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        let fonts = try XCTUnwrap(index(of: "fonts", in: model))
        XCTAssertEqual(index(of: "about", in: model), fonts + 1)
        XCTAssertGreaterThan(fonts, try XCTUnwrap(index(of: "advanced", in: model)))
    }

    func testNoNotificationsSayItOnce() throws {
        let model = try LauncherFixture.model()
        PreviewRenderer.signedIn(model)
        model.social.notifications.load(TogetherNotificationPage(notifications: [], unread: 0, more: false))
        XCTAssertNil(model.notificationsSubtitle, "the title says nothing beside it")
        let rows = model.notificationRows()
        XCTAssertEqual(rows.map(\.title), [TS.text(.notifNothingNew)])
        XCTAssertNotEqual(TS.text(.notifNothingNew), TS.text(.notifEmpty))
        model.social.notifications.load(TogetherNotificationPage(notifications: [], unread: 2, more: false))
        XCTAssertEqual(model.notificationsSubtitle, TS.format(.notifUnread, 2))
    }
}
