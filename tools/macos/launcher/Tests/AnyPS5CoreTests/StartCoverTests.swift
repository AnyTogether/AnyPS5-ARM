import CoreGraphics
import XCTest
@testable import AnyPS5Core

/// A game's start from its cover, as on Windows and Linux (AnyPS5 Desktop's desktop.dart and
/// game_settings.dart): Desktop's timings, the cover over the game held until the window settled
/// and then faded, let go at once when the game closes, and the Start animation setting with a
/// default for every game and a game's own choice.
final class StartCoverTests: XCTestCase {
    func testTheTimingsAreDesktops() {
        let timing = StartCoverTiming.standard
        XCTAssertEqual(timing.fade, 0.7, "coverFade")
        XCTAssertEqual(timing.reducedFade, 0.12, "the fade with reduced motion")
        XCTAssertEqual(timing.holdLimit, 6, "coverHoldLimit")
        XCTAssertEqual(timing.settle, 0.25, "coverSettle")
        XCTAssertEqual(timing.windowWait, 20, "coverWindowWait")
        XCTAssertEqual(timing.displayDelay, 1, "the second an engine that sizes its own window gets")
        XCTAssertEqual(timing.entrance, 0.45)
    }

    func testTheOpacityEasesFromOneToZero() {
        XCTAssertEqual(StartCoverTiming.opacity(sinceRelease: -0.1, fade: 0.7), 1)
        XCTAssertEqual(StartCoverTiming.opacity(sinceRelease: 0, fade: 0.7), 1)
        XCTAssertEqual(StartCoverTiming.opacity(sinceRelease: 0.35, fade: 0.7), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StartCoverTiming.opacity(sinceRelease: 0.7, fade: 0.7), 0)
        XCTAssertEqual(StartCoverTiming.opacity(sinceRelease: 2, fade: 0.7), 0)
        XCTAssertEqual(StartCoverTiming.opacity(sinceRelease: 0, fade: 0), 0, "no fade: gone at once")
        var last = 1.0
        for step in 0...70 {
            let value = StartCoverTiming.opacity(sinceRelease: Double(step) / 100, fade: 0.7)
            XCTAssertLessThanOrEqual(value, last + 0.0001, "it only ever fades")
            last = value
        }
        XCTAssertGreaterThan(StartCoverTiming.opacity(sinceRelease: 0.07, fade: 0.7), 0.95, "an ease in: slow at first")
    }

