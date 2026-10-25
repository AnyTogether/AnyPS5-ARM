import Foundation

/// A DualShock 3 (SIXAXIS) over USB, which macOS has no game controller profile for: its input
/// report 0x01 read as a pad state, the feature report that starts the reports, and the output
/// report for its motors and player lights. The layout is the one SDL's PS3 driver reads.
public enum DualShock3Report {
    public static let vendor = 0x054C
    public static let product = 0x0268

    /// Reading feature report 0xF2 over USB switches the controller into sending reports.
    public static let enableFeature: UInt8 = 0xF2
    /// The same through a set report, for the controllers that want it (SDL sends both).
    public static let enableCommand: [UInt8] = [0xF4, 0x42, 0x0C, 0x00, 0x00]

    /// Input report 0x01 (49 bytes with its id) as a pad state; nil for anything else.
    public static func parse(_ data: [UInt8]) -> PadState? {
        guard data.count >= 20, data[0] == 0x01 else { return nil }
        let first = data[2], second = data[3]
        var pressed = Set<PadButton>()
        let firstBits: [(UInt8, PadButton)] = [(0x01, .select), (0x02, .l3), (0x04, .r3), (0x08, .start),
                                               (0x10, .dpadUp), (0x20, .dpadRight), (0x40, .dpadDown), (0x80, .dpadLeft)]
        let secondBits: [(UInt8, PadButton)] = [(0x01, .l2), (0x02, .r2), (0x04, .l1), (0x08, .r1),
                                                (0x10, .north), (0x20, .east), (0x40, .south), (0x80, .west)]
        for (bit, button) in firstBits where first & bit != 0 { pressed.insert(button) }
        for (bit, button) in secondBits where second & bit != 0 { pressed.insert(button) }
        if data[4] & 0x01 != 0 { pressed.insert(.guide) }
        func axis(_ byte: UInt8) -> Double { max(-1, min(1, (Double(byte) - 128) / 127)) }
        return PadState(pressed: pressed, leftX: axis(data[6]), leftY: axis(data[7]), rightX: axis(data[8]), rightY: axis(data[9]),
                        l2: Double(data[18]) / 255, r2: Double(data[19]) / 255)
    }

    /// The battery byte (30): 0xEE charging, 0xEF charged, 0 to 5 a level; nil when the
    /// report has none.
    public static func battery(_ data: [UInt8]) -> PadBattery? {
        guard data.count > 30, data[0] == 0x01 else { return nil }
        switch data[30] {
        case 0xEE: return PadBattery(percent: 50, approximate: true, charging: true)
        case 0xEF, 0xF1: return PadBattery(percent: 100, approximate: true, charging: false)
        case 0...5: return PadBattery(percent: Int(data[30]) * 20, approximate: true, charging: false)
        default: return nil
        }
    }

    /// Output report 0x01 (the layout of Linux's hid-sony): the light motor on or off, the
    /// heavy one's strength, and the player lights (1 to 4; 0 for none).
    public static func output(strong: Double, weak: Double, player: Int) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 49)
        report[0] = 0x01
        report[2] = 0xFF
        report[3] = weak > 0.05 ? 0x01 : 0x00
        report[4] = 0xFF
        report[5] = UInt8(max(0, min(255, (strong * 255).rounded())))
        report[10] = (1...4).contains(player) ? UInt8(1 << player) : 0
        for light in 0..<4 { report.replaceSubrange((11 + light * 5)..<(16 + light * 5), with: [0xFF, 0x27, 0x10, 0x00, 0x32]) }
        return report
    }
}
