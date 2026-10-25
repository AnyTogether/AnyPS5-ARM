import XCTest
@testable import AnyPS5Core

final class UpdateNoticeTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheStateAboutShows() {
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: nil, progress: nil, ready: nil, lastCheck: nil, failed: false), .idle)
        XCTAssertEqual(LauncherUpdateState.of(checking: true, newer: nil, progress: nil, ready: nil, lastCheck: nil, failed: false), .checking)
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: nil, progress: nil, ready: nil, lastCheck: noon, failed: false), .upToDate(checked: noon))
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: nil, progress: nil, ready: nil, lastCheck: noon, failed: true), .failed)
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: "0.2.20", progress: nil, ready: nil, lastCheck: noon, failed: false), .available(version: "0.2.20"))
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: "0.2.20", progress: 0.42, ready: nil, lastCheck: noon, failed: false),
                       .downloading(version: "0.2.20", fraction: 0.42))
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: "0.2.20", progress: nil, ready: "0.2.20", lastCheck: noon, failed: false), .ready(version: "0.2.20"))
    }

    func testAReadyUpdateWinsOverAnotherCheck() {
        // A periodic check while the update waits for a restart says nothing new.
        XCTAssertEqual(LauncherUpdateState.of(checking: true, newer: "0.2.20", progress: nil, ready: "0.2.20", lastCheck: noon, failed: false), .ready(version: "0.2.20"))
        XCTAssertEqual(LauncherUpdateState.of(checking: false, newer: "0.2.20", progress: nil, ready: "0.2.20", lastCheck: noon, failed: true), .ready(version: "0.2.20"))
        XCTAssertEqual(LauncherUpdateState.of(checking: true, newer: "0.2.20", progress: 0.5, ready: nil, lastCheck: noon, failed: false),
                       .downloading(version: "0.2.20", fraction: 0.5))
    }

    func testThePercentShown() {
        XCTAssertEqual(LauncherUpdateState.downloading(version: "1", fraction: 0.423).percent, 42)
        XCTAssertEqual(LauncherUpdateState.downloading(version: "1", fraction: 1.4).percent, 100)
        XCTAssertEqual(LauncherUpdateState.downloading(version: "1", fraction: -1).percent, 0)
        XCTAssertNil(LauncherUpdateState.checking.percent)
    }

    func testTheNoticeShowsOnlyForAReadyUpdateUntilLater() {
        var notice = UpdateNotice()
        for state in [LauncherUpdateState.idle, .checking, .upToDate(checked: noon), .failed, .available(version: "0.2.20"),
                      .downloading(version: "0.2.20", fraction: 0.9)] {
            XCTAssertFalse(notice.shows(state), "\(state)")
        }
        XCTAssertTrue(notice.shows(.ready(version: "0.2.20")))
        notice.later(.ready(version: "0.2.20"))
        XCTAssertFalse(notice.shows(.ready(version: "0.2.20")), "Later: no nagging, the update goes in at the next launch")
        XCTAssertTrue(notice.shows(.ready(version: "0.2.21")), "a newer one ready is news once")
        notice.later(.checking)
        XCTAssertTrue(notice.shows(.ready(version: "0.2.21")), "Later on anything but a ready update changes nothing")
    }

    func testRestartNowNeverInterruptsAGame() {
        XCTAssertEqual(UpdateRestart.decide(gameRunning: false), .now)
        XCTAssertEqual(UpdateRestart.decide(gameRunning: true), .afterGame)
    }
}
