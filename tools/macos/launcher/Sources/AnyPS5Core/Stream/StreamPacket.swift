import Foundation

/// Remote Play's datagrams, from the launcher to the phone: video frames cut into pieces and
/// sound, little-endian with a magic, a version and the header's size up front as the pad
/// packets have. On a cable they go as binary messages on the control channel instead.
public enum StreamPacket {
    /// "APRV" and "APRA".
    public static let videoMagic: UInt32 = 0x5652_5041
    public static let audioMagic: UInt32 = 0x4152_5041
    public static let version: UInt16 = 1
    public static let videoHeader = 24
    public static let audioHeader = 16
    /// Small enough for one datagram on any network.
    public static let largest = 1200

    /// Pieces of one frame: magic, version, header size, frame number, piece index and count,
    /// flags (1 = key frame), milliseconds since the stream began, then the bytes.
    public struct Video: Equatable {
        public let number: UInt32
        public let index: Int
        public let count: Int
        public let key: Bool
        public let milliseconds: UInt32
        public let payload: Data

        public init?(_ data: Data) {
            guard data.count >= StreamPacket.videoHeader, RemotePacket.read(data, at: 0) as UInt32 == StreamPacket.videoMagic,
                  RemotePacket.read(data, at: 4) as UInt16 == StreamPacket.version, Int(RemotePacket.read(data, at: 6) as UInt16) == StreamPacket.videoHeader else { return nil }
            number = RemotePacket.read(data, at: 8)
            index = Int(RemotePacket.read(data, at: 12) as UInt16)
            count = Int(RemotePacket.read(data, at: 14) as UInt16)
            key = (RemotePacket.read(data, at: 16) as UInt16) & 1 != 0
            milliseconds = RemotePacket.read(data, at: 20)
            guard count > 0, index < count else { return nil }
            payload = data.subdata(in: data.startIndex + StreamPacket.videoHeader ..< data.endIndex)
        }
    }

    /// Sound: magic, version, header size, packet number, milliseconds, then 16-bit stereo
    /// samples at 48 kHz.
    public struct Audio: Equatable {
        public let number: UInt32
        public let milliseconds: UInt32
        public let payload: Data

        public init?(_ data: Data) {
            guard data.count >= StreamPacket.audioHeader, RemotePacket.read(data, at: 0) as UInt32 == StreamPacket.audioMagic,
                  RemotePacket.read(data, at: 4) as UInt16 == StreamPacket.version, Int(RemotePacket.read(data, at: 6) as UInt16) == StreamPacket.audioHeader else { return nil }
            number = RemotePacket.read(data, at: 8)
            milliseconds = RemotePacket.read(data, at: 12)
            payload = data.subdata(in: data.startIndex + StreamPacket.audioHeader ..< data.endIndex)
        }
    }

    public static func video(_ frame: Data, number: UInt32, key: Bool, milliseconds: UInt32) -> [Data] {
        let room = largest - videoHeader
        let count = max(1, (frame.count + room - 1) / room)
        return (0 ..< count).map { index in
            var packet = Data(capacity: largest)
            append(&packet, videoMagic, version, UInt16(videoHeader))
            append(&packet, number, UInt16(index), UInt16(count), UInt16(key ? 1 : 0), UInt16(0), milliseconds)
            let start = frame.startIndex + index * room
            packet += frame[start ..< min(frame.endIndex, start + room)]
            return packet
        }
    }

    public static func audio(_ samples: Data, number: UInt32, milliseconds: UInt32) -> Data {
        var packet = Data(capacity: audioHeader + samples.count)
        append(&packet, audioMagic, version, UInt16(audioHeader))
        append(&packet, number, milliseconds)
        return packet + samples
    }

    /// An encoded frame with a length before each NAL unit, as the start-code stream the phones'
    /// decoders take; the parameter sets go first when given (before a key frame).
    public static func annexB(_ frame: Data, parameterSets: [Data] = []) -> Data {
        let start = Data([0, 0, 0, 1])
        var out = Data(capacity: frame.count + 64)
        for set in parameterSets { out += start + set }
        var position = frame.startIndex
        while position + 4 <= frame.endIndex {
            let length = Int(frame[position]) << 24 | Int(frame[position + 1]) << 16 | Int(frame[position + 2]) << 8 | Int(frame[position + 3])
            position += 4
            guard length > 0, position + length <= frame.endIndex else { break }
            out += start + frame[position ..< position + length]
            position += length
        }
        return out
    }

    private static func append(_ data: inout Data, _ values: any FixedWidthInteger...) {
        for value in values {
            switch value {
            case let value as UInt32: withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            case let value as UInt16: withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            default: break
            }
        }
    }
}
