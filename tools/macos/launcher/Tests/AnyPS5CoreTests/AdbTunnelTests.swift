import Darwin
import XCTest
@testable import AnyPS5Core

final class AdbTunnelTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        signal(SIGPIPE, SIG_IGN)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("adb-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A pretend adb: one phone plugged in, whose port 47702 is forwarded to `phone`.
    func fakeAdb(phone: UInt16) throws -> URL {
        let adb = folder.appendingPathComponent("adb")
        try """
        #!/bin/sh
        echo "$@" >> "\(folder.path)/calls"
        case "$*" in
          devices) printf 'List of devices attached\\nR5CXC3L8NNK\\tdevice\\nEMULATOR1\\tunauthorized\\n\\n' ;;
          "-s R5CXC3L8NNK forward tcp:0 tcp:47702") echo \(phone) ;;
        esac
        """.write(to: adb, atomically: true, encoding: .utf8)
        chmod(adb.path, 0o755)
        return adb
    }

    func testDevicesAreReadFromAdb() {
        let listed = AdbTunnel.devices(in: "List of devices attached\nR5CXC3L8NNK\tdevice\nEMULATOR1\tunauthorized\n* daemon started\n\n")
        XCTAssertEqual(listed, ["R5CXC3L8NNK"])
    }

    /// The phone's port, forwarded by adb, is joined to the launcher's: the phone writes and
    /// hears the launcher's echo.
    func testAnAndroidPhoneOnTheCableReachesTheLaunchersPort() throws {
        let launcher = try TCPEcho()
        let phone = try TCPPhone(saying: "hello mac")
        let wired = Locked<[String]>([])
        let tunnel = AdbTunnel(adb: try fakeAdb(phone: phone.port), targetPort: launcher.port, interval: 0.2) { serials in wired.value = serials }
        tunnel.start()
        defer { tunnel.stop() }
        // Generous: on a busy Mac starting the pretend adb alone can take seconds, and the first
        // try that misses waits two more. The loop ends as soon as both are seen.
        let deadline = Date().addingTimeInterval(15)
        while phone.heard.value.count < 9 || wired.value.isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(String(decoding: phone.heard.value, as: UTF8.self), "hello mac")
        XCTAssertEqual(wired.value, ["R5CXC3L8NNK"])
    }

    func testAdbIsLookedForWhereItIsInstalled() {
        let home = folder!
        let tools = home.appendingPathComponent("Library/Android/sdk/platform-tools")
        try? FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        XCTAssertNil(AdbTunnel.locate(home: home, environment: [:], extra: []))
        FileManager.default.createFile(atPath: tools.appendingPathComponent("adb").path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(AdbTunnel.locate(home: home, environment: [:], extra: [])?.path, tools.appendingPathComponent("adb").path)
    }
}

/// A TCP server standing in for the phone app's cable port: it says something to whoever
/// connects and keeps what comes back.
final class TCPPhone: @unchecked Sendable {
    let port: UInt16
    let heard = Locked<[UInt8]>([])
    private let fd: Int32

    init(saying words: String) throws {
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
        let heard = heard
        Thread.detachNewThread {
            let client = accept(server, nil, nil)
            guard client >= 0 else { return }
            let bytes = Array(words.utf8)
            _ = write(client, bytes, bytes.count)
            var chunk = [UInt8](repeating: 0, count: 64)
            while heard.value.count < bytes.count {
                let count = read(client, &chunk, chunk.count)
                guard count > 0 else { break }
                heard.withLock { $0 += chunk[0 ..< count] }
            }
            Thread.sleep(forTimeInterval: 2)
            close(client)
        }
    }

    deinit { close(fd) }
}