    func testTheCoverStaysOpaqueUntilTheWindowSettledThenTheSettleThenTheFade() {
        var hold = StartCoverHold(reducedMotion: false)
        XCTAssertEqual(hold.opacity(at: 0, settled: false, gone: false), 1)
        XCTAssertEqual(hold.opacity(at: 3, settled: false, gone: false), 1, "still waiting for the window")
        XCTAssertEqual(hold.opacity(at: 3.1, settled: true, gone: false), 1)
        XCTAssertEqual(hold.opacity(at: 3.35, settled: true, gone: false), 1, "the settle: its first frames are drawn")
        XCTAssertEqual(hold.opacity(at: 3.35 + 0.35, settled: true, gone: false) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertNil(hold.opacity(at: 3.35 + 0.71, settled: true, gone: false), "gone after the fade")
    }

    func testTheHoldHasALimit() {
        var hold = StartCoverHold(reducedMotion: false)
        XCTAssertEqual(hold.opacity(at: 5.9, settled: false, gone: false), 1)
        XCTAssertEqual(hold.opacity(at: 6, settled: false, gone: false), 1)
        XCTAssertEqual(hold.releaseAt ?? 0, 6.25, accuracy: 0.0001, "never more than six seconds over a window that does not settle")
        XCTAssertNil(hold.opacity(at: 7, settled: false, gone: false))
    }

    func testAGameThatClosedLetsTheCoverGoAtOnce() {
        var hold = StartCoverHold(reducedMotion: false)
        XCTAssertEqual(hold.opacity(at: 0.5, settled: false, gone: false), 1)
        XCTAssertEqual(hold.opacity(at: 1, settled: false, gone: true), 1)
        XCTAssertEqual(hold.releaseAt, 1, "no settle: straight into the fade")
        XCTAssertLessThan(hold.opacity(at: 1.2, settled: false, gone: true) ?? 0, 1)
        XCTAssertNil(hold.opacity(at: 1.71, settled: false, gone: true))
    }

    func testReducedMotionHasTheShortFade() {
        var hold = StartCoverHold(reducedMotion: true)
        XCTAssertEqual(hold.fade, 0.12)
        XCTAssertEqual(hold.opacity(at: 0, settled: true, gone: false), 1)
        XCTAssertNotNil(hold.opacity(at: 0.3, settled: true, gone: false))
        XCTAssertNil(hold.opacity(at: 0.25 + 0.121, settled: true, gone: false), "gone 120 ms after the settle")
        XCTAssertEqual(StartCoverTiming.standard.fade(reducedMotion: false), 0.7)
    }

    func testTheWindowSettlesWhenItStaysPutAfterTheDisplayDelay() {
        let began = Date()
        var settle = StartCoverSettle(began: began, delay: 1)
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        XCTAssertFalse(settle.check(nil, now: began.addingTimeInterval(2)), "no window")
        XCTAssertFalse(settle.check(frame, now: began.addingTimeInterval(2)))
        XCTAssertFalse(settle.check(frame.offsetBy(dx: 0, dy: 30), now: began.addingTimeInterval(2.1)), "it moved: going full screen")
        XCTAssertFalse(settle.check(frame.offsetBy(dx: 0, dy: 30), now: began.addingTimeInterval(2.2)))
        XCTAssertTrue(settle.check(frame.offsetBy(dx: 0, dy: 30), now: began.addingTimeInterval(2.3)), "still for two checks")
        var early = StartCoverSettle(began: began, delay: 1)
        for step in 0..<4 { XCTAssertFalse(early.check(frame, now: began.addingTimeInterval(0.1 * Double(step))), "within the display delay") }
        XCTAssertTrue(early.check(frame, now: began.addingTimeInterval(1)))
    }

    func testTheCoverGoesOnTheScreenWithMostOfTheGamesWindow() {
        // The main screen 1512 x 982, a second one to its right whose bottom is 200 points higher.
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 200, width: 1920, height: 1080)]
        XCTAssertEqual(StartCoverPlace.screen(of: CGRect(x: 0, y: 0, width: 1512, height: 982), screens: screens, primaryHeight: 982), 0)
        XCTAssertEqual(StartCoverPlace.screen(of: CGRect(x: 1512, y: -298, width: 1920, height: 1080), screens: screens, primaryHeight: 982), 1, "full screen on the second")
        XCTAssertEqual(StartCoverPlace.screen(of: CGRect(x: 1400, y: 100, width: 800, height: 600), screens: screens, primaryHeight: 982), 1, "most of it on the second")
        XCTAssertNil(StartCoverPlace.screen(of: CGRect(x: -5000, y: 0, width: 800, height: 600), screens: screens, primaryHeight: 982))
    }

    func testStartAnimationIsOnByDefaultAndWrittenOnlyWhenOff() throws {
        XCTAssertTrue(DisplayDefaults().startAnimation)
        XCTAssertTrue(GameSettings().startAnimation)
        let on = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(DisplayDefaults())) as? [String: Any])
        XCTAssertNil(on["startAnimation"], "on is not written, as on Windows and Linux")
        let off = DisplayDefaults(startAnimation: false)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(off)) as? [String: Any])
        XCTAssertEqual(written["startAnimation"] as? Bool, false)
        XCTAssertEqual(try JSONDecoder().decode(DisplayDefaults.self, from: JSONEncoder().encode(off)), off)
        XCTAssertFalse(off.isBuiltIn)
        let older = try JSONDecoder().decode(DisplayDefaults.self, from: Data(#"{"fullscreen":true,"windowSize":75,"vsync":true}"#.utf8))
        XCTAssertTrue(older.startAnimation, "a file from before it is on")
        let odd = try JSONDecoder().decode(DisplayDefaults.self, from: Data(#"{"startAnimation":"no"}"#.utf8))
        XCTAssertTrue(odd.startAnimation, "a value of the wrong kind is the built-in one")
    }

    func testAGamesOwnOffWinsOverTheDefaultOn() throws {
        var settings = GameSettings()
        XCTAssertTrue(settings.followsDisplayDefaults)
        settings.ownStartAnimation = false
        XCTAssertFalse(settings.followsDisplayDefaults)
        let started = settings.withDefaults(DisplayDefaults(fullscreen: true, startAnimation: true))
        XCTAssertFalse(started.startAnimation, "the game's own Off")
        XCTAssertFalse(started.fadesCover, "nothing fades over the game")
        let following = GameSettings().withDefaults(DisplayDefaults(fullscreen: true, startAnimation: true))
        XCTAssertTrue(following.startAnimation)
        XCTAssertTrue(following.fadesCover, "full screen with its cover: it fades over the game")
        XCTAssertFalse(GameSettings().withDefaults(DisplayDefaults(fullscreen: false)).fadesCover, "in a window the cover goes on the home screen")
        var own = GameSettings()
        own.ownStartAnimation = true
        XCTAssertTrue(own.withDefaults(DisplayDefaults(startAnimation: false)).startAnimation, "the game's own On wins over the default Off")
        XCTAssertNil(settings.followingDisplayDefaults().ownStartAnimation)
        XCTAssertTrue(settings.followingDisplayDefaults().followsDisplayDefaults)
    }

    func testAGamesChoiceIsWrittenUnderDesktopsKey() throws {
        var settings = GameSettings()
        settings.ownStartAnimation = false
        for legacy in [false, true] {
            let encoder = JSONEncoder()
            if legacy { encoder.userInfo[GameSettings.legacyDisplayKeys] = true }
            let data = try encoder.encode(settings)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["startAnimation"] as? Bool, false)
            XCTAssertEqual(try JSONDecoder().decode(GameSettings.self, from: data), settings)
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(GameSettings())) as? [String: Any])
        XCTAssertNil(json["startAnimation"], "a game that follows the default writes nothing")
        let older = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"fullscreen":false,"windowSize":75,"vsync":true,"overlay":"off"}"#.utf8))
        XCTAssertNil(older.ownStartAnimation)
    }
}
