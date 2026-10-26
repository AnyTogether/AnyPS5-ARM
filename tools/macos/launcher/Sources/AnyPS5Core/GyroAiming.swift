import Foundation

/// Gyro aiming, a game's setting (Controls → Gyro Aiming): the controller's or phone's turn moves
/// the right stick, as Steam Input's gyro to joystick camera. The engine does the aiming
/// (ANYPS5_GYRO_AIM); an engine without it ignores the variable.
public struct GyroAiming: Codable, Equatable, Sendable {
    public enum Invert: String, Codable, CaseIterable, Sendable { case none, x, y, xy }
    /// When the gyro aims: always, while L2 is held, or while a finger is on the touchpad.
    public enum Activation: String, Codable, CaseIterable, Sendable { case always, l2, touch }

    public var enabled = false
    /// In tenths: 10 is a full stick at 90 degrees a second.
    public var sensitivity = 10
    public var invert = Invert.none
    public var activation = Activation.always
    /// Degrees a second a resting hand may turn without moving anything.
    public var deadzone = 2

    public static let sensitivityRange = 1...100
    public static let deadzoneRange = 0...45

    public init() {}

    /// Settings saved by an older launcher miss the newer fields, which keep their defaults.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GyroAiming()
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        sensitivity = try values.decodeIfPresent(Int.self, forKey: .sensitivity) ?? defaults.sensitivity
        invert = (try? values.decodeIfPresent(Invert.self, forKey: .invert)) ?? defaults.invert
        activation = (try? values.decodeIfPresent(Activation.self, forKey: .activation)) ?? defaults.activation
        deadzone = try values.decodeIfPresent(Int.self, forKey: .deadzone) ?? defaults.deadzone
    }

    /// ANYPS5_GYRO_AIM's value, clamped to what the engine accepts; nil while off.
    public var environment: String? {
        guard enabled else { return nil }
        let tenths = min(GyroAiming.sensitivityRange.upperBound, max(GyroAiming.sensitivityRange.lowerBound, sensitivity))
        let dead = min(GyroAiming.deadzoneRange.upperBound, max(GyroAiming.deadzoneRange.lowerBound, deadzone))
        return "sensitivity=\(Double(tenths) / 10),invert=\(invert.rawValue),activate=\(activation.rawValue),deadzone=\(dead)"
    }
}
