import AVFoundation
import CoreMedia
import XCTest
@testable import AnyPS5Core

final class ClipEncoderTests: XCTestCase {
    func pixels(_ width: Int, _ height: Int, shade: UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let made = buffer!
        CVPixelBufferLockBaseAddress(made, [])
        memset(CVPixelBufferGetBaseAddress(made), Int32(shade), CVPixelBufferGetDataSize(made))
        CVPixelBufferUnlockBaseAddress(made, [])
        return made
    }

    /// 10 ms of stereo silence at 48 kHz, as ScreenCaptureKit hands sound over (float PCM).
    func silence(at seconds: Double) -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                      mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let frames = 480
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frames * 8, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: frames * 8, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: frames * 8)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
                                                             presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48000), packetDescriptions: nil, sampleBufferOut: &sample)
        return sample!
    }

    /// 12 s of frames and sound, kept 5 s: the clip is about the last 5 s, with picture and sound.
    func testTheLastSecondsAreWrittenAsAnMP4() async throws {
        let encoder = ClipEncoder(length: 5)
        for frame in 0..<(12 * 60) {
            let time = Double(frame) / 60
            encoder.addFrame(pixels(640, 360, shade: UInt8(frame % 200)), at: CMTime(seconds: time, preferredTimescale: 600))
            if frame % 6 == 0 {
                for part in 0..<10 { encoder.addAudio(silence(at: time + Double(part) / 100)) }
            }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        try await encoder.save(to: file)
        let asset = AVURLAsset(url: file)
        let seconds = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(seconds, 4.9, "the clip is shorter than kept")
        XCTAssertLessThan(seconds, 6.5, "the clip reaches back more than a key frame before the window")
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
        let size = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 640, height: 360))
    }

    func testNothingRecordedFails() async {
        do {
            try await ClipEncoder(length: 5).save(to: FileManager.default.temporaryDirectory.appendingPathComponent("never.mp4"))
            XCTFail("an empty clip was written")
        } catch {}
    }
}
