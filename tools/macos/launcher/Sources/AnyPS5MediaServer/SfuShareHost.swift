import AnyPS5Core
import AVFoundation
import CoreVideo
import Foundation
import LiveKit

/// The host's side of a share play through the media server: the captured game published once
/// to the room as the video track "game" (H.264, 720p60, simulcast so the media server can send
/// smaller layers to viewers on a slow line), and the game's sound (16-bit stereo in) as the Opus track
/// "game-audio", fed by hand into LiveKit's audio engine without a device. Viewers holding a pad
/// keep the direct mesh connection (SharePlayHost); everyone else watches from here.
@MainActor
public final class SfuShareHost {
    public enum State: Equatable, Sendable {
        case connecting, connected, failed(String), closed
    }

    public private(set) var state: State = .connecting {
        didSet { if state != oldValue { changed() } }
    }

    private let room = Room()
    private let changed: () -> Void
    /// The video track's capturer, for the capture's thread.
    private let capturer = Locked<BufferCapturer?>(nil)
    private let framed = Locked(false)
    /// The game sound, gathered into 20 ms blocks while it is published.
    private let sound = Locked<SfuSoundBlocks?>(nil)
    private var video: LocalVideoTrack?
    private var audio: LocalTrackPublication?
    private var soundWanted = false
    private var soundChanging: Task<Void, Never>?

    public init(changed: @escaping () -> Void = {}) {
        self.changed = changed
    }

    /// Into the room with the host's token, then the picture published (once a first frame came:
    /// LiveKit needs its size) and the sound as the audio engine allows.
    public func start(_ access: TogetherSfuAccess) async throws {
        state = .connecting
        do {
            try await room.connect(url: access.url, token: access.token, roomOptions: RoomOptions(dynacast: true))
            let track = await LocalVideoTrack.createBufferTrack(name: SfuTrackNames.video, source: .camera,
                                                                options: BufferCaptureOptions(dimensions: .h720_169, fps: 60))
            capturer.value = track.capturer as? BufferCapturer
            video = track
            for _ in 0 ..< 100 where !framed.value { try await Task.sleep(for: .milliseconds(100)) }
            try await room.localParticipant.publish(videoTrack: track, options: SfuShareHost.videoOptions)
            state = .connected
            await SfuAudio.shared.hosting(self)
        } catch {
            state = .failed(String(describing: error))
            throw error
        }
    }

    /// 720p60 at up to 4.5 Mbit/s on H.264 (the Mac's media engine), with the smaller simulcast
    /// layers LiveKit makes; frame rate kept before resolution, as a game wants it.
    static let videoOptions = VideoPublishOptions(name: SfuTrackNames.video, encoding: VideoEncoding(maxBitrate: 4_500_000, maxFps: 60), simulcast: true,
                                                  preferredCodec: .h264, degradationPreference: .maintainFramerate, streamName: "game")

    /// Music, not speech: 128 kbit/s, no DTX (silence in a game is part of it), no RED.
    static let audioOptions = AudioPublishOptions(name: SfuTrackNames.audio, encoding: AudioEncoding(maxBitrate: 128_000), dtx: false, red: false,
                                                  streamName: "game-sound")

    /// A captured frame (NV12 or BGRA), from the capture's own thread.
    public nonisolated func push(_ pixels: CVPixelBuffer, timeNs: Int64) {
        guard let capturer = capturer.value else { return }
        capturer.capture(pixels, timeStampNs: timeNs)
        if !framed.value { framed.value = true }
    }

    /// The game's sound as StreamPacket audio (16-bit stereo at 48 kHz), from the capture's
    /// thread: into the room's audio track in 20 ms blocks while it is published.
    public nonisolated func push(sound packet: Data) {
        guard let audio = StreamPacket.Audio(packet), audio.payload.count >= 4 else { return }
        let samples = audio.payload.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        guard let blocks = sound.withLock({ held -> [[Int16]]? in
            guard held != nil else { return nil }
            return held?.add(samples)
        }) else { return }
        for block in blocks {
            guard let buffer = SfuShareHost.buffer(block) else { continue }
            AudioManager.shared.mixer.capture(appAudio: buffer)
        }
    }

    /// Interleaved 16-bit stereo as the PCM buffer LiveKit's mixer converts from.
    nonisolated static func buffer(_ samples: [Int16]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count / 2)),
              let target = buffer.int16ChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count / 2)
        samples.withUnsafeBufferPointer { target.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    /// The game sound in the room or not (SfuAudio decides: voice and watching come first).
    func setGameSound(_ on: Bool) async {
        soundWanted = on
        await soundChanging?.value
        guard soundWanted == on, (audio != nil) != on, state == .connected else { return }
        let change = Task { @MainActor in
            if on {
                let track = await LocalAudioTrack.createTrack(name: SfuTrackNames.audio, options: .noProcessing)
                do {
                    audio = try await room.localParticipant.publish(audioTrack: track, options: SfuShareHost.audioOptions)
                    sound.value = SfuSoundBlocks()
                } catch {
                    SfuAudio.log.error("media server: game sound: \(String(describing: error), privacy: .public)")
                }
            } else if let publication = audio {
                sound.value = nil
                audio = nil
                try? await room.localParticipant.unpublish(publication: publication)
            }
        }
        soundChanging = change
        await change.value
    }

    /// Out of the room; the server closes it when the share play ends.
    public func close() async {
        capturer.value = nil
        sound.value = nil
        state = .closed
        await SfuAudio.shared.hosting(nil)
        await room.disconnect()
        video = nil
        audio = nil
    }

    /// Whether the room's tracks are out: the picture, and the sound.
    public var publishing: (video: Bool, audio: Bool) { (state == .connected, audio != nil) }
}
