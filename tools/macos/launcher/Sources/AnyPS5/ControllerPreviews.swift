import AnyPS5Core
import AppKit
import SwiftUI

/// Settings → Controllers and the controller test drawn offscreen for `--render-preview`: two
/// pads connected (Player 1 a DualSense over Bluetooth), none at all (the troubleshooter), a low
/// battery with Steam open, and the test with buttons held, a stick pushed and a trigger half in.
@MainActor
enum ControllerPreviews {
    static let sense = PadInfo(id: "sense", name: "DualSense Wireless Controller", kind: .dualSense, connection: .bluetooth,
                               battery: PadBattery(percent: 80), driver: "GameController", vendor: 0x054C, product: 0x0CE6, hasRumble: true, hasLight: true)
    static let xbox = PadInfo(id: "xbox", name: "Xbox Wireless Controller", kind: .xbox, connection: .usb, driver: "GameController", hasRumble: true)
    static let ds3 = PadInfo(id: "ds3", name: "PLAYSTATION(R)3 Controller", kind: .dualShock3, connection: .usb,
                             battery: PadBattery(percent: 50, approximate: true, charging: true), driver: "IOHID (DualShock 3)", hasRumble: true)

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, preferences: Preferences, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                PreviewRenderer.signedIn(model)
                configure(model)
            }
        }
        func settings(_ model: AppModel, row: String? = nil) {
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "controllers" } ?? 0
            model.panelInRows = true
            model.panelRow = model.panelCategories().first { $0.id == "controllers" }?.rows.firstIndex { $0.id == row } ?? 0
        }
        render("controllers-two", preferences) { model in
            Controllers.shared.preview([sense, xbox], playerOne: "sense", findings: [.dualShock3])
            settings(model, row: "padLight")
        }
        render("controllers-none", preferences) { model in
            Controllers.shared.preview([])
            settings(model, row: "padTest")
        }
        var circle = preferences
        circle.confirmCircle = true
        circle.stickDeadzone = 8
        circle.controllerLight = PadLight.purple.rawValue
        render("controllers-trouble", circle) { model in
            var low = sense
            low.battery = PadBattery(percent: 9)
            Controllers.shared.preview([low, ds3], playerOne: "sense", findings: [.lowBattery(low.name, 9), .unmapped("Logitech Dual Action"), .steamRunning])
            settings(model, row: "padDeadzone")
        }
        let held = PadState(pressed: [.south, .r1, .dpadLeft], leftX: 0.62, leftY: -0.35, rightX: -0.2, rightY: 0.1, l2: 0, r2: 0.55)
        render("controller-test", circle) { model in
            Controllers.shared.preview([sense, xbox], states: ["sense": held], playerOne: "sense")
            model.overlay = .controllerTest
        }
        render("controller-test-xbox", preferences) { model in
            Controllers.shared.preview([xbox], states: ["xbox": PadState(pressed: [.north, .l1, .guide], leftX: 0, leftY: 0, rightX: 0.9, rightY: -0.3, l2: 1, r2: 0)], playerOne: "xbox")
            model.overlay = .controllerTest
        }
        render("controller-test-ds3", preferences) { model in
            Controllers.shared.preview([ds3], states: ["ds3": PadState(pressed: [.east, .start], leftY: 0.8)], playerOne: "ds3")
            model.overlay = .controllerTest
        }
        render("controllers-home-low-battery", preferences) { _ in
            var low = sense
            low.battery = PadBattery(percent: 9)
            Controllers.shared.preview([low], playerOne: "sense")
        }
        Controllers.shared.preview([])
    }
}
