import CoreMedia
import Foundation
import VideoToolbox

/// H.264 for a live broadcast on the Mac's media engine, as streaming services ask for it: High
/// profile, no B-frames, a key frame every two seconds, a steady bit rate (constant where the
/// encoder offers it, else an average held to a ceiling each second) and no more frames a
/// second than the preset's. Frames come out as length-prefixed NAL units, key frames with
/// their SPS and PPS.
public final class BroadcastVideoEncoder: @unchecked Sendable {
    public struct Frame: Sendable {
        /// NAL units, each with a four-byte length (AVCC).
        public let units: Data
        public let key: Bool
        public let seconds: Double
        /// SPS and PPS, on key frames.
        public let parameterSets: [Data]
    }

    public let bitRate: Int
    public let frameRate: Int
    /// Whether the encoder took the constant bit rate (else the average and its ceiling).
    public private(set) var constantBitRate = false
    private let output: @Sendable (Frame) -> Void
    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var size: (Int32, Int32) = (0, 0)
    private var keyWanted = true
    private var last: Double?
    private var skipped = 0

    public init(bitRate: Int, frameRate: Int, output: @escaping @Sendable (Frame) -> Void) {
        self.bitRate = bitRate
        self.frameRate = max(1, frameRate)
        self.output = output
    }

    deinit {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
    }

    /// Frames left out for coming faster than the preset's rate.
    public var framesSkipped: Int { lock.withLock { skipped } }

    public func wantKey() {
        lock.withLock { keyWanted = true }
    }

    public func flush() {
        lock.withLock { if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) } }
    }

    /// `seconds` on the clock the sound uses too.
    public func encode(_ pixels: CVPixelBuffer, at seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        // A little slack, so a 60 Hz capture of a 60 fps preset loses nothing to jitter.
        if let last, seconds - last < 0.8 / Double(frameRate) {
            skipped += 1
            return
        }
        let width = Int32(CVPixelBufferGetWidth(pixels)), height = Int32(CVPixelBufferGetHeight(pixels))
        if session == nil || size != (width, height) {
            if let session {
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(session)
            }
            session = makeSession(width: width, height: height)
            size = (width, height)
            keyWanted = true
        }
        guard let session else { return }
        last = seconds
        let properties: CFDictionary? = keyWanted ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        keyWanted = false
        let output = output
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixels, presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600_000),
                                        duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)), frameProperties: properties, infoFlagsOut: nil) { status, _, sample in
            guard status == noErr, let sample, let block = CMSampleBufferGetDataBuffer(sample) else { return }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
            let key = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr, let pointer else { return }
            let units = Data(bytes: pointer, count: length)
            output(Frame(units: units, key: key, seconds: CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                         parameterSets: key ? StreamEncoder.parameterSets(of: sample) : []))
        }
    }

    private func makeSession(width: Int32, height: Int32) -> VTCompressionSession? {
        var made: VTCompressionSession?
        let specification = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary
        guard VTCompressionSessionCreate(allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: specification,
                                         imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &made) == noErr,
              let session = made else { return nil }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_H264EntropyMode: kVTH264EntropyMode_CABAC,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: frameRate * 2,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 2.0,
            kVTCompressionPropertyKey_ExpectedFrameRate: frameRate,
        ]
        for (key, value) in properties { VTSessionSetProperty(session, key: key, value: value as CFTypeRef) }
        constantBitRate = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ConstantBitRate, value: bitRate as CFNumber) == noErr
        if !constantBitRate {
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
            // No second above 1.2 times the target, in bytes.
            let ceiling = [Double(bitRate) * 1.2 / 8, 1.0] as CFArray
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: ceiling)
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }
}
