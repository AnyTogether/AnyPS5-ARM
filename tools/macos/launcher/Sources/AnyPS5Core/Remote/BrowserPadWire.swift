import CryptoKit
import Foundation

/// The little HTTP the browser pad's server needs: one GET request's line and headers.
public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let target: String
    public let headers: [String: String]

    public var path: String { String(target.split(separator: "?", maxSplits: 1).first ?? "") }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// The largest request head the server reads.
    public static let maxHead = 8 * 1024

    /// The request in `buffer` and how many bytes it took, nil while the head is not complete;
    /// a head that cannot be one throws.
    public static func parse(_ buffer: Data) throws -> (HTTPRequest, Int)? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > maxHead { throw ParseError() }
            return nil
        }
        guard end.lowerBound - buffer.startIndex <= maxHead, let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else { throw ParseError() }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count == 3, start[2].hasPrefix("HTTP/1.") else { throw ParseError() }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError() }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = headers[name].map { $0 + (name == "cookie" ? "; " : ", ") + value } ?? value
        }
        return (HTTPRequest(method: String(start[0]), target: String(start[1]), headers: headers), end.upperBound - buffer.startIndex)
    }

    public struct ParseError: Error {}

    /// Whether this asks to become a WebSocket.
    public var isUpgrade: Bool {
        method == "GET" && header("upgrade")?.lowercased() == "websocket" && (header("connection")?.lowercased().contains("upgrade") ?? false)
            && header("sec-websocket-key") != nil && header("sec-websocket-version") == "13"
    }

    /// The Sec-WebSocket-Accept answer to a Sec-WebSocket-Key.
    public static func acceptKey(_ key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
    }

    /// A whole response with a body.
    public static func response(status: Int, reason: String, headers: [(String, String)] = [], body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers + [("Content-Length", "\(body.count)"), ("Connection", "close")] { head += "\(name): \(value)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}

/// WebSocket frames (RFC 6455) as the server reads and writes them: a browser's frames are
/// masked, the server's are not; control frames are short; nothing is longer than `maxPayload`.
public struct WebSocketFrame: Equatable, Sendable {
    public enum Opcode: UInt8, Sendable { case continuation = 0, text = 1, binary = 2, close = 8, ping = 9, pong = 10 }

    public var fin: Bool
    public var opcode: Opcode
    public var payload: Data

    public init(fin: Bool = true, opcode: Opcode, payload: Data) {
        self.fin = fin
        self.opcode = opcode
        self.payload = payload
    }

    public static let maxPayload = 4096

    public struct Violation: Error {}

    /// The first frame in `buffer` and its length, nil while it is not all there; a frame that
    /// breaks the rules (unmasked, too long, unknown opcode) throws.
    public static func decode(_ buffer: Data, requireMask: Bool = true) throws -> (WebSocketFrame, Int)? {
        let bytes = [UInt8](buffer.prefix(14))
        guard bytes.count >= 2 else { return nil }
        guard bytes[0] & 0x70 == 0, let opcode = Opcode(rawValue: bytes[0] & 0x0F) else { throw Violation() }
        let fin = bytes[0] & 0x80 != 0
        let masked = bytes[1] & 0x80 != 0
        if requireMask && !masked { throw Violation() }
        var length = Int(bytes[1] & 0x7F)
        var offset = 2
        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = Int(bytes[2]) << 8 | Int(bytes[3])
            offset = 4
        } else if length == 127 {
            guard bytes.count >= 10 else { return nil }
            var long: UInt64 = 0
            for index in 2..<10 { long = long << 8 | UInt64(bytes[index]) }
            guard long <= UInt64(maxPayload) else { throw Violation() }
            length = Int(long)
            offset = 10
        }
        guard length <= maxPayload else { throw Violation() }
        if opcode.rawValue >= 8 && (length > 125 || !fin) { throw Violation() }
        var mask: [UInt8] = []
        if masked {
            guard bytes.count >= offset + 4 else { return nil }
            mask = Array(bytes[offset..<(offset + 4)])
            offset += 4
        }
        guard buffer.count >= offset + length else { return nil }
        var payload = [UInt8](buffer[(buffer.startIndex + offset)..<(buffer.startIndex + offset + length)])
        if masked { for index in payload.indices { payload[index] ^= mask[index & 3] } }
        return (WebSocketFrame(fin: fin, opcode: opcode, payload: Data(payload)), offset + length)
    }

    /// The frame as the server sends it (unmasked), or masked as a client would with `mask`.
    public func encoded(mask: [UInt8]? = nil) -> Data {
        var out: [UInt8] = [(fin ? 0x80 : 0) | opcode.rawValue]
        let maskBit: UInt8 = mask == nil ? 0 : 0x80
        if payload.count < 126 {
            out.append(maskBit | UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            out += [maskBit | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        } else {
            out.append(maskBit | 127)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((UInt64(payload.count) >> UInt64(shift)) & 0xFF)) }
        }
        var body = [UInt8](payload)
        if let mask {
            out += mask
            for index in body.indices { body[index] ^= mask[index & 3] }
        }
        return Data(out + body)
    }

    public static func text(_ text: String) -> WebSocketFrame { WebSocketFrame(opcode: .text, payload: Data(text.utf8)) }

    /// A close frame with a status code.
    public static func close(_ code: UInt16) -> WebSocketFrame { WebSocketFrame(opcode: .close, payload: Data([UInt8(code >> 8), UInt8(code & 0xFF)])) }
}
