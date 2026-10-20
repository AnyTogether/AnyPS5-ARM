import AVFoundation
import AppKit
import ImageIO
import SwiftUI

/// Game artwork read at the size it is shown: pic0.png is 3840x2160 and icon0.png 512x512, so both are
/// decoded once as thumbnails off the main thread and kept.
@MainActor
final class Artwork: ObservableObject {
    static let shared = Artwork()
    private var cache: [String: NSImage] = [:]
    private var loading: Set<String> = []
    @Published private(set) var generation = 0

    /// Decodes at once (offscreen previews, which cannot wait for the background decode).
    func prepare(_ url: URL?, maxPixels: Int) {
        guard let url, let image = Artwork.decode(url, maxPixels: maxPixels) else { return }
        cache[url.path + "@\(maxPixels)"] = image
    }

    func image(_ url: URL?, maxPixels: Int) -> NSImage? {
        guard let url else { return nil }
        let key = url.path + "@\(maxPixels)"
        if let image = cache[key] { return image }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        Task.detached(priority: .userInitiated) {
            let image = Artwork.decode(url, maxPixels: maxPixels)
            await MainActor.run {
                self.loading.remove(key)
                if let image {
                    self.cache[key] = image
                    self.generation += 1
                }
            }
        }
        return nil
    }

    nonisolated static func decode(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// An artwork image that fades in once decoded.
struct ArtworkImage: View {
    let url: URL?
    let maxPixels: Int
    var contentMode: ContentMode = .fill
    @ObservedObject private var artwork = Artwork.shared

    var body: some View {
        let image = artwork.image(url, maxPixels: maxPixels)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: image != nil)
    }
}

/// A user's own background video, looping without sound.
struct LoopingVideo: NSViewRepresentable {
    let url: URL
    var paused: Bool

    func makeNSView(context: Context) -> VideoView {
        let view = VideoView()
        view.play(url)
        return view
    }

    func updateNSView(_ view: VideoView, context: Context) {
        if view.current != url { view.play(url) }
        paused ? view.player.pause() : view.player.play()
    }

    final class VideoView: NSView {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private(set) var current: URL?
        private let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func play(_ url: URL) {
            current = url
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }
    }
}

/// The user's own background picture, slowly drifting.
struct DriftingImage: View {
    let url: URL
    var animated: Bool
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            ArtworkImage(url: url, maxPixels: Int(max(proxy.size.width, proxy.size.height) * 2))
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(drift ? 1.08 : 1.0)
                .offset(x: drift ? -proxy.size.width * 0.015 : proxy.size.width * 0.015)
                .clipped()
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 28).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
