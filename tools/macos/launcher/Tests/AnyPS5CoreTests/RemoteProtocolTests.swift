import XCTest
@testable import AnyPS5Core

final class RemoteProtocolTests: XCTestCase {
    func testHelloRoundTrip() throws {
        let json = #"{"type":"hello","protocol":1,"deviceID":"A","deviceName":"Pixel","key":null}"#
        let message = try JSONDecoder().decode(RemoteMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message, .hello(protocol: 1, deviceID: "A", deviceName: "Pixel", key: nil))
        let again = try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message))
        XCTAssertEqual(again, message)
    }

    func testWelcomeSessionIsDecimalString() throws {
        let message = RemoteMessage.welcome(session: 18446744073709551615, udpPort: 5000, macName: "Mac", key: "a2V5")
        let text = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
        XCTAssertTrue(text.contains(#""session":"18446744073709551615""#), text)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: Data(text.utf8)), message)
    }

    func testEveryMessageRoundTrips() throws {
        let messages: [RemoteMessage] = [.pairing(code: "0042"), .rejected(reason: "denied"), .latency(milliseconds: 9.5)]
        for message in messages {
            XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        }
    }

    func testUnknownTypeFailsToDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteMessage.self, from: Data(#"{"type":"bogus"}"#.utf8)))
    }

    static func input(session: UInt64, size: UInt16 = 80, magic: UInt32 = RemotePacket.inputMagic, length: Int = 80) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (index, byte) in raw.enumerated() where offset + index < bytes.count { bytes[offset + index] = byte }
            }
        }
        put(magic, at: 0)
        put(UInt16(1), at: 4)
        put(size, at: 6)
        put(session, at: 24)
        return Data(bytes)
    }

    func testInputSession() {
        XCTAssertEqual(RemotePacket.inputSession(Self.input(session: 42)), 42)
        XCTAssertNil(RemotePacket.inputSession(Self.input(session: 42, size: 79)))
        XCTAssertNil(RemotePacket.inputSession(Self.input(session: 42, magic: 1)))
        XCTAssertNil(RemotePacket.inputSession(Self.input(session: 42, length: 79)))
    }

    func testOutputAndHelloAreRecognised() {
        var output = [UInt8](repeating: 0, count: 32)
        output.replaceSubrange(0..<4, with: [0x41, 0x50, 0x52, 0x4F])
        output.replaceSubrange(4..<8, with: [1, 0, 32, 0])
        XCTAssertTrue(RemotePacket.isOutput(Data(output)))
        XCTAssertFalse(RemotePacket.isOutput(Data(output.prefix(31))))
        var hello = [UInt8](repeating: 0, count: 16)
        hello.replaceSubrange(0..<8, with: [0x41, 0x50, 0x52, 0x48, 1, 0, 16, 0])
        XCTAssertTrue(RemotePacket.isHello(Data(hello)))
        XCTAssertFalse(RemotePacket.isHello(Data(output)))
    }

    func testPairedDevicesPersist() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let devices = PairedDevices(file: file)
        let added = devices.add(id: "phone-1", name: "Pixel 8")
        XCTAssertEqual(Data(base64Encoded: added.key)?.count, 32)
        let reloaded = PairedDevices(file: file)
        XCTAssertEqual(reloaded.device(id: "phone-1", key: added.key)?.name, "Pixel 8")
        XCTAssertNil(reloaded.device(id: "phone-1", key: "wrong"))
        reloaded.remove(id: "phone-1")
        XCTAssertTrue(PairedDevices(file: file).all.isEmpty)
    }
}
