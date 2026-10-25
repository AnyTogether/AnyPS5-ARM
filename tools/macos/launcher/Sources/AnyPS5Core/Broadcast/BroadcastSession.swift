import CoreVideo
import Foundation

/// One broadcast from start to stop: the game's frames through BroadcastVideoEncoder, its sound
/// (and the microphone's) through the mixer and AACEncoder, both on one clock to RTMPPublisher;
/// and what the launcher shows meanwhile: the state, how long it has been live, the bit rate
/// going out and the frames dropped.
public final class BroadcastSession: @unchecked Sendable {
    public struct Stats: Equatable, Sendable {
        public var state: RTMPPublisher.State = .connecting
        /// Seconds since the broadcast first went live.
        public var duration: Double = 0
        /// Bits a second going out, over the last few seconds.
        public var bitRate: Int = 0
        public var framesSent = 0
        /// Frames the network could not take.
        public var framesDropped = 0
        public var reconnects = 0

        public init() {}

        public var droppedPercent: Double {
            let total = framesSent + framesDropped
            return total == 0 ? 0 : Double(framesDropped) / Double(total) * 100
        }
    }

    public let quality: BroadcastSettings.Quality
    private let publisher: RTMPPublisher
    private let video: BroadcastVideoEncoder
    private let audio: AACEncoder?
    private let audioQueue = DispatchQueue(label: "org.anyps5.broadcast.audio", qos: .userInitiated)
    private let lock = NSLock()
    private var state = RTMPPublisher.State.connecting
    private var liveSince: Date?
    private var mixer = BroadcastAudioMixer()
    private var samples: [(time: Date, bytes: UInt64)] = []
    private let onState: @Sendable (RTMPPublisher.State) -> Void

    public init(endpoint: RTMPEndpoint, quality: BroadcastSettings.Quality, options: RTMPPublisher.Options? = nil,
                onState: @escaping @Sendable (RTMPPublisher.State) -> Void = { _ in }) {
        self.quality = quality
        self.onState = onState
        var tuned = options ?? RTMPPublisher.Options()
        tuned.bitRate = quality.bitRate + BroadcastSettings.audioBitRate
        let metadata = FLV.metadata(width: quality.width, height: quality.height, frameRate: quality.frameRate,
                                    videoBitRate: quality.bitRate, audioBitRate: BroadcastSettings.audioBitRate)
        let wanted = Locked<BroadcastVideoEncoder?>(nil)
        let state = Locked<(RTMPPublisher.State) -> Void>({ _ in })
        publisher = RTMPPublisher(endpoint: endpoint, metadata: metadata, options: tuned,
                                  onState: { new in state.value(new) }, wantKeyFrame: { wanted.value?.wantKey() })
        let publisher = self.publisher
        let clock = Locked<Double?>(nil)
        video = BroadcastVideoEncoder(bitRate: quality.bitRate, frameRate: quality.frameRate) { frame in
            guard let start = clock.value else { return }
            publisher.sendVideo(frame.units, key: frame.key, milliseconds: BroadcastSession.milliseconds(frame.seconds, since: start), parameterSets: frame.parameterSets)
        }
        audio = try? AACEncoder(sampleRate: BroadcastAudioMixer.sampleRate, channels: 2, bitRate: BroadcastSettings.audioBitRate)
        if let audio { publisher.setAudioConfig(audio.audioSpecificConfig) }
        wanted.value = video
        self.clock = clock
        state.value = { [weak self] new in self?.changed(new) }
    }

    private let clock: Locked<Double?>

    static func milliseconds(_ seconds: Double, since start: Double) -> UInt32 {
        UInt32(max(0, (seconds - start) * 1000).rounded())
    }

    public func start() {
        publisher.start()
    }

    public func stop(then done: (@Sendable () -> Void)? = nil) {
        publisher.stop(then: done)
    }

    /// The microphone's level, 0 for off, to 1.
    public var microphoneLevel: Float {
        get { audioQueue.sync { mixer.microphoneLevel } }
        set { audioQueue.async { self.mixer.microphoneLevel = max(0, min(1, newValue)) } }
    }

    /// A frame of the game at `seconds` (the capture's clock, the sound's too).
    public func video(_ pixels: CVPixelBuffer, at seconds: Double) {
        startClock(seconds)
        video.encode(pixels, at: seconds)
    }

    /// The game's sound, interleaved 48 kHz stereo, its first frame at `seconds`.
    public func gameAudio(_ samples: [Float], at seconds: Double) {
        startClock(seconds)
        audioQueue.async { [self] in send(mixer.addGame(samples, at: seconds)) }
    }

    /// The microphone, interleaved 48 kHz stereo, at `seconds`.
    public func microphone(_ samples: [Float], at seconds: Double) {
        audioQueue.async { [self] in send(mixer.addMicrophone(samples, at: seconds)) }
    }

    private func startClock(_ seconds: Double) {
        clock.withLock { if $0 == nil { $0 = seconds } }
    }

    private func send(_ blocks: [BroadcastAudioMixer.Block]) {
        guard let audio, let start = clock.value else { return }
        for block in blocks {
            for frame in audio.encode(block.samples, at: block.seconds) where frame.seconds >= start {
                publisher.sendAudio(frame.data, milliseconds: BroadcastSession.milliseconds(frame.seconds, since: start))
            }
        }
    }

    private func changed(_ new: RTMPPublisher.State) {
        lock.withLock {
            state = new
            if new == .live, liveSince == nil { liveSince = Date() }
        }
        onState(new)
    }

    /// What the launcher shows; `now` for tests.
    public func stats(now: Date = Date()) -> Stats {
        let sent = publisher.stats
        return lock.withLock {
            samples.append((now, sent.bytesSent))
            samples.removeAll { now.timeIntervalSince($0.time) > 3 }
            var stats = Stats()
            stats.state = state
            stats.duration = liveSince.map { now.timeIntervalSince($0) } ?? 0
            if let first = samples.first, now.timeIntervalSince(first.time) > 0.2 {
                stats.bitRate = Int(Double(sent.bytesSent - first.bytes) * 8 / now.timeIntervalSince(first.time))
            }
            stats.framesSent = sent.videoSent
            stats.framesDropped = sent.videoDropped
            stats.reconnects = sent.reconnects
            return stats
        }
    }
}
