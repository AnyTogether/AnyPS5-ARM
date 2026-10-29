import AnyPS5Core
import Foundation

/// Settings → Controllers, the controller test and the troubleshooter: their texts, from the language files (l10n).
enum TP {
    enum Key: String, CaseIterable {
        case title = "padTitle", noneConnected = "padNone", noneConnectedDetail = "padNoneDetail", playerOne = "padPlayerOne", testInputs = "padTest", testInputsDetail = "padTestDetail", testVibration = "padVibrate", testVibrationDetail = "padVibrateDetail"
        case light = "padLight", lightDetail = "padLightDetail", lightTheme = "padLight_theme", lightBlue = "padLight_blue", lightRed = "padLight_red", lightGreen = "padLight_green", lightPurple = "padLight_purple", lightPink = "padLight_pink", lightOrange = "padLight_orange", lightWhite = "padLight_white", lightOff = "padLight_off"
        case confirm = "padConfirm", confirmDetail = "padConfirmDetail", confirmCross = "padConfirmCross", confirmCircle = "padConfirmCircle", deadzone = "padDeadzone", deadzoneDetail = "padDeadzoneDetail"
        case usb = "padUsb", bluetooth = "padBluetooth", connectionUnknown = "padConnected", battery = "padBattery", batteryAbout = "padBatteryAbout", charging = "padCharging", generic = "padGeneric"
        case troubleshoot = "padTroubleshoot", allGood = "padAllGood", allGoodDetail = "padAllGoodLauncherDetail"
        case noControllers = "padFinding_noControllers", noControllersDetail = "padFinding_noControllersDetail", usbCable = "padFinding_usbCable", usbCableDetail = "padFinding_usbCableDetail", bluetoothPairing = "padFinding_bluetoothPairing", bluetoothPairingDetail = "padFinding_bluetoothPairingDetail"
        case dualShock3 = "padDualShock3", dualShock3Detail = "padDualShock3Detail", unmapped = "padFinding_unmapped", unmappedDetail = "padFinding_unmappedDetail", lowBattery = "padFinding_lowBattery", lowBatteryDetail = "padFinding_lowBatteryDetail", steamRunning = "padFinding_steamRunning", steamRunningDetail = "padFinding_steamRunningDetail"
        case testTitle = "padTestTitle", testHoldToLeave = "padHoldToLeave", testLeave = "padLeave", testNoPad = "padTestNoPad", testSticks = "padSticks", testTriggers = "padTriggers", vibrated = "padVibrating", noVibration = "padNoVibration"
        case connected = "padArrived", disconnected = "padLeft"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
    static func format(_ key: Key, _ arguments: CVarArg...) -> String { String(format: text(key), arguments: arguments) }

    static func light(_ light: PadLight) -> String {
        switch light {
        case .theme: return text(.lightTheme)
        case .blue: return text(.lightBlue)
        case .red: return text(.lightRed)
        case .green: return text(.lightGreen)
        case .purple: return text(.lightPurple)
        case .pink: return text(.lightPink)
        case .orange: return text(.lightOrange)
        case .white: return text(.lightWhite)
        case .off: return text(.lightOff)
        }
    }

    static func kind(_ kind: PadKind) -> String { kind == .generic ? text(.generic) : kind.reportName }

    static func connection(_ connection: PadConnection) -> String {
        switch connection {
        case .usb: return text(.usb)
        case .bluetooth: return text(.bluetooth)
        case .unknown: return text(.connectionUnknown)
        }
    }

    /// "DualSense · Bluetooth · 80% · charging".
    static func summary(_ pad: PadInfo) -> String {
        var parts = [kind(pad.kind), connection(pad.connection)]
        if let battery = pad.battery {
            parts.append(format(battery.approximate ? .batteryAbout : .battery, battery.percent))
            if battery.charging == true { parts.append(text(.charging)) }
        }
        return parts.joined(separator: " · ")
    }

    /// A finding's title and what to do.
    static func finding(_ finding: PadTroubleshooter.Finding) -> (title: String, detail: String) {
        switch finding {
        case .noControllers: return (text(.noControllers), text(.noControllersDetail))
        case .usbCable: return (text(.usbCable), text(.usbCableDetail))
        case .bluetoothPairing: return (text(.bluetoothPairing), text(.bluetoothPairingDetail))
        case .dualShock3: return (text(.dualShock3), text(.dualShock3Detail))
        case .unmapped(let name): return (format(.unmapped, name), text(.unmappedDetail))
        case .lowBattery(let name, let percent): return (format(.lowBattery, name, percent), text(.lowBatteryDetail))
        case .steamRunning: return (text(.steamRunning), text(.steamRunningDetail))
        }
    }
}
