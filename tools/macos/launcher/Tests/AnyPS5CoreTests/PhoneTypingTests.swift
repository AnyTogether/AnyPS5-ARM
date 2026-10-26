import XCTest
@testable import AnyPS5Core

/// Typing on the phone when a game asks for text: the engine's prompt (APRK) and typed text
/// (APRT) datagrams, the control channel's textInput and typed messages, and the browser pad's.
final class PhoneTypingTests: XCTestCase {
    /// A prompt exactly as the engine lays it out (RemotePad::EncodePrompt).
    static func enginePrompt(id: UInt32, kind: UInt8 = 2, flags: UInt8 = 0, type: UInt8 = 0, enter: UInt8 = 0, maxLength: UInt16 = 16,
                             title: String = "", placeholder: String = "", text: String = "") -> Data {
        let parts = [title, placeholder, text].map { [UInt8]($0.utf8) }
        var bytes = [UInt8](repeating: 0, count: 24)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        put(UInt32(0x4B52_5041), at: 0)
        put(UInt16(1), at: 4)
        put(UInt16(24 + parts.map(\.count).reduce(0, +)), at: 6)
        put(id, at: 8)
        bytes[12] = kind
        bytes[13] = flags
        bytes[14] = type
        bytes[15] = enter
        put(maxLength, at: 16)
        for (index, part) in parts.enumerated() { put(UInt16(part.count), at: 18 + index * 2) }
        return Data(bytes + parts.joined())
    }

    func testTheEnginesPromptIsRead() throws {
        let packet = Self.enginePrompt(id: 9, kind: 2, flags: 1, type: 4, enter: 3, maxLength: 12, title: "Kod gir", placeholder: "0000", text: "12")
        let prompt = try XCTUnwrap(RemotePacket.prompt(packet) ?? nil)
        XCTAssertEqual(prompt, RemoteTextPrompt(id: 9, kind: "dialog", title: "Kod gir", placeholder: "0000", text: "12", maxLength: 12, multiline: true, keyboard: "number", enter: "go"))
        XCTAssertEqual(RemotePacket.promptPacket(prompt), packet, "the stand-in game's prompt is the engine's")
        let keyboard = try XCTUnwrap(RemotePacket.prompt(Self.enginePrompt(id: 2, kind: 1)) ?? nil)
        XCTAssertEqual(keyboard.kind, "keyboard")
    }

    func testAClosedPromptAndForeignPacketsAreToldApart() {
        let closed = RemotePacket.prompt(Self.enginePrompt(id: 0, kind: 0))
        XCTAssertNotNil(closed, "a closed prompt is a prompt")
        XCTAssertNil(closed ?? RemoteTextPrompt(id: 1), "that says none is asked for")
        var short = Self.enginePrompt(id: 3, title: "abc")
        short.removeLast()
        XCTAssertNil(RemotePacket.prompt(short), "lengths that do not add up")
        var kind = Self.enginePrompt(id: 3)
        kind[12] = 7
        XCTAssertNil(RemotePacket.prompt(kind), "an unknown kind")
        XCTAssertNil(RemotePacket.prompt(RemoteRelayTests.hello), "a hello is no prompt")
    }

    /// The typed text as the engine reads it (RemotePad::DecodeText): header, then UTF-8.
    func testTypedTextForTheEngine() {
        let packet = [UInt8](RemotePacket.text(prompt: 9, id: 4, action: .submit, text: "Ayşe 😀"))
        let utf8 = [UInt8]("Ayşe 😀".utf8)
        XCTAssertEqual(packet.count, 20 + utf8.count)
        XCTAssertEqual(Array(packet[0..<4]), [0x41, 0x50, 0x52, 0x54])
        XCTAssertEqual(Array(packet[4..<8]), [1, 0, UInt8(packet.count & 0xFF), UInt8(packet.count >> 8)])
        XCTAssertEqual(Array(packet[8..<17]), [9, 0, 0, 0, 4, 0, 0, 0, 1])
        XCTAssertEqual(Array(packet[18..<20]), [UInt8(utf8.count), 0])
        XCTAssertEqual(Array(packet[20...]), utf8)
        XCTAssertEqual(RemotePacket.text(prompt: 1, id: 1, action: .cancel, text: "")[16], 2)
        XCTAssertEqual(RemotePacket.text(prompt: 1, id: 1, action: .update, text: "")[16], 0)
        let long = RemotePacket.text(prompt: 1, id: 1, action: .update, text: String(repeating: "ğ", count: 6000))
        XCTAssertLessThanOrEqual(long.count, RemotePacket.largestText, "a long text is cut to one datagram")
        XCTAssertEqual((long.count - 20) % 2, 0, "on a character")
    }

