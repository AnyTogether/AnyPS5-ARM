import CryptoKit
import Foundation

/// The launcher's half of the engine's online bridge protocol (docs/dev/ONLINE_PLAY.md):
/// 12-byte little-endian frame headers, fields packed in order, an HMAC handshake over a
/// per-start secret. Byte for byte the same as core/libs/prx/libSceNetCtl/src/OnlineWire.cpp.
public enum OnlineWire {
    public static let protocolVersion: UInt16 = 1
    public static let headerSize = 12
    public static let maxPayload = 16 * 1024 * 1024
    public static let maxDatagram = 65535
    public static let virtualNetwork: UInt32 = 0xC612_0000
    public static let virtualMask: UInt32 = 0xFFFE_0000

    public enum Kind: UInt16, Sendable {
        case hello = 0x0001
        case welcome = 0x0002
        case proof = 0x0003
        case refuse = 0x0004
        case account = 0x0101
        case observation = 0x0102
        case webRequest = 0x0201
        case pushEvent = 0x0204
        case datagram = 0x0310
    }

    public static let flagReply: UInt16 = 0x0001
    public static let flagUnsupported: UInt16 = 0x0002

    public enum RefuseReason: UInt16, Sendable {
        case badProof = 1
        case protocolVersion = 2
        case noGame = 3
        case busy = 4
    }

    public enum Side: Sendable { case launcher, engine }

    public static func isVirtual(_ address: UInt32) -> Bool { address & virtualMask == virtualNetwork }
    /// The virtual network's broadcast address.
    public static let virtualBroadcast: UInt32 = virtualNetwork | ~virtualMask
    /// A game datagram to the limited broadcast, the virtual network's broadcast or a multicast
    /// group goes to every other player in the session (LAN-style discovery).
    public static func isGroup(_ address: UInt32) -> Bool {
        address == 0xFFFF_FFFF || address == virtualBroadcast || address & 0xF000_0000 == 0xE000_0000
    }
    /// The largest game datagram online play carries: the largest UDP payload over IPv4 less the
    /// 12-byte header of the receiving engine's loopback hop (engine `MaxGameDatagram`). The engine
    /// refuses bigger ones with EMSGSIZE; a transport drops (and counts) any that still come.
    public static let maxGameDatagram = 65507 - 12


    public struct Header: Equatable, Sendable {
        public var length: UInt32
        public var kind: UInt16
        public var flags: UInt16
        public var call: UInt32

        public init(length: UInt32, kind: UInt16, flags: UInt16, call: UInt32) {
            self.length = length
            self.kind = kind
            self.flags = flags
            self.call = call
        }

        public var bytes: Data {
            let writer = Writer()
            writer.u32(length).u16(kind).u16(flags).u32(call)
            return writer.data
        }

        public init?(_ bytes: Data) {
            guard bytes.count >= OnlineWire.headerSize else { return nil }
            var reader = Reader(bytes.prefix(OnlineWire.headerSize))
            length = reader.u32()
            kind = reader.u16()
            flags = reader.u16()
            call = reader.u32()
            guard length <= UInt32(OnlineWire.maxPayload) else { return nil }
        }
    }

    public static func frame(_ kind: Kind, flags: UInt16 = 0, call: UInt32 = 0, _ payload: Data) -> Data {
        Header(length: UInt32(payload.count), kind: kind.rawValue, flags: flags, call: call).bytes + payload
    }

    public final class Writer {
        public private(set) var data = Data()
        public init() {}

        @discardableResult public func u8(_ value: UInt8) -> Writer { data.append(value); return self }
        @discardableResult public func u16(_ value: UInt16) -> Writer { little(value); return self }
        @discardableResult public func u32(_ value: UInt32) -> Writer { little(value); return self }
        @discardableResult public func u64(_ value: UInt64) -> Writer { little(value); return self }
        @discardableResult public func i32(_ value: Int32) -> Writer { u32(UInt32(bitPattern: value)) }
        @discardableResult public func raw(_ bytes: Data) -> Writer { data.append(bytes); return self }
        @discardableResult public func str(_ text: String) -> Writer {
            let bytes = Data(text.utf8.prefix(0xFFFF))
            u16(UInt16(bytes.count))
            data.append(bytes)
            return self
        }
        @discardableResult public func bytes(_ bytes: Data) -> Writer {
            u32(UInt32(bytes.count))
            data.append(bytes)
            return self
        }
        @discardableResult public func pairs(_ pairs: [(String, String)]) -> Writer {
            u16(UInt16(min(pairs.count, 0xFFFF)))
            for (name, value) in pairs.prefix(0xFFFF) { str(name); str(value) }
            return self
        }

        private func little<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
    }

    public struct Reader {
        private let buffer: [UInt8]
        private var offset = 0
        public private(set) var ok = true

