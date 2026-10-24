import CoreMedia
import Foundation
import VideoToolbox

/// Encodes the game's frames for Remote Play as soon as they come: H.264 on the Mac's media
/// engine with low-latency rate control (no frames held back or reordered), each frame handed
/// on as a start-code stream, key frames with their parameter sets, and a key frame whenever
/// the phone lost one.
public final class StreamEncoder: @unchecked Sendable {
    public struct Frame: Sendable {
        public let data: Data
        public let key: Bool
        public let milliseconds: UInt32
    }

    private let bitRate: Int
    private let output: @Sendable (Frame) -> Void
    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var size: (Int32, Int32) = (0, 0)
    private var keyWanted = true
    private var start: Double?

    public init(bitRate: Int, output: @escaping @Sendable (Frame) -> Void) {
        self.bitRate = bitRate
        self.output = output
    }

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
    }

    /// The next frame is a key frame.
    public func wantKey() {
        lock.withLock { keyWanted = true }
    }

    /// Waits for the frames given so far to come out.
    public func flush() {
        lock.withLock { if let session { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) } }
    }

    /// `seconds` on any clock that goes forward; the frames carry milliseconds from the first.
    public func encode(_ pixels: CVPixelBuffer, at seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
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
        let begin = start ?? seconds
        start = begin
        let milliseconds = UInt32(max(0, (seconds - begin) * 1000).rounded(.down))
        let properties: CFDictionary? = keyWanted ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        keyWanted = false
        let output = output
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixels, presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600_000), duration: .invalid,
                                        frameProperties: properties, infoFlagsOut: nil) { status, _, sample in
            guard status == noErr, let sample, let block = CMSampleBufferGetDataBuffer(sample) else { return }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
            let key = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr, let pointer else { return }
            let units = Data(bytes: pointer, count: length)
            let sets = key ? StreamEncoder.parameterSets(of: sample) : []
            output(Frame(data: StreamPacket.annexB(units, parameterSets: sets), key: key, milliseconds: milliseconds))
        }
    }

    static func parameterSets(of sample: CMSampleBuffer) -> [Data] {
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return [] }
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        return (0 ..< count).compactMap { index in
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
                  let pointer else { return nil }
            return Data(bytes: pointer, count: size)
        }
    }

    private func makeSession(width: Int32, height: Int32) -> VTCompressionSession? {
        var made: VTCompressionSession?
        let specification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true,
        ]
        guard VTCompressionSessionCreate(allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: specification as CFDictionary,
                                         imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &made) == noErr,
              let session = made else { return nil }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Main_AutoLevel,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 240,
            kVTCompressionPropertyKey_ExpectedFrameRate: 60,
            kVTCompressionPropertyKey_AverageBitRate: bitRate,
        ]
        for (key, value) in properties { VTSessionSetProperty(session, key: key, value: value as CFTypeRef) }
        VTCompressionSessionPrepareToEncodeFrames(session)
        return session
    }
}
