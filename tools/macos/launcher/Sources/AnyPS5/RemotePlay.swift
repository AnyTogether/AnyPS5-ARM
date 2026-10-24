import AnyPS5Core
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Remote Play: the game's window and sound sent to the phones that asked, as they come.
/// ScreenCaptureKit gives the window at the size the phone wants, StreamEncoder encodes each
/// frame at once, and the sound goes as 5 ms of 16-bit stereo.
@MainActor
final class RemotePlay {
    enum Failure: Error {
        case noPermission
        case noWindow
        case capture(Error)
    }

    private var stream: SCStream?
    private var output: Output?
    private(set) var pid: pid_t?
    private(set) var size: (width: Int, height: Int)?

    /// Starts sending the game with process `pid` at about `width` by `height`, through `send`.
    func start(pid: pid_t, width: Int, height: Int, send: @escaping @Sendable ([Data]) -> Void) async throws {
        if self.pid == pid, let size, size == (width, height) { return }
        stop()
        // Without the permission macOS shows its own prompt, once.
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Only a refusal is a missing permission; anything else is said as it is.
            if (error as NSError).code == SCStreamError.userDeclined.rawValue || !CGPreflightScreenCaptureAccess() { throw Failure.noPermission }
            throw Failure.capture(error)
        }
        guard let app = content.applications.first(where: { $0.processID == pid }), let window = ClipRecorder.mainWindow(of: pid, in: content),
              let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else { throw Failure.noWindow }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: window.frame.minX - display.frame.minX, y: window.frame.minY - display.frame.minY, width: window.frame.width, height: window.frame.height)
        // The window's shape at the phone's height or less, even sizes for the encoder.
        let scale = min(1, Double(height) / window.frame.height, Double(width) / window.frame.width)
        configuration.width = max(160, Int(window.frame.width * scale) & ~1)
        configuration.height = max(90, Int(window.frame.height * scale) & ~1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        // About 0.2 bit a pixel at 60 fps: 11 Mbit/s for 1280 x 720.
        let bitRate = max(2_000_000, Int(Double(configuration.width * configuration.height) * 60 * 0.2))
        let output = Output(bitRate: bitRate, send: send)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
        self.output = output
        self.pid = pid
        self.size = (width, height)
    }

    func stop() {
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        output = nil
        pid = nil
        size = nil
    }

    /// The phone lost part of the picture.
    func wantKey() {
        output?.encoder.wantKey()
    }

    final class Output: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "org.anyps5.remoteplay", qos: .userInteractive)
        let encoder: StreamEncoder
        private let send: @Sendable ([Data]) -> Void
        private let numbers = Locked((video: UInt32(0), audio: UInt32(0)))
        private var audioStart: Double?
        private var pending = Data()

        init(bitRate: Int, send: @escaping @Sendable ([Data]) -> Void) {
            self.send = send
            let numbers = numbers
            encoder = StreamEncoder(bitRate: bitRate) { frame in
                let number = numbers.withLock { value -> UInt32 in
                    value.video &+= 1
                    return value.video
                }
                send(StreamPacket.video(frame.data, number: number, key: frame.key, milliseconds: frame.milliseconds))
            }
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
            guard sample.isValid else { return }
            switch type {
            case .screen:
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                      let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
                encoder.encode(pixels, at: CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            case .audio:
                sound(sample)
            default:
                break
            }
        }

        /// The capture's float samples as 16-bit stereo, sent 240 frames (5 ms) at a time.
        private func sound(_ sample: CMSampleBuffer) {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let start = audioStart ?? time
            audioStart = start
            // Planar float: room for a buffer a channel.
            let buffers = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(buffers.unsafeMutablePointer) }
            var block: CMBlockBuffer?
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil, bufferListOut: buffers.unsafeMutablePointer,
                                                                          bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: 2),
                                                                          blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let format = CMSampleBufferGetFormatDescription(sample), let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  description.mFormatFlags & kAudioFormatFlagIsFloat != 0, let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
            let channels = max(1, Int(description.mChannelsPerFrame))
            let planar = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            // Planar: a buffer a channel. Interleaved: the channels side by side in one.
            let second = planar && buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? first : first
            var samples = [Int16](repeating: 0, count: frames * 2)
            for frame in 0 ..< frames {
                let left = planar ? first[frame] : first[frame * channels]
                let right = planar ? second[frame] : first[frame * channels + min(1, channels - 1)]
                samples[frame * 2] = Int16(max(-1, min(1, left)) * 32767)
                samples[frame * 2 + 1] = Int16(max(-1, min(1, right)) * 32767)
            }
            pending += samples.withUnsafeBytes { Data($0) }
            let chunk = 240 * 4
            var packets: [Data] = []
            while pending.count >= chunk {
                let number = numbers.withLock { value -> UInt32 in
                    value.audio &+= 1
                    return value.audio
                }
                packets.append(StreamPacket.audio(pending.prefix(chunk), number: number, milliseconds: UInt32(max(0, (time - start) * 1000))))
                pending.removeFirst(chunk)
            }
            if !packets.isEmpty { send(packets) }
        }
    }
}
