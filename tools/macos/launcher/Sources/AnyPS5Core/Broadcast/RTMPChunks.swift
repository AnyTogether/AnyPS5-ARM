import Foundation

/// One RTMP message: a command, a control message, or an audio or video tag body.
public struct RTMPMessage: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case setChunkSize = 1
        case abort = 2
        case acknowledgement = 3
        case userControl = 4
        case windowAcknowledgementSize = 5
        case setPeerBandwidth = 6
        case audio = 8
        case video = 9
        case dataAMF0 = 18
        case commandAMF0 = 20
    }

    /// The chunk streams the publisher writes on: control, commands, audio, metadata, video.
    public enum Channel {
        public static let control: UInt32 = 2
        public static let command: UInt32 = 3
        public static let audio: UInt32 = 4
        public static let data: UInt32 = 5
        public static let video: UInt32 = 6
    }

    public var chunkStream: UInt32
    public var type: UInt8
    public var streamID: UInt32
    public var timestamp: UInt32
    public var payload: Data

    public init(chunkStream: UInt32, type: UInt8, streamID: UInt32 = 0, timestamp: UInt32 = 0, payload: Data) {
        self.chunkStream = chunkStream
        self.type = type
        self.streamID = streamID
        self.timestamp = timestamp
        self.payload = payload
    }

    public init(chunkStream: UInt32, kind: Kind, streamID: UInt32 = 0, timestamp: UInt32 = 0, payload: Data) {
        self.init(chunkStream: chunkStream, type: kind.rawValue, streamID: streamID, timestamp: timestamp, payload: payload)
    }

    public var kind: Kind? { Kind(rawValue: type) }

    // MARK: Messages the publisher sends

    public static func setChunkSize(_ size: UInt32) -> RTMPMessage {
        var payload = Data()
        payload.appendBigEndian(size & 0x7FFF_FFFF)
        return RTMPMessage(chunkStream: Channel.control, kind: .setChunkSize, payload: payload)
    }

    public static func acknowledgement(_ received: UInt32) -> RTMPMessage {
        var payload = Data()
        payload.appendBigEndian(received)
        return RTMPMessage(chunkStream: Channel.control, kind: .acknowledgement, payload: payload)
    }

    public static func windowAcknowledgementSize(_ size: UInt32) -> RTMPMessage {
        var payload = Data()
        payload.appendBigEndian(size)
        return RTMPMessage(chunkStream: Channel.control, kind: .windowAcknowledgementSize, payload: payload)
    }

    /// A user control event (6 is the server's ping, 7 the answer to it).
    public static func userControl(_ event: UInt16, _ value: UInt32) -> RTMPMessage {
        var payload = Data()
        payload.appendBigEndian(event)
        payload.appendBigEndian(value)
        return RTMPMessage(chunkStream: Channel.control, kind: .userControl, payload: payload)
    }

    public static func command(_ name: String, transaction: Double, _ arguments: [AMF0], streamID: UInt32 = 0) -> RTMPMessage {
        RTMPMessage(chunkStream: Channel.command, kind: .commandAMF0, streamID: streamID, payload: AMF0.encode([.string(name), .number(transaction)] + arguments))
    }

    /// The control message's 32-bit value (chunk size, acknowledgement, window size).
    public var value32: UInt32? {
        guard payload.count >= 4 else { return nil }
        let bytes = Array(payload.prefix(4))
        return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }
}

/// Cuts messages into chunks of the agreed size, each chunk stream's header made as small as
/// what changed since its last message allows (types 0, 1 and 2, type 3 for the rest of a
/// message), with the extended timestamp past 0xFFFFFF.
public struct RTMPChunkWriter: Sendable {
    public private(set) var chunkSize = 128
    private struct Last: Sendable {
        var streamID: UInt32
        var timestamp: UInt32
        var length: Int
        var type: UInt8
    }
    private var last: [UInt32: Last] = [:]

    public init() {}

    /// What follows is cut at `size` (after sending the Set Chunk Size message saying so).
    public mutating func setChunkSize(_ size: Int) {
        chunkSize = max(1, min(size, 0x7FFF_FFFF))
    }

