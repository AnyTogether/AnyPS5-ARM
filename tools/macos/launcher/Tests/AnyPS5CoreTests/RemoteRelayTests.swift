import Darwin
import XCTest
@testable import AnyPS5Core

/// A loopback UDP socket standing in for the phone's pad sender or for the game.
final class UDPPeer {
    let socket: Int32
    let port: UInt16

    init() {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        socket = fd
        port = UInt16(bigEndian: address.sin_port)
    }

    deinit { close(socket) }

    func send(_ data: Data, to port: UInt16) {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(socket, bytes.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        }
    }

    func receive() -> Data? {
        var buffer = [UInt8](repeating: 0, count: 2048)
        let got = recv(socket, &buffer, buffer.count, 0)
        return got < 0 ? nil : Data(buffer.prefix(got))
    }
}

final class RemoteRelayTests: XCTestCase {
    var file: URL!
    var devices: PairedDevices!
    var server: RemoteServer!
    var phone: FakePhone!
    var session: UInt64 = 0
    var udpPort: UInt16 = 0

    static let hello = Data([0x41, 0x50, 0x52, 0x48, 1, 0, 16, 0] + [UInt8](repeating: 0, count: 8))
    static let output = Data([0x41, 0x50, 0x52, 0x4F, 1, 0, 32, 0] + [UInt8](repeating: 7, count: 24))

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString).json")
        devices = PairedDevices(file: file)
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        server = RemoteServer(name: "Test Mac", devices: devices, events: RemoteServer.Events(), advertise: false)
        try server.start()
        phone = FakePhone(port: server.controlPort!)
        try await phone.hello(key: known.key)
        guard case .welcome(let session, let udpPort, _, _, _) = try await phone.receive() else { return XCTFail("no welcome") }
        self.session = session
        self.udpPort = udpPort
    }

    override func tearDown() async throws {
        phone.close()
        server.stop()
        try? FileManager.default.removeItem(at: file)
    }

    func greet(_ game: UDPPeer) throws {
        game.send(Self.hello, to: server.bridgePort!)
        Thread.sleep(forTimeInterval: 0.05)
    }

    func testWelcomeNamesTheRelayPort() {
        XCTAssertNotEqual(udpPort, 0)
        XCTAssertEqual(udpPort, server.udpPort)
    }

    func testInputReachesGame() throws {
        let game = UDPPeer()
        try greet(game)
        let sender = UDPPeer()
        let input = RemoteProtocolTests.input(session: session)
        sender.send(input, to: udpPort)
        XCTAssertEqual(game.receive(), input)
    }

    func testForeignSessionIsDropped() throws {
        let game = UDPPeer()
        try greet(game)
        let sender = UDPPeer()
        sender.send(RemoteProtocolTests.input(session: session &+ 1), to: udpPort)
        sender.send(RemoteProtocolTests.input(session: session, magic: 1), to: udpPort)
        sender.send(RemoteProtocolTests.input(session: session, length: 79), to: udpPort)
        XCTAssertNil(game.receive())
    }

    func testOutputReachesPhone() throws {
        let game = UDPPeer()
        try greet(game)
        let sender = UDPPeer()
        sender.send(RemoteProtocolTests.input(session: session), to: udpPort)
        _ = game.receive()
        game.send(Self.output, to: server.bridgePort!)
        XCTAssertEqual(sender.receive(), Self.output)
    }

    func testNewGameHelloRedirectsBridge() throws {
        let first = UDPPeer()
        try greet(first)
        let second = UDPPeer()
        try greet(second)
        let sender = UDPPeer()
        sender.send(RemoteProtocolTests.input(session: session), to: udpPort)
        XCTAssertNotNil(second.receive())
        XCTAssertNil(first.receive())
    }

    func testSessionEndsWithControlSocket() async throws {
        let game = UDPPeer()
        try greet(game)
        phone.close()
        for _ in 0..<50 where server.connectedDevice != nil { try await Task.sleep(for: .milliseconds(20)) }
        UDPPeer().send(RemoteProtocolTests.input(session: session), to: udpPort)
        XCTAssertNil(game.receive())
    }

    func testBridgeEnvironment() {
        XCTAssertEqual(server.bridgeEnvironment["ANYPS5_REMOTE_PAD"], "127.0.0.1:\(server.bridgePort!)")
        XCTAssertEqual(server.bridgePorts.count, 4)
        XCTAssertEqual(Set(server.bridgePorts).count, 4)
        XCTAssertEqual(server.bridgePorts.first, server.bridgePort)
        for (index, port) in server.bridgePorts.enumerated().dropFirst() {
            XCTAssertEqual(server.bridgeEnvironment["ANYPS5_REMOTE_PAD_\(index + 1)"], "127.0.0.1:\(port)")
        }
    }

    /// The game's hello on a bridge says which player that bridge's phone is.
    func testTheGameSaysWhichPlayerEachPhoneIs() async throws {
        var told = Self.hello
        told[8] = 2
        let game = UDPPeer()
        game.send(told, to: server.bridgePorts[0])
        for _ in 0..<50 where server.phonePlayers.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(server.phonePlayers, ["phone-1": 2])
        game.send(Self.hello, to: server.bridgePorts[0])
        for _ in 0..<50 where !server.phonePlayers.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(server.phonePlayers, [:])
    }

    /// Remote Play: a phone that asks for the picture gets the stream's packets where it sends
    /// its pad from, and a phone that did not ask gets none.
    func testTheStreamGoesToThePhoneThatAskedForIt() async throws {
        XCTAssertTrue(server.streamWishes.isEmpty)
        let sender = UDPPeer()
        sender.send(RemoteProtocolTests.input(session: session), to: udpPort)
        try await phone.send(.stream(on: true, width: 1280, height: 720))
        for _ in 0..<50 where server.streamWishes.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(server.streamWishes.first?.width, 1280)
        let packets = StreamPacket.video(Data(repeating: 5, count: 3000), number: 1, key: true, milliseconds: 0)
        server.sendStream(packets)
        for packet in packets { XCTAssertEqual(sender.receive(), packet) }
        try await phone.send(.stream(on: false, width: 0, height: 0))
        for _ in 0..<50 where !server.streamWishes.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        server.sendStream(packets)
        XCTAssertNil(sender.receive())
    }

    func testAStreamOnACableGoesOnTheControlChannel() async throws {
        let game = UDPPeer()
        try greet(game)
        try await phone.task.send(.data(RemoteProtocolTests.input(session: session)))
        try await phone.send(.stream(on: true, width: 640, height: 360))
        for _ in 0..<50 where server.streamWishes.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let packet = StreamPacket.audio(Data(repeating: 1, count: 960), number: 1, milliseconds: 0)
        server.sendStream([packet])
        let answer = Task { try await phone.task.receive() }
        let giveUp = Task { try await Task.sleep(for: .seconds(2)); phone.close() }
        defer { giveUp.cancel() }
        guard case .data(let back) = try await answer.value else { return XCTFail("not binary") }
        XCTAssertEqual(back, packet)
    }

    /// A phone on a cable has no UDP path: its pad comes on the control channel as binary
    /// messages, and the game's answers go back the same way.
    func testAPadOnTheControlChannelReachesTheGameAndBack() async throws {
        let game = UDPPeer()
        try greet(game)
        let input = RemoteProtocolTests.input(session: session)
        try await phone.task.send(.data(input))
        XCTAssertEqual(game.receive(), input)
        game.send(Self.output, to: server.bridgePort!)
        let answer = Task { try await phone.task.receive() }
        let giveUp = Task { try await Task.sleep(for: .seconds(2)); phone.close() }
        defer { giveUp.cancel() }
        guard case .data(let back) = try await answer.value else { return XCTFail("the answer was not binary") }
        XCTAssertEqual(back, Self.output)
    }

    func testAForeignPadOnTheControlChannelIsDropped() async throws {
        let game = UDPPeer()
        try greet(game)
        try await phone.task.send(.data(RemoteProtocolTests.input(session: session &+ 1)))
        XCTAssertNil(game.receive())
    }

    /// The second phone's pad goes to the game through the second bridge, and back.
    func testEachPhoneHasItsOwnBridge() async throws {
        let known = devices.add(id: "phone-2", name: "Galaxy")
        let other = FakePhone(port: server.controlPort!)
        try await other.hello(id: known.id, name: known.name, key: known.key)
        guard case .welcome(let otherSession, _, _, _, _) = try await other.receive() else { return XCTFail("no welcome") }
        let firstGame = UDPPeer()
        let secondGame = UDPPeer()
        firstGame.send(Self.hello, to: server.bridgePorts[0])
        secondGame.send(Self.hello, to: server.bridgePorts[1])
        Thread.sleep(forTimeInterval: 0.05)
        let sender = UDPPeer()
        let input = RemoteProtocolTests.input(session: otherSession)
        sender.send(input, to: udpPort)
        XCTAssertEqual(secondGame.receive(), input)
        XCTAssertNil(firstGame.receive())
        secondGame.send(Self.output, to: server.bridgePorts[1])
        XCTAssertEqual(sender.receive(), Self.output)
        let firstSender = UDPPeer()
        firstSender.send(RemoteProtocolTests.input(session: session), to: udpPort)
        XCTAssertNotNil(firstGame.receive())
        XCTAssertNil(secondGame.receive())
        other.close()
    }
}
