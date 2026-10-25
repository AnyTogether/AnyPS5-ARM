import Foundation
import Network
@testable import AnyPS5Core

/// A local RTMP server for the publisher's tests: it checks the handshake byte by byte, answers
/// connect, createStream and publish as Twitch and YouTube do, and keeps every message and byte
/// each connection sent, so the tests can look at the stream as a server sees it.
final class FakeRTMPServer: @unchecked Sendable {
    struct Options {
        /// publish with this key is refused (NetStream.Publish.BadName).
        var refusedKey: String?
        /// The first connection is closed after this many audio and video messages.
        var closeAfterMedia: Int?
        /// After publish starts the server stops reading, as a full uplink would.
        var stall = false
        /// The stream ID createStream answers with.
        var streamID: Double = 1
        var chunkSize: UInt32 = 4096
        var window: UInt32 = 2_500_000
    }

    final class Session: @unchecked Sendable {
        var c0: UInt8?
        var c1 = Data()
        var c2 = Data()
        var s1 = Data()
        /// Everything after C2, as it came.
        var raw = Data()
        var messages: [RTMPMessage] = []
        var commands: [(name: String, values: [AMF0], streamID: UInt32)] = []
        var problems: [String] = []
        var closed = false

        var media: [RTMPMessage] { messages.filter { $0.kind == .audio || $0.kind == .video } }
        var handshakeIsValid: Bool {
            c0 == 3 && c1.count == RTMPHandshake.size && c1.subdata(in: 4 ..< 8) == Data(count: 4) && c2 == s1
        }
    }

    let options: Options
    private let listener: NWListener
    let queue = DispatchQueue(label: "fake-rtmp")
    private var all: [Session] = []
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0

    init(options: Options = Options()) throws {
        self.options = options
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else { throw URLError(.cannotConnectToHost) }
        self.port = port
    }

    /// Not stop(): the last reference can go on `queue` itself (a connection's handlers ending
    /// there), where waiting on `queue` traps. Nothing else can touch `connections` by now.
    deinit {
        listener.cancel()
        for connection in connections { connection.cancel() }
    }

    func stop() {
        listener.cancel()
        queue.sync { for connection in connections { connection.cancel() } }
    }

    var sessions: [Session] { queue.sync { all } }