    /// Forgets the headers written, for a new connection.
    public mutating func reset() {
        chunkSize = 128
        last = [:]
    }

    public mutating func chunks(_ message: RTMPMessage) -> Data {
        var data = Data()
        let csid = message.chunkStream
        let previous = last[csid]
        let format: UInt8
        let stamp: UInt32
        if let previous, previous.streamID == message.streamID, message.timestamp >= previous.timestamp {
            let delta = message.timestamp - previous.timestamp
            format = previous.length == message.payload.count && previous.type == message.type ? 2 : 1
            stamp = delta
        } else {
            format = 0
            stamp = message.timestamp
        }
        last[csid] = Last(streamID: message.streamID, timestamp: message.timestamp, length: message.payload.count, type: message.type)
        let extended = stamp >= 0xFF_FFFF
        RTMPChunkWriter.basicHeader(format: format, csid: csid, into: &data)
        data.appendBigEndian24(extended ? 0xFF_FFFF : stamp)
        if format <= 1 {
            data.appendBigEndian24(UInt32(message.payload.count))
            data.append(message.type)
        }
        if format == 0 {
            // The message stream ID is the one little-endian field.
            Swift.withUnsafeBytes(of: message.streamID.littleEndian) { data.append(contentsOf: $0) }
        }
        if extended { data.appendBigEndian(stamp) }
        var offset = 0
        let payload = message.payload
        repeat {
            let end = min(payload.count, offset + chunkSize)
            data.append(payload[payload.startIndex + offset ..< payload.startIndex + end])
            offset = end
            if offset < payload.count {
                RTMPChunkWriter.basicHeader(format: 3, csid: csid, into: &data)
                if extended { data.appendBigEndian(stamp) }
            }
        } while offset < payload.count
        return data
    }

    static func basicHeader(format: UInt8, csid: UInt32, into data: inout Data) {
        switch csid {
        case 2 ... 63:
            data.append(format << 6 | UInt8(csid))
        case 64 ... 319:
            data.append(format << 6)
            data.append(UInt8(csid - 64))
        default:
            let value = csid - 64
            data.append(format << 6 | 1)
            data.append(UInt8(value & 0xFF))
            data.append(UInt8(value >> 8 & 0xFF))
        }
    }
}

/// Puts messages back together from the chunks that come in, as they come: any chunk size the
/// other side sets, chunk streams interleaved, every header type and extended timestamps.
public struct RTMPChunkReader: Sendable {
    public struct Malformed: Error, CustomStringConvertible {
        public let description: String
    }

