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

    func testLauncherModeMessagesRoundTrip() throws {
        let game = RemoteGame(id: "/Games/Silksong", name: "Hollow Knight: Silksong", state: .installed, trophies: "3/47", art: "a1")
        let messages: [RemoteMessage] = [
            .library(games: [game], selected: game.id, running: nil, language: "en"),
            .art(id: game.id, icon: "aWNvbg==", background: nil),
            .command(name: "select"), .select(id: game.id), .launch(id: game.id), .close, .home, .wantArt(id: game.id),
        ]
        for message in messages {
            XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        }
    }

    func testLibraryAsThePhoneReadsIt() throws {
        let message = RemoteMessage.library(games: [RemoteGame(id: "x", name: "DOOM", state: .running, trophies: nil, art: "b")], selected: "x", running: "x", language: "tr")
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(message)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "library")
        XCTAssertEqual(json?["language"] as? String, "tr")
        let games = json?["games"] as? [[String: Any]]
        XCTAssertEqual(games?.first?["state"] as? String, "running")
        XCTAssertEqual(games?.first?["name"] as? String, "DOOM")
    }

    func testAGameCarriesThePhoneLayoutSavedForIt() throws {
        let layout = #"{"cross":{"x":0.8,"y":0.6,"scale":1.2}}"#
        let game = RemoteGame(id: "g", name: "DOOM", state: .installed, trophies: nil, art: "a", layout: layout)
        let message = RemoteMessage.library(games: [game], selected: nil, running: nil, language: "en")
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        let older = #"{"type":"library","games":[{"id":"g","name":"DOOM","state":"installed","art":"a"}],"language":"en"}"#
        guard case .library(let games, _, _, _) = try JSONDecoder().decode(RemoteMessage.self, from: Data(older.utf8)) else { return XCTFail("no library") }
        XCTAssertNil(games.first?.layout)
    }

    /// The theme in use tints the phone: its deep and middle tones and its accent.
    func testTheLookIsToldToThePhone() throws {
        let message = RemoteMessage.look(deep: "#0A0014", middle: "#4A0E6B", accent: "#FF4FD8")
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(message)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "look")
        XCTAssertEqual(json?["accent"] as? String, "#FF4FD8")
    }

    func testATrophyIsToldToThePhone() throws {
        let message = RemoteMessage.trophy(name: "Pharloom's Heart", detail: "Acquire all other trophies", grade: "platinum", icon: "aWNvbg==")
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(message)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "trophy")
        XCTAssertEqual(json?["grade"] as? String, "platinum")
    }

    func testWhatTheLauncherIsDoingIsToldToThePhone() throws {
        let activity = RemoteActivity(id: "PPSA15065", phase: .relink, updating: true, fraction: 0.42, elapsed: 12.5)
        let message = RemoteMessage.activity(activity)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(message)) as? [String: Any]
        XCTAssertEqual(json?["type"] as? String, "activity")
        let inner = json?["activity"] as? [String: Any]
        XCTAssertEqual(inner?["phase"] as? String, "relink")
        XCTAssertEqual(inner?["fraction"] as? Double, 0.42)
        let idle = RemoteMessage.activity(nil)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: Data(#"{"type":"activity","activity":null}"#.utf8)), idle)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(idle)), idle)
    }

    func testAnActivityChangesForThePhoneOnlyWhenItLooksDifferent() {
        let base = RemoteActivity(id: "g", phase: .relink, updating: false, fraction: 0.40, elapsed: 3)
        var later = base
        later.elapsed = 9
        later.fraction = 0.404
        XCTAssertTrue(base.looksLike(later))
        later.fraction = 0.42
        XCTAssertFalse(base.looksLike(later))
        later = base
        later.phase = .copy
        XCTAssertFalse(base.looksLike(later))
    }

    func testThePhoneSavesALayout() throws {
        let message = RemoteMessage.saveLayout(id: "g", layout: #"{"r1":{"hidden":true}}"#)
        XCTAssertEqual(try JSONDecoder().decode(RemoteMessage.self, from: try JSONEncoder().encode(message)), message)
        XCTAssertEqual(RemoteMessage.saveLayout(id: "g", layout: nil), try JSONDecoder().decode(RemoteMessage.self, from: Data(#"{"type":"saveLayout","id":"g"}"#.utf8)))
    }

    func testGameSettingsKeepAPhoneLayoutAndReadOlderFiles() throws {
        var settings = GameSettings()
        settings.phoneLayout = #"{"square":{"opacity":0.5}}"#
        XCTAssertEqual(try JSONDecoder().decode(GameSettings.self, from: try JSONEncoder().encode(settings)).phoneLayout, settings.phoneLayout)
        XCTAssertNil(try JSONDecoder().decode(GameSettings.self, from: try JSONEncoder().encode(GameSettings())).phoneLayout)
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