    func testTheHelloSaysTheEngineTakesText() {
        var hello = RemoteRelayTests.hello
        XCTAssertFalse(RemotePacket.helloTakesText(hello))
        hello[9] = 3
        XCTAssertTrue(RemotePacket.helloTakesText(hello))
        XCTAssertTrue(RemotePacket.helloTakesPresses(hello))
    }

    func testTheMessagesRoundTrip() throws {
        let prompt = RemoteTextPrompt(id: 7, kind: "dialog", title: "Name", placeholder: "Hero", text: "Ab", maxLength: 16, multiline: false, keyboard: "latin", enter: "send")
        for message in [RemoteMessage.textInput(prompt), .textInput(nil), .typed(prompt: 7, text: "Kral ü", action: .submit), .typed(prompt: 7, text: "", action: .cancel)] {
            XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        }
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(RemoteMessage.textInput(prompt).text.utf8)) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "textInput")
        let inner = try XCTUnwrap(json["prompt"] as? [String: Any])
        XCTAssertEqual(inner["id"] as? Int, 7)
        XCTAssertEqual(inner["maxLength"] as? Int, 16)
        XCTAssertEqual(inner["keyboard"] as? String, "latin")
        let closed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(RemoteMessage.textInput(nil).text.utf8)) as? [String: Any])
        XCTAssertTrue(closed["prompt"] is NSNull, "none is said with a null prompt")
        let phone = #"{"type":"typed","prompt":7,"text":"abc","action":"update"}"#
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: Data(phone.utf8)), .typed(prompt: 7, text: "abc", action: .update))
    }

    func testTheBrowserPadsSide() throws {
        XCTAssertEqual(BrowserPadMessage.parse(#"{"t":"type","id":7,"text":"Selam","a":"submit"}"#), .typed(prompt: 7, text: "Selam", action: .submit))
        XCTAssertNil(BrowserPadMessage.parse(#"{"t":"type","id":7,"text":"x","a":"explode"}"#))
        XCTAssertNil(BrowserPadMessage.parse(#"{"t":"type","id":0,"text":"x","a":"submit"}"#))
        XCTAssertNil(BrowserPadMessage.parse(#"{"t":"type","id":7,"a":"submit"}"#))
        let long = #"{"t":"type","id":7,"a":"update","text":""# + String(repeating: "a", count: 3000) + #""}"#
        XCTAssertNotNil(BrowserPadMessage.parse(long), "a long text is one of the page's")
        let prompt = RemoteTextPrompt(id: 7, kind: "dialog", title: "Name", text: "Ab", maxLength: 16, keyboard: "number")
        let open = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(BrowserPadReply.ime(prompt).text.utf8)) as? [String: Any])
        XCTAssertEqual(open["t"] as? String, "ime")
        XCTAssertEqual(open["id"] as? Int, 7)
        XCTAssertEqual(open["title"] as? String, "Name")
        XCTAssertEqual(open["max"] as? Int, 16)
        XCTAssertEqual(open["kb"] as? String, "number")
        XCTAssertEqual(BrowserPadReply.ime(nil).text, #"{"id":0,"t":"ime"}"#)
    }
}

/// The phone server between the game's prompts and the phones' keyboards.
final class PhoneTypingRelayTests: XCTestCase {
    var file: URL!
    var devices: PairedDevices!
    var server: RemoteServer!
    var phone: FakePhone!

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("typing-\(UUID().uuidString).json")
        devices = PairedDevices(file: file)
        server = RemoteServer(name: "Test Mac", devices: devices, events: RemoteServer.Events(), advertise: false)
        try server.start()
        phone = try await welcomed(id: "phone-1", name: "Pixel 8")
    }

    override func tearDown() async throws {
        phone.close()
        server.stop()
        try? FileManager.default.removeItem(at: file)
    }

    func welcomed(id: String, name: String) async throws -> FakePhone {
        let known = devices.add(id: id, name: name)
        let phone = FakePhone(port: server.controlPort!)
        try await phone.hello(id: id, name: name, key: known.key)
        guard case .welcome = try await phone.receive() else { throw URLError(.badServerResponse) }
        return phone
    }

    /// A game whose engine takes text, said hello on the first bridge.
    func game() -> UDPPeer {
        let game = UDPPeer()
        var hello = RemoteRelayTests.hello
        hello[9] = 3
        game.send(hello, to: server.bridgePorts[0])
        Thread.sleep(forTimeInterval: 0.05)
        return game
    }

    func nextTextInput(_ phone: FakePhone) async throws -> RemoteTextPrompt?? {
        for _ in 0..<10 {
            if case .textInput(let prompt) = try await phone.receive() { return .some(prompt) }
        }
        return nil
    }

    func receiveLarge(_ game: UDPPeer) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 9000)
        let got = recv(game.socket, &buffer, buffer.count, 0)
        return got < 0 ? nil : Data(buffer.prefix(got))
    }

    func testThePromptReachesThePhoneAndTheTextTheGame() async throws {
        let game = game()
        game.send(PhoneTypingTests.enginePrompt(id: 5, title: "Name your save", text: "Save"), to: server.bridgePorts[0])
        let told = try await nextTextInput(phone)
        XCTAssertEqual(told??.id, 5)
        XCTAssertEqual(told??.title, "Name your save")
        XCTAssertEqual(server.textPrompt?.id, 5)
        // The engine says it again every second: the phone is not told twice.
        game.send(PhoneTypingTests.enginePrompt(id: 5, title: "Name your save", text: "Save"), to: server.bridgePorts[0])
        try await phone.send(.typed(prompt: 5, text: "Kral", action: .submit))
        let typed = receiveLarge(game)
        XCTAssertEqual(typed.map { [UInt8]($0.prefix(4)) }, [0x41, 0x50, 0x52, 0x54])
        XCTAssertEqual(typed.map { Array($0.suffix(4)) }, Array("Kral".utf8))
        XCTAssertNotNil(receiveLarge(game), "sent twice in case one is lost")
        let away = try await nextTextInput(phone)
        XCTAssertEqual(away.map { $0 == nil }, true, "answered, the keyboard goes away")
        game.send(PhoneTypingTests.enginePrompt(id: 5, title: "Name your save", text: "Save"), to: server.bridgePorts[0])
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertNil(server.textPrompt, "the answered prompt said again does not come back")
    }

    func testTextForAnotherPromptOrAnOlderEngineIsDropped() async throws {
        let older = UDPPeer()
        older.send(RemoteRelayTests.hello, to: server.bridgePorts[0])
        Thread.sleep(forTimeInterval: 0.05)
        older.send(PhoneTypingTests.enginePrompt(id: 5), to: server.bridgePorts[0])
        _ = try await nextTextInput(phone)
        try await phone.send(.typed(prompt: 5, text: "x", action: .submit))
        XCTAssertNil(receiveLarge(older), "an engine whose hello does not take text gets none")
        let game = game()
        try await phone.send(.typed(prompt: 4, text: "x", action: .submit))
        XCTAssertNil(receiveLarge(game), "text for a prompt that is not open is dropped")
    }

    func testAPhoneThatComesLaterSeesThePromptAndAClosedOneGoes() async throws {
        let game = game()
        game.send(PhoneTypingTests.enginePrompt(id: 8, text: "abc"), to: server.bridgePorts[0])
        _ = try await nextTextInput(phone)
        let late = try await welcomed(id: "phone-2", name: "Galaxy")
        let seen = try await nextTextInput(late)
        XCTAssertEqual(seen??.text, "abc")
        game.send(PhoneTypingTests.enginePrompt(id: 0, kind: 0, maxLength: 0), to: server.bridgePorts[0])
        let closed = try await nextTextInput(late)
        XCTAssertEqual(closed.map { $0 == nil }, true)
        late.close()
    }

    func testAPromptTheGameStopsSayingEnds() async throws {
        let game = game()
        game.send(PhoneTypingTests.enginePrompt(id: 3), to: server.bridgePorts[0])
        _ = try await nextTextInput(phone)
        let ended = try await nextTextInput(phone)
        XCTAssertEqual(ended.map { $0 == nil }, true, "a game gone with its keyboard open leaves the phones")
        XCTAssertNil(server.textPrompt)
    }
}
