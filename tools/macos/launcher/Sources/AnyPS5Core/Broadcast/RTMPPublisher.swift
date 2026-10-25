import Foundation
import Network

/// Publishes one live stream to an RTMP or RTMPS server: TCP (TLS for rtmps://) through
/// Network.framework, the handshake, connect, createStream and publish, then the metadata, the
/// sequence headers and the frames as FLV tag bodies. A dropped connection is made again with a
/// growing pause; while the network cannot keep up, frames are dropped (to the next key frame)
/// rather than queued, so the broadcast stays live instead of falling behind.
public final class RTMPPublisher: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case connecting
        case live
        /// Connecting again after `reason`, the `attempt`th time in a row, in `delay` seconds.
        case reconnecting(attempt: Int, delay: Double, reason: String)
        case stopped
        case failed(String)
    }

    public struct Options: Sendable {
        /// The chunk size asked of the server for what the publisher sends.
        public var chunkSize = 4096
        /// Pauses before connecting again, the last one repeated.
        public var backoff: [Double] = [1, 2, 4, 8, 15, 30]
        /// Connections in a row that may fail before the broadcast gives up.
        public var attempts = 12
        /// How long reaching "publishing" may take.
        public var timeout: Double = 12
        /// The stream's bits a second, video and sound, for how much may wait unsent.
        public var bitRate = 3_000_000
        /// Seconds of the stream that may wait unsent before frames are dropped.
        public var backlogSeconds = 1.0

        public init() {}
    }

    public struct Stats: Equatable, Sendable {
        public var bytesSent: UInt64 = 0
        public var videoSent = 0
        public var videoDropped = 0
        public var audioSent = 0
        public var audioDropped = 0
        public var reconnects = 0
        /// Bytes handed to the network that it has not taken yet.
        public var backlog = 0
    }

    public let endpoint: RTMPEndpoint
    private let options: Options
    private let metadata: [AMF0.Property]
    private let queue = DispatchQueue(label: "org.anyps5.broadcast.rtmp", qos: .userInitiated)
    private let onState: @Sendable (State) -> Void
    private let wantKeyFrame: @Sendable () -> Void

    // Everything below is used on `queue` only.
    private var connection: NWConnection?
    /// Tells callbacks of an earlier connection from the current one's.
    private var generation = 0
    private enum Phase { case idle, handshake, connecting, creatingStream, publishing, live }
    private var phase = Phase.idle
    private var handshakeBytes = Data()
    private var writer = RTMPChunkWriter()
    private var reader = RTMPChunkReader()
    private var window: UInt64 = 2_500_000
    private var acknowledged: UInt64 = 0
    private var streamID: UInt32 = 0
    private var stopping = false
    private var attempt = 0
    private var everLive = false
    private var current = Stats()
    private var videoHeader: Data?
    private var videoSets: [Data] = []
    private var audioHeader: Data?
    /// The first key frame since going live is the stream's time zero.
    private var epoch: UInt32?
    private var needKey = true
    private var congested = false

    public init(endpoint: RTMPEndpoint, metadata: [AMF0.Property], options: Options = Options(),
                onState: @escaping @Sendable (State) -> Void, wantKeyFrame: @escaping @Sendable () -> Void = {}) {
        self.endpoint = endpoint
        self.metadata = metadata
        self.options = options
        self.onState = onState
        self.wantKeyFrame = wantKeyFrame
    }

    public var stats: Stats { queue.sync { current } }

    public func start() {
        queue.async { [self] in
            stopping = false
            attempt = 0
            connect()
        }
    }

    /// Ends the broadcast: the server is told the stream is over, then the connection closes.
    public func stop(then done: (@Sendable () -> Void)? = nil) {
        queue.async { [self] in
            stopping = true
            generation += 1
            guard let connection else {
                set(.stopped)
                done?()
                return
            }
            self.connection = nil
            if phase == .live {
                write(.command("FCUnpublish", transaction: 6, [.null, .string(endpoint.streamKey)]), on: connection)
                write(.command("deleteStream", transaction: 7, [.null, .number(Double(streamID))]), on: connection)
            }
            phase = .idle
            // The goodbye goes out before the connection closes, or after a second at most.
            let closed = Locked(false)
            let close: @Sendable () -> Void = { [weak self] in
                guard !closed.withLock({ let was = $0; $0 = true; return was }) else { return }
                connection.cancel()
                self?.queue.async { self?.set(.stopped) }
                done?()
            }
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in close() })
            queue.asyncAfter(deadline: .now() + 1, execute: close)
        }
    }

    /// A frame of length-prefixed NAL units at `milliseconds` on the stream's clock; a key frame
    /// brings its SPS and PPS, which become a new sequence header when they change.
    public func sendVideo(_ units: Data, key: Bool, milliseconds: UInt32, parameterSets: [Data] = []) {
        queue.async { [self] in
            if key, parameterSets.count >= 2, parameterSets != videoSets {
                videoSets = parameterSets
                videoHeader = FLV.avcSequenceHeader(sps: parameterSets[0], pps: parameterSets[1])
                if phase == .live, let epoch, let videoHeader {
                    write(RTMPMessage(chunkStream: RTMPMessage.Channel.video, kind: .video, streamID: streamID, timestamp: milliseconds &- min(epoch, milliseconds), payload: videoHeader))
                }
            }
            guard phase == .live, videoHeader != nil else {
                if everLive { current.videoDropped += 1 }
                return
            }
            let high = max(32_768, Int(Double(options.bitRate) / 8 * options.backlogSeconds))
            if current.backlog > high { congested = true }
            if congested {
                if current.backlog < high / 2 {
                    congested = false
                    needKey = true
                    if !key { wantKeyFrame() }
                } else {
                    current.videoDropped += 1
                    return
                }
            }
            if needKey {
                guard key else {
                    current.videoDropped += 1
                    return
                }
                needKey = false
                if epoch == nil {
                    epoch = milliseconds
                    sendHeaders()
                }
            }
            guard let epoch, milliseconds >= epoch else { return }
            write(RTMPMessage(chunkStream: RTMPMessage.Channel.video, kind: .video, streamID: streamID, timestamp: milliseconds - epoch, payload: FLV.avcFrame(units, key: key)))
            current.videoSent += 1
        }
    }

    /// The sound's AudioSpecificConfig, sent before its first frame.
    public func setAudioConfig(_ config: Data) {
        queue.async { [self] in audioHeader = FLV.aacSequenceHeader(config) }
    }

    /// One raw AAC frame at `milliseconds` on the stream's clock.
    public func sendAudio(_ frame: Data, milliseconds: UInt32) {
        queue.async { [self] in
            guard phase == .live, audioHeader != nil, let epoch, milliseconds >= epoch else { return }
            let high = max(32_768, Int(Double(options.bitRate) / 8 * options.backlogSeconds))
            guard current.backlog <= high * 2 else {
                current.audioDropped += 1
                return
            }
            write(RTMPMessage(chunkStream: RTMPMessage.Channel.audio, kind: .audio, streamID: streamID, timestamp: milliseconds - epoch, payload: FLV.aacFrame(frame)))
            current.audioSent += 1
        }
    }

    // MARK: Connecting

    private func set(_ state: State) {
        onState(state)
    }

    private func connect() {
        generation += 1
        let mine = generation
        phase = .handshake
        handshakeBytes = Data()
        writer.reset()
        reader = RTMPChunkReader()
        window = 2_500_000
        acknowledged = 0
        streamID = 0
        epoch = nil
        needKey = true
        congested = false
        current.backlog = 0
        set(.connecting)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = Int(options.timeout)
        let parameters = endpoint.tls ? NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp) : NWParameters(tls: nil, tcp: tcp)
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: NWEndpoint.Port(rawValue: endpoint.port) ?? 1935, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == mine else { return }
            switch state {
            case .ready:
                self.write(RTMPHandshake.c0c1(time: 0), raw: true)
                self.receive(on: connection, generation: mine)
            case .failed(let error):
                self.lost("\(error)")
            case .waiting(let error):
                self.lost("\(error)")
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + options.timeout) { [weak self] in
            guard let self, self.generation == mine, self.phase != .live else { return }
            self.lost("the server did not start the stream in time")
        }
    }

    private func receive(on connection: NWConnection, generation mine: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, self.generation == mine else { return }
            if let data, !data.isEmpty { self.received(data) }
            guard self.generation == mine else { return }
            if let error { return self.lost("\(error)") }
            if complete { return self.lost("the server closed the connection") }
            self.receive(on: connection, generation: mine)
        }
    }

    private func received(_ data: Data) {
        var data = data
        if phase == .handshake {
            handshakeBytes.append(data)
            let whole = 1 + 2 * RTMPHandshake.size
            guard handshakeBytes.count >= whole else { return }
            do {
                write(try RTMPHandshake.c2(answering: handshakeBytes), raw: true)
            } catch {
                return lost("\(error)", fatal: true)
            }
            data = handshakeBytes.subdata(in: whole ..< handshakeBytes.count)
            handshakeBytes = Data()
            write(.setChunkSize(UInt32(options.chunkSize)))
            writer.setChunkSize(options.chunkSize)
            write(.command("connect", transaction: 1, [.object([
                .init("app", .string(endpoint.app)),
                .init("type", .string("nonprivate")),
                .init("flashVer", .string("FMLE/3.0 (compatible; AnyPS5)")),
                .init("tcUrl", .string(endpoint.tcURL)),
            ])]))
            phase = .connecting
        }
        guard !data.isEmpty else { return }
        reader.append(data)
        do {
            for message in try reader.messages() { handle(message) }
        } catch {
            return lost("\(error)")
        }
        if reader.received - acknowledged >= window {
            acknowledged = reader.received
            write(.acknowledgement(UInt32(truncatingIfNeeded: reader.received)))
        }
    }

    private func handle(_ message: RTMPMessage) {
        switch message.kind {
        case .windowAcknowledgementSize:
            if let size = message.value32, size > 0 { window = UInt64(size) }
        case .userControl:
            // A ping is answered with its own time.
            let bytes = [UInt8](message.payload)
            if bytes.count >= 6, bytes[0] == 0, bytes[1] == 6 {
                write(.userControl(7, UInt32(bytes[2]) << 24 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 8 | UInt32(bytes[5])))
            }
        case .commandAMF0:
            guard let values = try? AMF0.decodeAll(message.payload), let name = values.first?.string else { return }
            command(name, transaction: values.count > 1 ? values[1].number ?? 0 : 0, values: values)
        default:
            break
        }
    }

    private func command(_ name: String, transaction: Double, values: [AMF0]) {
        let info = values.count > 3 ? values[3] : nil
        let text = info?["description"]?.string ?? info?["code"]?.string ?? name
        switch (name, transaction) {
        case ("_result", 1):
            let key = AMF0.string(endpoint.streamKey)
            write(.command("releaseStream", transaction: 2, [.null, key]))
            write(.command("FCPublish", transaction: 3, [.null, key]))
            write(.command("createStream", transaction: 4, [.null]))
            phase = .creatingStream
        case ("_result", 4):
            streamID = UInt32(values.count > 3 ? values[3].number ?? 1 : 1)
            write(.command("publish", transaction: 5, [.null, .string(endpoint.streamKey), .string("live")], streamID: streamID))
            phase = .publishing
        case ("_error", 1):
            lost("the server refused the connection: \(text)", fatal: true)
        case ("_error", 4), ("_error", 5):
            lost("the server refused the stream: \(text)")
        case ("onStatus", _):
            let code = info?["code"]?.string ?? ""
            if code == "NetStream.Publish.Start" {
                goLive()
            } else if info?["level"]?.string == "error" || code.hasSuffix("BadName") || code.hasSuffix("Failed") || code.hasSuffix("Rejected") {
                lost("the server refused the stream: \(text)")
            }
        case ("close", _):
            lost("the server ended the stream")
        default:
            break
        }
    }

    private func goLive() {
        guard phase == .publishing else { return }
        phase = .live
        if everLive { current.reconnects += 1 }
        everLive = true
        attempt = 0
        needKey = true
        epoch = nil
        set(.live)
        wantKeyFrame()
    }

    /// The metadata and both sequence headers, at time zero, before the first key frame.
    private func sendHeaders() {
        write(RTMPMessage(chunkStream: RTMPMessage.Channel.data, kind: .dataAMF0, streamID: streamID, payload: FLV.setDataFrame(metadata)))
        if let videoHeader { write(RTMPMessage(chunkStream: RTMPMessage.Channel.video, kind: .video, streamID: streamID, payload: videoHeader)) }
        if let audioHeader { write(RTMPMessage(chunkStream: RTMPMessage.Channel.audio, kind: .audio, streamID: streamID, payload: audioHeader)) }
    }

    /// The connection is gone: made again after a pause, unless the broadcast was stopped, the
    /// server refused it outright, or it failed too many times in a row.
    private func lost(_ reason: String, fatal: Bool = false) {
        guard !stopping, connection != nil else { return }
        generation += 1
        connection?.cancel()
        connection = nil
        phase = .idle
        attempt += 1
        // A stream that never went live (a wrong key, a wrong address) is not tried for long.
        let limit = everLive ? options.attempts : min(options.attempts, 3)
        guard !fatal || everLive, attempt <= limit else { return set(.failed(reason)) }
        let delay = options.backoff.isEmpty ? 1 : options.backoff[min(attempt - 1, options.backoff.count - 1)]
        set(.reconnecting(attempt: attempt, delay: delay, reason: reason))
        let mine = generation
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopping, self.generation == mine else { return }
            self.connect()
        }
    }

    // MARK: Writing

    private func write(_ message: RTMPMessage, on connection: NWConnection? = nil) {
        write(writer.chunks(message), raw: true, on: connection)
    }

    private func write(_ bytes: Data, raw: Bool, on given: NWConnection? = nil) {
        guard let connection = given ?? connection else { return }
        let mine = generation
        current.backlog += bytes.count
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            // Completions run on `queue`, the connection's.
            guard self.generation == mine else { return }
            self.current.backlog = max(0, self.current.backlog - bytes.count)
            if error == nil { self.current.bytesSent += UInt64(bytes.count) }
        })
    }
}
