import Foundation

/// FLV's audio and video tag bodies, which RTMP carries as they are: H.264 as an AVC sequence
/// header (the decoder configuration) then length-prefixed NAL units, AAC as its
/// AudioSpecificConfig then raw frames; and the onMetaData script data.
public enum FLV {
    /// The AVCDecoderConfigurationRecord tag for `sps` and `pps` (without start codes), sent
    /// before the first frame and again whenever the encoder's parameters change.
    public static func avcSequenceHeader(sps: Data, pps: Data) -> Data {
        let sps = Data(sps), pps = Data(pps)
        var data = Data([0x17, 0x00, 0x00, 0x00, 0x00])
        data.append(0x01)
        data.append(sps.count > 1 ? sps[1] : 0x64)
        data.append(sps.count > 2 ? sps[2] : 0x00)
        data.append(sps.count > 3 ? sps[3] : 0x28)
        // Four-byte NAL unit lengths, one SPS, one PPS.
        data.append(0xFF)
        data.append(0xE1)
        data.appendBigEndian(UInt16(sps.count))
        data.append(sps)
        data.append(0x01)
        data.appendBigEndian(UInt16(pps.count))
        data.append(pps)
        return data
    }

    /// A frame's NAL units, each with its four-byte length (as VideoToolbox makes them).
    public static func avcFrame(_ units: Data, key: Bool, compositionTime: Int32 = 0) -> Data {
        var data = Data([key ? 0x17 : 0x27, 0x01])
        data.appendBigEndian24(UInt32(bitPattern: compositionTime) & 0xFF_FFFF)
        data.append(units)
        return data
    }

    /// AAC, 44 kHz in the header as FLV requires for AAC (the real rate is in the config), 16-bit, stereo.
    static let aacHeader: UInt8 = 0xAF

    public static func aacSequenceHeader(_ audioSpecificConfig: Data) -> Data {
        Data([aacHeader, 0x00]) + audioSpecificConfig
    }

    public static func aacFrame(_ frame: Data) -> Data {
        Data([aacHeader, 0x01]) + frame
    }

    /// The two bytes describing AAC to a decoder: the object type (2 for LC), the sample rate's
    /// index and the channels. AAC-LC at 48 kHz in stereo is 0x11 0x90.
    public static func audioSpecificConfig(objectType: UInt8 = 2, sampleRate: Int, channels: UInt8) -> Data {
        let rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let index = UInt16(rates.firstIndex(of: sampleRate) ?? 3)
        let bits = UInt16(objectType & 0x1F) << 11 | index << 7 | UInt16(channels & 0x0F) << 3
        return Data([UInt8(bits >> 8), UInt8(bits & 0xFF)])
    }

    /// What players and services read about the stream before its first frame.
    public static func metadata(width: Int, height: Int, frameRate: Int, videoBitRate: Int, audioBitRate: Int, sampleRate: Int = 48000) -> [AMF0.Property] {
        [
            .init("duration", .number(0)),
            .init("width", .number(Double(width))),
            .init("height", .number(Double(height))),
            .init("videodatarate", .number(Double(videoBitRate) / 1000)),
            .init("framerate", .number(Double(frameRate))),
            .init("videocodecid", .number(7)),
            .init("audiodatarate", .number(Double(audioBitRate) / 1000)),
            .init("audiosamplerate", .number(Double(sampleRate))),
            .init("audiosamplesize", .number(16)),
            .init("stereo", .boolean(true)),
            .init("audiocodecid", .number(10)),
            .init("encoder", .string("AnyPS5")),
            .init("filesize", .number(0)),
        ]
    }

    /// The metadata as RTMP sends it, through @setDataFrame.
    public static func setDataFrame(_ metadata: [AMF0.Property]) -> Data {
        AMF0.encode([.string("@setDataFrame"), .string("onMetaData"), .ecmaArray(metadata)])
    }

    /// The tag types of an FLV file.
    public enum TagType: UInt8 {
        case audio = 8
        case video = 9
        case script = 18
    }

    /// The FLV file header for a file with audio and video, and the first PreviousTagSize.
    public static var fileHeader: Data {
        var data = Data("FLV".utf8)
        data.append(contentsOf: [0x01, 0x05])
        data.appendBigEndian(UInt32(9))
        data.appendBigEndian(UInt32(0))
        return data
    }

    /// One tag of an FLV file with its PreviousTagSize after it.
    public static func fileTag(_ type: TagType, timestamp: UInt32, body: Data) -> Data {
        var data = Data([type.rawValue])
        data.appendBigEndian24(UInt32(body.count))
        data.appendBigEndian24(timestamp & 0xFF_FFFF)
        data.append(UInt8(timestamp >> 24 & 0xFF))
        data.appendBigEndian24(0)
        data.append(body)
        data.appendBigEndian(UInt32(11 + body.count))
        return data
    }
}
