import Foundation

/// A JSON value of the emulator host's control stream, read as anyps5-retro-host
/// docs/protocol.md "Values" says: RFC 8259 JSON in strict UTF-8, where a key twice in one object
/// (at any depth), an escaped lone surrogate or a number that is not finite as a 64-bit double is
/// an error. Foundation's JSONSerialization lets one of two equal keys win and is not this strict,
/// so the body is parsed here by hand. A number keeps its value as a double: the protocol judges
/// integers by value (`1.0` and `1e0` are 1), and no range in version 1 goes past what a double
/// holds exactly.
public enum RetroJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RetroJSON])
    case object([String: RetroJSON])

    /// The deepest nesting of arrays and objects a body may have. No message comes near it; it
    /// keeps a hostile body of a million brackets from running the reader's stack out.
    public static let maxDepth = 256

    /// The value when it is a number whose value is a whole number, else nil.
    public var intValue: Int? {
        guard case .number(let value) = self, value.rounded(.towardZero) == value,
              abs(value) <= 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: RetroJSON]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [RetroJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var isNull: Bool { self == .null }

    /// An integer as a JSON number.
    public static func int(_ value: Int) -> RetroJSON { .number(Double(value)) }

    // MARK: Reading

    /// Why a body could not be read.
    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    /// Reads one JSON value from `bytes`, the whole of them (white space around it allowed).
    public static func parse<Bytes: Collection>(_ bytes: Bytes) throws -> RetroJSON where Bytes.Element == UInt8 {
        try Array(bytes).withUnsafeBufferPointer { buffer in
            var parser = Parser(buffer)
            try parser.checkUTF8()
            parser.skipSpace()
            let value = try parser.value(depth: 0)
            parser.skipSpace()
            guard parser.at == buffer.count else { throw ParseError("There is more after the JSON value.") }
            return value
        }
    }

    private struct Parser {
        let bytes: UnsafeBufferPointer<UInt8>
        var at = 0

        init(_ bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        /// Strict UTF-8: no overlong forms, no encoded surrogates, nothing above U+10FFFF.
        func checkUTF8() throws {
            var index = 0
            let count = bytes.count
            while index < count {
                let first = bytes[index]
                if first < 0x80 {
                    index += 1
                    continue
                }
                let length: Int
                var low: UInt8 = 0x80
                var high: UInt8 = 0xBF
                switch first {
                case 0xC2...0xDF: length = 2
                case 0xE0: length = 3; low = 0xA0
                case 0xE1...0xEC, 0xEE...0xEF: length = 3
                case 0xED: length = 3; high = 0x9F
                case 0xF0: length = 4; low = 0x90
                case 0xF1...0xF3: length = 4
                case 0xF4: length = 4; high = 0x8F
                default: throw ParseError("The body is not UTF-8.")
                }
                guard index + length <= count else { throw ParseError("The body is not UTF-8.") }
                let second = bytes[index + 1]
                guard second >= low, second <= high else { throw ParseError("The body is not UTF-8.") }
                for offset in 2..<length where bytes[index + offset] & 0xC0 != 0x80 {
                    throw ParseError("The body is not UTF-8.")
                }
                index += length
            }
        }

        mutating func skipSpace() {
            while at < bytes.count {
                switch bytes[at] {
                case 0x20, 0x09, 0x0A, 0x0D: at += 1
                default: return
                }
            }
        }

        mutating func value(depth: Int) throws -> RetroJSON {
            guard at < bytes.count else { throw ParseError("The JSON ends early.") }
            switch bytes[at] {
            case UInt8(ascii: "{"): return try object(depth: depth + 1)
            case UInt8(ascii: "["): return try array(depth: depth + 1)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try word("true"); return .bool(true)
            case UInt8(ascii: "f"): try word("false"); return .bool(false)
            case UInt8(ascii: "n"): try word("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
            default: throw ParseError("The body is not JSON.")
            }
        }

        mutating func word(_ text: StaticString) throws {
            let length = text.utf8CodeUnitsCount
            guard at + length <= bytes.count else { throw ParseError("The body is not JSON.") }
            let start = text.utf8Start
            for offset in 0..<length where bytes[at + offset] != start[offset] {
                throw ParseError("The body is not JSON.")
            }
            at += length
        }

        mutating func object(depth: Int) throws -> RetroJSON {
            guard depth <= RetroJSON.maxDepth else { throw ParseError("The JSON is nested too deeply.") }
            at += 1
            var members: [String: RetroJSON] = [:]
            skipSpace()
            if at < bytes.count, bytes[at] == UInt8(ascii: "}") {
                at += 1
                return .object(members)
            }
            while true {
                skipSpace()
                guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { throw ParseError("An object key is not a string.") }
                let key = try string()
                skipSpace()
                guard at < bytes.count, bytes[at] == UInt8(ascii: ":") else { throw ParseError("An object key has no colon after it.") }
                at += 1
                skipSpace()
                let item = try value(depth: depth)
                guard members.updateValue(item, forKey: key) == nil else {
                    throw ParseError("The key \(key) appears twice in one object.")
                }
                skipSpace()
                guard at < bytes.count else { throw ParseError("The JSON ends early.") }
                if bytes[at] == UInt8(ascii: ",") {
                    at += 1
                    continue
                }
                guard bytes[at] == UInt8(ascii: "}") else { throw ParseError("An object is not closed.") }
                at += 1
                return .object(members)
            }
        }

        mutating func array(depth: Int) throws -> RetroJSON {
            guard depth <= RetroJSON.maxDepth else { throw ParseError("The JSON is nested too deeply.") }
            at += 1
            var items: [RetroJSON] = []
            skipSpace()
            if at < bytes.count, bytes[at] == UInt8(ascii: "]") {
                at += 1
                return .array(items)
            }
            while true {
                skipSpace()
                items.append(try value(depth: depth))
                skipSpace()
                guard at < bytes.count else { throw ParseError("The JSON ends early.") }
                if bytes[at] == UInt8(ascii: ",") {
                    at += 1
                    continue
                }
                guard bytes[at] == UInt8(ascii: "]") else { throw ParseError("An array is not closed.") }
                at += 1
                return .array(items)
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard at + 4 <= bytes.count else { throw ParseError("A \\u escape is cut short.") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[at]
                let digit: UInt32
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
                default: throw ParseError("A \\u escape has a character that is not hexadecimal.")
                }
                value = value << 4 | digit
                at += 1
            }
            return value
        }

        mutating func string() throws -> String {
            at += 1
            var out: [UInt8] = []
            while true {
                guard at < bytes.count else { throw ParseError("A string is not closed.") }
                let byte = bytes[at]
                if byte == UInt8(ascii: "\"") {
                    at += 1
                    return String(decoding: out, as: UTF8.self)
                }
                if byte < 0x20 { throw ParseError("A string holds a control character.") }
                if byte != UInt8(ascii: "\\") {
                    out.append(byte)
                    at += 1
                    continue
                }
                at += 1
                guard at < bytes.count else { throw ParseError("A string is not closed.") }
                let escape = bytes[at]
                at += 1
                switch escape {
                case UInt8(ascii: "\""): out.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"): out.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"): out.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xDC00...0xDFFF).contains(scalar) {
                        throw ParseError("A low surrogate has no high surrogate before it.")
                    }
                    if (0xD800...0xDBFF).contains(scalar) {
                        guard at + 2 <= bytes.count, bytes[at] == UInt8(ascii: "\\"), bytes[at + 1] == UInt8(ascii: "u") else {
                            throw ParseError("A high surrogate has no low surrogate after it.")
                        }
                        at += 2
                        let second = try hex4()
                        guard (0xDC00...0xDFFF).contains(second) else {
                            throw ParseError("A high surrogate has no low surrogate after it.")
                        }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (second - 0xDC00)
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw ParseError("A \\u escape is not a character.") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default:
                    throw ParseError("A string has an unknown escape.")
                }
            }
        }

        mutating func digits() -> Int {
            let start = at
            while at < bytes.count, bytes[at] >= UInt8(ascii: "0"), bytes[at] <= UInt8(ascii: "9") { at += 1 }
            return at - start
        }

        mutating func number() throws -> Double {
            let start = at
            if bytes[at] == UInt8(ascii: "-") { at += 1 }
            guard at < bytes.count else { throw ParseError("A number is cut short.") }
            if bytes[at] == UInt8(ascii: "0") {
                at += 1
            } else if digits() == 0 {
                throw ParseError("A number has no digits.")
            }
            if at < bytes.count, bytes[at] == UInt8(ascii: ".") {
                at += 1
                guard digits() > 0 else { throw ParseError("A number has no digits after its point.") }
            }
            if at < bytes.count, bytes[at] == UInt8(ascii: "e") || bytes[at] == UInt8(ascii: "E") {
                at += 1
                if at < bytes.count, bytes[at] == UInt8(ascii: "+") || bytes[at] == UInt8(ascii: "-") { at += 1 }
                guard digits() > 0 else { throw ParseError("A number has no digits in its exponent.") }
            }
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<at]), as: UTF8.self)
            guard let value = Double(text), value.isFinite else {
                throw ParseError("A number is not finite as a 64-bit double.")
            }
            return value
        }
    }

    // MARK: Writing

    /// Why a value could not be written.
    public struct EncodeError: Error, CustomStringConvertible {
        public let description: String
    }

    /// The value as compact JSON in UTF-8. A whole number within ±2^53 is written as an integer.
    public func encoded() throws -> [UInt8] {
        var out: [UInt8] = []
        try write(into: &out, depth: 0)
        return out
    }

    private func write(into out: inout [UInt8], depth: Int) throws {
        guard depth <= RetroJSON.maxDepth else { throw EncodeError(description: "The value is nested too deeply.") }
        switch self {
        case .null: out.append(contentsOf: Array("null".utf8))
        case .bool(let value): out.append(contentsOf: Array((value ? "true" : "false").utf8))
        case .number(let value):
            guard value.isFinite else { throw EncodeError(description: "A number is not finite.") }
            if let whole = intValue {
                out.append(contentsOf: Array(String(whole).utf8))
            } else {
                out.append(contentsOf: Array("\(value)".utf8))
            }
        case .string(let value): RetroJSON.writeString(value, into: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (index, item) in items.enumerated() {
                if index > 0 { out.append(UInt8(ascii: ",")) }
                try item.write(into: &out, depth: depth + 1)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let members):
            out.append(UInt8(ascii: "{"))
            for (index, key) in members.keys.sorted().enumerated() {
                if index > 0 { out.append(UInt8(ascii: ",")) }
                RetroJSON.writeString(key, into: &out)
                out.append(UInt8(ascii: ":"))
                try members[key]!.write(into: &out, depth: depth + 1)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func writeString(_ value: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "\""): out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\"")])
            case UInt8(ascii: "\\"): out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\\")])
            case 0x0A: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "n")])
            case 0x0D: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "r")])
            case 0x09: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "t")])
            case 0..<0x20:
                let hex = Array("0123456789abcdef".utf8)
                out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0"),
                                        hex[Int(byte >> 4)], hex[Int(byte & 0xF)]])
            default: out.append(byte)
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}
