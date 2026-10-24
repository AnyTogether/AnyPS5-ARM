import CoreVideo
import XCTest
@testable import AnyPS5Core

final class StreamEncoderTests: XCTestCase {
    func pixels(_ width: Int, _ height: Int, shade: UInt8) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), Int32(shade), CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        return buffer!
    }

    /// Frames come out as start-code streams, the first a key frame with its parameter sets, and
    /// a key frame asked for comes next.
    func testFramesComeOutReadyForThePhone() throws {
        let frames = Locked<[StreamEncoder.Frame]>([])
        let encoder = StreamEncoder(bitRate: 2_000_000) { frame in frames.withLock { $0.append(frame) } }
        for index in 0 ..< 10 {
            encoder.encode(pixels(320, 240, shade: UInt8(index * 20)), at: Double(index) / 60)
        }
        encoder.wantKey()
        encoder.encode(pixels(320, 240, shade: 9), at: 10.0 / 60)
        encoder.flush()
        let made = frames.value
        XCTAssertEqual(made.count, 11)
        XCTAssertTrue(made[0].key)
        XCTAssertEqual(Array(made[0].data.prefix(4)), [0, 0, 0, 1])
        XCTAssertEqual(made[0].data[4] & 0x1F, 7, "the first unit is the sequence parameter set")
        XCTAssertFalse(made[5].key)
        XCTAssertTrue(made[10].key, "the key frame asked for")
        XCTAssertEqual(made.map(\.milliseconds), (0 ... 10).map { UInt32((Double($0) / 60 * 1000).rounded(.down)) })
    }
}
