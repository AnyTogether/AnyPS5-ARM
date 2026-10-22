import AnyPS5Core
import AppKit
import SwiftUI

/// Draws the launcher's screens into PNG files offscreen: no window opens, nothing is saved.
@MainActor
enum PreviewRenderer {
    static let size = CGSize(width: 1600, height: 900)
    static var stills: [Theme: NSImage] = [:]

    static func run(output: URL, games root: URL) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let found = GameLibrary.scan(root)
        for game in found {
            Artwork.shared.prepare(game.icon, maxPixels: 400)
            Artwork.shared.prepare(game.background, maxPixels: Int(max(size.width, size.height) * 1.6))
        }
        var preferences = Preferences()
        preferences.onboarded = true
        preferences.gamesFolder = root.path
        preferences.sounds = false
        preferences.profileName = "Utku"
        // ANYPS5_PREVIEW_LANGUAGE=en draws the screens in English.
        preferences.language = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_LANGUAGE"].flatMap(Language.init(rawValue:)) ?? .turkish

        for theme in Theme.allCases {
            stills[theme] = BackgroundView.still(theme: theme, width: 660, height: 372, time: 200)
        }
        for theme in Theme.allCases {
            preferences.theme = theme
            let still = BackgroundView.still(theme: theme, width: Int(size.width), height: Int(size.height), time: 260)
            preferences.gameArtwork = false
            render(preferences, found, root, still, output.appendingPathComponent("home-theme\(theme.rawValue).png"))
        }
        preferences.theme = .cosmic
        preferences.gameArtwork = true
        let still = BackgroundView.still(theme: .cosmic, width: Int(size.width), height: Int(size.height), time: 260)
        render(preferences, found, root, still, output.appendingPathComponent("home-artwork.png"))
        render(preferences, found, root, still, output.appendingPathComponent("home-actions.png")) { model in model.focus = .actions(0) }
        render(preferences, found, root, still, output.appendingPathComponent("home-unlocking.png")) { model in
            if let game = model.selectedGame { model.previewProgress(game, step: .copy, fraction: 0.4) }
        }
        render(preferences, found, root, still, output.appendingPathComponent("starting.png")) { model in
            if let game = model.selectedGame { model.previewStarting(game) }
        }
        render(preferences, found, root, still, output.appendingPathComponent("game-settings.png")) { model in model.overlay = .gameSettings; model.panelInRows = true; model.panelRow = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("controls.png")) { model in model.overlay = .controls; model.panelInRows = true; model.panelRow = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("controls-capture.png")) { model in model.overlay = .controls; model.panelInRows = true; model.panelRow = 3; model.capturing = .square }
        render(preferences, found, root, still, output.appendingPathComponent("advanced.png")) { model in model.overlay = .advanced; model.panelInRows = true; model.panelRow = 4 }
        render(preferences, found, root, still, output.appendingPathComponent("update-choice.png")) { model in model.overlay = .updateChoice; model.panelInRows = true; model.panelRow = 0 }
        render(preferences, found, root, still, output.appendingPathComponent("home-trophies.png")) { model in model.focus = .actions(1) }
        render(preferences, found, root, still, output.appendingPathComponent("trophies.png")) { model in model.overlay = .trophies; model.trophyIndex = 1 }
        render(preferences, found, root, still, output.appendingPathComponent("settings.png")) { model in model.overlay = .settings; model.panelInRows = true; model.panelRow = 0 }
        for category in 1..<6 {
            render(preferences, found, root, still, output.appendingPathComponent("settings\(category).png")) { model in model.overlay = .settings; model.panelCategory = category }
        }
        render(preferences, found, root, still, output.appendingPathComponent("library.png")) { model in model.overlay = .library; model.libraryIndex = 1 }
        renderBanner(preferences, found, root, output.appendingPathComponent("trophy-banner.png"))
        var fresh = preferences
        fresh.onboarded = false
        fresh.gamesFolder = nil
        for step in 0..<3 {
            if step == 2 { fresh.gamesFolder = root.path }
            render(fresh, step == 2 ? found : [], root, still, output.appendingPathComponent("onboarding\(step).png")) { model in model.onboardingStep = step }
        }
        print("rendered into \(output.path)")
    }

    /// The trophy card over a picture of a game (ANYPS5_PREVIEW_BANNER_BACKDROP), with the selected
    /// game's first earned trophy.
    static func renderBanner(_ preferences: Preferences, _ games: [Game], _ root: URL, _ file: URL) {
        let model = AppModel(preferences: preferences)
        model.preview(games: games, root: root)
        let pick = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SELECT"].flatMap { id in games.first { $0.titleID == id } } ?? games.first
        guard let game = pick, let trophy = model.trophies[game.id]?.trophies.first(where: { $0.unlocked != nil }) else { return }
        let backdrop = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_BANNER_BACKDROP"].flatMap { NSImage(contentsOfFile: $0) }
        let view = ZStack(alignment: .top) {
            if let backdrop {
                Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height)
            } else {
                Color.black
            }
            TrophyToast(trophy: trophy, still: true) {}
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    }

    static func render(_ preferences: Preferences, _ games: [Game], _ root: URL, _ still: NSImage?, _ file: URL, configure: (AppModel) -> Void = { _ in }) {
        let model = AppModel(preferences: preferences)
        model.preview(games: games, root: root)
        // ANYPS5_PREVIEW_SELECT=<title ID> picks the game the screens show.
        let pick = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_SELECT"].flatMap { id in games.firstIndex { $0.titleID == id } }
        model.selected = pick ?? min(1, max(0, games.count - 1))
        configure(model)
        let view = RootView()
            .environmentObject(model)
            .environment(\.stillBackground, still)
            .environment(\.themeStills, stills)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { print("could not render \(file.lastPathComponent)"); return }
        let representation = NSBitmapImageRep(cgImage: image)
        try? representation.representation(using: .png, properties: [:])?.write(to: file)
    }
}
