@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// The home screen's start animation as on Windows and Linux: 2.6 seconds, the curtain fading
/// first, the tiles one after the other, then the top bar, the game's details and the hints. It
/// plays once per run, when the home screen is first seen with nothing over it, and not with
/// reduced motion or a game starting or running. A key, a button or a click finishes it at once.
@MainActor
final class StartupIntroTests: XCTestCase {
    func testTheTimingsAreTheSameAsOnWindowsAndLinux() {
        XCTAssertEqual(StartupIntro.duration, 2.6)
        XCTAssertEqual(StartupIntro.curtainFade.0, 0.18)
        XCTAssertEqual(StartupIntro.curtainFade.1, 0.55)
        XCTAssertEqual(StartupIntro.topBar.0, 0.50)
        XCTAssertEqual(StartupIntro.topBar.1, 0.75)
        XCTAssertEqual(StartupIntro.hero.0, 0.62)
        XCTAssertEqual(StartupIntro.hero.1, 0.90)
        XCTAssertEqual(StartupIntro.hints.0, 0.75)
        XCTAssertEqual(StartupIntro.hints.1, 0.95)
    }

    func testTheTilesComeInThreePercentApartForTenStepsAtMost() {
        XCTAssertEqual(StartupIntro.tile(0).0, 0.30, accuracy: 0.0001)
        XCTAssertEqual(StartupIntro.tile(0).1, 0.52, accuracy: 0.0001)
        XCTAssertEqual(StartupIntro.tile(1).0, 0.33, accuracy: 0.0001)
        XCTAssertEqual(StartupIntro.tile(9).0, 0.57, accuracy: 0.0001)
        XCTAssertEqual(StartupIntro.tile(30).0, StartupIntro.tile(9).0, "the later ones come with the tenth")
        XCTAssertLessThanOrEqual(StartupIntro.tile(9).1, 1)
    }

    func testAPartIsHiddenBeforeItsSpanAndInPlaceAfterIt() {
        let span = StartupIntro.topBar
        XCTAssertEqual(StartupIntro.reveal(0, span: span), 0)
        XCTAssertEqual(StartupIntro.reveal(span.0, span: span), 0)
        XCTAssertEqual(StartupIntro.reveal(span.1, span: span), 1)
        XCTAssertEqual(StartupIntro.reveal(1, span: span), 1)
        var last = 0.0
        for step in 0...40 {
            let value = StartupIntro.reveal(span.0 + (span.1 - span.0) * Double(step) / 40, span: span)
            XCTAssertGreaterThanOrEqual(value, last - 0.0001, "it only ever comes in")
            last = value
        }
        XCTAssertGreaterThan(StartupIntro.reveal(span.0 + (span.1 - span.0) * 0.3, span: span), 0.6, "a strong ease-out: most of the way early")
    }

    func testTheCurvesMatchFlutters() {
        XCTAssertEqual(StartupIntro.settle.transform(0), 0)
        XCTAssertEqual(StartupIntro.settle.transform(1), 1)
        XCTAssertEqual(StartupIntro.easeInOut.transform(0.5), 0.5, accuracy: 0.001)
        XCTAssertLessThan(StartupIntro.easeInOut.transform(0.2), 0.2)
        XCTAssertGreaterThan(StartupIntro.easeInOut.transform(0.8), 0.8)
    }

    func testTheCurtainCoversAtTheStartAndIsGoneByTheTiles() {
        XCTAssertEqual(StartupIntro.curtainGone(0), 0)
        XCTAssertEqual(StartupIntro.curtainGone(0.18), 0)
        XCTAssertEqual(StartupIntro.curtainGone(0.55), 1)
        let lifting = StartupIntro.curtainGone(StartupIntro.tile(0).0)
        XCTAssertGreaterThan(lifting, 0.1, "the first tile comes in as it lifts")
        XCTAssertLessThan(lifting, 1)
        for index in 0..<4 {
            let dot = IntroCurtain.dot(index, progress: Double(index) * 0.1)
            XCTAssertGreaterThanOrEqual(dot, 0.3)
            XCTAssertLessThanOrEqual(dot, 1)
        }
    }

    func testProgressRunsFromTheStartToOneAndIsOneWhenItDoesNotPlay() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(StartupIntro.progress(since: nil, now: start), 1)
        XCTAssertEqual(StartupIntro.progress(since: start, now: start), 0)
        XCTAssertEqual(StartupIntro.progress(since: start, now: start.addingTimeInterval(1.3)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StartupIntro.progress(since: start, now: start.addingTimeInterval(9)), 1)
    }

    func testItPlaysOnceWhenTheHomeScreenIsFirstSeenWithNothingOverIt() {
        func decide(enabled: Bool = true, played: Bool = false, offscreen: Bool = false, covered: Bool = false, gameBusy: Bool = false, reduceMotion: Bool = false) -> StartupIntro.Start {
            StartupIntro.decide(enabled: enabled, played: played, offscreen: offscreen, covered: covered, gameBusy: gameBusy, reduceMotion: reduceMotion)
        }
        XCTAssertEqual(decide(), .play)
        XCTAssertEqual(decide(played: true), .none, "once per run")
        XCTAssertEqual(decide(enabled: false), .none, "tests and previews never wait for it")
        XCTAssertEqual(decide(offscreen: true), .none)
        XCTAssertEqual(decide(covered: true), .wait, "the profile picker at launch: after it")
        XCTAssertEqual(decide(covered: true, reduceMotion: true), .wait, "the picked profile's setting counts")
        XCTAssertEqual(decide(reduceMotion: true), .skip)
        XCTAssertEqual(decide(gameBusy: true), .skip, "a Steam shortcut goes straight into its game")
    }

    func testAKeyOrAButtonFinishesTheIntroAndStillDoesItsWork() throws {
        let model = try LauncherFixture.model()
        var finished = 0
        model.onInput = { finished += 1 }
        XCTAssertTrue(model.handle(.right), "the key still does what it was for")
        XCTAssertEqual(finished, 1, "a key, a button or a click finishes the animation at once")
    }

    func testOnlyTheLauncherTurnsItOn() {
        XCTAssertFalse(StartupIntro.enabled)
    }
}
