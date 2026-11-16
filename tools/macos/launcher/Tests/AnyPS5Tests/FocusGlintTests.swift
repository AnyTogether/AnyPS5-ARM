@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// The focus ring as on Windows and Linux: a white ring as easy to see as before, a glint that
/// goes round once every 4.8 seconds, a halo that breathes twice per turn and never goes out, a
/// short settle from slightly outside, and only a focused home tile moving, never under a layer
/// or while a game starts or runs.
@MainActor
final class FocusGlintTests: XCTestCase {
    /// How far apart two moments of a turn are, the short way round.
    func apart(_ a: Double, _ b: Double) -> Double {
        let gap = abs(a - b)
        return min(gap, 1 - gap)
    }

    func testTheGlintGoesRoundOnceEvery4Point8Seconds() {
        XCTAssertEqual(FocusGlint.period, 4.8)
        let start = Date(timeIntervalSinceReferenceDate: 48)
        XCTAssertLessThan(apart(FocusGlint.phase(at: start), 0), 0.0001)
        XCTAssertLessThan(apart(FocusGlint.phase(at: start.addingTimeInterval(1.2)), 0.25), 0.0001)
        XCTAssertLessThan(apart(FocusGlint.phase(at: start.addingTimeInterval(4.8)), 0), 0.0001, "a whole turn later it is back")
        for step in 0..<50 {
            let phase = FocusGlint.phase(at: start.addingTimeInterval(Double(step) * 0.37))
            XCTAssertGreaterThanOrEqual(phase, 0)
            XCTAssertLessThan(phase, 1)
        }
    }

    func testTheHaloBreathesTwicePerTurnAndNeverGoesOut() {
        XCTAssertEqual(FocusGlint.breath(0), 0, accuracy: 0.0001)
        XCTAssertEqual(FocusGlint.breath(0.25), 1, accuracy: 0.0001)
        XCTAssertEqual(FocusGlint.breath(0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(FocusGlint.breath(0.75), 1, accuracy: 0.0001)
        XCTAssertEqual(FocusGlint.haloOpacity(0), 0.16, accuracy: 0.0001)
        XCTAssertEqual(FocusGlint.haloOpacity(1), 0.32, accuracy: 0.0001)
        XCTAssertEqual(FocusGlint.haloBlur(0), 9)
        XCTAssertEqual(FocusGlint.haloBlur(1), 14)
    }

    func testTheRingStaysAsEasyToSeeAndTheGlintBrightensIt() {
        XCTAssertGreaterThanOrEqual(FocusGlint.ringOpacity, 0.9)
        XCTAssertEqual(FocusGlint.ringStops.map { $0.opacity }.min(), FocusGlint.ringOpacity)
        let peak = FocusGlint.ringStops.max { $0.opacity < $1.opacity }
        XCTAssertEqual(peak?.opacity, 1)
        XCTAssertEqual(peak?.location, 0.8)
        XCTAssertEqual(FocusGlint.glowStops.max { $0.opacity < $1.opacity }?.location, 0.8, "the glow follows the glint")
        XCTAssertEqual(FocusGlint.glowStops.first?.opacity, 0)
        XCTAssertEqual(FocusGlint.glowStops.last?.opacity, 0)
    }

    func testTheRingClosesInFromItsWidthOutsideButNotWithReducedMotion() {
        XCTAssertEqual(FocusGlint.settle(width: 3, focused: false, reduceMotion: false), 3)
        XCTAssertEqual(FocusGlint.settle(width: 3, focused: true, reduceMotion: false), 0)
        XCTAssertEqual(FocusGlint.settle(width: 3, focused: false, reduceMotion: true), 0)
    }

    func testOnlyAFocusedHomeTileWithNothingOverItMoves() {
        XCTAssertTrue(FocusGlint.moves(focused: true, covered: false, gameBusy: false, active: true))
        XCTAssertFalse(FocusGlint.moves(focused: false, covered: false, gameBusy: false, active: true))
        XCTAssertFalse(FocusGlint.moves(focused: true, covered: true, gameBusy: false, active: true), "a layer's blur is not redone every frame")
        XCTAssertFalse(FocusGlint.moves(focused: true, covered: false, gameBusy: true, active: true), "the GPU is the game's")
        XCTAssertFalse(FocusGlint.moves(focused: true, covered: false, gameBusy: false, active: false), "behind another window it rests")
    }

    func testTheHomeTileRingStopsUnderALayer() throws {
        let model = try LauncherFixture.model()
        XCTAssertTrue(model.homeTileGlints(true))
        XCTAssertFalse(model.homeTileGlints(false))
        model.open(.settings)
        XCTAssertFalse(model.homeTileGlints(true))
        model.overlay = nil
        model.active = false
        XCTAssertFalse(model.homeTileGlints(true))
    }
}