        public init(_ data: Data) { buffer = [UInt8](data) }

        public mutating func u8() -> UInt8 { take(1)?.first ?? 0 }
        public mutating func u16() -> UInt16 { little(2) }
        public mutating func u32() -> UInt32 { little(4) }
        public mutating func u64() -> UInt64 { little(8) }
        public mutating func i32() -> Int32 { Int32(bitPattern: u32()) }
        public mutating func raw(_ count: Int) -> Data { take(count).map { Data($0) } ?? Data() }
        public mutating func str() -> String {
            let count = Int(u16())
            return take(count).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        public mutating func bytes() -> Data {
            let count = Int(u32())
            return take(count).map { Data($0) } ?? Data()
        }
        public mutating func pairs() -> [(String, String)] {
            let count = Int(u16())
            var out: [(String, String)] = []
            for _ in 0 ..< count where ok {
                let name = str()
                let value = str()
                if ok { out.append((name, value)) }
            }
            return out
        }

        private mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
            guard ok, count >= 0, buffer.count - offset >= count else {
                ok = false
                return nil
            }
            defer { offset += count }
            return buffer[offset ..< offset + count]
        }

        private mutating func little<T: FixedWidthInteger>(_ size: Int) -> T {
            guard let slice = take(size) else { return 0 }
            var value: T = 0
            for (index, byte) in slice.enumerated() { value |= T(byte) << (8 * index) }
            return value
        }
    }

    public struct Hello: Equatable, Sendable {
        public var protocolVersion: UInt16
        public var nonce: Data
        public var build: String
        public var pid: UInt32

        public init(protocolVersion: UInt16 = OnlineWire.protocolVersion, nonce: Data, build: String, pid: UInt32) {
            self.protocolVersion = protocolVersion
            self.nonce = nonce
            self.build = build
            self.pid = pid
        }

        public var payload: Data {
            let writer = Writer()
            writer.u16(protocolVersion).raw(nonce).str(build).u32(pid)
            return writer.data
        }

        public init?(_ payload: Data) {
            var reader = Reader(payload)
            protocolVersion = reader.u16()
            nonce = reader.raw(16)
            build = reader.str()
            pid = reader.u32()
            guard reader.ok else { return nil }
        }
    }

    public struct Account: Equatable, Sendable {
        public var signedIn: Bool
        public var accountId: UInt64
        public var onlineId: String
        public var country: String
        public var language: String
        public var age: UInt8
        public var address: UInt32
        public var nat: UInt8

        public init(signedIn: Bool, accountId: UInt64 = 0, onlineId: String = "", country: String = "", language: String = "", age: UInt8 = 0, address: UInt32 = 0, nat: UInt8 = 0) {
            self.signedIn = signedIn
            self.accountId = accountId
            self.onlineId = onlineId
            self.country = country
            self.language = language
            self.age = age
            self.address = address
            self.nat = nat
        }

        public static let signedOut = Account(signedIn: false)

        public var payload: Data {
            let writer = Writer()
            writer.u8(signedIn ? 1 : 0).u64(accountId).str(onlineId).str(country).str(language).u8(age).u32(address).u8(nat)
            return writer.data
        }
    }

    public struct WebRequest: Equatable, Sendable {
        public var userId: Int32
        public var apiGroup: String
        public var path: String
        public var method: String
        public var headers: [Pair]
        public var body: Data

        public init(userId: Int32, apiGroup: String, path: String, method: String, headers: [Pair] = [], body: Data = Data()) {
            self.userId = userId
            self.apiGroup = apiGroup
            self.path = path
            self.method = method
            self.headers = headers
            self.body = body
        }

        public var payload: Data {
            let writer = Writer()
            writer.i32(userId).str(apiGroup).str(path).str(method).pairs(headers.map { ($0.name, $0.value) }).bytes(body)
            return writer.data
        }

        public init?(_ payload: Data) {
            var reader = Reader(payload)
            userId = reader.i32()
            apiGroup = reader.str()
            path = reader.str()
            method = reader.str()
            headers = reader.pairs().map { Pair($0.0, $0.1) }
            body = reader.bytes()
            guard reader.ok else { return nil }
        }
    }

    public struct WebReply: Equatable, Sendable {
        public var status: UInt16
        public var headers: [Pair]
        public var body: Data

        public init(status: UInt16, headers: [Pair] = [], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        /// "Not offered": the engine answers the game exactly as it does offline.
        public static let notOffered = WebReply(status: 0)

        public var payload: Data {
            let writer = Writer()
            writer.u16(status).pairs(headers.map { ($0.name, $0.value) }).bytes(body)
            return writer.data
        }

        public init?(_ payload: Data) {
            var reader = Reader(payload)
            status = reader.u16()
            headers = reader.pairs().map { Pair($0.0, $0.1) }
            body = reader.bytes()
            guard reader.ok else { return nil }
        }
    }

