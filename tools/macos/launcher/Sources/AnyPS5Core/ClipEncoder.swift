import AVFoundation
import CoreMedia
import VideoToolbox

/// Encodes frames as they come (H.264 on the Mac's media engine, a key frame each second, at
/// ReplayBudget's bit rate) and keeps them with the sound in a ClipBuffer, a few megabytes a second; writes what is kept as an
/// MP4 with AAC sound. Frames and sound arrive on one queue; saving can come from any.
public final class ClipEncoder: @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private let kept: Locked<ClipBuffer<CMSampleBuffer>>
    private let encoding = NSLock()
    private var session: VTCompressionSession?
    private var sessionSize: (Int32, Int32) = (0, 0)

    private let length: Double

    public init(length: Double) {
        self.length = length
        kept = Locked(ClipBuffer(length: length))
    }

    deinit {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
    }

    public func addAudio(_ sample: CMSampleBuffer) {
        kept.withLock { $0.addAudio(sample, at: CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
    }

    public func addFrame(_ pixels: CVPixelBuffer, at time: CMTime) {
        encoding.lock()
        defer { encoding.unlock() }
        let width = Int32(CVPixelBufferGetWidth(pixels)), height = Int32(CVPixelBufferGetHeight(pixels))
        if session == nil || sessionSize != (width, height) {
            if let session {
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(session)
            }
            session = ClipEncoder.makeSession(width: width, height: height, bitRate: ReplayBudget.bitRate(width: Int(width), height: Int(height), seconds: Int(length.rounded())))
            sessionSize = (width, height)
        }
        guard let session else { return }
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixels, presentationTimeStamp: time, duration: .invalid, frameProperties: nil, infoFlagsOut: nil) { [kept] status, _, encoded in
            guard status == noErr, let encoded, encoded.isValid else { return }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(encoded, createIfNecessary: false) as? [[CFString: Any]]
            let key = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
            kept.withLock { $0.addVideo(encoded, at: CMSampleBufferGetPresentationTimeStamp(encoded).seconds, key: key) }
        }
    }

    /// Writes what is kept to `file`, an MP4, the frames as encoded and the sound as AAC.
    public func save(to file: URL) async throws {
        encoding.lock()
        if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }
        encoding.unlock()
        guard let clip = kept.withLock({ $0.clip() }), let first = clip.video.first?.payload, let format = CMSampleBufferGetFormatDescription(first) else {
            throw Failure(description: "nothing was recorded yet")
        }
        try? FileManager.default.removeItem(at: file)
        let writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        video.expectsMediaDataInRealTime = false
        writer.add(video)
        var audio: AVAssetWriterInput?
        if !clip.audio.isEmpty {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audio = input
            }
        }
        guard writer.startWriting() else { throw writer.error ?? Failure(description: "the clip could not be started") }
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(first))
        // The writer interleaves its tracks and holds back the one ahead until the other catches
        // up: each is fed whenever the writer wants more of it, both at once.
        var feeds = [(video, clip.video)]
        if let audio { feeds.append((audio, clip.audio)) }
        await withTaskGroup(of: Void.self) { group in
            for (index, (input, items)) in feeds.enumerated() {
                group.addTask {
                    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                        var next = items.startIndex
                        input.requestMediaDataWhenReady(on: DispatchQueue(label: "org.anyps5.clips.write.\(index)")) {
                            while input.isReadyForMoreMediaData && next < items.endIndex {
                                if !input.append(items[next].payload) { next = items.endIndex; break }
                                next += 1
                            }
                            if next >= items.endIndex {
                                input.markAsFinished()
                                done.resume()
                            }
                        }
                    }
                }
            }
        }
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? Failure(description: "the clip could not be finished") }
    }

    /// `bitRate` from ReplayBudget: the clip quality, lower for the longest buffers.
    private static func makeSession(width: Int32, height: Int32, bitRate: Int) -> VTCompressionSession? {
        var made: VTCompressionSession?
        let encoder = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary
        guard VTCompressionSessionCreate(allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: encoder,
                                         imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &made) == noErr,
              let session = made else { return nil }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 1.0,
            kVTCompressionPropertyKey_ExpectedFrameRate: 60,
            kVTCompressionPropertyKey_AverageBitRate: bitRate,
        ]
        for (key, value) in properties { VTSessionSetProperty(session, key: key, value: value as CFTypeRef) }
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }
}
