import AVFoundation
import CAtrac9
import Foundation

/// A game's theme song (sce_sys/snd0.at9), the music the PS5 plays while the game is selected:
/// ATRAC9 in a RIFF file, decoded here to interleaved float samples.
public struct ThemeSong: Sendable {
    public let sampleRate: Int
    public let channels: Int
    public let samples: [Float]
    /// The part that repeats, in frames; nil repeats the whole song.
    public let loop: Range<Int>?

    public var frames: Int { samples.count / max(channels, 1) }

    /// KSDATAFORMAT_SUBTYPE_ATRAC9, 47E142D2-36BA-4D8D-88FC-61654F8C836C.
    public static let atrac9Format: [UInt8] = [0xd2, 0x42, 0xe1, 0x47, 0xba, 0x36, 0x8d, 0x4d, 0x88, 0xfc, 0x61, 0x65, 0x4f, 0x8c, 0x83, 0x6c]

    public struct Header: Equatable, Sendable {
        public var channels: Int
        public var sampleRate: Int
        public var blockAlign: Int
        public var config: [UInt8]
        public var totalFrames: Int
        /// The encoder's delay: frames at the start that are not part of the song.
        public var delay: Int
        public var loop: Range<Int>?
        public var data: Range<Int>
    }

    public struct Unreadable: Error, CustomStringConvertible {
        public let description: String
    }

    public static func header(_ file: Data) throws -> Header {
        let bytes = [UInt8](file)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x41, 0x56, 0x45] else {
            throw Unreadable(description: "not a RIFF WAVE file")
        }
        var format: Range<Int>?
        var fact: Range<Int>?
        var sampler: Range<Int>?
        var data: Range<Int>?
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = u32(offset + 4)
            let body = offset + 8..<min(bytes.count, offset + 8 + size)
            switch id {
            case "fmt ": format = body
            case "fact": fact = body
            case "smpl": sampler = body
            case "data": data = body
            default: break
            }
            offset = body.upperBound + (size & 1)
        }
        guard let format, format.count >= 52, u16(format.lowerBound) == 0xfffe,
              Array(bytes[format.lowerBound + 24..<format.lowerBound + 40]) == atrac9Format else {
            throw Unreadable(description: "not ATRAC9")
        }
        guard let data, !data.isEmpty else { throw Unreadable(description: "no audio data") }
        let blockAlign = u16(format.lowerBound + 12)
        var header = Header(channels: u16(format.lowerBound + 2), sampleRate: u32(format.lowerBound + 4), blockAlign: blockAlign,
                            config: Array(bytes[format.lowerBound + 44..<format.lowerBound + 48]), totalFrames: 0, delay: 0, loop: nil, data: data)
        guard header.channels > 0, header.sampleRate > 0, blockAlign > 0 else { throw Unreadable(description: "an empty format") }
        if let fact, fact.count >= 8 {
            header.totalFrames = u32(fact.lowerBound)
            header.delay = u32(fact.lowerBound + 4)
        }
        if let sampler, sampler.count >= 60, u32(sampler.lowerBound + 28) > 0 {
            let start = u32(sampler.lowerBound + 44)
            let end = u32(sampler.lowerBound + 48) + 1
            if start < end, header.totalFrames == 0 || end <= header.totalFrames { header.loop = start..<end }
        }
        return header
    }

    /// The whole song, without the encoder's delay and cut to its length.
    public static func decode(_ url: URL) throws -> ThemeSong {
        let file = try Data(contentsOf: url)
        let header = try header(file)
        guard let decoder = Atrac9GetHandle() else { throw Unreadable(description: "no decoder") }
        defer { Atrac9ReleaseHandle(decoder) }
        var config = header.config
        guard Atrac9InitDecoder(decoder, &config) == 0 else { throw Unreadable(description: "unusable ATRAC9 config") }
        var info = Atrac9CodecInfo()
        guard Atrac9GetCodecInfo(decoder, &info) == 0, info.channels == header.channels, info.frameSamples > 0 else {
            throw Unreadable(description: "ATRAC9 config does not match the file")
        }
        let frameValues = Int(info.frameSamples) * header.channels
        var samples: [Float] = []
        samples.reserveCapacity(header.totalFrames > 0 ? (header.totalFrames + header.delay) * header.channels : header.data.count * 8)
        var pcm = [Float](repeating: 0, count: frameValues)
        try file.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            // Each superframe is blockAlign bytes; its frames may leave padding at its end, so every
            // superframe is read from its own start.
            var superframe = header.data.lowerBound
            while superframe + header.blockAlign <= header.data.upperBound {
                var position = superframe
                for _ in 0..<max(1, Int(info.framesInSuperframe)) {
                    var used: Int32 = 0
                    let status = Atrac9DecodeF32(decoder, base + position, Int32(superframe + header.blockAlign - position), &pcm, &used, 0)
                    guard status == 0, used > 0 else { throw Unreadable(description: "ATRAC9 frame at \(position) failed (\(status))") }
                    samples.append(contentsOf: pcm)
                    position += Int(used)
                }
                superframe += header.blockAlign
            }
        }
        let skip = min(samples.count, header.delay * header.channels)
        var song = Array(samples[skip...])
        if header.totalFrames > 0, song.count > header.totalFrames * header.channels { song.removeLast(song.count - header.totalFrames * header.channels) }
        let frames = song.count / header.channels
        let loop = header.loop.flatMap { $0.upperBound <= frames ? $0 : nil }
        return ThemeSong(sampleRate: header.sampleRate, channels: header.channels, samples: song, loop: loop)
    }

    public typealias Buffers = (intro: AVAudioPCMBuffer, loop: AVAudioPCMBuffer?)

    /// For playing: the song up to the end of its loop, and the loop to repeat after it (nil: the whole song repeats).
    public func buffers() -> Buffers? {
        let song = self
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(song.sampleRate), channels: AVAudioChannelCount(song.channels)) else { return nil }
        func buffer(_ frames: Range<Int>) -> AVAudioPCMBuffer? {
            guard !frames.isEmpty, let made = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames.count)),
                  let channels = made.floatChannelData else { return nil }
            made.frameLength = AVAudioFrameCount(frames.count)
            song.samples.withUnsafeBufferPointer { samples in
                for channel in 0..<song.channels {
                    let out = channels[channel]
                    for (index, frame) in frames.enumerated() { out[index] = samples[frame * song.channels + channel] }
                }
            }
            return made
        }
        guard let loop = song.loop, loop.lowerBound > 0 else { return buffer(0..<song.frames).map { ($0, nil) } }
        guard let intro = buffer(0..<loop.upperBound), let repeating = buffer(loop) else { return nil }
        return (intro, repeating)
    }
}
