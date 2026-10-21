import Foundation

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

    public static let protocolVersion = 1

    enum CodingKeys: String, CodingKey {
        case type, `protocol`, deviceID, deviceName, key, code, session, udpPort, macName, reason, milliseconds
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
