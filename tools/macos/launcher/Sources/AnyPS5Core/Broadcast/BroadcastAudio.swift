import AudioToolbox
import Foundation

/// The broadcast's sound before it is encoded: the game's 48 kHz stereo with the microphone
/// mixed in at its own level, cut into the 1024-frame blocks AAC encodes, on a clock that
/// follows the game's sound (and the microphone's alone while the game is silent).
public struct BroadcastAudioMixer: Sendable {
    public static let sampleRate = 48000.0
    public static let blockFrames = 1024

    public struct Block: Equatable, Sendable {
        /// Interleaved stereo, 2048 samples.
        public let samples: [Float]
        public let seconds: Double
    }

    /// The microphone's level, 0 (off) to 1, mixed over the game.
    public var microphoneLevel: Float = 0
    private var game: [Float] = []
    private var microphone: [Float] = []
    /// The time of the next block's first frame.
    private var clock: Double?
    private var lastGame: Double?

    public init() {}

    private static var blockSeconds: Double { Double(blockFrames) / sampleRate }
    /// Larger jumps than this between where the sound should be and where it is start the clock again.
    static let tolerance = 0.25

    /// Interleaved stereo of the game, its first frame at `seconds`; returns the blocks it completes.
    public mutating func addGame(_ samples: [Float], at seconds: Double) -> [Block] {
        let expected = (clock ?? seconds) + Double(game.count / 2) / BroadcastAudioMixer.sampleRate
        if clock == nil || abs(expected - seconds) > BroadcastAudioMixer.tolerance {
            game.removeAll()
            clock = seconds
        }
        lastGame = seconds
        game += samples
        var blocks: [Block] = []
        let size = BroadcastAudioMixer.blockFrames * 2
        while game.count >= size {
            var block = Array(game.prefix(size))
            game.removeFirst(size)
            mixMicrophone(into: &block)
            blocks.append(emit(block))
        }
        return blocks
    }

    /// Interleaved stereo from the microphone at `seconds`. Mixed into the game's blocks; while
    /// the game makes no sound (none for a quarter second) it makes blocks on its own.
    public mutating func addMicrophone(_ samples: [Float], at seconds: Double) -> [Block] {
        guard microphoneLevel > 0 else {
            microphone.removeAll()
            return []
        }
        microphone += samples
        let size = BroadcastAudioMixer.blockFrames * 2
        let gameSilent = lastGame.map { seconds - $0 > BroadcastAudioMixer.tolerance } ?? true
        guard gameSilent else {
            // The game's blocks take it; a microphone running ahead loses its oldest sound.
            let most = Int(BroadcastAudioMixer.sampleRate * 0.5) * 2
            if microphone.count > most { microphone.removeFirst(microphone.count - most) }
            return []
        }
        let pending = Double(microphone.count / 2) / BroadcastAudioMixer.sampleRate
        let start = seconds + Double(samples.count / 2) / BroadcastAudioMixer.sampleRate - pending
        if clock.map({ abs($0 - start) > BroadcastAudioMixer.tolerance }) ?? true { clock = start }
        game.removeAll()
        var blocks: [Block] = []
        while microphone.count >= size {
            var block = [Float](repeating: 0, count: size)
            mixMicrophone(into: &block)
            blocks.append(emit(block))
        }
        return blocks
    }

    private mutating func mixMicrophone(into block: inout [Float]) {
        guard microphoneLevel > 0, !microphone.isEmpty else { return }
        let count = min(block.count, microphone.count)
        for index in 0 ..< count {
            block[index] = max(-1, min(1, block[index] + microphone[index] * microphoneLevel))
        }
        microphone.removeFirst(count)
    }

    private mutating func emit(_ samples: [Float]) -> Block {
        let time = clock ?? 0
        clock = time + BroadcastAudioMixer.blockSeconds
        return Block(samples: samples, seconds: time)
    }
}

