import Darwin
import XCTest
@testable import AnyPS5Core

/// A pretend usbmuxd on a socket of its own: it tells of one phone, then answers a Connect for
/// port 47702 and echoes what comes through, and refuses any other port.
final class FakeUsbmuxd: @unchecked Sendable {
    let path: String
    private let fd: Int32
    /// What the phone does with a connection to its port 47702; echoes by default.
    var phone: @Sendable (Int32) -> Void = { client in
        var chunk = [UInt8](repeating: 0, count: 256)
        while true {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { break }
            _ = write(client, chunk, count)
        }
    }
    /// Whether the phone is unplugged again after a moment.
    var unplugs = true

    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("usbmuxd-\(UUID().uuidString.prefix(8))").path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { target in for (index, byte) in path.utf8.enumerated() { target[index] = byte } }
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        listen(fd, 8)
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                Thread.detachNewThread { self.serve(client) }
            }
        }
    }

    deinit {
        close(fd)
        unlink(path)
    }

    private func serve(_ client: Int32) {
        var buffer = Data()
        guard let request = try? Usbmux.read(from: client, buffer: &buffer) else { close(client); return }
        switch request["MessageType"] as? String {
        case "Listen":
            try? Usbmux.write(Usbmux.frame(["MessageType": "Result", "Number": 0], tag: 1), to: client)
            try? Usbmux.write(Usbmux.frame(["MessageType": "Attached", "DeviceID": 7, "Properties": ["ConnectionType": "USB", "SerialNumber": "00008120-0001"]], tag: 0), to: client)
            Thread.sleep(forTimeInterval: 0.2)
            try? Usbmux.write(Usbmux.frame(["MessageType": "Attached", "DeviceID": 8, "Properties": ["ConnectionType": "Network", "SerialNumber": "wifi"]], tag: 0), to: client)
            if unplugs { try? Usbmux.write(Usbmux.frame(["MessageType": "Detached", "DeviceID": 7], tag: 0), to: client) }
            Thread.sleep(forTimeInterval: 5)
            close(client)
        case "Connect":
            let port = UInt16(truncatingIfNeeded: request["PortNumber"] as? Int ?? 0).bigEndian
            guard request["DeviceID"] as? Int == 7, port == 47702 else {
                try? Usbmux.write(Usbmux.frame(["MessageType": "Result", "Number": 3], tag: 1), to: client)
                close(client)
                return
            }
            try? Usbmux.write(Usbmux.frame(["MessageType": "Result", "Number": 0], tag: 1), to: client)
            phone(client)
            close(client)
        default:
            close(client)
        }
    }
}

final class UsbmuxTests: XCTestCase {
    func testAMessageGoesThereAndBack() throws {
        var data = try Usbmux.frame(["MessageType": "Listen", "DeviceID": 3], tag: 9)
        data.append(contentsOf: [1, 2])
        let message = try XCTUnwrap(try Usbmux.takeMessage(from: &data))
        XCTAssertEqual(message["MessageType"] as? String, "Listen")
        XCTAssertEqual(message["DeviceID"] as? Int, 3)
        XCTAssertEqual(data, Data([1, 2]), "what follows the message is left")
        var half = try Usbmux.frame(["MessageType": "Result"], tag: 1).prefix(20)
        XCTAssertNil(try Usbmux.takeMessage(from: &half), "a message not all there yet")
    }

    func testPhonesOnACableAreToldAsTheyComeAndGo() throws {
        let fake = try FakeUsbmuxd()
        let events = Locked<[Usbmux.Event]>([])
        let watching = try Usbmux.watch(path: fake.path, queue: .global()) { event in events.withLock { $0.append(event) } }
        defer { close(watching) }
        let deadline = Date().addingTimeInterval(3)
        while events.value.count < 2, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(events.value, [.attached(Usbmux.Device(id: 7, serial: "00008120-0001")), .detached(7)], "a phone on Wi-Fi was told too, or one was missed")
    }

    func testAConnectionToThePhoneCarriesBytes() throws {
        let fake = try FakeUsbmuxd()
        let fd = try Usbmux.connect(device: 7, port: 47702, path: fake.path)
        defer { close(fd) }
        let hello = Array("hello phone".utf8)
        XCTAssertEqual(write(fd, hello, hello.count), hello.count)
        var back = [UInt8](repeating: 0, count: hello.count)
        var got = 0
        while got < hello.count {
            let count = back.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, hello.count - got) }
            guard count > 0 else { break }
            got += count
        }
        XCTAssertEqual(back, hello)
    }

    func testAPortNothingListensOnIsRefused() throws {
        let fake = try FakeUsbmuxd()
        XCTAssertThrowsError(try Usbmux.connect(device: 7, port: 1234, path: fake.path)) { error in
            XCTAssertTrue("\(error)".contains("nothing listens"))
        }
    }
}

final class UsbTunnelTests: XCTestCase {
    /// The phone's connection over the cable comes out on the launcher's own port: what the
    /// phone writes reaches the server there, and the server's answer reaches the phone.
    override func setUp() {
        // The pretend ends write to sockets the tunnel already closed.
        signal(SIGPIPE, SIG_IGN)
    }

    func testThePhonesConnectionReachesTheLaunchersPort() throws {
        let server = try TCPEcho()
        let fake = try FakeUsbmuxd()
        fake.unplugs = false
        let heard = Locked<[UInt8]>([])
        fake.phone = { client in
            let hello = Array("hello mac".utf8)
            _ = write(client, hello, hello.count)
            var chunk = [UInt8](repeating: 0, count: 64)
            while heard.value.count < hello.count {
                let count = read(client, &chunk, chunk.count)
                guard count > 0 else { break }
                heard.withLock { $0 += chunk[0 ..< count] }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        let wired = Locked<[String]>([])
        let tunnel = UsbTunnel(phonePort: 47702, targetPort: server.port, usbmux: fake.path) { serials in wired.value = serials }
        tunnel.start()
        defer { tunnel.stop() }
        let deadline = Date().addingTimeInterval(3)
        while heard.value.count < 9, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(String(decoding: heard.value, as: UTF8.self), "hello mac")
        XCTAssertEqual(wired.value, ["00008120-0001"])
    }
}

/// A TCP server on the loopback that echoes, standing in for the launcher's phone server.
final class TCPEcho: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32

    init() throws {
        let server = socket(AF_INET, SOCK_STREAM, 0)
        fd = server
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, length) } }
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(server, $0, &length) } }
        port = UInt16(bigEndian: address.sin_port)
        listen(server, 4)
        Thread.detachNewThread {
            while true {
                let client = accept(server, nil, nil)
                guard client >= 0 else { return }
                Thread.detachNewThread {
                    var chunk = [UInt8](repeating: 0, count: 256)
                    while true {
                        let count = read(client, &chunk, chunk.count)
                        guard count > 0 else { break }
                        _ = write(client, chunk, count)
                    }
                    close(client)
                }
            }
        }
    }

    deinit { close(fd) }
}
