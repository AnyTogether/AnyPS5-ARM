import Foundation
import XCTest
@testable import AnyPS5Core

/// The interface sounds as Windows and Linux make them (AnyPS5-Desktop's interface_sounds_test.dart):
/// the same lengths, the same samples, a rounded rise, a silent end and almost nothing above 1 kHz.
final class TonesTests: XCTestCase {
    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    func testEveryCueIsAsLongAsItsPartialsAnd20msMoreAsOnWindowsAndLinux() {
        let lengths = Dictionary(uniqueKeysWithValues: SoundCue.allCases.map { ($0, Tones.render($0).count) })
        XCTAssertEqual(lengths, [.move: 5733, .select: 12348, .back: 12348, .unlocked: 37926, .ring: 30869, .bump: 5733, .hover: 5733])
    }

    func testTheSampleValuesF4WithItsOctaveBelowAndAboveARounded16msRiseAFastDecay() {
        let move = Tones.render(.move)
        XCTAssertEqual(move[0], 0)
        // 10 ms in: 349 Hz, the octave below it (the body) and the octave above it (a trace).
        let time = 441.0 / 44_100
        let rise: Double = sin(Double.pi / 2 * time / 0.016)
        let main: Double = sin(2 * Double.pi * 349 * time) * exp(-time * 26) * 0.46
        let body: Double = sin(Double.pi * 349 * time) * exp(-time * 26 * 0.8) * 0.28
        let air: Double = sin(4 * Double.pi * 349 * time) * exp(-time * 26 * 1.8) * 0.08
        let expected = (main + body + air) * rise * rise
        XCTAssertEqual(Double(move[441]), expected, accuracy: 1e-6)
    }

    func testNoCueClipsEachRisesWithinItsAttackDiesAwayAndEndsInSilence() {
        for cue in SoundCue.allCases {
            let samples = Tones.render(cue)
            let peak = samples.map(abs).max() ?? 0
            XCTAssertLessThan(peak, 1, "\(cue)")
            XCTAssertGreaterThan(peak, 0.2, "\(cue)")
            // The first 16 ms stay under the attack's line: a rounded rise, no click.
            let frames = 705
            let gain = Tones.gains[cue] ?? 1
            for frame in 0..<frames {
                let rise: Double = sin(Double.pi / 2 * Double(frame) / Double(frames))
                XCTAssertLessThanOrEqual(Double(abs(samples[frame])), 0.82 * gain * rise * rise + 1e-6, "\(cue) at \(frame)")
            }
            // The last 20 ms are silent.
            XCTAssertTrue(samples.suffix(880).allSatisfy { $0 == 0 }, "\(cue)")
            // Each cue is quieter in its second half than in its first.
            let half = samples.count / 2
            XCTAssertLessThan(rms(samples[half...]), rms(samples[..<half]) * 0.9, "\(cue)")
        }
    }

    func testSoftAndDeepLikeThePS5AlmostAllOfEveryCueIsUnder1kHzNoneAbove2kHz() {
        for cue in SoundCue.allCases {
            let samples = Tones.render(cue)
            var total = 0.0
            var low = 0.0
            var high = 0.0
            // A direct Fourier sum over the bins from 50 Hz to 4 kHz in 25 Hz steps.
            for frequency in stride(from: 50.0, through: 4000, by: 25) {
                var re = 0.0
                var im = 0.0
                for (frame, sample) in samples.enumerated() {
                    let angle: Double = 2 * Double.pi * frequency * Double(frame) / Tones.sampleRate
                    re += Double(sample) * cos(angle)
                    im += Double(sample) * sin(angle)
                }
                let power = re * re + im * im
                total += power
                if frequency < 1000 { low += power }
                if frequency >= 2000 { high += power }
            }
            XCTAssertGreaterThan(low / total, 0.97, "\(cue)")
            XCTAssertLessThan(high / total, 0.001, "\(cue)")
        }
    }

    func testTheQuietCuesAreTheLoudOnesAtTheirGain() {
        let move = Tones.render(.move)
        let hover = Tones.render(.hover)
        XCTAssertEqual(move.count, hover.count)
        for frame in stride(from: 0, to: move.count, by: 37) {
            XCTAssertEqual(Double(hover[frame]), Double(move[frame]) * 0.7, accuracy: 1e-6)
        }
    }
}