/// AAC-LC through AudioToolbox: 48 kHz stereo float blocks in, raw AAC frames (as FLV carries
/// them) out, each with the time of the sound it holds.
public final class AACEncoder: @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    public struct Frame: Sendable {
        public let data: Data
        public let seconds: Double
    }

    public let audioSpecificConfig: Data
    private var converter: AudioConverterRef?
    private let maximumPacket: Int
    private let sampleRate: Double
    /// The frames the encoder holds back at the start: frame k holds the sound from
    /// k x 1024 - leading frames on.
    private let leading: Int
    private var input: [Float] = []
    /// Each block fed: where its first frame is among all frames fed, and its time.
    private var blocks: [(start: Int, seconds: Double)] = []
    private var queued = 0
    /// What the converter reads from, kept until it asks again.
    private var feeding: UnsafeMutablePointer<Float>
    private var feedingCapacity = 0
    private var produced = 0
    private static let noData: OSStatus = 0x6E6F_6461 // 'noda'

    public init(sampleRate: Double = 48000, channels: UInt32 = 2, bitRate: Int = 160_000) throws {
        var source = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
                                                 mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        var destination = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
                                                      mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
                                                      mChannelsPerFrame: channels, mBitsPerChannel: 0, mReserved: 0)
        var made: AudioConverterRef?
        let status = AudioConverterNew(&source, &destination, &made)
        guard status == noErr, let made else { throw Failure(description: "the AAC encoder could not be made (\(status))") }
        // A constant bit rate, as streaming services ask for.
        var mode = UInt32(kAudioCodecBitRateControlMode_Constant)
        AudioConverterSetProperty(made, kAudioCodecPropertyBitRateControlMode, UInt32(MemoryLayout<UInt32>.size), &mode)
        var rate = UInt32(bitRate)
        AudioConverterSetProperty(made, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &rate)
        var size = UInt32(0)
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        AudioConverterGetProperty(made, kAudioConverterPropertyMaximumOutputPacketSize, &propertySize, &size)
        var prime = AudioConverterPrimeInfo()
        var primeSize = UInt32(MemoryLayout<AudioConverterPrimeInfo>.size)
        AudioConverterGetProperty(made, kAudioConverterPrimeInfo, &primeSize, &prime)
        converter = made
        maximumPacket = Int(max(size, 1536))
        leading = Int(prime.leadingFrames)
        self.sampleRate = sampleRate
        feedingCapacity = 4096
        feeding = .allocate(capacity: feedingCapacity)
        audioSpecificConfig = FLV.audioSpecificConfig(sampleRate: Int(sampleRate), channels: UInt8(channels))
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
        feeding.deallocate()
    }

    /// One block of interleaved stereo (1024 frames) at `seconds`; returns the frames encoded so far.
    public func encode(_ samples: [Float], at seconds: Double) -> [Frame] {
        guard let converter else { return [] }
        blocks.append((queued, seconds))
        queued += samples.count / 2
        input += samples
        var frames: [Frame] = []
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var buffer = [UInt8](repeating: 0, count: maximumPacket)
        while true {
            var packets = UInt32(1)
            var description = AudioStreamPacketDescription()
            let status: OSStatus = buffer.withUnsafeMutableBytes { raw in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                let status = AudioConverterFillComplexBuffer(converter, AACEncoder.supply, refcon, &packets, &list, &description)
                if packets > 0 {
                    let length = Int(description.mDataByteSize > 0 ? description.mDataByteSize : list.mBuffers.mDataByteSize)
                    frames.append(Frame(data: Data(raw.prefix(length)), seconds: frameTime()))
                }
                return status
            }
            if status != noErr || packets == 0 { break }
        }
        return frames
    }

    /// The time of the sound in the next frame out, from the block it starts in.
    private func frameTime() -> Double {
        defer { produced += 1 }
        let position = produced * 1024 - leading
        while blocks.count > 1, blocks[1].start <= position { blocks.removeFirst() }
        guard let block = blocks.first else { return 0 }
        return block.seconds + Double(position - block.start) / sampleRate
    }

    private static let supply: AudioConverterComplexInputDataProc = { _, packets, data, _, refcon in
        guard let refcon else { return noData }
        let encoder = Unmanaged<AACEncoder>.fromOpaque(refcon).takeUnretainedValue()
        guard !encoder.input.isEmpty else {
            packets.pointee = 0
            return noData
        }
        // What is handed over must stay where it is until the next call.
        let count = encoder.input.count
        if count > encoder.feedingCapacity {
            encoder.feeding.deallocate()
            encoder.feedingCapacity = count
            encoder.feeding = .allocate(capacity: count)
        }
        encoder.input.withUnsafeBufferPointer { encoder.feeding.update(from: $0.baseAddress!, count: count) }
        encoder.input.removeAll(keepingCapacity: true)
        packets.pointee = UInt32(count / 2)
        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers.mNumberChannels = 2
        data.pointee.mBuffers.mDataByteSize = UInt32(count * 4)
        data.pointee.mBuffers.mData = UnsafeMutableRawPointer(encoder.feeding)
        return noErr
    }
}
