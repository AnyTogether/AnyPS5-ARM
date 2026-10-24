import XCTest
@testable import AnyPS5Core

/// A phone's side of the control channel, for the tests.
final class FakePhone {
    let task: URLSessionWebSocketTask

    init(port: UInt16) {
        task = URLSession(configuration: .ephemeral).webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
    }

    func send(_ message: RemoteMessage) async throws {
        try await task.send(.string(message.text))
    }

    func receive() async throws -> RemoteMessage {
        switch try await task.receive() {
        case .string(let text): return try JSONDecoder().decode(RemoteMessage.self, from: Data(text.utf8))
        case .data(let data): return try JSONDecoder().decode(RemoteMessage.self, from: data)
        @unknown default: throw URLError(.cannotParseResponse)
        }
    }

    func hello(id: String = "phone-1", name: String = "Pixel 8", key: String? = nil, version: Int = 1) async throws {
        try await send(.hello(protocol: version, deviceID: id, deviceName: name, key: key))
    }

    func close() { task.cancel(with: .goingAway, reason: nil) }
}

/// The server's events, collected for the tests.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pairings: [PairingRequest] = []
    private(set) var connected: [String] = []
    private(set) var disconnects = 0
    private(set) var latencies: [Double] = []
    private(set) var requests: [RemoteMessage] = []
    private(set) var connecting: [String?] = []

    var events: RemoteServer.Events {
        RemoteServer.Events(
            pairing: { request in self.lock.withLock { self.pairings.append(request) } },
            connected: { name in self.lock.withLock { self.connected.append(name) } },
            disconnected: { self.lock.withLock { self.disconnects += 1 } },
            latency: { value in self.lock.withLock { self.latencies.append(value) } },
            request: { message in self.lock.withLock { self.requests.append(message) } },
            connecting: { name in self.lock.withLock { self.connecting.append(name) } })
    }

    func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock(condition) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