    /// Waits up to `timeout` seconds for `condition` to hold of the sessions so far.
    @discardableResult
    func wait(_ timeout: Double = 10, until condition: ([Session]) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if queue.sync(execute: { condition(all) }) { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return queue.sync(execute: { condition(all) })
    }

    /// The media a session received as an FLV file, for ffprobe.
    func flv(_ session: Session) -> Data {
        queue.sync {
            var file = FLV.fileHeader
            for message in session.messages {
                switch message.kind {
                case .audio: file += FLV.fileTag(.audio, timestamp: message.timestamp, body: message.payload)
                case .video: file += FLV.fileTag(.video, timestamp: message.timestamp, body: message.payload)
                case .dataAMF0:
                    // @setDataFrame is dropped, as servers do before writing onMetaData.
                    guard var values = try? AMF0.decodeAll(message.payload), values.first?.string == "@setDataFrame" else { continue }
                    values.removeFirst()
                    file += FLV.fileTag(.script, timestamp: 0, body: AMF0.encode(values))
                default: break
                }
            }
            return file
        }
    }

    // MARK: One connection

    private func accept(_ connection: NWConnection) {
        // The handlers below keep the connection's state, not the server: a connection still
        // open when a test ends does not keep the server alive.
        let options = options
        let session = Session()
        all.append(session)
        connections.append(connection)
        let index = all.count - 1
        var writer = RTMPChunkWriter()
        var reader = RTMPChunkReader()
        var pending = Data()
        var handshaken = false
        var mediaCount = 0
        var stalled = false

        func send(_ message: RTMPMessage) {
            connection.send(content: writer.chunks(message), completion: .contentProcessed { _ in })
        }
        func command(_ name: String, _ transaction: Double, _ arguments: [AMF0], streamID: UInt32 = 0) {
            send(.command(name, transaction: transaction, arguments, streamID: streamID))
        }
        func handle(_ message: RTMPMessage) {
            session.messages.append(message)
            switch message.kind {
            case .audio, .video:
                mediaCount += 1
                if index == 0, let limit = options.closeAfterMedia, mediaCount >= limit {
                    session.closed = true
                    connection.cancel()
                }
            case .commandAMF0:
                guard let values = try? AMF0.decodeAll(message.payload), let name = values.first?.string else {
                    session.problems.append("a command that is not AMF0")
                    return
                }
                session.commands.append((name, values, message.streamID))
                let transaction = values.count > 1 ? values[1].number ?? 0 : 0
                switch name {
                case "connect":
                    send(.windowAcknowledgementSize(options.window))
                    var bandwidth = Data()
                    bandwidth.appendBigEndian(options.window)
                    bandwidth.append(2)
                    send(RTMPMessage(chunkStream: 2, kind: .setPeerBandwidth, payload: bandwidth))
                    send(.setChunkSize(options.chunkSize))
                    writer.setChunkSize(Int(options.chunkSize))
                    send(.userControl(0, 0))
                    // A ping the publisher must answer.
                    send(.userControl(6, 4242))
                    command("_result", transaction, [
                        .object([.init("fmsVer", .string("FMS/3,0,1,123")), .init("capabilities", .number(31))]),
                        .object([.init("level", .string("status")), .init("code", .string("NetConnection.Connect.Success")),
                                 .init("description", .string("Connection succeeded.")), .init("objectEncoding", .number(0))]),
                    ])
                    command("onBWDone", 0, [.null])
                case "createStream":
                    command("_result", transaction, [.null, .number(options.streamID)])
                case "publish":
                    let key = values.count > 3 ? values[3].string ?? "" : ""
                    if key == options.refusedKey {
                        command("onStatus", 0, [.null, .object([.init("level", .string("error")), .init("code", .string("NetStream.Publish.BadName")),
                                                                .init("description", .string("Bad stream key"))])], streamID: 1)
                    } else {
                        send(.userControl(0, 1))
                        command("onStatus", 0, [.null, .object([.init("level", .string("status")), .init("code", .string("NetStream.Publish.Start")),
                                                                .init("description", .string("Publishing \(key).")), .init("clientid", .number(1))])], streamID: 1)
                        if options.stall { stalled = true }
                    }
                default:
                    break
                }
            default:
                break
            }
        }
        func received(_ data: Data) {
            if !handshaken {
                pending.append(data)
                if session.c0 == nil, pending.count >= 1 + RTMPHandshake.size {
                    session.c0 = pending[pending.startIndex]
                    session.c1 = pending.subdata(in: pending.startIndex + 1 ..< pending.startIndex + 1 + RTMPHandshake.size)
                    pending = pending.subdata(in: pending.startIndex + 1 + RTMPHandshake.size ..< pending.endIndex)
                    // S0, S1 (time, zero, random) and S2 (C1 echoed).
                    var s1 = Data()
                    s1.appendBigEndian(UInt32(1000))
                    s1.appendBigEndian(UInt32(0))
                    s1.append(Data((0 ..< RTMPHandshake.size - 8).map { _ in UInt8.random(in: 0 ... 255) }))
                    session.s1 = s1
                    connection.send(content: Data([3]) + s1 + session.c1, completion: .contentProcessed { _ in })
                }
                guard session.c0 != nil, pending.count >= RTMPHandshake.size else { return }
                session.c2 = pending.prefix(RTMPHandshake.size)
                let rest = pending.dropFirst(RTMPHandshake.size)
                handshaken = true
                guard !rest.isEmpty else { return }
                return received(Data(rest))
            }
            session.raw.append(data)
            reader.append(data)
            do {
                for message in try reader.messages() { handle(message) }
            } catch {
                session.problems.append("\(error)")
            }
        }
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                if let data, !data.isEmpty { received(data) }
                if complete || error != nil {
                    session.closed = true
                    return
                }
                if stalled { return }
                receive()
            }
        }
        connection.start(queue: queue)
        receive()
    }
}
