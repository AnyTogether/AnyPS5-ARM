import XCTest
@testable import AnyPS5Core

final class StreamPacketTests: XCTestCase {
    /// A frame larger than one packet is cut into pieces that each fit a datagram, every piece
    /// saying which frame it belongs to, where it goes and whether the frame is a key frame.
    func testAFrameIsCutIntoPiecesThatFit() throws {
        let frame = Data((0..<5000).map { UInt8($0 % 251) })
        let packets = StreamPacket.video(frame, number: 7, key: true, milliseconds: 1234)
        XCTAssertEqual(packets.count, 5)
        XCTAssertTrue(packets.allSatisfy { $0.count <= StreamPacket.largest })
        var joined = Data()
        for (index, packet) in packets.enumerated() {
            let header = try XCTUnwrap(StreamPacket.Video(packet))
            XCTAssertEqual(header.number, 7)
            XCTAssertEqual(header.index, index)
            XCTAssertEqual(header.count, 5)
            XCTAssertTrue(header.key)
            XCTAssertEqual(header.milliseconds, 1234)
            joined += header.payload
        }
        XCTAssertEqual(joined, frame)
    }

    func testSoundIsOnePacket() throws {
        let samples = Data(repeating: 3, count: 960)
        let packet = StreamPacket.audio(samples, number: 9, milliseconds: 55)
        let header = try XCTUnwrap(StreamPacket.Audio(packet))
        XCTAssertEqual(header.number, 9)
        XCTAssertEqual(header.milliseconds, 55)
        XCTAssertEqual(header.payload, samples)
    }

    func testOtherPacketsAreNotStreamPackets() {
        XCTAssertNil(StreamPacket.Video(Data(repeating: 0, count: 40)))
        XCTAssertNil(StreamPacket.Audio(StreamPacket.video(Data([1]), number: 1, key: false, milliseconds: 0)[0]))
        XCTAssertFalse(RemotePacket.isOutput(StreamPacket.video(Data(repeating: 1, count: 8), number: 1, key: false, milliseconds: 0)[0]))
    }

    /// The encoder's frames (lengths before each NAL unit) become the start-code stream decoders
    /// on the phone take, with the parameter sets before a key frame.
    func testLengthPrefixedUnitsBecomeStartCodes() {
        let avcc = Data([0, 0, 0, 3, 0x65, 1, 2, 0, 0, 0, 2, 0x41, 9])
        let annexB = StreamPacket.annexB(avcc, parameterSets: [Data([0x67, 7]), Data([0x68, 8])])
        XCTAssertEqual(annexB, Data([0, 0, 0, 1, 0x67, 7, 0, 0, 0, 1, 0x68, 8, 0, 0, 0, 1, 0x65, 1, 2, 0, 0, 0, 1, 0x41, 9]))
    }
}
