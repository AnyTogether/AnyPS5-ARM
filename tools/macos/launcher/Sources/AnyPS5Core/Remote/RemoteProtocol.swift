import Foundation

/// A game as the phone lists it. `art` changes whenever its icon or background does, so the
/// phone asks for the pictures again only then.
public struct RemoteGame: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case installed, update, locked, installing, starting, running, unavailable
    }

    public var id: String
    public var name: String
    public var state: State
    public var trophies: String?
    public var art: String
    /// The phone's pad layout saved for this game (the phone's own JSON), nil for the default.
    public var layout: String?

    public init(id: String, name: String, state: State, trophies: String?, art: String, layout: String? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.trophies = trophies
        self.art = art
        self.layout = layout
    }
}

/// A message on the phone's control channel: one JSON object per WebSocket text frame, told
/// apart by its `type`.
public enum RemoteMessage: Codable, Equatable, Sendable {
    /// The phone introduces itself; `key` is the one a previous pairing gave it.
    case hello(protocol: Int, deviceID: String, deviceName: String, key: String?)
    /// The Mac is asking its user to allow the phone; both show `code`.
    case pairing(code: String)
    /// The phone may send pad packets with `session` to `udpPort`; `key` lets it in next time.
    case welcome(session: UInt64, udpPort: UInt16, macName: String, key: String)
    case rejected(reason: String)
    /// The phone's measured latency, every two seconds.
    case latency(milliseconds: Double)
    /// The launcher's games as it shows them, with the one selected, the one playing and the
    /// language, sent again whenever any of it changes.
    case library(games: [RemoteGame], selected: String?, running: String?, language: String)
    /// A game's pictures as base64 JPEG, after the phone asked with `wantArt`.
    case art(id: String, icon: String?, background: String?)
    case wantArt(id: String)
    /// A move on the launcher's screen: left, right, up, down, select, back or options.
    case command(name: String)
    case select(id: String)
    /// What Play does for the game; another game playing is stopped first.
    case launch(id: String)
    /// Stops the game playing.
    case close
    /// The PS button: the launcher comes in front of the game.
    case home
    /// The phone's pad layout for a game, kept with the game's settings; nil goes back to the default.
    case saveLayout(id: String, layout: String?)
    /// A trophy just earned in the game playing: its name, description, grade (platinum, gold,
    /// silver or bronze) and icon as base64 PNG.
    case trophy(name: String, detail: String, grade: String, icon: String?)

    public static let protocolVersion = 1

    enum CodingKeys: String, CodingKey {
        case type, `protocol`, deviceID, deviceName, key, code, session, udpPort, macName, reason, milliseconds
        case games, selected, running, language, id, icon, background, name, layout, detail, grade
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(protocol: try values.decode(Int.self, forKey: .protocol), deviceID: try values.decode(String.self, forKey: .deviceID),
                          deviceName: try values.decode(String.self, forKey: .deviceName), key: try values.decodeIfPresent(String.self, forKey: .key))
        case "pairing":
            self = .pairing(code: try values.decode(String.self, forKey: .code))
        case "welcome":
            let text = try values.decode(String.self, forKey: .session)
            guard let session = UInt64(text) else {
                throw DecodingError.dataCorruptedError(forKey: .session, in: values, debugDescription: "session is not a decimal UInt64")
            }
            self = .welcome(session: session, udpPort: try values.decode(UInt16.self, forKey: .udpPort), macName: try values.decode(String.self, forKey: .macName),
                            key: try values.decode(String.self, forKey: .key))
        case "rejected":
            self = .rejected(reason: try values.decode(String.self, forKey: .reason))
        case "latency":
            self = .latency(milliseconds: try values.decode(Double.self, forKey: .milliseconds))
        case "library":
            self = .library(games: try values.decode([RemoteGame].self, forKey: .games), selected: try values.decodeIfPresent(String.self, forKey: .selected),
                            running: try values.decodeIfPresent(String.self, forKey: .running), language: try values.decode(String.self, forKey: .language))
        case "art":
            self = .art(id: try values.decode(String.self, forKey: .id), icon: try values.decodeIfPresent(String.self, forKey: .icon),
                        background: try values.decodeIfPresent(String.self, forKey: .background))
        case "wantArt":
            self = .wantArt(id: try values.decode(String.self, forKey: .id))
        case "command":
            self = .command(name: try values.decode(String.self, forKey: .name))
        case "select":
            self = .select(id: try values.decode(String.self, forKey: .id))
        case "launch":
            self = .launch(id: try values.decode(String.self, forKey: .id))
        case "close":
            self = .close
        case "home":
            self = .home
        case "saveLayout":
            self = .saveLayout(id: try values.decode(String.self, forKey: .id), layout: try values.decodeIfPresent(String.self, forKey: .layout))
        case "trophy":
            self = .trophy(name: try values.decode(String.self, forKey: .name), detail: try values.decode(String.self, forKey: .detail),
                           grade: try values.decode(String.self, forKey: .grade), icon: try values.decodeIfPresent(String.self, forKey: .icon))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "unknown message type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let version, let deviceID, let deviceName, let key):
            try values.encode("hello", forKey: .type)
            try values.encode(version, forKey: .protocol)
            try values.encode(deviceID, forKey: .deviceID)
            try values.encode(deviceName, forKey: .deviceName)
            try values.encode(key, forKey: .key)
        case .pairing(let code):
            try values.encode("pairing", forKey: .type)
            try values.encode(code, forKey: .code)
        case .welcome(let session, let udpPort, let macName, let key):
            try values.encode("welcome", forKey: .type)
            try values.encode(String(session), forKey: .session)
            try values.encode(udpPort, forKey: .udpPort)
            try values.encode(macName, forKey: .macName)
            try values.encode(key, forKey: .key)
        case .rejected(let reason):
            try values.encode("rejected", forKey: .type)
            try values.encode(reason, forKey: .reason)
        case .latency(let milliseconds):
            try values.encode("latency", forKey: .type)
            try values.encode(milliseconds, forKey: .milliseconds)
        case .library(let games, let selected, let running, let language):
            try values.encode("library", forKey: .type)
            try values.encode(games, forKey: .games)
            try values.encode(selected, forKey: .selected)
            try values.encode(running, forKey: .running)
            try values.encode(language, forKey: .language)
        case .art(let id, let icon, let background):
            try values.encode("art", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(icon, forKey: .icon)
            try values.encode(background, forKey: .background)
        case .wantArt(let id):
            try values.encode("wantArt", forKey: .type)
            try values.encode(id, forKey: .id)
        case .command(let name):
            try values.encode("command", forKey: .type)
            try values.encode(name, forKey: .name)
        case .select(let id):
            try values.encode("select", forKey: .type)
            try values.encode(id, forKey: .id)
        case .launch(let id):
            try values.encode("launch", forKey: .type)
            try values.encode(id, forKey: .id)
        case .close:
            try values.encode("close", forKey: .type)
        case .home:
            try values.encode("home", forKey: .type)
        case .saveLayout(let id, let layout):
            try values.encode("saveLayout", forKey: .type)
            try values.encode(id, forKey: .id)
            try values.encode(layout, forKey: .layout)
        case .trophy(let name, let detail, let grade, let icon):
            try values.encode("trophy", forKey: .type)
            try values.encode(name, forKey: .name)
            try values.encode(detail, forKey: .detail)
            try values.encode(grade, forKey: .grade)
            try values.encode(icon, forKey: .icon)
        }
    }

