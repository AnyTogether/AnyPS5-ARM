import Foundation

/// The game's sound as share play (and Remote Play) send it: 16-bit stereo at 48 kHz cut into
/// 5 ms StreamPacket audio packets, numbered, with milliseconds since the first sample.
public struct SoundChunker: Sendable {
    /// 5 ms at 48 kHz.
    public static let frames = 240
    private var pending = Data()
    private var number: UInt32 = 0
    private var start: Double?

    public init() {}

    /// Float samples (planar: one buffer a channel; or interleaved) as 16-bit stereo.
    public static func stereo16(first: UnsafePointer<Float>, second: UnsafePointer<Float>?, planar: Bool, channels: Int, frames: Int) -> [Int16] {
        let channels = max(1, channels)
        var samples = [Int16](repeating: 0, count: frames * 2)
        for frame in 0 ..< frames {
            let left = planar ? first[frame] : first[frame * channels]
            let right = planar ? (second ?? first)[frame] : first[frame * channels + min(1, channels - 1)]
            samples[frame * 2] = Int16(max(-1, min(1, left)) * 32767)
            samples[frame * 2 + 1] = Int16(max(-1, min(1, right)) * 32767)
        }
        return samples
    }

    /// Interleaved 16-bit stereo captured at `seconds`; returns the whole packets it completes.
    public mutating func add(_ samples: [Int16], at seconds: Double) -> [Data] {
        let begin = start ?? seconds
        start = begin
        pending += samples.withUnsafeBytes { Data($0) }
        let chunk = SoundChunker.frames * 4
        var packets: [Data] = []
        while pending.count >= chunk {
            number &+= 1
            packets.append(StreamPacket.audio(pending.prefix(chunk), number: number, milliseconds: UInt32(max(0, (seconds - begin) * 1000))))
            pending.removeFirst(chunk)
        }
        return packets
    }
}
