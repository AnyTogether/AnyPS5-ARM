import Foundation

/// Steam's binary KeyValues, as in `userdata/<id>/config/shortcuts.vdf`: a type byte, a key
/// ended by a zero byte, then the value; a map's entries end with 0x08. Every value is kept as
/// the bytes it was read from (strings undecoded, floats and 64-bit numbers raw), so a file read
/// and written again is the same file to the byte. The Windows and Linux launcher has the same
/// reader (lib/core/steam/binary_vdf.dart).
public enum BinaryVdf {
    public static let typeMap: UInt8 = 0x00
    public static let typeString: UInt8 = 0x01
    public static let typeInt32: UInt8 = 0x02
    public static let typeFloat32: UInt8 = 0x03
    public static let typePointer: UInt8 = 0x04
    public static let typeWideString: UInt8 = 0x05
    public static let typeColor: UInt8 = 0x06
    public static let typeUint64: UInt8 = 0x07
    public static let typeEnd: UInt8 = 0x08
    public static let typeInt64: UInt8 = 0x0A
    public static let typeEndAlternate: UInt8 = 0x0B

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let reason: String
        public let offset: Int
        public var description: String { "binary VDF: \(reason) at \(offset)" }
    }

    /// Reads a whole file: the root map's entries up to its end byte, and anything after it.
    public static func decode(_ bytes: [UInt8]) throws -> VdfDocument {
        var reader = Reader(bytes: bytes)
        let root = try reader.map()
        return VdfDocument(root: root, trailing: Array(bytes[reader.at...]))
    }

    public static func encode(_ document: VdfDocument) -> [UInt8] {
        var out: [UInt8] = []
        write(document.root, into: &out)
        out += document.trailing
        return out
    }

    /// One entry as it sits inside its map: type, key, value.
    public static func encode(_ entry: VdfEntry) -> [UInt8] {
        var out: [UInt8] = []
        write(entry, into: &out)
        return out
    }

    private static func write(_ map: VdfMap, into out: inout [UInt8]) {
        for entry in map.entries { write(entry, into: &out) }
        out.append(map.end)
    }

    private static func write(_ entry: VdfEntry, into out: inout [UInt8]) {
        out.append(entry.type)
        out += entry.key
        out.append(0)
        switch entry.value {
        case .map(let map):
            write(map, into: &out)
        case .int32(let number):
            withUnsafeBytes(of: number.littleEndian) { out += $0 }
        case .raw(let raw):
            out += raw
            if entry.type == typeString { out.append(0) }
            if entry.type == typeWideString { out += [0, 0] }
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0

        func fail(_ reason: String) -> Failure { Failure(reason: reason, offset: at) }

        mutating func byte() throws -> UInt8 {
            guard at < bytes.count else { throw fail("ends early") }
            defer { at += 1 }
            return bytes[at]
        }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard at + count <= bytes.count else { throw fail("ends early") }
            defer { at += count }
            return Array(bytes[at..<at + count])
        }

        mutating func cString() throws -> [UInt8] {
            let start = at
            while at < bytes.count, bytes[at] != 0 { at += 1 }
            guard at < bytes.count else { throw fail("a text without its end") }
            defer { at += 1 }
            return Array(bytes[start..<at])
        }

        mutating func wideString() throws -> [UInt8] {
            let start = at
            while at + 1 < bytes.count, bytes[at] != 0 || bytes[at + 1] != 0 { at += 2 }
            guard at + 1 < bytes.count else { throw fail("a wide text without its end") }
            defer { at += 2 }
            return Array(bytes[start..<at])
        }

        mutating func map() throws -> VdfMap {
            var entries: [VdfEntry] = []
            while true {
                let type = try byte()
                if type == typeEnd || type == typeEndAlternate { return VdfMap(entries, end: type) }
                let key = try cString()
                let value: VdfValue
                switch type {
                case typeMap: value = .map(try map())
                case typeString: value = .raw(try cString())
                case typeInt32:
                    let raw = try take(4)
                    value = .int32(Int32(bitPattern: UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24))
                case typeFloat32, typePointer, typeColor: value = .raw(try take(4))
                case typeUint64, typeInt64: value = .raw(try take(8))
                case typeWideString: value = .raw(try wideString())
                default: throw fail("unknown type 0x" + String(type, radix: 16))
                }
                entries.append(VdfEntry(type: type, key: key, value: value))
            }
        }
    }
}

public struct VdfDocument: Equatable {
    public var root: VdfMap
    /// What followed the root map's end (nothing in the files Steam writes).
    public var trailing: [UInt8]

    public init(root: VdfMap, trailing: [UInt8] = []) {
        self.root = root
        self.trailing = trailing
    }
}

public indirect enum VdfValue: Equatable {
    case map(VdfMap)
    case int32(Int32)
    /// A string's bytes without its zero, or the bytes of any other type.
    case raw([UInt8])
}

public struct VdfEntry: Equatable {
    public var type: UInt8
    public var key: [UInt8]
    public var value: VdfValue

    public init(type: UInt8, key: [UInt8], value: VdfValue) {
        self.type = type
        self.key = key
        self.value = value
    }

    public static func string(_ name: String, _ text: String) -> VdfEntry {
        VdfEntry(type: BinaryVdf.typeString, key: Array(name.utf8), value: .raw(Array(text.utf8)))
    }

