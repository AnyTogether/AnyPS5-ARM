import Foundation

extension RemotePacket {
    /// The engine's pad button bits (libScePad's PadButton), as the phone app and the browser pad
    /// send them, and the launcher's names for them.
    public static let buttonBits: [(bit: UInt32, button: PadButton)] = [
        (0x0002, .l3), (0x0004, .r3), (0x0008, .start),
        (0x0010, .dpadUp), (0x0020, .dpadRight), (0x0040, .dpadDown), (0x0080, .dpadLeft),
        (0x0100, .l2), (0x0200, .r2), (0x0400, .l1), (0x0800, .r1),
        (0x1000, .north), (0x2000, .east), (0x4000, .south), (0x8000, .west),
        (0x10_0000, .touchpad),
    ]

    /// The pad an input packet holds (its buttons at byte 32, the sticks at 36 to 39 with 128 in
    /// the middle and up at 0, the triggers at 40 and 41), as a controller's state: sticks -1 to 1
    /// with up negative, triggers 0 to 1. nil for anything that is not an input packet.
    public static func padState(_ data: Data) -> PadState? {
        guard inputSession(data) != nil else { return nil }
        let bits: UInt32 = read(data, at: 32)
        let bytes = [UInt8](data)
        func axis(_ offset: Int) -> Double { max(-1, min(1, (Double(bytes[offset]) - 128) / 127)) }
        var pressed = Set<PadButton>()
        for (bit, button) in buttonBits where bits & bit != 0 { pressed.insert(button) }
        return PadState(pressed: pressed, leftX: axis(36), leftY: axis(37), rightX: axis(38), rightY: axis(39),
                        l2: Double(bytes[40]) / 255, r2: Double(bytes[41]) / 255)
    }
}

/// The phones' pads as the launcher's own screens read them while no game takes them: each
/// phone's pad when it changes, and the idle pad once a phone holding something goes quiet
/// (the engine lets a silent pad go too) or leaves, so a held direction never repeats for good.
public struct PhonePadNavigation: Sendable {
    /// A phone silent this long has let go (the browser pad sends its pad every 150 ms, the
    /// app at least that often while its pad is open).
    public static let silence: TimeInterval = 0.6

    private var pads: [String: (state: PadState, heard: TimeInterval)] = [:]

    public init() {}

    /// A packet's pad from `device` at `time`: the pad to act on when it changed, else nil.
    public mutating func heard(_ device: String, _ state: PadState, at time: TimeInterval) -> PadState? {
        let before = pads[device]?.state
        pads[device] = (state, time)
        return before == state || (before == nil && state == .idle) ? nil : state
    }

    /// The phones gone quiet while holding something: each is let go (and so said idle).
    public mutating func quiet(at time: TimeInterval) -> [String] {
        let gone = pads.filter { $0.value.state != .idle && time - $0.value.heard >= Self.silence }.map(\.key).sorted()
        for device in gone { pads[device] = (.idle, time) }
        return gone
    }

    /// The phone left: true when it was holding something, which is let go.
    public mutating func left(_ device: String) -> Bool {
        guard let pad = pads.removeValue(forKey: device) else { return false }
        return pad.state != .idle
    }

    /// Every phone that holds something, let go at once (a game took the pads).
    public mutating func releaseAll() -> [String] {
        let held = pads.filter { $0.value.state != .idle }.map(\.key).sorted()
        pads = [:]
        return held
    }
}
