import AnyPS5Core
import AppKit
import SwiftUI

// Settings › Default Display and the display rows of a game's settings: Display, Window Size and
// Vertical Sync default for every game, and a game's own choice wins (as AnyPS5 Desktop does).

extension AppModel {
    static let windowSizes = 40...100

    /// Settings › Default Display.
    func displayDefaultRows() -> [PanelRow] {
        let defaults = displayDefaults
        var rows = [
            PanelRow(id: "displayDefaultsIntro", title: T.text(.displayDefaultsDetail), kind: .info("")),
            PanelRow(id: "defaultDisplay", title: T.text(.display), symbol: "macwindow",
                     kind: .choice(options: [T.text(.windowed), T.text(.fullscreen)], selected: defaults.fullscreen ? 1 : 0) { [weak self] index in
                         self?.updateDisplayDefaults { $0.fullscreen = index == 1 }
                     }),
        ]
        if !defaults.fullscreen {
            rows.append(PanelRow(id: "defaultSize", title: T.text(.windowSize), symbol: "arrow.up.left.and.arrow.down.right",
                                 kind: .stepper(value: defaults.windowSize, range: Self.windowSizes, step: 5, format: { "\($0)%" }) { [weak self] value in
                                     self?.updateDisplayDefaults { $0.windowSize = value }
                                 }))
        }
        rows.append(PanelRow(id: "defaultVsync", title: T.text(.vsync), symbol: "waveform.path", kind: .toggle(defaults.vsync) { [weak self] value in
            self?.updateDisplayDefaults { $0.vsync = value }
        }))
        return rows
    }

    /// A game's Display, Window Size and Vertical Sync: "Default (…)" follows Settings › Default
    /// Display, and Use Default Display puts all three back on it.
    func gameDisplayRows(_ game: Game, _ settings: GameSettings) -> [PanelRow] {
        let defaults = displayDefaults
        let started = settings.withDefaults(defaults)
        func followed(_ value: String) -> String { T.format(.followDefault, value) }
        func own(_ value: Bool?) -> Int { value.map { $0 ? 2 : 1 } ?? 0 }
        var rows = [
            PanelRow(id: "display", title: T.text(.display), symbol: "macwindow",
                     kind: .choice(options: [followed(T.text(defaults.fullscreen ? .fullscreen : .windowed)), T.text(.windowed), T.text(.fullscreen)],
                                   selected: own(settings.ownFullscreen)) { [weak self] index in
                         self?.update(game) { $0.ownFullscreen = index == 0 ? nil : index == 2 }
                     }),
        ]
        if !started.fullscreen {
            let following = settings.ownWindowSize == nil
            rows.append(PanelRow(id: "size", title: T.text(.windowSize), symbol: "arrow.up.left.and.arrow.down.right",
                                 kind: .stepper(value: started.windowSize, range: Self.windowSizes, step: 5, format: { following ? followed("\($0)%") : "\($0)%" }) { [weak self] value in
                                     self?.update(game) { $0.windowSize = value }
                                 }))
        }
        // Frame generation needs vertical sync: on whatever is chosen while it is on.
        let vsync = settings.frameGeneration == true ? 1 : settings.ownVsync.map { $0 ? 1 : 2 } ?? 0
        rows.append(PanelRow(id: "vsync", title: T.text(.vsync), symbol: "waveform.path",
                             kind: .choice(options: [followed(T.text(defaults.vsync ? .on : .off)), T.text(.on), T.text(.off)], selected: vsync) { [weak self] index in
                                 self?.update(game) { $0.ownVsync = index == 0 ? nil : index == 1 }
                             }))
        if !settings.followsDisplayDefaults {
            rows.append(PanelRow(id: "useDisplayDefaults", title: T.text(.useDisplayDefaults), detail: T.text(.useDisplayDefaultsDetail), symbol: "arrow.uturn.backward",
                                 kind: .action(destructive: false) { [weak self] in
                                     guard let self else { return }
                                     self.update(game) { $0 = $0.followingDisplayDefaults() }
                                     Sounds.shared.play(.select)
                                 }))
        }
        return rows
    }
}

/// Settings › Default Display and a game's display rows, offscreen for `--render-preview`
/// (ANYPS5_PREVIEW_ONLY=display).
@MainActor
enum DisplayPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("display-settings.png")) { model in
            model.updateDisplayDefaults { $0.windowSize = 85 }
            model.open(.settings)
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "display" } ?? 0
            model.panelInRows = true
            model.panelRow = 1
        }
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("display-game.png")) { model in
            model.updateDisplayDefaults { $0.fullscreen = true }
            if let game = model.selectedGame { model.update(game) { $0.vsync = false } }
            model.open(.gameSettings)
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "display" } ?? 0
        }
    }
}
