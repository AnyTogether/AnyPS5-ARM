import Darwin
import Foundation

/// A frame on Discord's local socket: a little-endian opcode and length, then JSON.
public enum DiscordFrame {
    public static func encode(op: UInt32, json: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: op.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(json)
        return data
    }

    public static func decode(_ data: Data) -> (op: UInt32, json: Data)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }
        let op = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let length = Int(UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24)
        guard bytes.count == 8 + length else { return nil }
        return (op, Data(bytes[8...]))
    }
}

/// "Playing <game>" on the user's Discord profile, through the Discord app's local socket
/// (discord-ipc-N in the temporary folder). Without Discord, or without an application ID,
/// nothing happens; a Discord started later is found on the next game.
public final class DiscordPresence: @unchecked Sendable {
    /// The AnyPS5 application in the Discord Developer Portal; empty turns the presence off.
    public static let anyps5ApplicationID = ""

    private let applicationID: String
    private let directory: URL
    private let queue = DispatchQueue(label: "org.anyps5.discord")
    private var socket: Int32 = -1

    public init(applicationID: String, directory: URL = URL(fileURLWithPath: NSTemporaryDirectory())) {
        self.applicationID = applicationID
        self.directory = directory
    }

    deinit { if socket >= 0 { Darwin.close(socket) } }

    /// Shows the game, with the time it has been played since `since`.
    public func playing(_ game: String, since: Date) {
        let activity: [String: Any] = [
            "details": game,
            "state": "AnyPS5 · Mac",
            "timestamps": ["start": Int(since.timeIntervalSince1970)],
            "assets": ["large_image": "anyps5", "large_text": "AnyPS5"],
            "type": 0,
        ]
        queue.async { [self] in setActivity(activity) }
    }

    public func clear() {
        queue.async { [self] in
            guard socket >= 0 else { return }
            setActivity(NSNull())
        }
    }

    public func close() {
        queue.sync {
            if socket >= 0 { Darwin.close(socket) }
            socket = -1
        }
    }

    private func setActivity(_ activity: Any) {
        guard !applicationID.isEmpty else { return }
        let command: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(ProcessInfo.processInfo.processIdentifier), "activity": activity],
            "nonce": UUID().uuidString,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: command) else { return }
        // A Discord that restarted closed the old socket: connect once more and send again.
        for _ in 0..<2 {
            guard connected() else { return }
            if write(op: 1, json: json), read() != nil { return }
            Darwin.close(socket)
            socket = -1
        }
    }

    /// Connects and shakes hands with the first Discord socket that answers.
    private func connected() -> Bool {
        if socket >= 0 { return true }
        for index in 0..<10 {
            let path = directory.appendingPathComponent("discord-ipc-\(index)").path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let candidate = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard candidate >= 0 else { continue }
            var on: Int32 = 1
            setsockopt(candidate, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let fits = withUnsafeMutableBytes(of: &address.sun_path) { raw -> Bool in
                let bytes = Array(path.utf8) + [0]
                guard bytes.count <= raw.count else { return false }
                raw.copyBytes(from: bytes)
                return true
            }
            let reached = fits && withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
            }
            guard reached else {
                Darwin.close(candidate)
                continue
            }
            socket = candidate
            let handshake = try? JSONSerialization.data(withJSONObject: ["v": 1, "client_id": applicationID])
            if let handshake, write(op: 0, json: handshake), let ready = read(), ready.op == 1 { return true }
            Darwin.close(candidate)
            socket = -1
        }
        return false
    }

    private func write(op: UInt32, json: Data) -> Bool {
        let frame = DiscordFrame.encode(op: op, json: json)
        return frame.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, frame.count, 0) } == frame.count
    }

    private func read() -> (op: UInt32, json: Data)? {
        var header = [UInt8](repeating: 0, count: 8)
        guard recv(socket, &header, 8, MSG_WAITALL) == 8 else { return nil }
        let length = Int(UInt32(header[4]) | UInt32(header[5]) << 8 | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
        guard length < 1 << 20 else { return nil }
        var body = [UInt8](repeating: 0, count: length)
        guard length == 0 || recv(socket, &body, length, MSG_WAITALL) == length else { return nil }
        return DiscordFrame.decode(Data(header + body))
    }
}
