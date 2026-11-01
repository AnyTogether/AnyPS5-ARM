import AnyPS5Core
import AppKit
import SwiftUI

/// The files panel (a zip to unpack, Add Update) and Settings › Engine with a git checkout, drawn
/// offscreen for `--render-preview`. The zips and the checkout are made up; the checkout is a few
/// empty files in a temporary folder.
@MainActor
enum GameFilesPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, prefs: Preferences, configure: (AppModel) -> Void) in
            PreviewRenderer.render(prefs, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                PreviewRenderer.signedIn(model)
                configure(model)
            }
        }
        guard let game = found.indices.contains(min(1, max(0, found.count - 1))) ? found[min(1, max(0, found.count - 1))] : nil else { return }
        let gb: Int64 = 1_000_000_000
        let archive = GameArchive(url: root.appendingPathComponent("PPSA01234.zip"), size: 2 * gb)
        let plan = ArchivePlan(files: 4_873, size: 3 * gb, strip: "PPSA01234/", looksLikeGame: true, refused: [], titleID: "PPSA01234", version: "01.000.000")
        render("files-unpack", preferences) { $0.previewFiles(GameFilesState(asked: .unpack(archive, plan, into: archive.folder, updateOf: nil))) }
        let patch = GameArchive(url: root.appendingPathComponent(game.titleID + "-v104.zip"), size: 3 * gb)
        var newer = plan
        newer.size = gb
        newer.version = "01.004.000"
        render("files-unpack-update", preferences) {
            $0.previewFiles(GameFilesState(asked: .unpack(patch, newer, into: GameUpdates.target(game), updateOf: game)))
        }
        var unsafe = plan
        unsafe.refused = ["../../Library/LaunchAgents/evil.plist"]
        render("files-unsafe", preferences) { $0.previewFiles(GameFilesState(asked: .unpack(archive, unsafe, into: archive.folder, updateOf: nil))) }
        var huge = plan
        huge.size = 40_000 * gb
        render("files-no-space", preferences) { $0.previewFiles(GameFilesState(asked: .unpack(archive, huge, into: archive.folder, updateOf: nil))) }
        let job = FilesAsk.unpack(archive, plan, into: archive.folder, updateOf: nil)
        render("files-unpacking", preferences) { $0.previewFiles(GameFilesState(asked: job, working: job, done: 1_300_000_000, total: 3 * gb)) }
        let update = UpdateCandidate(folder: URL(fileURLWithPath: "/Volumes/Backup/\(game.titleID)-patch"), titleID: game.titleID, version: "01.004.000")
        render("files-add-update", preferences) { $0.previewFiles(GameFilesState(asked: .update(update, game: game, size: 6 * gb))) }
        let copy = FilesAsk.update(update, game: game, size: 6 * gb)
        render("files-copying", preferences) { $0.previewFiles(GameFilesState(asked: copy, working: copy, done: 2 * gb, total: 6 * gb)) }
        render("files-game-settings", preferences) { model in
            model.overlay = .gameSettings
            model.panelInRows = true
            model.panelRow = model.panelCategories().first?.rows.firstIndex { $0.id == "addUpdate" } ?? 0
        }

        // Settings › Engine with a checkout of AnyPS5-ARM as the engine folder.
        let checkout = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-preview-checkout-\(UUID().uuidString)/AnyPS5-ARM")
        defer { try? FileManager.default.removeItem(at: checkout.deletingLastPathComponent()) }
        for part in ["core/relinker", "core/libs", "tools/macos/patches", "build-mac", ".git"] {
            try? FileManager.default.createDirectory(at: checkout.appendingPathComponent(part), withIntermediateDirectories: true)
        }
        try? Data().write(to: checkout.appendingPathComponent("CMakeLists.txt"))
        try? Data("CMAKE_GENERATOR:INTERNAL=Ninja\n".utf8).write(to: checkout.appendingPathComponent("build-mac/CMakeCache.txt"))
        var withCheckout = preferences
        withCheckout.engineCheckout = checkout.path
        let tools = DevTools(developer: URL(fileURLWithPath: "/Library/Developer/CommandLineTools"), git: URL(fileURLWithPath: "/usr/bin/git"),
                             cmake: URL(fileURLWithPath: "/opt/homebrew/bin/cmake"), ninja: URL(fileURLWithPath: "/opt/homebrew/bin/ninja"))
        let states: [(String, EngineGitState)] = [
            ("engine-git", EngineGitState(tools: tools)),
            ("engine-git-building", EngineGitState(step: .building, lines: ["[812/1406] Building CXX object core/libs/CMakeFiles/libSceGnmDriver.dir/gnm.cpp.o",
                                                                             "[813/1406] Building CXX object core/libs/CMakeFiles/libSceAgc.dir/agc.cpp.o"], tools: tools)),
            ("engine-git-failed", EngineGitState(failure: GitUpdateFailure(.pull, ["hint: Diverging branches can't be fast-forwarded.", "fatal: Not possible to fast-forward, aborting."]), tools: tools)),
            ("engine-git-missing", EngineGitState(tools: DevTools(developer: tools.developer, git: tools.git))),
        ]
        for (name, state) in states {
            render(name, withCheckout) { model in
                model.engineGit = state
                model.overlay = .settings
                model.panelCategory = model.panelCategories().firstIndex { $0.id == "engine" } ?? 0
                model.panelInRows = true
                model.panelRow = model.panelCategories()[model.panelCategory].rows.firstIndex { $0.id == "engineGitUpdate" || $0.id == "engineGitFailed" } ?? 0
            }
        }
    }
}