    public private(set) var chunkSize = 128
    /// Every byte taken in, for acknowledgements.
    public private(set) var received: UInt64 = 0
    private var buffer = Data()
    /// Where the bytes not read yet start in `buffer`, which is compacted now and then.
    private var offset = 0
    private struct Stream: Sendable {
        var timestamp: UInt32 = 0
        var delta: UInt32 = 0
        var length = 0
        var type: UInt8 = 0
        var streamID: UInt32 = 0
        var extended = false
        var partial = Data()
        var started = false
    }
    private var streams: [UInt32: Stream] = [:]

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
        received += UInt64(data.count)
    }

    /// Every message completed by the bytes taken in so far; Set Chunk Size messages also change
    /// how the rest is read.
    public mutating func messages() throws -> [RTMPMessage] {
        var done: [RTMPMessage] = []
        while let message = try next() {
            if message.kind == .setChunkSize, let size = message.value32 {
                guard size > 0 else { throw Malformed(description: "a chunk size of 0") }
                chunkSize = Int(size & 0x7FFF_FFFF)
            }
            done.append(message)
        }
        return done
    }

    /// Reads one chunk if it is all there; returns the message it completes, if any.
    private mutating func next() throws -> RTMPMessage? {
        while true {
            if offset > 65536 {
                buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + offset)
                offset = 0
            }
            let available = buffer.count - offset
            let bytes = [UInt8](buffer[(buffer.startIndex + offset)...].prefix(18))
            guard let first = bytes.first else { return nil }
            let format = first >> 6
            var position = 1
            var csid = UInt32(first & 0x3F)
            if csid == 0 {
                guard bytes.count >= 2 else { return nil }
                csid = UInt32(bytes[1]) + 64
                position = 2
            } else if csid == 1 {
                guard bytes.count >= 3 else { return nil }
                csid = UInt32(bytes[1]) + UInt32(bytes[2]) << 8 + 64
                position = 3
            }
            let headerLength = [11, 7, 3, 0][Int(format)]
            guard bytes.count >= position + headerLength else { return nil }
            var stream = streams[csid] ?? Stream()
            if format != 0 && !stream.started { throw Malformed(description: "chunk stream \(csid) starts without a full header") }
            func u24(_ at: Int) -> UInt32 { UInt32(bytes[at]) << 16 | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) }
            var stamp: UInt32 = 0
            if format <= 2 { stamp = u24(position) }
            let newMessage = stream.partial.isEmpty
            var length = stream.length, type = stream.type, streamID = stream.streamID
            if format <= 1 {
                length = Int(u24(position + 3))
                type = bytes[position + 6]
            }
            if format == 0 {
                streamID = UInt32(bytes[position + 7]) | UInt32(bytes[position + 8]) << 8 | UInt32(bytes[position + 9]) << 16 | UInt32(bytes[position + 10]) << 24
            }
            position += headerLength
            let extended = format <= 2 ? stamp == 0xFF_FFFF : stream.extended
            if extended {
                guard bytes.count >= position + 4 else { return nil }
                let value = UInt32(bytes[position]) << 24 | UInt32(bytes[position + 1]) << 16 | UInt32(bytes[position + 2]) << 8 | UInt32(bytes[position + 3])
                if format <= 2 { stamp = value }
                position += 4
            }
            let wanted = min(chunkSize, length - (newMessage ? 0 : stream.partial.count))
            guard available >= position + wanted else { return nil }
            // The whole chunk is here: take it.
            if newMessage {
                switch format {
                case 0:
                    stream.timestamp = stamp
                    stream.delta = stamp
                case 1, 2:
                    stream.timestamp &+= stamp
                    stream.delta = stamp
                default:
                    stream.timestamp &+= stream.delta
                }
            }
            stream.length = length
            stream.type = type
            stream.streamID = streamID
            stream.extended = extended
            stream.started = true
            let start = buffer.startIndex + offset + position
            stream.partial.append(buffer[start ..< start + wanted])
            offset += position + wanted
            if stream.partial.count >= length {
                let message = RTMPMessage(chunkStream: csid, type: type, streamID: streamID, timestamp: stream.timestamp, payload: stream.partial)
                stream.partial = Data()
                streams[csid] = stream
                return message
            }
            streams[csid] = stream
        }
    }
}

/// The plain RTMP handshake: C0 and C1 out, S0, S1 and S2 in, C2 (S1 echoed) out.
public enum RTMPHandshake {
    public static let size = 1536

    /// C0 (version 3) and C1: four bytes of time, four of zero, then random bytes.
    public static func c0c1(time: UInt32 = 0, random: Data? = nil) -> Data {
        var data = Data([3])
        data.appendBigEndian(time)
        data.appendBigEndian(UInt32(0))
        let filler = random ?? Data((0 ..< size - 8).map { _ in UInt8.random(in: 0 ... 255) })
        data.append(filler.prefix(size - 8))
        if data.count < 1 + size { data.append(Data(count: 1 + size - data.count)) }
        return data
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// S0 to S2 (3073 bytes) as they came: C2 to send, or why the server is not RTMP.
    public static func c2(answering server: Data) throws -> Data {
        let bytes = Data(server)
        guard bytes.count >= 1 + 2 * size else { throw Failure(description: "the server's handshake is short") }
        guard bytes[0] == 3 else { throw Failure(description: "the server speaks RTMP version \(bytes[0]), not 3") }
        return bytes.subdata(in: 1 ..< 1 + size)
    }
}
