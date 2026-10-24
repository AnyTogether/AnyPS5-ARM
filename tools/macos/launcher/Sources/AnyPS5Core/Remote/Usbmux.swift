import Darwin
import Foundation

/// The Mac's usbmuxd, which the system runs for iPhones on a cable (Finder and Xcode talk to
/// phones through it): it tells which phones are plugged in and opens a TCP connection to a port
/// on one of them, over the cable. Messages are a 16-byte header (length, version 1, type 8 for
/// a property list, tag), all little-endian, and an XML property list.
public enum Usbmux {
    public static let socketPath = "/var/run/usbmuxd"

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// A phone plugged in, by usbmuxd's number for it, with its serial (the UDID).
    public struct Device: Equatable, Sendable {
        public let id: Int
        public let serial: String
    }

    public enum Event: Equatable, Sendable {
        case attached(Device)
        case detached(Int)
    }

    static func frame(_ message: [String: Any], tag: UInt32) throws -> Data {
        let body = try PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0)
        var data = Data()
        for value in [UInt32(16 + body.count), 1, 8, tag] { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(body)
        return data
    }

    /// The first whole message in `buffer`, taken out of it; nil until one has arrived.
    static func takeMessage(from buffer: inout Data) throws -> [String: Any]? {
        guard buffer.count >= 16 else { return nil }
        let length = Int(buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }.littleEndian)
        guard length >= 16, length < 1 << 24 else { throw Failure(description: "usbmuxd sent a message of \(length) bytes") }
        guard buffer.count >= length else { return nil }
        let body = buffer.subdata(in: buffer.startIndex + 16 ..< buffer.startIndex + length)
        buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + length)
        guard let message = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw Failure(description: "usbmuxd sent something other than a dictionary")
        }
        return message
    }

    static func event(from message: [String: Any]) -> Event? {
        switch message["MessageType"] as? String {
        case "Attached":
            guard let id = message["DeviceID"] as? Int, let properties = message["Properties"] as? [String: Any],
                  properties["ConnectionType"] as? String == "USB" else { return nil }
            return .attached(Device(id: id, serial: properties["SerialNumber"] as? String ?? ""))
        case "Detached":
            return (message["DeviceID"] as? Int).map(Event.detached)
        default:
            return nil
        }
    }

    static func request(_ type: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["MessageType": type, "ClientVersionString": "AnyPS5", "ProgName": "AnyPS5"].merging(extra) { _, new in new }
    }

    static func open(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(description: "no socket: \(String(cString: strerror(errno)))") }
        noSignal(fd)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw Failure(description: "the usbmuxd path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            for (index, byte) in bytes.enumerated() { target[index] = byte }
        }
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw Failure(description: "usbmuxd is not there (\(reason))")
        }
        return fd
    }

    /// A write to a socket the other end closed fails instead of killing the launcher.
    static func noSignal(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func write(_ data: Data, to fd: Int32) throws {
        var sent = 0
        while sent < data.count {
            let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, data.count - sent) }
            guard count > 0 else { throw Failure(description: "usbmuxd closed the connection") }
            sent += count
        }
    }

    /// Reads one whole message, waiting for it.
    static func read(from fd: Int32, buffer: inout Data) throws -> [String: Any] {
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let message = try takeMessage(from: &buffer) { return message }
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else { throw Failure(description: "usbmuxd closed the connection") }
            buffer.append(contentsOf: chunk[0 ..< count])
        }
    }

    /// Reads one message and not a byte more: what follows belongs to the phone.
    static func readExactly(from fd: Int32) throws -> [String: Any] {
        func take(_ count: Int) throws -> Data {
            var data = Data(count: count)
            var got = 0
            while got < count {
                let read = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + got, count - got) }
                guard read > 0 else { throw Failure(description: "usbmuxd closed the connection") }
                got += read
            }
            return data
        }
        var buffer = try take(16)
        let length = Int(buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }.littleEndian)
        guard length >= 16, length < 1 << 24 else { throw Failure(description: "usbmuxd sent a message of \(length) bytes") }
        buffer += try take(length - 16)
        guard let message = try takeMessage(from: &buffer) else { throw Failure(description: "usbmuxd sent half a message") }
        return message
    }

    /// A TCP connection to `port` on the phone `device`, over the cable: a socket descriptor
    /// that carries the bytes from then on, which the caller closes.
    public static func connect(device: Int, port: UInt16, path: String = socketPath) throws -> Int32 {
        let fd = try open(path)
        do {
            try write(frame(request("Connect", ["DeviceID": device, "PortNumber": Int(port.bigEndian)]), tag: 1), to: fd)
            let answer = try readExactly(from: fd)
            let result = answer["Number"] as? Int ?? -1
            guard answer["MessageType"] as? String == "Result", result == 0 else {
                throw Failure(description: result == 3 ? "nothing listens on port \(port) of the phone" : "usbmuxd refused the connection (\(result))")
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    /// Phones as they are plugged in and out, until the descriptor it returns is closed or
    /// usbmuxd goes away (then `ended`): usbmuxd tells those already plugged in at once.
    public static func watch(path: String = socketPath, queue: DispatchQueue, _ handle: @escaping @Sendable (Event) -> Void,
                             ended: @escaping @Sendable () -> Void = {}) throws -> Int32 {
        let fd = try open(path)
        do {
            try write(frame(request("Listen"), tag: 1), to: fd)
            var buffer = Data()
            let answer = try read(from: fd, buffer: &buffer)
            guard answer["MessageType"] as? String == "Result", answer["Number"] as? Int == 0 else { throw Failure(description: "usbmuxd refused to tell of phones") }
            let pending = buffer
            Thread.detachNewThread {
                var buffer = pending
                while let message = try? read(from: fd, buffer: &buffer) {
                    if let event = event(from: message) { queue.async { handle(event) } }
                }
                queue.async { ended() }
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }
}
