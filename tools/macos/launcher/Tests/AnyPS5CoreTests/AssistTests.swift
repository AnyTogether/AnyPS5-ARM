import XCTest
@testable import AnyPS5Core

/// Assist: another device helps the first player. The engine's wire (byte 13 = 1 on an input,
/// the APRA datagram for the Mac's controllers), the setting, the phone server and share play.
final class AssistTests: XCTestCase {
    func testTheAssistDatagramAsTheEngineReadsIt() {
        XCTAssertEqual([UInt8](RemotePacket.assist(controllers: true)), [0x41, 0x50, 0x52, 0x41, 1, 0, 16, 0, 1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual([UInt8](RemotePacket.assist(controllers: false))[8], 0)
        var hello = RemoteRelayTests.hello
        XCTAssertFalse(RemotePacket.helloTakesAssist(hello))
        hello[9] = 7
        XCTAssertTrue(RemotePacket.helloTakesAssist(hello))
    }

    func testAHelpersInputIsMarked() {
        let input = RemoteProtocolTests.input(session: 9)
        let marked = RemotePacket.helping(input)
        XCTAssertEqual(marked[13], 1)
        XCTAssertEqual(marked.count, input.count)
        var unmarked = marked
        unmarked[13] = 0
        XCTAssertEqual(unmarked, input, "nothing else changes")
        XCTAssertEqual(RemotePacket.helping(RemoteRelayTests.hello), RemoteRelayTests.hello, "only inputs are marked")
    }

    func testTheSetting() {
        XCTAssertEqual(AssistTarget(stored: nil), .off)
        XCTAssertEqual(AssistTarget(stored: ""), .off)
        XCTAssertEqual(AssistTarget(stored: "controllers"), .controllers)
        XCTAssertEqual(AssistTarget(stored: "phone-1"), .device("phone-1"))
        for target in [AssistTarget.off, .controllers, .device("browser-x")] { XCTAssertEqual(AssistTarget(stored: target.stored), target) }
        XCTAssertTrue(AssistTarget.controllers.controllers)
        XCTAssertEqual(AssistTarget.controllers.devices, [])
        XCTAssertEqual(AssistTarget.device("phone-1").devices, ["phone-1"])
        XCTAssertFalse(AssistTarget.device("phone-1").controllers)
    }

    func testTheChoicesKeepAChosenDeviceThatLeft() {
        let connected = [(id: "phone-1", name: "Pixel 8"), (id: "phone-2", name: "iPhone")]
        let choices = AssistTarget.choices(devices: connected, chosen: .device("phone-9"), names: ["phone-9": "Galaxy"])
        XCTAssertEqual(choices.map(\.target), [.off, .controllers, .device("phone-1"), .device("phone-2"), .device("phone-9")])
        XCTAssertEqual(choices.last?.name, "Galaxy")
        XCTAssertEqual(AssistTarget.choices(devices: connected, chosen: .device("phone-1"), names: [:]).count, 4)
    }

    /// A share play guest set to help is marked as a helper instead of carrying its pad.
    func testAShareGuestCanHelp() {
        final class Bridges: SharePadBridges, @unchecked Sendable {
            var sent: [Data] = []
            func reservePadBridge() -> Int? { 3 }
            func releasePadBridge(_ bridge: Int) {}
            func sendPad(_ data: Data, bridge: Int) { sent.append(data) }
        }
        let bridges = Bridges()
        let router = SharePadRouter(bridges: bridges)
        router.update(pads: ["friend": 2])
        XCTAssertTrue(router.receive(RemoteProtocolTests.input(session: 5), from: "friend"))
        XCTAssertEqual(bridges.sent.last?[13], 2)
        router.assist = ["friend"]
        router.receive(RemoteProtocolTests.input(session: 5), from: "friend")
        XCTAssertEqual(bridges.sent.last?[13], 1)
        router.assist = []
        router.receive(RemoteProtocolTests.input(session: 5), from: "friend")
        XCTAssertEqual(bridges.sent.last?[13], 2, "back to their own pad")
    }
}

/// The phone server marks a helping phone's pad and tells the engine whether controllers help.
final class AssistRelayTests: XCTestCase {
    var file: URL!
    var server: RemoteServer!
    var phone: FakePhone!
    var session: UInt64 = 0
    var udpPort: UInt16 = 0

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("assist-\(UUID().uuidString).json")
        let devices = PairedDevices(file: file)
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

    func game(takesAssist: Bool) -> UDPPeer {
        let game = UDPPeer()
        var hello = RemoteRelayTests.hello
        hello[9] = takesAssist ? 7 : 3
        game.send(hello, to: server.bridgePorts[0])
        Thread.sleep(forTimeInterval: 0.05)
        return game
    }

    func testAHelpingPhonesPadIsMarked() throws {
        let game = game(takesAssist: true)
        _ = game.receive()
        let sender = UDPPeer()
        let input = RemoteProtocolTests.input(session: session)
        sender.send(input, to: udpPort)
        XCTAssertEqual(game.receive()?[13], 0, "a phone that does not help is a player of its own")
        server.setAssist(devices: ["phone-1"], controllers: false)
        Thread.sleep(forTimeInterval: 0.05)
        sender.send(input, to: udpPort)
        XCTAssertEqual(game.receive()?[13], 1, "set to help, its pad is marked")
        server.setAssist(devices: [], controllers: false)
        Thread.sleep(forTimeInterval: 0.05)
        sender.send(input, to: udpPort)
        XCTAssertEqual(game.receive()?[13], 0)
    }

    func testTheEngineHearsWhetherControllersHelp() throws {
        let game = game(takesAssist: true)
        XCTAssertEqual(game.receive().map { [UInt8]($0) }, [UInt8](RemotePacket.assist(controllers: false)), "each hello is answered with the assist flags")
        server.setAssist(devices: [], controllers: true)
        XCTAssertEqual(game.receive(), RemotePacket.assist(controllers: true), "a change is said at once")
        var hello = RemoteRelayTests.hello
        hello[9] = 7
        game.send(hello, to: server.bridgePorts[0])
        XCTAssertEqual(game.receive(), RemotePacket.assist(controllers: true))
        let older = self.game(takesAssist: false)
        XCTAssertNil(older.receive(), "an engine that does not take assist is not told")
    }
}
