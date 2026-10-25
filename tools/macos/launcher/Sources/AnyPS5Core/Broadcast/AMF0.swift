import Foundation

/// Action Message Format 0, the encoding of RTMP's commands (connect, publish, onStatus) and of
/// a stream's metadata: numbers, booleans, strings, objects and arrays, big endian.
public indirect enum AMF0: Equatable, Sendable {
    case number(Double)
    case boolean(Bool)
    case string(String)
    /// An anonymous object, its properties in the order written.
    case object([Property])
    case null
    case undefined
    /// An associative array (onMetaData's), an object with a count in front.
    case ecmaArray([Property])
    case strictArray([AMF0])
    /// Milliseconds since 1970 and a time zone nobody reads.
    case date(Double)

    public struct Property: Equatable, Sendable {
        public let key: String
        public let value: AMF0

        public init(_ key: String, _ value: AMF0) {
            self.key = key
            self.value = value
        }
    }

    public struct Malformed: Error, CustomStringConvertible {
        public let description: String
    }

    // MARK: Reading values

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A property of an object or associative array.
    public subscript(key: String) -> AMF0? {
        switch self {
        case .object(let properties), .ecmaArray(let properties): return properties.first { $0.key == key }?.value
        default: return nil
        }
    }

    // MARK: Writing

    public var encoded: Data {
        var data = Data()
        encode(into: &data)
        return data
    }

    public static func encode(_ values: [AMF0]) -> Data {
        var data = Data()
        for value in values { value.encode(into: &data) }
        return data
    }

    public func encode(into data: inout Data) {
        switch self {
        case .number(let value):
            data.append(0x00)
            data.appendBigEndian(value.bitPattern)
        case .boolean(let value):
            data.append(0x01)
            data.append(value ? 1 : 0)
        case .string(let value):
            let bytes = Data(value.utf8)
            if bytes.count > 0xFFFF {
                data.append(0x0C)
                data.appendBigEndian(UInt32(bytes.count))
            } else {
                data.append(0x02)
                data.appendBigEndian(UInt16(bytes.count))
            }
            data.append(bytes)
        case .object(let properties):
            data.append(0x03)
            AMF0.encode(properties, into: &data)
        case .null:
            data.append(0x05)
        case .undefined:
            data.append(0x06)
        case .ecmaArray(let properties):
            data.append(0x08)
            data.appendBigEndian(UInt32(properties.count))
            AMF0.encode(properties, into: &data)
        case .strictArray(let values):
            data.append(0x0A)
            data.appendBigEndian(UInt32(values.count))
            for value in values { value.encode(into: &data) }
        case .date(let milliseconds):
            data.append(0x0B)
            data.appendBigEndian(milliseconds.bitPattern)
            data.appendBigEndian(UInt16(0))
        }
    }

    private static func encode(_ properties: [Property], into data: inout Data) {
        for property in properties {
            let key = Data(property.key.utf8.prefix(0xFFFF))
            data.appendBigEndian(UInt16(key.count))
            data.append(key)
            property.value.encode(into: &data)
        }
        // The empty key and the object end marker.
        data.append(contentsOf: [0x00, 0x00, 0x09])
    }

    // MARK: Reading

    /// Every value in `data`, one after the other (a command's name, number and arguments).
    public static func decodeAll(_ data: Data) throws -> [AMF0] {
        var reader = ByteReader(data)
        var values: [AMF0] = []
        while !reader.atEnd { values.append(try decode(&reader)) }
        return values
    }

    static func decode(_ reader: inout ByteReader) throws -> AMF0 {
        let marker = try reader.byte()
        switch marker {
        case 0x00: return .number(Double(bitPattern: try reader.bigEndian(UInt64.self)))
        case 0x01: return .boolean(try reader.byte() != 0)
        case 0x02: return .string(try reader.string(length: Int(try reader.bigEndian(UInt16.self))))
        case 0x0C: return .string(try reader.string(length: Int(try reader.bigEndian(UInt32.self))))
        case 0x03: return .object(try properties(&reader))
        case 0x05: return .null
        case 0x06: return .undefined
        case 0x08:
            _ = try reader.bigEndian(UInt32.self)
            return .ecmaArray(try properties(&reader))
        case 0x0A:
            let count = Int(try reader.bigEndian(UInt32.self))
            guard count <= reader.remaining else { throw Malformed(description: "an array longer than its message") }
            return .strictArray(try (0 ..< count).map { _ in try decode(&reader) })
        case 0x0B:
            let milliseconds = Double(bitPattern: try reader.bigEndian(UInt64.self))
            _ = try reader.bigEndian(UInt16.self)
            return .date(milliseconds)
        default:
            throw Malformed(description: "AMF0 marker \(marker) is not one RTMP uses")
        }
    }

    private static func properties(_ reader: inout ByteReader) throws -> [Property] {
        var properties: [Property] = []
        while true {
            let key = try reader.string(length: Int(try reader.bigEndian(UInt16.self)))
            if key.isEmpty, reader.peek() == 0x09 {
                _ = try reader.byte()
                return properties
            }
            properties.append(Property(key, try decode(&reader)))
        }
    }
}

/// Big-endian reading through bytes, failing instead of running past their end.
struct ByteReader {
    private let data: Data
    private(set) var position: Int

    init(_ data: Data) {
        self.data = Data(data)
        position = 0
    }

    var atEnd: Bool { position >= data.count }
    var remaining: Int { data.count - position }

    func peek() -> UInt8? { atEnd ? nil : data[position] }

    mutating func byte() throws -> UInt8 {
        guard position < data.count else { throw AMF0.Malformed(description: "the message ends early") }
        defer { position += 1 }
        return data[position]
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw AMF0.Malformed(description: "the message ends early") }
        defer { position += count }
        return data.subdata(in: position ..< position + count)
    }

    mutating func bigEndian<Value: FixedWidthInteger>(_: Value.Type) throws -> Value {
        var value: Value = 0
        for byte in try bytes(MemoryLayout<Value>.size) { value = value << 8 | Value(byte) }
        return value
    }

    mutating func string(length: Int) throws -> String {
        String(decoding: try bytes(length), as: UTF8.self)
    }
}

extension Data {
    mutating func appendBigEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    /// The low three bytes of `value`, big endian (RTMP's and FLV's 24-bit fields).
    mutating func appendBigEndian24(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}