    public struct Pair: Equatable, Sendable {
        public var name: String
        public var value: String
        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public enum DatagramKind: UInt8, Sendable { case udp = 1, p2p = 2 }

    /// A game packet. From the engine `peer` is where it goes; to the engine, where it came from.
    public struct Datagram: Equatable, Sendable {
        public var peer: UInt32
        public var peerPort: UInt16
        public var peerVport: UInt16
        public var localPort: UInt16
        public var localVport: UInt16
        public var kind: DatagramKind
        public var data: Data

        public init(peer: UInt32, peerPort: UInt16, peerVport: UInt16, localPort: UInt16, localVport: UInt16, kind: DatagramKind, data: Data) {
            self.peer = peer
            self.peerPort = peerPort
            self.peerVport = peerVport
            self.localPort = localPort
            self.localVport = localVport
            self.kind = kind
            self.data = data
        }

        public var payload: Data {
            let writer = Writer()
            writer.u32(peer).u16(peerPort).u16(peerVport).u16(localPort).u16(localVport).u8(kind.rawValue).bytes(data)
            return writer.data
        }

        public init?(_ payload: Data) {
            var reader = Reader(payload)
            peer = reader.u32()
            peerPort = reader.u16()
            peerVport = reader.u16()
            localPort = reader.u16()
            localVport = reader.u16()
            guard let kind = DatagramKind(rawValue: reader.u8()) else { return nil }
            self.kind = kind
            data = reader.bytes()
            guard reader.ok, OnlineWire.isVirtual(peer) || OnlineWire.isGroup(peer), data.count <= OnlineWire.maxDatagram else { return nil }
        }
    }

    /// Session and invitation news for the game (launcher → engine, event), what the platform's
    /// web API push events carry. An empty push context goes to the game's plain push callbacks
    /// and to every push context; otherwise only to that context's callbacks.
    public struct PushEvent: Equatable, Sendable {
        public static let maxDataType = 64
        public static let maxExtendedKey = 32
        public static let maxPushContextId = 36

        public var service: String
        public var label: UInt32
        public var pushContextId: String
        public var dataType: String
        public var data: Data
        public var extended: [Pair]
        public var to: UInt64
        public var from: UInt64
        public var fromOnlineId: String

        public init(service: String, label: UInt32 = 0, pushContextId: String = "", dataType: String, data: Data = Data(), extended: [Pair] = [],
                    to: UInt64 = 0, from: UInt64 = 0, fromOnlineId: String = "") {
            self.service = service
            self.label = label
            self.pushContextId = pushContextId
            self.dataType = dataType
            self.data = data
            self.extended = extended
            self.to = to
            self.from = from
            self.fromOnlineId = fromOnlineId
        }

        public var payload: Data {
            let writer = Writer()
            writer.str(service).u32(label).str(pushContextId).str(dataType).bytes(data).pairs(extended.map { ($0.name, $0.value) })
                .u64(to).u64(from).str(fromOnlineId)
            return writer.data
        }

        public init?(_ payload: Data) {
            var reader = Reader(payload)
            service = reader.str()
            label = reader.u32()
            pushContextId = reader.str()
            dataType = reader.str()
            data = reader.bytes()
            extended = reader.pairs().map { Pair($0.0, $0.1) }
            to = reader.u64()
            from = reader.u64()
            fromOnlineId = reader.str()
            guard reader.ok, isValid else { return nil }
        }

        /// What the engine accepts: the platform's structures hold a 64-letter data type and
        /// 32-letter extended data keys.
        public var isValid: Bool {
            !dataType.isEmpty && dataType.utf8.count <= PushEvent.maxDataType && pushContextId.utf8.count <= PushEvent.maxPushContextId
                && fromOnlineId.utf8.count <= 16 && extended.allSatisfy { !$0.name.isEmpty && $0.name.utf8.count <= PushEvent.maxExtendedKey }
        }
    }

    public static func welcome(nonce: Data, proof: Data) -> Data {
        let writer = Writer()
        writer.u16(protocolVersion).raw(nonce).raw(proof)
        return writer.data
    }

    public static func refuse(_ reason: RefuseReason, _ text: String) -> Data {
        let writer = Writer()
        writer.u16(reason.rawValue).str(text)
        return writer.data
    }

    public static func proof(secret: Data, side: Side, engineNonce: Data, launcherNonce: Data) -> Data {
        let label = side == .launcher ? "anyps5-online/1 launcher" : "anyps5-online/1 engine"
        let message = Data(label.utf8) + engineNonce + launcherNonce
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
    }

    public static func sameProof(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(left, right) { difference |= a ^ b }
        return difference == 0
    }

    public static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0 ..< count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
