import Foundation
import XCTest
@testable import AnyPS5Core

final class ThemeSongTests: XCTestCase {
    /// A RIFF file in the layout a game's snd0.at9 has: fmt (WAVE_FORMAT_EXTENSIBLE, the ATRAC9
    /// GUID and its config data), fact (samples, encoder delay), smpl (one loop) and data.
    static func riff(guid: [UInt8] = ThemeSong.atrac9Format, loop: (Int, Int)? = (1000, 40000), data: [UInt8] = [UInt8](repeating: 0, count: 768)) -> Data {
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xffff) + u16(v >> 16) }
        func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] { Array(id.utf8) + u32(body.count) + body + (body.count % 2 == 1 ? [0] : []) }
        let fmt = u16(0xfffe) + u16(2) + u32(48000) + u32(18000) + u16(384) + u16(0) + u16(34) + u16(1024) + u32(3) + guid + u32(1) + [0xfe, 0x74, 0x0b, 0xf0] + u32(0)
        let fact = u32(50000) + u32(256) + u32(256)
        var smpl = u32(0) + u32(0) + u32(20833) + u32(60) + u32(0) + u32(0) + u32(0)
        if let loop { smpl += u32(1) + u32(0) + u32(0) + u32(0) + u32(loop.0) + u32(loop.1) + u32(0) + u32(0) } else { smpl += u32(0) + u32(0) }
        let body = Array("WAVE".utf8) + chunk("fmt ", fmt) + chunk("fact", fact) + chunk("smpl", smpl) + chunk("data", data)
        return Data(Array("RIFF".utf8) + u32(body.count) + body)
    }

    func testTheHeaderOfAThemeSong() throws {
        let header = try ThemeSong.header(Self.riff())
        XCTAssertEqual(header.channels, 2)
        XCTAssertEqual(header.sampleRate, 48000)
        XCTAssertEqual(header.blockAlign, 384)
        XCTAssertEqual(header.config, [0xfe, 0x74, 0x0b, 0xf0])
        XCTAssertEqual(header.totalFrames, 50000)
        XCTAssertEqual(header.delay, 256)
        XCTAssertEqual(header.loop, 1000..<40001)
        XCTAssertEqual(header.data.count, 768)
    }

    func testNoLoopOrAnImpossibleOneLoopsTheWholeSong() throws {
        XCTAssertNil(try ThemeSong.header(Self.riff(loop: nil)).loop)
        XCTAssertNil(try ThemeSong.header(Self.riff(loop: (40000, 1000))).loop)
        XCTAssertNil(try ThemeSong.header(Self.riff(loop: (0, 90000))).loop)
    }

    func testOtherFilesAreRefused() {
        XCTAssertThrowsError(try ThemeSong.header(Data("not a riff file at all".utf8)))
        XCTAssertThrowsError(try ThemeSong.header(Self.riff(guid: [UInt8](repeating: 7, count: 16))))
        XCTAssertThrowsError(try ThemeSong.header(Self.riff().prefix(60)))
    }

    /// The real thing, when this Mac has a game whose dump carries one (set ANYPS5_TEST_AT9).
    func testARealThemeSongDecodesToMusic() throws {
        guard let path = ProcessInfo.processInfo.environment["ANYPS5_TEST_AT9"], FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("set ANYPS5_TEST_AT9 to a game's sce_sys/snd0.at9")
        }
        let song = try ThemeSong.decode(URL(fileURLWithPath: path))
        let header = try ThemeSong.header(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(song.channels, header.channels)
        XCTAssertEqual(song.frames, header.totalFrames)
        let peak = song.samples.lazy.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThanOrEqual(peak, 1.5)
    }

    func testASongWithALoopPlaysItsIntroOnceThenTheLoop() throws {
        // Left channel counts frames up, right one counts them down.
        let frames = 1000
        let samples = (0..<frames).flatMap { [Float($0), Float(-$0)] }
        let song = ThemeSong(sampleRate: 48000, channels: 2, samples: samples, loop: 200..<800)
        let buffers = try XCTUnwrap(song.buffers())
        XCTAssertEqual(buffers.intro.frameLength, 800)
        let loop = try XCTUnwrap(buffers.loop)
        XCTAssertEqual(loop.frameLength, 600)
        XCTAssertEqual(loop.floatChannelData![0][0], 200)
        XCTAssertEqual(loop.floatChannelData![1][599], -799)
        XCTAssertEqual(buffers.intro.floatChannelData![1][10], -10)
    }

    func testASongWithoutALoopRepeatsWhole() throws {
        let song = ThemeSong(sampleRate: 48000, channels: 2, samples: [Float](repeating: 0.25, count: 2000), loop: nil)
        let buffers = try XCTUnwrap(song.buffers())
        XCTAssertEqual(buffers.intro.frameLength, 1000)
        XCTAssertNil(buffers.loop)
    }
}
