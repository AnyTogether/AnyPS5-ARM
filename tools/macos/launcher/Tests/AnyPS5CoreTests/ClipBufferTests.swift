import XCTest
@testable import AnyPS5Core

final class ClipBufferTests: XCTestCase {
    /// 60 frames a second with a key frame each second, and audio every 10 ms, for `seconds`.
    func filled(seconds: Double, keep: Double = 30) -> ClipBuffer<Int> {
        var buffer = ClipBuffer<Int>(length: keep)
        var frame = 0
        var time = 0.0
        while time < seconds {
            buffer.addVideo(frame, at: time, key: frame % 60 == 0)
            frame += 1
            time = Double(frame) / 60
        }
        var audio = 0.0
        var chunk = 0
        while audio < seconds {
            buffer.addAudio(chunk, at: audio)
            chunk += 1
            audio = Double(chunk) / 100
        }
        return buffer
    }

    func testTheLastSecondsAreKeptFromAKeyFrame() throws {
        let buffer = filled(seconds: 50)
        let clip = try XCTUnwrap(buffer.clip())
        XCTAssertEqual(clip.video.first?.key, true, "a clip does not start at a key frame")
        // Kept from the key frame at or before 50 - 30 s, that is 19 or 20 s in.
        let start = try XCTUnwrap(clip.video.first?.time)
        XCTAssertGreaterThanOrEqual(start, 19)
        XCTAssertLessThanOrEqual(start, 20.001)
        XCTAssertEqual(clip.video.last?.payload, 2999)
        XCTAssertGreaterThanOrEqual(clip.audio.first?.time ?? 0, start - 0.0001, "audio starts before the video")
        XCTAssertLessThan(clip.audio.first?.time ?? 0, start + 0.02)
    }

    func testAShortRecordingIsAllKept() throws {
        let clip = try XCTUnwrap(filled(seconds: 5).clip())
        XCTAssertEqual(clip.video.first?.payload, 0)
        XCTAssertEqual(clip.video.count, 300)
    }

    func testMemoryStaysBoundedWhileRecordingLong() {
        let buffer = filled(seconds: 600)
        XCTAssertLessThan(buffer.videoCount, 60 * 33, "old frames are not let go")
        XCTAssertLessThan(buffer.audioCount, 100 * 33, "old audio is not let go")
    }

    func testNothingRecordedIsNoClip() {
        XCTAssertNil(ClipBuffer<Int>(length: 30).clip())
        var buffer = ClipBuffer<Int>(length: 30)
        buffer.addVideo(1, at: 0, key: false)
        XCTAssertNil(buffer.clip(), "frames before any key frame cannot start a clip")
    }

    func testClearingStartsOver() {
        var buffer = filled(seconds: 10)
        buffer.clear()
        XCTAssertNil(buffer.clip())
    }
}
