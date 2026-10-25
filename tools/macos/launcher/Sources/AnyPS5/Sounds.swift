import AVFoundation

/// Soft interface sounds, synthesized once: a short tick for moving (a quieter one when the
/// pointer arrives on something), a rising pair for selecting, a falling one for going back and a
/// low, dull knock when a direction has nowhere to go.
@MainActor
final class Sounds {
    static let shared = Sounds()

    enum Cue: String { case move, select, back, unlocked, ring, bump, hover }

    var enabled = true
    /// Every cue asked for, sounds on or off: a command that asked for none and changed nothing
    /// did nothing (Input's edge bump).
    private(set) var requests = 0
    /// When the last cue other than the hover tick played (system uptime).
    private(set) var lastCue: TimeInterval?
    /// 0 to 1, on top of the sounds' own soft level.
    var volume: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = 0.32 * volume }
    }
    private let engine = AVAudioEngine()
    private let players: [AVAudioPlayerNode]
    private var next = 0
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var started = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private init() {
        players = (0..<4).map { _ in AVAudioPlayerNode() }
        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.32
        buffers[.move] = tone([(1320, 0.0, 0.045)], decay: 70)
        buffers[.select] = tone([(880, 0.0, 0.07), (1320, 0.05, 0.1)], decay: 32)
        buffers[.back] = tone([(990, 0.0, 0.06), (660, 0.045, 0.09)], decay: 34)
        buffers[.unlocked] = tone([(660, 0.0, 0.12), (990, 0.09, 0.14), (1320, 0.18, 0.3)], decay: 12)
        // A friend calling: two soft trills.
        buffers[.ring] = tone([(988, 0.0, 0.11), (1319, 0.1, 0.11), (988, 0.2, 0.11), (1319, 0.3, 0.16)], decay: 5)
        // The end of a row: B3 and a fast decay, the quietest cue.
        buffers[.bump] = tone([(247, 0.0, 0.06)], decay: 55, gain: 0.6)
        // The pointer on something new: the move tick, about 3 dB lower.
        buffers[.hover] = tone([(1320, 0.0, 0.045)], decay: 70, gain: 0.7)
    }

    func play(_ cue: Cue) {
        requests += 1
        Feel.shared.sound(cue)
        if cue != .hover { lastCue = ProcessInfo.processInfo.systemUptime }
        guard enabled, let buffer = buffers[cue] else { return }
        if !started {
            do { try engine.start() } catch { return }
            started = true
        }
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    /// Sine partials (frequency, start, length in seconds) with an exponential decay.
    private func tone(_ partials: [(Double, Double, Double)], decay: Double, gain: Double = 1) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let length = partials.map { $0.1 + $0.2 }.max() ?? 0.1
        let frames = AVAudioFrameCount(rate * (length + 0.02))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else { return nil }
        for frame in 0..<Int(frames) {
            let time = Double(frame) / rate
            var sample = 0.0
            for (frequency, start, duration) in partials where time >= start && time < start + duration {
                let local = time - start
                let attack = min(1, local / 0.004)
                sample += sin(2 * .pi * frequency * local) * attack * exp(-local * decay) * 0.5
                sample += sin(4 * .pi * frequency * local) * attack * exp(-local * decay * 1.6) * 0.12
            }
            left[frame] = Float(sample * gain)
            right[frame] = Float(sample * gain)
        }
        return buffer
    }
}