final class RemoteServerTests: XCTestCase {
    var file: URL!
    var devices: PairedDevices!
    var log: EventLog!
    var server: RemoteServer!

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("remote-\(UUID().uuidString).json")
        devices = PairedDevices(file: file)
        log = EventLog()
        server = RemoteServer(name: "Test Mac", devices: devices, events: log.events, advertise: false)
        try server.start()
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: file)
    }

    func phone() -> FakePhone { FakePhone(port: server.controlPort!) }

    /// A phone allowed before, welcomed at once.
    func pairedPhone() async throws -> FakePhone {
        let device = devices.add(id: "phone-1", name: "Pixel 8")
        let phone = phone()
        try await phone.hello(key: device.key)
        guard case .welcome = try await phone.receive() else { throw URLError(.badServerResponse) }
        return phone
    }

    func testAWelcomedPhoneIsHeardAndToldTheLibrary() async throws {
        let phone = try await pairedPhone()
        try await phone.send(.command(name: "left"))
        try await phone.send(.launch(id: "g"))
        let heard = await log.waitFor { self.log.requests.count == 2 }
        XCTAssertTrue(heard)
        XCTAssertEqual(log.requests, [.command(name: "left"), .launch(id: "g")])
        let library = RemoteMessage.library(games: [], selected: nil, running: nil, language: "en")
        server.publish(library)
        let received = try await phone.receive()
        XCTAssertEqual(received, library)
    }

    func testAPhoneIsConnectingFromItsHelloUntilItIsWelcomed() async throws {
        let phone = phone()
        try await phone.hello()
        _ = try await phone.receive()
        let asking = await log.waitFor { self.log.connecting == ["Pixel 8"] }
        XCTAssertTrue(asking)
        XCTAssertTrue(log.connected.isEmpty)
        server.respond(to: log.pairings[0].id, allow: true)
        _ = try await phone.receive()
        let welcomed = await log.waitFor { self.log.connected == ["Pixel 8"] }
        XCTAssertTrue(welcomed)
    }

    func testAPhoneThatGivesUpBeforeItIsWelcomedStopsConnecting() async throws {
        let phone = phone()
        try await phone.hello()
        _ = try await phone.receive()
        phone.close()
        let gone = await log.waitFor { self.log.connecting == ["Pixel 8", nil] }
        XCTAssertTrue(gone)
        XCTAssertEqual(log.disconnects, 0)
    }

    func testARefusedPhoneStopsConnecting() async throws {
        let phone = phone()
        try await phone.hello()
        _ = try await phone.receive()
        let asked = await log.waitFor { !self.log.pairings.isEmpty }
        XCTAssertTrue(asked)
        server.respond(to: log.pairings[0].id, allow: false)
        let gone = await log.waitFor { self.log.connecting == ["Pixel 8", nil] }
        XCTAssertTrue(gone)
    }

    func testAPhoneNotWelcomedIsNotHeard() async throws {
        let phone = phone()
        try await phone.hello()
        _ = try await phone.receive()
        try await phone.send(.home)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(log.requests.isEmpty)
    }

    func testUnknownPhoneIsAskedThenWelcomed() async throws {
        server.togetherServer = "https://together.example.org"
        let phone = phone()
        try await phone.hello()
        guard case .pairing(let code) = try await phone.receive() else { return XCTFail("no pairing message") }
        XCTAssertEqual(code.count, 4)
        XCTAssertTrue(code.allSatisfy(\.isNumber))
        let asked = await log.waitFor { !self.log.pairings.isEmpty }
        XCTAssertTrue(asked)
        XCTAssertEqual(log.pairings.first?.code, code)
        XCTAssertEqual(log.pairings.first?.deviceName, "Pixel 8")
        server.respond(to: log.pairings[0].id, allow: true)
        guard case .welcome(_, _, let macName, let key, let together) = try await phone.receive() else { return XCTFail("no welcome") }
        XCTAssertEqual(macName, "Test Mac")
        XCTAssertEqual(together, "https://together.example.org", "the phone learns which AnyTogether the Mac uses")
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32)
        XCTAssertEqual(devices.all.count, 1)
        let connected = await log.waitFor { self.log.connected == ["Pixel 8"] }
        XCTAssertTrue(connected)
        XCTAssertEqual(server.connectedDevice, "Pixel 8")
        phone.close()
    }

    func testDeniedPhoneIsRejected() async throws {
        let phone = phone()
        try await phone.hello()
        _ = try await phone.receive()
        _ = await log.waitFor { !self.log.pairings.isEmpty }
        server.respond(to: log.pairings[0].id, allow: false)
        let answer = try await phone.receive()
        XCTAssertEqual(answer, .rejected(reason: "denied"))
        do {
            _ = try await phone.receive()
            XCTFail("the socket stayed open")
        } catch {}
        XCTAssertTrue(devices.all.isEmpty)
    }

    func testKnownKeyIsWelcomedWithoutPrompt() async throws {
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let phone = phone()
        try await phone.hello(key: known.key)
        guard case .welcome = try await phone.receive() else { return XCTFail("no welcome") }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(log.pairings.isEmpty)
        phone.close()
    }

    func testASecondPhoneIsAskedWhileTheFirstIsConnected() async throws {
        let first = try await pairedPhone()
        let second = phone()
        try await second.hello(id: "phone-2", name: "Galaxy")
        guard case .pairing = try await second.receive() else { return XCTFail("the second phone was not asked about") }
        let asked = await log.waitFor { self.log.pairings.count == 1 }
        XCTAssertTrue(asked)
        server.respond(to: log.pairings[0].id, allow: true)
        guard case .welcome = try await second.receive() else { return XCTFail("the second phone was not welcomed") }
        XCTAssertEqual(server.connectedDevices, ["Pixel 8", "Galaxy"])
        XCTAssertEqual(server.connectedDevice, "Pixel 8")
        second.close()
        first.close()
    }

    func testAnotherNewPhoneWaitsWhileOneIsAskedAbout() async throws {
        let asked = phone()
        try await asked.hello(id: "phone-2", name: "Galaxy")
        _ = try await asked.receive()
        let other = phone()
        try await other.hello(id: "phone-3", name: "iPhone")
        let answer = try await other.receive()
        XCTAssertEqual(answer, .rejected(reason: "busy"))
        asked.close()
    }

    func testAFifthPhoneIsBusy() async throws {
        var phones: [FakePhone] = []
        for number in 1...4 {
            let device = devices.add(id: "phone-\(number)", name: "Phone \(number)")
            let phone = phone()
            try await phone.hello(id: device.id, name: device.name, key: device.key)
            guard case .welcome = try await phone.receive() else { return XCTFail("phone \(number) was not welcomed") }
            phones.append(phone)
        }
        let fifth = devices.add(id: "phone-5", name: "Phone 5")
        let extra = phone()
        try await extra.hello(id: fifth.id, name: fifth.name, key: fifth.key)
        let answer = try await extra.receive()
        XCTAssertEqual(answer, .rejected(reason: "busy"))
        for phone in phones { phone.close() }
    }

    func testAPhoneThatLeavesGivesItsPlaceBack() async throws {
        let first = try await pairedPhone()
        let device = devices.add(id: "phone-2", name: "Galaxy")
        let second = phone()
        try await second.hello(id: device.id, name: device.name, key: device.key)
        _ = try await second.receive()
        first.close()
        let gone = await log.waitFor { self.log.disconnects == 1 }
        XCTAssertTrue(gone)
        XCTAssertEqual(server.connectedDevices, ["Galaxy"])
        second.close()
    }

    func testSameDeviceTakesOverAnAbandonedConnection() async throws {
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let gone = phone()
        try await gone.hello(key: known.key)
        _ = try await gone.receive()
        let back = phone()
        try await back.hello(key: known.key)
        guard case .welcome = try await back.receive() else { return XCTFail("the returning phone was not welcomed") }
        do {
            _ = try await gone.receive()
            XCTFail("the abandoned connection stayed open")
        } catch {}
        XCTAssertEqual(server.connectedDevice, "Pixel 8")
        back.close()
    }

    func testRestartsOnTheSamePortRightAway() async throws {
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let port = UInt16.random(in: 50000...59000)
        let first = RemoteServer(name: "Test Mac", devices: devices, events: log.events, advertise: false, controlPort: port)
        try first.start()
        let phone = FakePhone(port: port)
        try await phone.hello(key: known.key)
        _ = try await phone.receive()
        first.stop()
        let second = RemoteServer(name: "Test Mac", devices: devices, events: log.events, advertise: false, controlPort: port)
        XCTAssertNoThrow(try second.start())
        second.stop()
    }

    func testBridgeUsesTheRequestedPort() throws {
        let port = UInt16.random(in: 50000...59000)
        let bridged = RemoteServer(name: "Test Mac", devices: devices, events: log.events, advertise: false, bridgePort: port)
        try bridged.start()
        XCTAssertEqual(bridged.bridgePort, port)
        bridged.stop()
    }

    func testWrongProtocolIsRejected() async throws {
        let phone = phone()
        try await phone.hello(version: 2)
        let answer = try await phone.receive()
        XCTAssertEqual(answer, .rejected(reason: "protocol"))
    }

    func testLatencyIsReported() async throws {
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let phone = phone()
        try await phone.hello(key: known.key)
        _ = try await phone.receive()
        try await phone.send(.latency(milliseconds: 9.5))
        let reported = await log.waitFor { self.log.latencies == [9.5] }
        XCTAssertTrue(reported)
        phone.close()
    }

    func testDisconnectIsReported() async throws {
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let phone = phone()
        try await phone.hello(key: known.key)
        _ = try await phone.receive()
        phone.close()
        let gone = await log.waitFor { self.log.disconnects == 1 }
        XCTAssertTrue(gone)
        XCTAssertNil(server.connectedDevice)
    }
}
