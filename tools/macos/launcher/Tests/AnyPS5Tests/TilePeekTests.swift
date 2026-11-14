@testable import AnyPS5
import AnyPS5Core
import XCTest

/// The home tile row as on Windows and Linux: the previous game stays in view at the left edge,
/// the next tiles follow right after the selected one, and the name sits beside it with the
/// state as an icon.
@MainActor
final class TilePeekTests: XCTestCase {
    let small: CGFloat = 118, large: CGFloat = 176, gap: CGFloat = 16, leading: CGFloat = 64

    func x(_ offset: Int, peek: CGFloat = 0) -> CGFloat {
        TileRow.x(index: offset + 3, offset: offset, preview: false, leading: leading + peek, small: small, large: large, gap: gap)
    }

    func testThePreviousTileStaysInViewAndTheOnesBeforeItFadeOut() {
        XCTAssertEqual(TileRow.opacity(offset: -1), TilePeek.opacity)
        XCTAssertEqual(TileRow.opacity(offset: -1), 0.85, accuracy: 0.0001)
        XCTAssertEqual(TileRow.opacity(offset: -2), 0)
        XCTAssertEqual(TileRow.opacity(offset: 0), 1)
        XCTAssertEqual(TileRow.opacity(offset: 4), 1)
    }

    func testTheNextTilesFollowRightAfterTheSelectedOne() {
        XCTAssertEqual(x(0), leading)
        XCTAssertEqual(x(1), leading + large + gap, "no room for the name between them any more")
        XCTAssertEqual(x(2), leading + large + gap + small + gap)
    }

    func testFromTheSecondGameOnTheRowMovesRightSoThePreviousTilePeeksIn() {
        let peek = TilePeek.shift
        XCTAssertEqual(peek, 48)
        XCTAssertEqual(x(0, peek: peek), leading + peek)
        // The previous tile starts past the window's left edge and ends before the selected one.
        let previous = x(-1, peek: peek)
        XCTAssertLessThan(previous, 0)
        XCTAssertGreaterThan(previous + small, 0)
        XCTAssertEqual(previous + small + gap, leading + peek)
        XCTAssertLessThan(x(-2, peek: peek) + small, 0, "the one before it is out of the window")
    }

    func testThePreviewRowOfAFolderLaysItsTilesOutInOrder() {
        XCTAssertEqual(TileRow.x(index: 2, offset: 2, preview: true, leading: leading, small: 112, large: 148, gap: gap), leading + 2 * (112 + gap))
    }

    func testThePlainLockedGameShowsNoIconBesideItsName() {
        XCTAssertTrue(StateLabel.iconOnlyHidden(.locked, waitingToPrepare: false), "its tile carries the padlock")
        XCTAssertFalse(StateLabel.iconOnlyHidden(.locked, waitingToPrepare: true), "waiting to be prepared shows the clock")
        XCTAssertFalse(StateLabel.iconOnlyHidden(.queued, waitingToPrepare: false))
        XCTAssertFalse(StateLabel.iconOnlyHidden(.installed(outdated: false), waitingToPrepare: false))
    }
}
