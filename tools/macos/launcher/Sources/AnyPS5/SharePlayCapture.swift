import AnyPS5Core
import AnyPS5SharePlay
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// The game's window and sound for share play, as Remote Play captures them: ScreenCaptureKit at
/// up to 1280 x 720 and 60 frames a second, each frame handed to WebRTC as it comes (its encoder
/// works on the Mac's media engine), the sound as 5 ms packets of 16-bit stereo.
@MainActor
final class SharePlayCapture {
    private var stream: SCStream?
    private var output: Output?
    private(set) var pid: pid_t?

    func start(pid: pid_t, host: SharePlayHost) async throws {
        if self.pid == pid, stream != nil { return }
        stop()
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if (error as NSError).code == SCStreamError.userDeclined.rawValue || !CGPreflightScreenCaptureAccess() { throw RemotePlay.Failure.noPermission }
            throw RemotePlay.Failure.capture(error)
        }
        guard let app = content.applications.first(where: { $0.processID == pid }), let window = ClipRecorder.mainWindow(of: pid, in: content),
              let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else { throw RemotePlay.Failure.noWindow }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: window.frame.minX - display.frame.minX, y: window.frame.minY - display.frame.minY, width: window.frame.width, height: window.frame.height)
        // The window's shape within 1280 x 720, even sizes for the encoder.
        let scale = min(1, 720 / window.frame.height, 1280 / window.frame.width)
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
        let output = Output(host: host)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.audioQueue)
        try await stream.startCapture()
        self.stream = stream
        self.output = output
        self.pid = pid
    }

    func stop() {
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        output = nil
        pid = nil
    }

    final class Output: NSObject, SCStreamOutput, @unchecked Sendable {
        let queue = DispatchQueue(label: "org.anyps5.shareplay.video", qos: .userInteractive)
        let audioQueue = DispatchQueue(label: "org.anyps5.shareplay.audio", qos: .userInteractive)
        private let host: SharePlayHost
        private var chunker = SoundChunker()

        init(host: SharePlayHost) { self.host = host }

        func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
            guard sample.isValid else { return }
            switch type {
            case .screen:
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                      let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                host.push(pixels, timeNs: Int64(time.seconds * 1_000_000_000))
            case .audio:
                sound(sample)
            default:
                break
            }
        }

        private func sound(_ sample: CMSampleBuffer) {
            let buffers = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(buffers.unsafeMutablePointer) }
            var block: CMBlockBuffer?
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil, bufferListOut: buffers.unsafeMutablePointer,
                                                                          bufferListSize: AudioBufferList.sizeInBytes(maximumBuffers: 2),
                                                                          blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let format = CMSampleBufferGetFormatDescription(sample), let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  description.mFormatFlags & kAudioFormatFlagIsFloat != 0, let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
            let planar = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            let second = planar && buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            let samples = SoundChunker.stereo16(first: first, second: second, planar: planar, channels: Int(description.mChannelsPerFrame), frames: frames)
            for packet in chunker.add(samples, at: CMSampleBufferGetPresentationTimeStamp(sample).seconds) { host.push(sound: packet) }
        }
    }
}
