import Foundation

/// A pad as a share play viewer's launcher reads it from the controller, and the 80-byte input
/// packet the engine's RemotePad takes (the phone's layout: magic, version, size, sequence,
/// flags, sent time, session, buttons, sticks, triggers, touch, motion).
public struct SharePadState: Equatable, Sendable {
    /// The engine's pad button bits (libScePad).
    public enum Button {
        public static let l3: UInt32 = 0x0002, r3: UInt32 = 0x0004, options: UInt32 = 0x0008
        public static let up: UInt32 = 0x0010, right: UInt32 = 0x0020, down: UInt32 = 0x0040, left: UInt32 = 0x0080
        public static let l2: UInt32 = 0x0100, r2: UInt32 = 0x0200, l1: UInt32 = 0x0400, r1: UInt32 = 0x0800
        public static let triangle: UInt32 = 0x1000, circle: UInt32 = 0x2000, cross: UInt32 = 0x4000, square: UInt32 = 0x8000
        public static let touchPad: UInt32 = 0x100000
    }

    public var buttons: UInt32 = 0
    /// Left x, left y, right x, right y: 0 to 255, 128 at the centre, up is 0.
    public var sticks: [UInt8] = [128, 128, 128, 128]
    public var l2: UInt8 = 0
    public var r2: UInt8 = 0

    public init() {}

    /// A stick axis from -1...1 (a controller's y is up-positive: pass `up: true`).
    public static func axis(_ value: Float, up: Bool = false) -> UInt8 {
        let clamped = max(-1, min(1, up ? -value : value))
        return UInt8(max(0, min(255, ((clamped + 1) * 127.5).rounded())))
    }

    public static func trigger(_ value: Float) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }

    public func packet(sequence: UInt32, sentMicros: UInt64, session: UInt64) -> Data {
        var bytes = [UInt8](repeating: 0, count: RemotePacket.inputSize)
        func put<T: FixedWidthInteger>(_ value: T, _ offset: Int) {
            withUnsafeBytes(of: value.littleEndian) { for (index, byte) in $0.enumerated() { bytes[offset + index] = byte } }
        }
        put(RemotePacket.inputMagic, 0)
        put(RemotePacket.version, 4)
        put(UInt16(RemotePacket.inputSize), 6)
        put(sequence, 8)
        put(sentMicros, 16)
        put(session, 24)
        put(buttons, 32)
        for (index, value) in sticks.prefix(4).enumerated() { bytes[36 + index] = value }
        bytes[40] = l2
        bytes[41] = r2
        // No motion: gravity straight down, as the phone sends it.
        put(Float(9.80665).bitPattern, 60)
        return Data(bytes)
    }
}

/// The game's sound for a viewer: 5 ms packets in, a steady 48 kHz stereo stream out, kept about
/// `target` behind so a late packet still plays, never more than `limit` (old sound is dropped),
/// silence when it runs dry until it has `target` again.
public struct SoundJitterBuffer: Sendable {
    public let target: Int
    public let limit: Int
    private var samples: [Int16] = []
    private var priming = true
    private var newest: UInt32?

    /// `target` and `limit` in stereo frames (48 per millisecond).
    public init(target: Int = 48 * 50, limit: Int = 48 * 160) {
        self.target = target
        self.limit = limit
    }

    public var buffered: Int { samples.count / 2 }

    /// A StreamPacket audio packet; an older one than the newest is dropped.
    public mutating func push(_ packet: Data) {
        guard let audio = StreamPacket.Audio(packet) else { return }
        if let newest, Int32(bitPattern: audio.number &- newest) <= 0 { return }
        newest = audio.number
        audio.payload.withUnsafeBytes { raw in samples.append(contentsOf: raw.bindMemory(to: Int16.self).map { Int16(littleEndian: $0) }) }
        if buffered > limit { samples.removeFirst((buffered - target) * 2) }
    }

    /// `frames` stereo frames, interleaved; silence while priming or dry.
    public mutating func pull(_ frames: Int) -> [Int16] {
        if priming {
            guard buffered >= target else { return [Int16](repeating: 0, count: frames * 2) }
            priming = false
        }
        let take = min(frames, buffered) * 2
        var out = Array(samples.prefix(take))
        samples.removeFirst(take)
        if out.count < frames * 2 {
            out += [Int16](repeating: 0, count: frames * 2 - out.count)
            priming = true
        }
        return out
    }
}
