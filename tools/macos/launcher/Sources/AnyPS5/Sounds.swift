import AVFoundation
import AnyPS5Core

/// Soft interface sounds, synthesized once (Tones): low and round, a short one for moving (a
/// quieter one when the pointer arrives on something), a rising pair for selecting, a falling one
/// for going back and a low, dull knock when a direction has nowhere to go.
@MainActor
final class Sounds {
    static let shared = Sounds()

    typealias Cue = SoundCue

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
        for cue in Cue.allCases {
            buffers[cue] = buffer(Tones.render(cue, rate: format.sampleRate))
        }
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

    /// Mono samples on both sides.
    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else { return nil }
        for (frame, sample) in samples.enumerated() {
            left[frame] = sample
            right[frame] = sample
        }
        return buffer
    }
}