    public static func int32(_ name: String, _ number: Int32) -> VdfEntry {
        VdfEntry(type: BinaryVdf.typeInt32, key: Array(name.utf8), value: .int32(number))
    }

    public static func map(_ name: String, _ map: VdfMap) -> VdfEntry {
        VdfEntry(type: BinaryVdf.typeMap, key: Array(name.utf8), value: .map(map))
    }

    public var name: String { String(decoding: key, as: UTF8.self) }

    /// The same value under another key: what renumbering a list of shortcuts changes.
    public func renamed(_ name: String) -> VdfEntry { VdfEntry(type: type, key: Array(name.utf8), value: value) }
}

/// A map's entries in file order; keys may repeat, as the format allows.
public struct VdfMap: Equatable {
    public var entries: [VdfEntry]
    /// The byte that ended the map (0x08, or 0x0B in some files).
    public var end: UInt8

    public init(_ entries: [VdfEntry] = [], end: UInt8 = BinaryVdf.typeEnd) {
        self.entries = entries
        self.end = end
    }

    /// The first entry named `key`, ignoring case as Steam does.
    public func entry(_ key: String) -> VdfEntry? {
        let wanted = key.lowercased()
        return entries.first { $0.name.lowercased() == wanted }
    }

    public func string(_ key: String) -> String? {
        guard let entry = entry(key), entry.type == BinaryVdf.typeString, case .raw(let raw) = entry.value else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }

    public func int32(_ key: String) -> Int32? {
        guard let entry = entry(key), case .int32(let number) = entry.value else { return nil }
        return number
    }

    public func map(_ key: String) -> VdfMap? {
        guard let entry = entry(key), case .map(let map) = entry.value else { return nil }
        return map
    }

    /// The string values of a map such as a shortcut's tags ("0": "Tag", "1": …).
    public func strings(_ key: String) -> [String] {
        (map(key)?.entries ?? []).compactMap { entry in
            guard entry.type == BinaryVdf.typeString, case .raw(let raw) = entry.value else { return nil }
            return String(decoding: raw, as: UTF8.self)
        }
    }
}

/// Steam's text KeyValues (config/loginusers.vdf): quoted keys, a quoted value or a braced block,
/// `//` comments. Read only.
public enum TextVdf {
    public indirect enum Value: Equatable {
        case text(String)
        case block([(String, Value)])

        public static func == (a: Value, b: Value) -> Bool {
            switch (a, b) {
            case (.text(let x), .text(let y)): return x == y
            case (.block(let x), .block(let y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default: return false
            }
        }

        /// The value under `key`, ignoring case.
        public subscript(key: String) -> Value? {
            guard case .block(let entries) = self else { return nil }
            let wanted = key.lowercased()
            return entries.first { $0.0 == key }?.1 ?? entries.first { $0.0.lowercased() == wanted }?.1
        }

        public var text: String? {
            if case .text(let text) = self { return text }
            return nil
        }

        public var entries: [(String, Value)] {
            if case .block(let entries) = self { return entries }
            return []
        }
    }

    public struct Failure: Error, Equatable { public let reason: String }

    public static func parse(_ text: String) throws -> Value {
        let tokens = try tokenize(text)
        var at = 0
        func block(top: Bool) throws -> Value {
            var out: [(String, Value)] = []
            while at < tokens.count {
                switch tokens[at] {
                case .close:
                    if top { throw Failure(reason: "a } without its {") }
                    at += 1
                    return .block(out)
                case .open:
                    throw Failure(reason: "a { without a key")
                case .word(let key):
                    at += 1
                    guard at < tokens.count else { throw Failure(reason: "a key without a value") }
                    switch tokens[at] {
                    case .open:
                        at += 1
                        out.append((key, try block(top: false)))
                    case .close:
                        throw Failure(reason: "a key without a value")
                    case .word(let value):
                        at += 1
                        out.append((key, .text(value)))
                    }
                }
            }
            if !top { throw Failure(reason: "a { without its }") }
            return .block(out)
        }
        return try block(top: true)
    }

    private enum Token { case open, close, word(String) }

    private static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var i = 0
        while i < characters.count {
            let c = characters[i]
            if c.isWhitespace {
                i += 1
            } else if c == "/", i + 1 < characters.count, characters[i + 1] == "/" {
                while i < characters.count, characters[i] != "\n" { i += 1 }
            } else if c == "{" {
                tokens.append(.open); i += 1
            } else if c == "}" {
                tokens.append(.close); i += 1
            } else if c == "\"" {
                var out = ""
                i += 1
                while i < characters.count, characters[i] != "\"" {
                    if characters[i] == "\\", i + 1 < characters.count {
                        switch characters[i + 1] {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        default: out.append(characters[i + 1])
                        }
                        i += 2
                    } else {
                        out.append(characters[i]); i += 1
                    }
                }
                guard i < characters.count else { throw Failure(reason: "a text without its closing quote") }
                i += 1
                tokens.append(.word(out))
            } else {
                var out = ""
                while i < characters.count, !characters[i].isWhitespace, !"{}\"".contains(characters[i]) {
                    out.append(characters[i]); i += 1
                }
                tokens.append(.word(out))
            }
        }
        return tokens
    }
}
