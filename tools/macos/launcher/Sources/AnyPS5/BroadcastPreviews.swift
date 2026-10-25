import AnyPS5Core
import AppKit
import SwiftUI

/// Broadcasting drawn offscreen for `--render-preview`: Settings → Broadcasting before and while
/// live, the game's panel with Go live and with the broadcast's numbers, and the LIVE badge.
/// ANYPS5_PREVIEW_ONLY=broadcast draws only these.
@MainActor
enum BroadcastPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png"), configure: configure)
        }
        var live = BroadcastSession.Stats()
        live.state = .live
        live.duration = 47 * 60 + 12
        live.bitRate = 3_120_000
        live.framesSent = 169_870
        live.framesDropped = 42
        func settings(_ model: AppModel) {
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "broadcast" } ?? 0
            model.panelInRows = true
        }
        render("broadcast-settings") { model in
            settings(model)
            model.panelRow = 1
        }
        render("broadcast-settings-custom") { model in
            model.broadcaster.settings.service = .custom
            model.broadcaster.settings.customURL = "rtmp://192.168.1.20/live"
            model.broadcaster.settings.microphone = true
            model.broadcaster.setKey("room-7f3a9c")
            settings(model)
            model.panelRow = 1
        }
        guard let game = model(found) else { return }
        render("broadcast-settings-live") { model in
            model.broadcaster.setKey("live_123456789_abcdef")
            model.broadcaster.settings.viewerLink = "twitch.tv/robin"
            model.broadcaster.preview(.live, stats: live, game: game.id)
            settings(model)
            model.panelRow = 0
        }
        render("broadcast-game-golive") { model in
            model.broadcaster.setKey("live_123456789_abcdef")
            model.broadcaster.preview(.off, stats: BroadcastSession.Stats(), game: game.id)
            model.overlay = .gameSettings
            model.panelInRows = true
            model.panelRow = 0
        }
        render("broadcast-game-live") { model in
            model.broadcaster.setKey("live_123456789_abcdef")
            model.broadcaster.settings.viewerLink = "twitch.tv/robin"
            model.broadcaster.settings.microphone = true
            model.broadcaster.preview(.live, stats: live, game: game.id)
            model.overlay = .gameSettings
            model.panelInRows = true
            model.panelRow = 3
        }
        render("broadcast-game-reconnecting") { model in
            model.broadcaster.setKey("live_123456789_abcdef")
            var stats = live
            stats.bitRate = 0
            model.broadcaster.preview(.reconnecting(attempt: 2, delay: 4), stats: stats, game: game.id)
            model.overlay = .gameSettings
            model.panelInRows = true
            model.panelRow = 0
        }
        renderBadge(output.appendingPathComponent("broadcast-badge.png"), live: true)
        renderBadge(output.appendingPathComponent("broadcast-badge-reconnecting.png"), live: false)
    }

    /// The game the screens show, as PreviewRenderer picks it.
    private static func model(_ games: [Game]) -> Game? {
        let pick = PreviewRenderer.selectedTitle.flatMap { id in games.first { $0.titleID == id } }
        return pick ?? (games.isEmpty ? nil : games[min(1, games.count - 1)])
    }

    /// The badge at the top left of a picture of a game (ANYPS5_PREVIEW_BANNER_BACKDROP) or grey.
    static func renderBadge(_ file: URL, live: Bool) {
        if let only = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_ONLY"]?.split(separator: ","), !only.contains(where: { file.lastPathComponent.hasPrefix($0) }) { return }
        let size = CGSize(width: 640, height: 220)
        let backdrop = ProcessInfo.processInfo.environment["ANYPS5_PREVIEW_BANNER_BACKDROP"].flatMap { NSImage(contentsOfFile: $0) }
        let state = LiveBadgeState()
        state.live = live
        state.duration = 47 * 60 + 12
        let view = ZStack(alignment: .topLeading) {
            if let backdrop {
                Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height)
            } else {
                LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LiveBadgeView(state: state).frame(width: 220, height: 44).padding(18)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    }
}
