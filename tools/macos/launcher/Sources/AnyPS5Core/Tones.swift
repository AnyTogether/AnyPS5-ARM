import Foundation

/// The launcher's interface sounds: `bump` when a direction has nowhere to go, `hover` when the
/// pointer arrives on something.
public enum SoundCue: String, CaseIterable, Sendable { case move, select, back, unlocked, ring, bump, hover }

/// Soft interface sounds, synthesized: a short one for moving, a rising pair for selecting, a
/// falling one for going back, a rising three for something finished and two trills for a call.
/// Shaped after the PS5's own: low and round, nearly everything under 1 kHz, built on F4 (349 Hz)
/// with its octave below, a gentle rise and a soft fall, so no click and nothing sharp. The Windows
/// and Linux launcher's tones (AnyPS5-Desktop's tones.dart), sample for sample.
public enum Tones {
    public static let sampleRate = 44_100.0

    /// How long a partial takes to reach its full level, in seconds: a rounded rise, not a tick.
    public static let attack = 0.016

    /// How long the end of a partial takes to fall to silence, so it never stops with a click.
    public static let release = 0.012

    /// One sine of a cue: its frequency, when it starts and how long it lasts, in seconds.
    public typealias Partial = (frequency: Double, start: Double, length: Double)

    /// Each cue's partials and how fast they die away. The notes are F4 (349 Hz), A4 (440 Hz) and C5
    /// (523 Hz); the quietest cue is an octave lower.
    public static let recipes: [SoundCue: (partials: [Partial], decay: Double)] = [
        .move: ([(349, 0.0, 0.11)], 26),
        .select: ([(349, 0.0, 0.13), (523, 0.06, 0.2)], 15),
        .back: ([(523, 0.0, 0.12), (349, 0.06, 0.2)], 15),
        .unlocked: ([(349, 0.0, 0.2), (440, 0.12, 0.22), (523, 0.24, 0.6)], 6),
        // A friend calling: two soft trills.
        .ring: ([(440, 0.0, 0.16), (523, 0.14, 0.16), (440, 0.28, 0.16), (523, 0.42, 0.26)], 5),
        // The end of a row: F3 and a fast decay, the quietest cue.
        .bump: ([(175, 0.0, 0.11)], 38),
        // The pointer on something new: the move sound, about 3 dB lower.
        .hover: ([(349, 0.0, 0.11)], 26),
    ]

    /// How loud each cue is against the others (1 for the rest).
    public static let gains: [SoundCue: Double] = [.bump: 0.6, .hover: 0.7]

    /// The cue as mono samples at `rate`.
    public static func render(_ cue: SoundCue, rate: Double = sampleRate) -> [Float] {
        guard let (partials, decay) = recipes[cue] else { return [] }
        let samples = synthesize(partials, decay: decay, rate: rate)
        let gain = gains[cue] ?? 1
        return gain == 1 ? samples : samples.map { Float(Double($0) * gain) }
    }

    /// Sine partials with a rounded `attack` and a soft `release`, an exponential decay, the octave
    /// below that dies away a little slower (the body) and a quiet octave above that dies away
    /// faster; 20 ms of silence after the last one ends.
    public static func synthesize(_ partials: [Partial], decay: Double, rate: Double = sampleRate) -> [Float] {
        let length = partials.map { $0.start + $0.length }.max() ?? 0.1
        let frames = Int((rate * (length + 0.02)).rounded(.down))
        var samples = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            let time = Double(frame) / rate
            var sample = 0.0
            for (frequency, start, duration) in partials where time >= start && time < start + duration {
                let local = time - start
                let rise = sin(.pi / 2 * min(1, local / attack))
                let shape = rise * rise * min(1, (duration - local) / release)
                let main = sin(2 * .pi * frequency * local) * exp(-local * decay) * 0.46
                let body = sin(.pi * frequency * local) * exp(-local * decay * 0.8) * 0.28
                let air = sin(4 * .pi * frequency * local) * exp(-local * decay * 1.8) * 0.08
                sample += (main + body + air) * shape
            }
            samples[frame] = Float(sample)
        }
        return samples
    }
}
