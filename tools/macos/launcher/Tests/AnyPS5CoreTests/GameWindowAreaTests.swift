import AnyPS5Core
import CoreGraphics
import XCTest

/// What share play, Remote Play and clips capture of a game's window: the game, not its title bar.
final class GameWindowAreaTests: XCTestCase {
    let display = CGRect(x: 0, y: 0, width: 1920, height: 1200)

    func testAWindowedGameLosesItsTitleBar() {
        // Cat Quest III at 60 %: 1152 x 648 of game under a 28 pt title bar.
        let window = CGRect(x: 384, y: 248, width: 1152, height: 676)
        XCTAssertEqual(GameWindowArea.capture(window: window, display: display, titleBar: 28), CGRect(x: 384, y: 276, width: 1152, height: 648))
    }

    func testAFullScreenGameIsCapturedWhole() {
        XCTAssertEqual(GameWindowArea.capture(window: display, display: display, titleBar: 28), CGRect(x: 0, y: 0, width: 1920, height: 1200))
    }

    func testTheAreaIsInTheDisplaysOwnCoordinates() {
        // A second display to the right: sourceRect counts from that display's corner.
        let second = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let window = CGRect(x: 2020, y: 100, width: 1280, height: 748)
        XCTAssertEqual(GameWindowArea.capture(window: window, display: second, titleBar: 28), CGRect(x: 100, y: 128, width: 1280, height: 720))
        XCTAssertEqual(GameWindowArea.capture(window: second, display: second, titleBar: 28), CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    func testTheOutputIsInPixelsUpToTheTarget() {
        // 60 % on Retina: 1152 x 648 points are 2304 x 1296 pixels, so a 720p target gets 720p.
        XCTAssertTrue(GameWindowArea.outputSize(area: CGSize(width: 1152, height: 648), scale: 2, maxWidth: 1280, maxHeight: 720) == (1280, 720))
        // Without Retina the window's own pixels, never stretched up.
        XCTAssertTrue(GameWindowArea.outputSize(area: CGSize(width: 1152, height: 648), scale: 1, maxWidth: 1280, maxHeight: 720) == (1152, 648))
        // A phone's target: its height, the shape kept.
        XCTAssertTrue(GameWindowArea.outputSize(area: CGSize(width: 1920, height: 1200), scale: 2, maxWidth: 2400, maxHeight: 1080) == (1728, 1080))
        // Odd pixels become even; tiny windows stay at least 160 x 90.
        XCTAssertTrue(GameWindowArea.outputSize(area: CGSize(width: 641, height: 361), scale: 1, maxWidth: 4000, maxHeight: 4000) == (640, 360))
        XCTAssertTrue(GameWindowArea.outputSize(area: CGSize(width: 50, height: 20), scale: 1, maxWidth: 1280, maxHeight: 720) == (160, 90))
        // A clip keeps every pixel.
        XCTAssertTrue(GameWindowArea.outputSize(area: CGSize(width: 1512, height: 982), scale: 2, maxWidth: .max, maxHeight: .max) == (3024, 1964))
    }

    func testNoTitleBarNoCrop() {
        let window = CGRect(x: 384, y: 248, width: 1152, height: 648)
        XCTAssertEqual(GameWindowArea.capture(window: window, display: display, titleBar: 0), CGRect(x: 384, y: 248, width: 1152, height: 648))
    }
}
