import AVFoundation
import AppKit
import CoreImage
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

    /// The Glass theme's frosted key art: decoded small, blurred and a little richer in color, once.
    func frosted(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        let key = url.path + "@frost"
        if let image = cache[key] { return image }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        Task.detached(priority: .userInitiated) {
            let image = Artwork.frost(url)
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

    func prepareFrosted(_ url: URL?) {
        guard let url, let image = Artwork.frost(url) else { return }
        cache[url.path + "@frost"] = image
    }

    /// A blurred image needs few pixels: 480 across, blurred there, is as soft as a 30 point blur
    /// over the whole window, and costs nothing to draw or to drift.
    nonisolated static func frost(_ url: URL) -> NSImage? {
        guard let small = decode(url, maxPixels: 480), let cgImage = small.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: 6.5)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3, kCIInputContrastKey: 1.04])
            .cropped(to: input.extent)
        guard let frosted = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: frosted, size: NSSize(width: frosted.width, height: frosted.height))
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
        .drifting($drift, animated: animated, period: 28)
    }
}

extension View {
    /// The slow drift of a background picture: running while `animated`, settling back when not (a
    /// game playing, the launcher behind other windows), as a forever-repeating animation keeps the
    /// window drawing frames, and the GPU busy, the whole time.
    func drifting(_ drift: Binding<Bool>, animated: Bool, period: Double) -> some View {
        onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { drift.wrappedValue = true }
        }
        .onChange(of: animated) { _, on in
            if on {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { drift.wrappedValue = true }
            } else {
                withAnimation(.easeOut(duration: 0.6)) { drift.wrappedValue = false }
            }
        }
    }
}
