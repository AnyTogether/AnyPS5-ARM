import CoreGraphics
import XCTest
@testable import AnyPS5Core

final class KeyRepeatTests: XCTestCase {
    func testAHeldDirectionWaitsThenRepeatsThenSpeedsUpALittle() {
        XCTAssertEqual(KeyRepeat.delay(beforeRepeat: 1), 0.40, accuracy: 1e-9)
        for repeatNumber in 2...KeyRepeat.fastAfter { XCTAssertEqual(KeyRepeat.delay(beforeRepeat: repeatNumber), 0.08, accuracy: 1e-9) }
        XCTAssertEqual(KeyRepeat.delay(beforeRepeat: KeyRepeat.fastAfter + 1), 0.06, accuracy: 1e-9)
        XCTAssertEqual(KeyRepeat.delay(beforeRepeat: 40), 0.06, accuracy: 1e-9)
    }

    func testAOneSecondHoldMovesThePaceOfAConsoleMenu() {
        let times = KeyRepeat.times(within: 1.0)
        // The press itself at 0, then 0.40, 0.48 ... 0.80, 0.86, 0.92, 0.98.
        XCTAssertEqual(times.first ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(times[1], 0.40, accuracy: 1e-9)
        XCTAssertEqual(times.count, 1 + 1 + 5 + 3)
        XCTAssertTrue(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertTrue(KeyRepeat.times(within: 0.39).count == 1, "a tap is one move")
    }
}

final class StickGateTests: XCTestCase {
    func testItEngagesPastHalfAndLetsGoOnlyBelowAThird() {
        var stick = StickGate()
        XCTAssertNil(stick.update(x: 0.45, y: 0))
        XCTAssertEqual(stick.update(x: 0.52, y: 0), .right)
        // A resting stick near the threshold does not flicker.
        for x in [0.48, 0.41, 0.35, 0.31, 0.44] { XCTAssertEqual(stick.update(x: x, y: 0), .right, "x \(x)") }
        XCTAssertNil(stick.update(x: 0.29, y: 0))
        XCTAssertNil(stick.update(x: 0.45, y: 0), "below the engage line again after letting go")
    }

    func testUpIsPositiveAndTheBiggerAxisWinsAtFirst() {
        var stick = StickGate()
        XCTAssertEqual(stick.update(x: 0.3, y: 0.6), .up)
        stick = StickGate()
        XCTAssertEqual(stick.update(x: -0.7, y: -0.6), .left)
        stick = StickGate()
        XCTAssertEqual(stick.update(x: 0.1, y: -0.9), .down)
    }

    func testTheOtherAxisTakesOverOnlyWhenItClearlyLeads() {
        var stick = StickGate()
        XCTAssertEqual(stick.update(x: 0.7, y: 0), .right)
        // Near the diagonal the held direction stays.
        XCTAssertEqual(stick.update(x: 0.6, y: 0.7), .right)
        XCTAssertEqual(stick.update(x: 0.5, y: 0.7), .up, "0.7 is more than 1.25 × 0.5")
    }

    func testAFlickThroughTheMiddleTurnsAtOnce() {
        var stick = StickGate()
        XCTAssertEqual(stick.update(x: 0.9, y: 0), .right)
        XCTAssertEqual(stick.update(x: -0.8, y: 0), .left)
        XCTAssertEqual(stick.update(x: 0, y: 0), nil)
    }
}

final class EdgeBumpTests: XCTestCase {
    func testAMoveIntoTheWallBumpsOncePerHold() {
        var edge = EdgeBump()
        XCTAssertFalse(edge.handled(.right, repeat: false, changed: true))
        XCTAssertFalse(edge.handled(.right, repeat: true, changed: true))
        XCTAssertTrue(edge.handled(.right, repeat: true, changed: false), "the hold reached the last tile")
        XCTAssertFalse(edge.handled(.right, repeat: true, changed: false), "silent for the rest of the hold")
        XCTAssertTrue(edge.handled(.right, repeat: false, changed: false), "a new press against the wall")
    }

    func testOnlyDirectionsBump() {
        var edge = EdgeBump()
        for command in [Command.select, .back, .options, .previousGame, .nextGame, .home, .capture] {
            XCTAssertFalse(edge.handled(command, repeat: false, changed: false), "\(command)")
        }
        for command in [Command.left, .right, .up, .down] {
            XCTAssertTrue(edge.handled(command, repeat: false, changed: false), "\(command)")
        }
    }
}

final class HoverGateTests: XCTestCase {
    private func arrive(_ gate: inout HoverGate, _ id: String, x: CGFloat, at now: TimeInterval, lastCue: TimeInterval? = nil,
                        buttons: Bool = false, allowed: Bool = true) -> Bool {
        gate.arrive(id, pointer: CGPoint(x: x, y: 10), now: now, lastCue: lastCue, buttonsDown: buttons, allowed: allowed)
    }

    func testOneTickPerArrivalOnANewElement() {
        var gate = HoverGate()
        XCTAssertTrue(arrive(&gate, "tile-1", x: 10, at: 1.0))
        XCTAssertFalse(arrive(&gate, "tile-1", x: 30, at: 1.5), "still on the same tile")
        XCTAssertTrue(arrive(&gate, "tile-2", x: 60, at: 2.0))
        gate.leave("tile-2")
        XCTAssertTrue(arrive(&gate, "tile-2", x: 70, at: 2.5), "back on it after leaving it")
    }

    func testOnlyRealPointerMovementTicks() {
        var gate = HoverGate()
        XCTAssertTrue(arrive(&gate, "row-1", x: 10, at: 1.0))
        // The list scrolled under a resting pointer.
        XCTAssertFalse(arrive(&gate, "row-2", x: 10, at: 1.5))
        XCTAssertTrue(arrive(&gate, "row-3", x: 14, at: 2.0))
    }

    func testRateLimitedAndNeverLate() {
        var gate = HoverGate()
        XCTAssertTrue(arrive(&gate, "a", x: 0, at: 1.000))
        XCTAssertFalse(arrive(&gate, "b", x: 20, at: 1.030), "inside 60 ms")
        XCTAssertTrue(arrive(&gate, "c", x: 40, at: 1.070))
        XCTAssertFalse(arrive(&gate, "d", x: 60, at: 1.200, lastCue: 1.150), "within 90 ms of another sound")
        XCTAssertTrue(arrive(&gate, "e", x: 80, at: 1.300, lastCue: 1.150))
    }

    func testQuietWithAButtonHeldOrWhenNotAllowed() {
        var gate = HoverGate()
        XCTAssertFalse(arrive(&gate, "a", x: 0, at: 1.0, buttons: true))
        XCTAssertFalse(arrive(&gate, "b", x: 20, at: 2.0, allowed: false), "sounds off, a game in front or the launcher behind")
        XCTAssertTrue(arrive(&gate, "c", x: 40, at: 3.0))
    }
}

final class HapticTests: XCTestCase {
    final class FakeOutput: HapticOutput {
        var played: [[HapticPulse]] = []
        var stops = 0
        func play(_ pulses: [HapticPulse]) { played.append(pulses) }
        func stop() { stops += 1 }
    }

    private func peak(_ cue: HapticCue) -> Double { HapticPatterns.pulses(for: cue).map { max($0.strong, $0.weak) }.max() ?? 0 }

    func testThePatternsAreSoftShortAndOrdered() {
        XCTAssertLessThan(peak(.edge), peak(.back))
        XCTAssertLessThan(peak(.back), peak(.select))
        XCTAssertLessThan(peak(.select), peak(.error))
        XCTAssertEqual(HapticPatterns.pulses(for: .error).count, 2)
        XCTAssertEqual(HapticPatterns.pulses(for: .trophy).count, 3)
        let trophy = HapticPatterns.pulses(for: .trophy).map { max($0.strong, $0.weak) }
        XCTAssertEqual(trophy, trophy.sorted(), "the trophy's taps swell")
        let ring = HapticPatterns.pulses(for: .ring)
        XCTAssertGreaterThan(ring[0].strong, ring[1].strong, "a heavy beat, then a light one")
        for cue in HapticCue.allCases {
            let pulses = HapticPatterns.pulses(for: cue)
            XCTAssertFalse(pulses.isEmpty, "\(cue)")
            XCTAssertLessThanOrEqual(pulses.last.map { $0.start + $0.length } ?? 1, 0.4, "\(cue) is short")
            for pulse in pulses {
                XCTAssertTrue((0...1).contains(pulse.strong) && (0...1).contains(pulse.weak), "\(cue)")
                XCTAssertLessThanOrEqual(max(pulse.strong, pulse.weak), 0.75, "\(cue) stays soft")
                XCTAssertGreaterThan(pulse.length, 0)
            }
            for (a, b) in zip(pulses, pulses.dropFirst()) { XCTAssertLessThanOrEqual(a.start + a.length, b.start, "\(cue) pulses do not overlap") }
        }
        XCTAssertLessThanOrEqual(HapticPatterns.pulses(for: .edge)[0].length, 0.015, "the bump is barely there")
    }

    func testItPlaysOnlyForAPadInUseWithTheLauncherInFront() {
        let output = FakeOutput()
        let haptics = HapticFeedback(output: output)
        XCTAssertFalse(haptics.play(.select, now: 1), "the keyboard was used last")
        haptics.padInUse = true
        XCTAssertTrue(haptics.play(.select, now: 2))
        XCTAssertEqual(output.played, [HapticPatterns.pulses(for: .select)])
        haptics.launcherInFront = false
        XCTAssertEqual(output.stops, 1, "a game came in front: the motors stop at once")
        XCTAssertFalse(haptics.play(.trophy, now: 3), "the game owns the pad")
        haptics.launcherInFront = true
        haptics.enabled = false
        XCTAssertEqual(output.stops, 2)
        XCTAssertFalse(haptics.play(.ring, now: 4), "Controller vibration is off")
        haptics.enabled = true
        XCTAssertTrue(haptics.play(.ring, now: 5))
        XCTAssertEqual(output.played.count, 2)
    }

    func testTheSameCueTwiceInOneStepPlaysOnce() {
        let output = FakeOutput()
        let haptics = HapticFeedback(output: output)
        haptics.padInUse = true
        XCTAssertTrue(haptics.play(.select, now: 1.000))
        XCTAssertFalse(haptics.play(.select, now: 1.010))
        XCTAssertTrue(haptics.play(.back, now: 1.015))
        XCTAssertTrue(haptics.play(.select, now: 1.100))
    }

    func testTheSoundCuesThatVibrate() {
        XCTAssertEqual(HapticCue(sound: "select"), .select)
        XCTAssertEqual(HapticCue(sound: "back"), .back)
        XCTAssertEqual(HapticCue(sound: "bump"), .edge)
        XCTAssertNil(HapticCue(sound: "move"), "moving the focus has none")
        XCTAssertNil(HapticCue(sound: "hover"))
        XCTAssertNil(HapticCue(sound: "unlocked"), "a notice's chime is not a trophy: trophies are told on their own")
    }
}
