import AnyPS5Core
import AVFoundation

/// The host's game sound on a viewer's Mac: StreamPacket audio from the "audio" channel through a
/// small jitter buffer (about 50 ms) into the output device. No microphone, no voice processing.
public final class SharePlaySpeaker: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let buffer = Locked(SoundJitterBuffer())
    private var source: AVAudioSourceNode?
    private let volume = Locked<Float>(1)

    public init() {}

    /// 0 (muted) to 1.
    public var level: Float {
        get { volume.value }
        set { volume.value = max(0, min(1, newValue)) }
    }

    public func start() throws {
        guard source == nil, let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return }
        let buffer = buffer, volume = volume
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let samples = buffer.withLock { $0.pull(frames) }
            let gain = volume.value / 32768
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard list.count >= 2, let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for frame in 0 ..< frames {
                left[frame] = Float(samples[frame * 2]) * gain
                right[frame] = Float(samples[frame * 2 + 1]) * gain
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
    }
}
