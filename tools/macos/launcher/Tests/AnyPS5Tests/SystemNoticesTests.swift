@testable import AnyPS5
import AnyPS5Core
import UserNotifications
import XCTest

/// The card's words in Notification Center while the launcher is away and no game plays, as AnyPS5
/// Desktop's toast (Windows) and notify-send (Linux); the card over a game; macOS asked once, at
/// the first word away, never at launch.
@MainActor
final class SystemNoticesTests: XCTestCase {
    var delivered: [UNNotificationRequest] = []
    var asks = 0
    var inFront = false
    var playing = false

    func notices(_ permission: SystemNotice.Permission) -> SystemNotices {
        let notices = SystemNotices()
        notices.permission = permission
        notices.launcherInFront = { [unowned self] in self.inFront }
        notices.gamePlaying = { [unowned self] in self.playing }
        notices.deliver = { [unowned self] in self.delivered.append($0) }
        notices.askPermission = { [unowned self] in self.asks += 1 }
        return notices
    }

    func testATestRunHasNoNotificationCentre() {
        XCTAssertEqual(SystemNotices().permission, .unavailable, "swift test is not an app: UNUserNotificationCenter is never touched")
        XCTAssertFalse(SystemNotices().take("New game: Stray", detail: "", icon: nil))
    }

    func testAwayWithNoGameTheWordsGoToNotificationCenter() throws {
        let notices = notices(.allowed)
        XCTAssertTrue(notices.take("New game: Stray", detail: "Ready in your library", icon: nil))
        let request = try XCTUnwrap(delivered.first)
        XCTAssertEqual(request.content.title, "New game: Stray")
        XCTAssertEqual(request.content.body, "Ready in your library")
        XCTAssertNil(request.content.sound, "the launcher's own cue plays, as with the card")
        XCTAssertNil(request.trigger, "at once")
    }

    func testOverAGameOrInFrontItIsTheCard() {
        let notices = notices(.allowed)
        playing = true
        XCTAssertFalse(notices.take("Mira wants to join", detail: "Party", icon: nil))
        playing = false
        inFront = true
        XCTAssertFalse(notices.take("Mira wants to join", detail: "Party", icon: nil))
        XCTAssertTrue(delivered.isEmpty)
    }

    func testMacOSIsAskedOnceAtTheFirstWordAway() {
        let notices = notices(.undecided)
        inFront = true
        XCTAssertFalse(notices.take("Ready to play", detail: "", icon: nil))
        XCTAssertEqual(asks, 0, "not while the launcher is in front")
        inFront = false
        playing = true
        XCTAssertFalse(notices.take("Ready to play", detail: "", icon: nil))
        XCTAssertEqual(asks, 0, "not over a game")
        playing = false
        XCTAssertFalse(notices.take("Ready to play", detail: "", icon: nil), "the card says this one")
        XCTAssertFalse(notices.take("Ready to play", detail: "", icon: nil))
        XCTAssertEqual(asks, 1)
        XCTAssertTrue(delivered.isEmpty)
    }

    func testAfterANoTheCardStays() {
        let notices = notices(.denied)
        XCTAssertFalse(notices.take("Unpacked Stray.zip", detail: "", icon: nil))
        XCTAssertEqual(asks, 0)
        XCTAssertTrue(delivered.isEmpty)
    }
}