    /// The message's type, as its JSON names it.
    public var kind: String {
        switch self {
        case .hello: return "hello"
        case .pairing: return "pairing"
        case .welcome: return "welcome"
        case .rejected(let reason): return "rejected(\(reason))"
        case .latency: return "latency"
        case .library(let games, _, let running, let language): return "library(\(games.count) games, running \(running != nil), \(language))"
        case .art(_, let icon, let background): return "art(icon \(icon?.count ?? 0), background \(background?.count ?? 0))"
        case .wantArt: return "wantArt"
        case .command(let name): return "command(\(name))"
        case .select: return "select"
        case .launch: return "launch"
        case .close: return "close"
        case .home: return "home"
        case .saveLayout(_, let layout): return "saveLayout(\(layout?.count ?? 0) bytes)"
        case .trophy(let name, _, let grade, _): return "trophy(\(grade), \(name))"
        }
    }

    /// The message as the text of one WebSocket frame.
    public var text: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// The pad datagrams the launcher relays between the phone and the game, the engine's
/// RemotePad wire format: little-endian, with a magic, a version and a size up front.
public enum RemotePacket {
    public static let inputMagic: UInt32 = 0x4952_5041
    public static let outputMagic: UInt32 = 0x4F52_5041
    public static let helloMagic: UInt32 = 0x4852_5041
    public static let version: UInt16 = 1
    public static let inputSize = 80
    public static let outputSize = 32
    public static let helloSize = 16

    /// The session of a well-formed input packet, nil for anything else.
    public static func inputSession(_ data: Data) -> UInt64? {
        guard header(data, magic: inputMagic, size: inputSize) else { return nil }
        return read(data, at: 24)
    }

    public static func isOutput(_ data: Data) -> Bool { header(data, magic: outputMagic, size: outputSize) }

    public static func isHello(_ data: Data) -> Bool { header(data, magic: helloMagic, size: helloSize) }

    static func header(_ data: Data, magic: UInt32, size: Int) -> Bool {
        data.count == size && read(data, at: 0) as UInt32 == magic && read(data, at: 4) as UInt16 == version && Int(read(data, at: 6) as UInt16) == size
    }

    static func read<T: FixedWidthInteger>(_ data: Data, at offset: Int) -> T {
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { target in
            data.withUnsafeBytes { source in
                target.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[(source.startIndex + offset)..<(source.startIndex + offset + MemoryLayout<T>.size)]))
            }
        }
        return T(littleEndian: value)
    }
}
