@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// A launcher model over a few fake dumps in a temporary folder, as the offscreen previews make
/// it: nothing is saved, no window opens, no sound plays.
@MainActor
enum LauncherFixture {
    static func folder(games count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-tests-\(UUID().uuidString)")
        for index in 1...count {
            let title = String(format: "PPSA%05d", index)
            let folder = root.appendingPathComponent(title)
            let system = folder.appendingPathComponent("sce_sys")
            try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
            let json = #"{"titleId":"\#(title)","contentVersion":"01.000","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"Game \#(index)"}}}"#
            try Data(json.utf8).write(to: system.appendingPathComponent("param.json"))
            try Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0, 0]).write(to: folder.appendingPathComponent("eboot.bin"))
        }
        return root
    }

    static func model(games count: Int = 3, configure: (inout Preferences) -> Void = { _ in }) throws -> AppModel {
        _ = NSApplication.shared
        T.texts = T.load([T.sourceFolder])
        let root = try folder(games: count)
        var preferences = Preferences()
        preferences.onboarded = true
        preferences.sounds = false
        preferences.libraryFolders = [root.path]
        configure(&preferences)
        let model = AppModel(preferences: preferences)
        model.preview(games: GameLibrary.scan(root), root: root)
        return model
    }
}
