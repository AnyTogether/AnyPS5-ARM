import XCTest
@testable import AnyPS5Core

final class SystemNoticeTests: XCTestCase {
    func testAwayWithNoGameItIsTheSystemsNotification() {
        XCTAssertEqual(SystemNotice.route(launcherInFront: false, gamePlaying: false, permission: .allowed), .system)
    }

    func testOverAGameItStaysTheCard() {
        for permission: SystemNotice.Permission in [.allowed, .denied, .undecided, .unavailable] {
            XCTAssertEqual(SystemNotice.route(launcherInFront: false, gamePlaying: true, permission: permission), .card, "\(permission)")
        }
    }

    func testInFrontNothingGoesToTheSystem() {
        for permission: SystemNotice.Permission in [.allowed, .denied, .undecided, .unavailable] {
            XCTAssertEqual(SystemNotice.route(launcherInFront: true, gamePlaying: false, permission: permission), .card, "\(permission)")
        }
    }

    func testTheQuestionComesWithTheFirstWordAway() {
        XCTAssertEqual(SystemNotice.route(launcherInFront: false, gamePlaying: false, permission: .undecided), .cardAndAsk)
        XCTAssertEqual(SystemNotice.route(launcherInFront: true, gamePlaying: false, permission: .undecided), .card, "not asked in front")
        XCTAssertEqual(SystemNotice.route(launcherInFront: false, gamePlaying: true, permission: .undecided), .card, "not asked over a game")
    }

    func testANoOrNoCentreKeepsTheCard() {
        XCTAssertEqual(SystemNotice.route(launcherInFront: false, gamePlaying: false, permission: .denied), .card)
        XCTAssertEqual(SystemNotice.route(launcherInFront: false, gamePlaying: false, permission: .unavailable), .card)
    }

    func testOnlyAnAppWithAnIdentifierHasNotifications() {
        XCTAssertTrue(SystemNotice.available(bundlePath: "/Applications/AnyPS5.app", bundleIdentifier: "org.anyps5.launcher"))
        XCTAssertFalse(SystemNotice.available(bundlePath: "/Applications/AnyPS5.app", bundleIdentifier: nil))
        XCTAssertFalse(SystemNotice.available(bundlePath: "/Applications/AnyPS5.app", bundleIdentifier: ""))
        XCTAssertFalse(SystemNotice.available(bundlePath: "/Applications/Xcode.app/Contents/Developer/usr/bin", bundleIdentifier: "com.apple.dt.xctest.tool"), "swift test")
        XCTAssertFalse(SystemNotice.available(bundlePath: "/tmp/launcher/.build/debug", bundleIdentifier: nil), "swift run")
    }

    func testTheLinesAreTheCardsTitleAndDetail() {
        let lines = SystemNotice.lines(title: "New game: Stray", detail: "Ready in your library")
        XCTAssertEqual(lines.title, "New game: Stray")
        XCTAssertEqual(lines.body, "Ready in your library")
        XCTAssertEqual(SystemNotice.lines(title: "Unpacked Stray.zip", detail: "").body, "", "no second line, as on Desktop")
        XCTAssertEqual(SystemNotice.lines(title: " Hi \n", detail: "  ").title, "Hi")
    }
}
