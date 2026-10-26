import AnyPS5Core
import AppKit
import SwiftUI

/// Settings → Battery & Heat, the quick menu's power line and Undo, and the heat note over a game,
/// drawn offscreen for `--render-preview` with made-up readings.
@MainActor
enum PowerPreviews {
    static let battery = PowerReading(hasBattery: true, onBattery: true, batteryPercent: 64, minutesToEmpty: 125, thermal: .fair, lowPowerMode: false)
    static let hot = PowerReading(hasBattery: true, onBattery: false, batteryPercent: 100, minutesToEmpty: nil, thermal: .serious, lowPowerMode: false)
    static let hotOnBattery = PowerReading(hasBattery: true, onBattery: true, batteryPercent: 41, minutesToEmpty: nil, thermal: .critical, lowPowerMode: false)

    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, mode: InputMode, reading: PowerReading, configure: (AppModel) -> Void) in
            InputModeState.shared.preview(mode)
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.power.read(reading)
                configure(model)
            }
            InputModeState.shared.preview(.keyboard)
        }
        func settings(_ model: AppModel, row: String) {
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "power" } ?? 0
            model.panelInRows = true
            let rows = model.panelCategories().first { $0.id == "power" }?.rows ?? []
            model.panelRow = rows.firstIndex { $0.id == row } ?? 0
        }
        render("power-settings", .pad, battery) { model in settings(model, row: "batteryCap") }
        render("power-settings-hot", .keyboard, hot) { model in settings(model, row: "powerUndo") }
        render("power-settings-tr", .pad, battery) { model in
            var turkish = model.preferences
            turkish.language = .turkish
            model.preferences = turkish
            settings(model, row: "hotOn")
        }
        render("power-quick", .pad, battery) { model in model.overlay = .quickMenu }
        render("power-quick-hot", .pad, hotOnBattery) { model in
            model.overlay = .quickMenu
            model.menuIndex = 2
        }
        let cards: [(String, NoticeToast)] = [
            ("power-hot-banner.png", NoticeToast(title: TPow.text(.hotTitle), detail: AppModel.hotDetail(lowered: true), symbol: "thermometer.sun.fill", still: true) {}),
        ]
        for (name, card) in cards {
            let file = output.appendingPathComponent(name)
            if let only = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"]?.split(separator: ","), !only.contains(where: { file.lastPathComponent.hasPrefix($0) }) { continue }
            let view = ZStack(alignment: .top) {
                Color(white: 0.15)
                card
            }
            .frame(width: TrophyBanner.size.width, height: TrophyBanner.size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
        }
    }
}
