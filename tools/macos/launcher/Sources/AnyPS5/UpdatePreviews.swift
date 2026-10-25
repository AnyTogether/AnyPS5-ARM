import AnyPS5Core
import AppKit
import SwiftUI

/// The launcher's own update drawn offscreen for `--render-preview`: the home screen's notice
/// (ready, its Restart Now focused, waiting for a game) and About in each state.
@MainActor
enum UpdatePreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                PreviewRenderer.signedIn(model)
                configure(model)
            }
        }
        let ready = LauncherUpdateState.ready(version: "0.2.20")
        render("update-notice") { $0.previewUpdate(ready) }
        render("update-notice-focus") { $0.previewUpdate(ready); $0.focus = .notice(0) }
        render("update-notice-waiting") { $0.previewUpdate(ready, waitingForGame: true); $0.focus = .notice(0) }
        let states: [(String, LauncherUpdateState)] = [
            ("ready", ready), ("downloading", .downloading(version: "0.2.20", fraction: 0.42)), ("available", .available(version: "0.2.20")),
            ("current", .upToDate(checked: Date())), ("checking", .checking), ("failed", .failed),
        ]
        for (name, state) in states {
            render("about-update-\(name)") { model in
                model.previewUpdate(state)
                model.overlay = .settings
                model.panelCategory = model.panelCategories().firstIndex { $0.id == "about" } ?? 0
                model.panelInRows = true
                model.panelRow = model.panelCategories().first { $0.id == "about" }?.rows.firstIndex { $0.id == "update" || $0.id == "checkForUpdates" } ?? 0
            }
        }
    }
}
