import AnyPS5Core
import SwiftUI

/// A game's Controls page, first: gyro aiming (GyroAiming), on or off, and while on its
/// sensitivity, invert, when it aims and its dead zone.
extension AppModel {
    func gyroRows(_ game: Game) -> [PanelRow] {
        let aim = settings(for: game).gyro ?? GyroAiming()
        func change(_ set: @escaping (inout GyroAiming) -> Void) {
            update(game) { settings in
                var changed = settings.gyro ?? GyroAiming()
                set(&changed)
                settings.gyro = changed == GyroAiming() ? nil : changed
            }
        }
        var rows = [
            PanelRow(id: "gyroSection", title: TA.text(.gyroSection), kind: .info("")),
            PanelRow(id: "gyro", title: TA.text(.gyro), detail: TA.text(.gyroDetail), symbol: "gyroscope",
                     kind: .toggle(aim.enabled) { on in change { $0.enabled = on } }),
        ]
        guard aim.enabled else { return rows }
        let inverts = GyroAiming.Invert.allCases
        let activations = GyroAiming.Activation.allCases
        rows += [
            PanelRow(id: "gyroSensitivity", title: TA.text(.gyroSensitivity), detail: TA.text(.gyroSensitivityDetail), symbol: "dial.medium",
                     kind: .stepper(value: aim.sensitivity, range: GyroAiming.sensitivityRange, step: 1, format: { String(format: "%.1f", Double($0) / 10) }) { value in
                         change { $0.sensitivity = value }
                     }),
            PanelRow(id: "gyroActivation", title: TA.text(.gyroActivation), detail: TA.text(.gyroActivationDetail), symbol: "l2.rectangle.roundedtop",
                     kind: .choice(options: [TA.text(.gyroAlways), TA.text(.gyroL2), TA.text(.gyroTouch)], selected: activations.firstIndex(of: aim.activation) ?? 0) { index in
                         change { $0.activation = activations[index] }
                     }),
            PanelRow(id: "gyroInvert", title: TA.text(.gyroInvert), symbol: "arrow.left.arrow.right",
                     kind: .choice(options: [TA.text(.gyroInvertNone), TA.text(.gyroInvertX), TA.text(.gyroInvertY), TA.text(.gyroInvertBoth)],
                                   selected: inverts.firstIndex(of: aim.invert) ?? 0) { index in
                         change { $0.invert = inverts[index] }
                     }),
            PanelRow(id: "gyroDeadzone", title: TA.text(.gyroDeadzone), detail: TA.text(.gyroDeadzoneDetail), symbol: "smallcircle.circle",
                     kind: .stepper(value: aim.deadzone, range: GyroAiming.deadzoneRange, step: 1, format: { $0 == 0 ? T.text(.off) : TA.format(.degreesPerSecond, $0) }) { value in
                         change { $0.deadzone = value }
                     }),
        ]
        return rows
    }
}
