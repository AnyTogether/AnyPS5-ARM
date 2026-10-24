import CryptoKit
import Darwin
import Foundation

/// Game packets between two launchers over plain UDP: the first, direct transport, before WebRTC
/// data channels or QUIC and the relay. Each packet carries both virtual addresses, ports and
/// virtual ports, and an HMAC under the session's key, so a packet from someone outside the
/// session, or from a member's address but another endpoint, is dropped. Not encrypted yet.
public final class OnlinePeerLink: @unchecked Sendable {
    public struct Endpoint: Equatable, Sendable {
        public var host: String
        public var port: UInt16
        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }

    static let magic: UInt32 = 0x314C_5041
    static let headerSize = 21
    static let tagSize = 16

    private let key: SymmetricKey
    private let lock = NSLock()
    private var ownAddress: UInt32
    private var peers: [UInt32: Endpoint] = [:]
    private var socket: Int32 = -1
    private var boundPort: UInt16 = 0
    private var stopped = false
    private let receive: @Sendable (OnlineWire.Datagram) -> Void

    /// `receive` gets each packet addressed as the engine wants it: `peer` is the sender.
    public init(sessionKey: Data, ownAddress: UInt32, receive: @escaping @Sendable (OnlineWire.Datagram) -> Void) {
        key = SymmetricKey(data: sessionKey)
        self.ownAddress = ownAddress
        self.receive = receive
    }

    deinit { stop() }

    public var port: UInt16 { lock.withLock { boundPort } }

    public func setOwnAddress(_ address: UInt32) { lock.withLock { ownAddress = address } }

    public func setPeer(_ address: UInt32, at endpoint: Endpoint?) {
        lock.withLock { peers[address] = endpoint }
    }

    public func start(host: String = "0.0.0.0", port: UInt16 = 0) throws {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr(host)
        address.sin_port = port.bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) } }) == 0,
              withUnsafeMutablePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
        }
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        lock.withLock {
            socket = fd
            boundPort = UInt16(bigEndian: address.sin_port)
        }
        let thread = Thread { [weak self] in self?.receiveLoop(fd) }
        thread.name = "online peer link"
        thread.start()
    }

    public func stop() {
        let fd = lock.withLock { () -> Int32 in
            stopped = true
            defer { socket = -1 }
            return socket
        }
        if fd >= 0 { close(fd) }
    }

    /// Sends a packet the engine gave the launcher; false when its peer has no endpoint.
    @discardableResult
    public func send(_ datagram: OnlineWire.Datagram) -> Bool {
        let (fd, own, endpoint) = lock.withLock { (socket, ownAddress, peers[datagram.peer]) }
        guard fd >= 0, let endpoint, own != 0 else { return false }
        let packet = seal(source: own, datagram: datagram)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr(endpoint.host)
        address.sin_port = endpoint.port.bigEndian
        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count
    }

    func seal(source: UInt32, datagram: OnlineWire.Datagram) -> Data {
        let writer = OnlineWire.Writer()
        writer.u32(OnlinePeerLink.magic).u32(source).u32(datagram.peer).u16(datagram.localPort).u16(datagram.localVport)
            .u16(datagram.peerPort).u16(datagram.peerVport).u8(datagram.kind.rawValue).raw(datagram.data)
        let tag = HMAC<SHA256>.authenticationCode(for: writer.data, using: key)
        return writer.data + Data(tag).prefix(OnlinePeerLink.tagSize)
    }

    /// The packet as the engine wants it, or nil when it is not for us or not from the session.
    func open(_ packet: Data, from endpoint: Endpoint) -> OnlineWire.Datagram? {
        guard packet.count >= OnlinePeerLink.headerSize + OnlinePeerLink.tagSize else { return nil }
        let body = packet.prefix(packet.count - OnlinePeerLink.tagSize)
        let tag = packet.suffix(OnlinePeerLink.tagSize)
        let expected = Data(HMAC<SHA256>.authenticationCode(for: body, using: key)).prefix(OnlinePeerLink.tagSize)
        guard OnlineWire.sameProof(Data(tag), expected) else { return nil }
        var reader = OnlineWire.Reader(Data(body))
        guard reader.u32() == OnlinePeerLink.magic else { return nil }
        let source = reader.u32()
        let destination = reader.u32()
        let sourcePort = reader.u16()
        let sourceVport = reader.u16()
        let destinationPort = reader.u16()
        let destinationVport = reader.u16()
        guard let kind = OnlineWire.DatagramKind(rawValue: reader.u8()), reader.ok else { return nil }
        let data = Data(body.dropFirst(OnlinePeerLink.headerSize))
        let (own, known) = lock.withLock { (ownAddress, peers[source]) }
        guard destination == own, known == endpoint, OnlineWire.isVirtual(source) else { return nil }
        return OnlineWire.Datagram(peer: source, peerPort: sourcePort, peerVport: sourceVport, localPort: destinationPort, localVport: destinationVport, kind: kind, data: data)
    }

    private func receiveLoop(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536 + OnlinePeerLink.headerSize + OnlinePeerLink.tagSize)
        while !lock.withLock({ stopped }) {
            var address = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let got = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, raw.baseAddress, raw.count, 0, $0, &length) }
                }
            }
            guard got > 0 else { continue }
            let host = String(cString: inet_ntoa(address.sin_addr))
            let endpoint = Endpoint(host: host, port: UInt16(bigEndian: address.sin_port))
            if let datagram = open(Data(buffer[0 ..< got]), from: endpoint) { receive(datagram) }
        }
    }
}
