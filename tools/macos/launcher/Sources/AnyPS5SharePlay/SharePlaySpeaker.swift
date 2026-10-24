import AnyPS5Core
import AVFoundation

/// The host's game sound on a viewer's Mac, into the output device: the Opus track as WebRTC
/// decodes it (pulled from ShareWebRTC.audioDevice, its jitter buffer WebRTC's own), plus
/// StreamPacket audio from the "audio" channel (hosts without the track) through a small jitter
/// buffer (about 50 ms). No microphone, no voice processing.
public final class SharePlaySpeaker: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let buffer = Locked(SoundJitterBuffer())
    private var source: AVAudioSourceNode?
    private let volume = Locked<Float>(1)
    private var track: UnsafeMutablePointer<Int16>?

    public init() {}

    /// 0 (muted) to 1.
    public var level: Float {
        get { volume.value }
        set { volume.value = max(0, min(1, newValue)) }
    }

    public func start() throws {
        guard source == nil, let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return }
        let buffer = buffer, volume = volume, device = ShareWebRTC.audioDevice
        // The track's samples, pulled on the output's thread: room for any buffer the device asks.
        let track = UnsafeMutablePointer<Int16>.allocate(capacity: 16384 * 2)
        self.track = track
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let samples = buffer.withLock { $0.pull(frames) }
            let gain = volume.value / 32768
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard list.count >= 2, let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            if frames <= 16384, device.isPlaying, device.pull(track, frames: UInt32(frames)) {
                for frame in 0 ..< frames {
                    left[frame] = (Float(samples[frame * 2]) + Float(track[frame * 2])) * gain
                    right[frame] = (Float(samples[frame * 2 + 1]) + Float(track[frame * 2 + 1])) * gain
                }
            } else {
                for frame in 0 ..< frames {
                    left[frame] = Float(samples[frame * 2]) * gain
                    right[frame] = Float(samples[frame * 2 + 1]) * gain
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.source = source
    }

    /// A packet from the host, from WebRTC's thread.
    public func play(_ packet: Data) {
        buffer.withLock { $0.push(packet) }
    }

    public func stop() {
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        track?.deallocate()
        track = nil
    }
}
