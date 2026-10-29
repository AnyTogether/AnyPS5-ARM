import AnyPS5Core
import AppKit
import SwiftUI

/// The PS button's menus, Settings → Shortcuts and a choice being edited with the pad, drawn
/// offscreen for `--render-preview`, with the pad's glyphs or the keyboard's as each would show them.
@MainActor
enum HomeMenuPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, mode: InputMode, configure: (AppModel) -> Void) in
            InputModeState.shared.preview(mode)
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                PreviewRenderer.signedIn(model)
                configure(model)
            }
            InputModeState.shared.preview(.keyboard)
        }
        func settings(_ model: AppModel, _ category: String, row: String?) {
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == category } ?? 0
            model.panelInRows = row != nil
            let rows = model.panelCategories().first { $0.id == category }?.rows ?? []
            model.panelRow = rows.firstIndex { $0.id == row } ?? 0
        }
        render("menu-quick", .pad) { model in
            model.pausedGame = true
            model.overlay = .quickMenu
        }
        render("menu-quick-running", .keyboard) { model in
            model.overlay = .quickMenu
            model.menuIndex = 1
        }
        render("menu-close", .pad) { model in
            model.overlay = .closeGame
            model.menuIndex = 1
        }
        render("menu-home", .pad) { model in
            model.overlay = .homeMenu
            model.menuIndex = 1
        }
        // The launcher's own crash or stall last time, offered at the next start.
        render("menu-report", .keyboard) { model in
            model.launcherReport = LauncherReportState(problem: LauncherProblem(kind: .crash, at: Date(), version: "0.2.26", platform: "macOS"), forget: {})
            model.overlay = .launcherReport
        }
        render("menu-report-hang", .pad) { model in
            model.launcherReport = LauncherReportState(problem: LauncherProblem(kind: .hang, at: Date(), version: "0.2.26", platform: "macOS", stalledMs: 12_000, recovered: true), forget: {})
            model.overlay = .launcherReport
            model.menuIndex = 1
        }
        render("shortcuts", .keyboard) { model in settings(model, "shortcuts", row: "shortcut-key-home") }
        render("shortcuts-pad", .pad) { model in
            var changed = model.preferences
            var map = ShortcutMap()
            map.setPad(PadChord([.l1, .r1]), for: .quickMenu)
            changed.shortcuts = map
            model.preferences = changed
            settings(model, "shortcuts", row: "shortcut-pad-quickMenu")
            model.shortcutCapture = ShortcutCapture(action: .screenshot, pad: true)
        }
        // A choice with the pad: highlighted it shows no arrows, edited it wears the ring.
        render("settings-pad-choice", .pad) { model in settings(model, "behaviour", row: "clipLength") }
        render("settings-pad-editing", .pad) { model in
            settings(model, "behaviour", row: "clipLength")
            let rows = model.panelCategories()[model.panelCategory].rows
            _ = model.rowEditor.intent(for: .select, row: rows[model.panelRow].id, kind: .choice, mode: .pad)
        }
        render("settings-keyboard-choice", .keyboard) { model in settings(model, "appearance", row: "fullScreen") }
        render("home-pad", .pad) { _ in }
    }
}
