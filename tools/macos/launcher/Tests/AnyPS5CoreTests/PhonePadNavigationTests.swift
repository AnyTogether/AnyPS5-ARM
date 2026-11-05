import XCTest
@testable import AnyPS5Core

/// The phones' pads on the launcher's own screens: the packet read as a controller's state, the
/// changes and the let-go of a phone gone quiet, and the server handing them over only while
/// no game takes them.
final class PhonePadNavigationTests: XCTestCase {
    func packet(_ buttons: UInt32, sticks: [UInt8] = [128, 128, 128, 128], session: UInt64 = 7) -> Data {
        var pad = SharePadState()
        pad.buttons = buttons
        pad.sticks = sticks
        return pad.packet(sequence: 1, sentMicros: 0, session: session)
    }

    func testAPacketReadsAsTheControllersButtonsAndSticks() throws {
        let state = try XCTUnwrap(RemotePacket.padState(packet(SharePadState.Button.cross | SharePadState.Button.up | SharePadState.Button.options, sticks: [255, 0, 128, 128])))
        XCTAssertEqual(state.pressed, [.south, .dpadUp, .start])
        XCTAssertEqual(state.leftX, 1, accuracy: 0.01)
        XCTAssertEqual(state.leftY, -1, accuracy: 0.01, "up is negative, as the screens draw it")
        XCTAssertEqual(state.rightX, 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(RemotePacket.padState(packet(0))), .idle, "a pad at rest is idle")
        XCTAssertNil(RemotePacket.padState(Data(repeating: 0, count: 80)), "not an input packet")
    }

    func testEveryButtonOfTheWireHasItsName() throws {
        let bits: [(UInt32, PadButton)] = [(SharePadState.Button.circle, .east), (SharePadState.Button.triangle, .north), (SharePadState.Button.square, .west),
                                           (SharePadState.Button.l1, .l1), (SharePadState.Button.r1, .r1), (SharePadState.Button.left, .dpadLeft),
                                           (SharePadState.Button.right, .dpadRight), (SharePadState.Button.down, .dpadDown), (SharePadState.Button.touchPad, .touchpad)]
        for (bit, button) in bits {
            XCTAssertEqual(try XCTUnwrap(RemotePacket.padState(packet(bit))).pressed, [button])
        }
    }

    func testOnlyChangesAreToldAndAQuietPhoneLetsGo() {
        var feed = PhonePadNavigation()
        let held = PadState(pressed: [.dpadDown])
        XCTAssertNil(feed.heard("p", .idle, at: 0), "a phone at rest says nothing")
        XCTAssertEqual(feed.heard("p", held, at: 0.1), held)
        XCTAssertNil(feed.heard("p", held, at: 0.2), "the same pad again is no change")
        XCTAssertEqual(feed.quiet(at: 0.5), [], "not quiet long enough")
        XCTAssertEqual(feed.quiet(at: 0.2 + PhonePadNavigation.silence), ["p"], "gone quiet holding down: let go")
        XCTAssertEqual(feed.quiet(at: 5), [], "once")
        XCTAssertEqual(feed.heard("p", held, at: 6), held, "held again after the let-go")
        XCTAssertTrue(feed.left("p"), "left holding something")
        XCTAssertFalse(feed.left("p"))
        _ = feed.heard("a", held, at: 7)
        XCTAssertEqual(feed.releaseAll(), ["a"])
    }

    func testTheServerHandsAPhonesPadToTheLauncherOnlyWhileAsked() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("phone-pad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let devices = PairedDevices(file: file)
        let known = devices.add(id: "phone-1", name: "Pixel 8")
        let heard = Locked<[(String, PadState)]>([])
        let server = RemoteServer(name: "Test Mac", devices: devices, events: RemoteServer.Events(pad: { id, state in heard.withLock { $0.append((id, state)) } }), advertise: false)
        try server.start()
        defer { server.stop() }
        let phone = FakePhone(port: server.controlPort!)
        defer { phone.close() }
        try await phone.hello(key: known.key)
        guard case .welcome(let session, let udpPort, _, _, _) = try await phone.receive() else { return XCTFail("no welcome") }
        let sender = UDPPeer()
        func waitFor(_ count: Int) async -> Bool {
            for _ in 0..<100 where heard.value.count < count { try? await Task.sleep(for: .milliseconds(20)) }
            return heard.value.count >= count
        }

        // A game in front: nothing for the launcher.
        sender.send(packet(SharePadState.Button.cross, session: session), to: udpPort)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(heard.value.isEmpty)

        server.padsDriveLauncher = true
        sender.send(packet(SharePadState.Button.down, session: session), to: udpPort)
        let first = await waitFor(1)
        XCTAssertTrue(first)
        XCTAssertEqual(heard.value.first?.0, "phone-1")
        XCTAssertEqual(heard.value.first?.1.pressed, [.dpadDown])
        // The phone goes quiet holding down: the launcher hears it let go.
        let released = await waitFor(2)
        XCTAssertTrue(released)
        XCTAssertEqual(heard.value.last?.1, .idle)

        // Another session's packet is not this phone's.
        sender.send(packet(SharePadState.Button.cross, session: session &+ 1), to: udpPort)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(heard.value.count, 2)

        // The browser pad's way (and a phone's on a cable): the pad on the control channel.
        try await phone.task.send(.data(packet(SharePadState.Button.options, session: session)))
        let options = await waitFor(3)
        XCTAssertTrue(options)
        XCTAssertEqual(heard.value.last?.1.pressed, [.start])

        // A game starts: what the phone held is let go, and nothing more comes.
        server.padsDriveLauncher = false
        let letGo = await waitFor(4)
        XCTAssertTrue(letGo)
        XCTAssertEqual(heard.value.last?.1, .idle)
        sender.send(packet(SharePadState.Button.cross, session: session), to: udpPort)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(heard.value.count, 4)
    }
}
