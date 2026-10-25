import AnyPS5Core
import AppKit
import AVFoundation
import AVKit
import ImageIO
import SwiftUI

/// The selected game's F12 screenshots and clips, like the console's media gallery: a grid of
/// them, and one at a time over the whole screen, a clip playing.
struct Gallery: View {
    let game: Game
    let shots: [URL]
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    static let columns = 4

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).background(.ultraThinMaterial).ignoresSafeArea()
            if model.galleryViewing, shots.indices.contains(model.galleryIndex) {
                viewer(shots[model.galleryIndex])
            } else {
                VStack(alignment: .leading, spacing: 28 * scale) {
                    header
                    if shots.isEmpty {
                        Text(T.text(.screenshotsNone))
                            .font(.display(17 * scale))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                    } else {
                        grid
                    }
                }
                .padding(.horizontal, 80 * scale)
                .padding(.vertical, 56 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if model.cloud.sharing {
                HStack(spacing: 0) {
                    Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.closeShareMenu() }
                    ShareMenu()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 26 * scale) {
            VStack(alignment: .leading, spacing: 12 * scale) {
                Text(T.text(.screenshots))
                    .font(.display(13 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(game.name)
                    .font(.display(36 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(shots.count)")
                    .font(.display(17 * scale, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            // △ shares where AnyTogether keeps files (else it shows the file in Finder, as before).
            let sharing = model.cloudAvailable && !shots.isEmpty
            HintBar(options: !sharing)
            if sharing { Hint(keys: "O / △", label: TCloud.text(.hintShare)) }
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18 * scale), count: Gallery.columns), spacing: 18 * scale) {
                    ForEach(Array(shots.enumerated()), id: \.element) { index, shot in
                        Thumbnail(url: shot, focused: index == model.galleryIndex, accent: model.accent)
                            .id(shot)
                            .onTapGesture {
                                if model.galleryIndex == index { model.galleryViewing = true } else { model.galleryIndex = index }
                            }
                    }
                }
                .padding(4 * scale)
    }

    @ViewBuilder private var grid: some View {
        if previewRender {
            Color.clear.overlay(alignment: .top) { tiles }.clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) { tiles }
                    .onChange(of: model.galleryIndex) { _, index in
                        guard shots.indices.contains(index) else { return }
                        withAnimation(Motion.focus) { proxy.scrollTo(shots[index], anchor: .center) }
                    }
            }
            .id(game.id)
        }
    }

    private func viewer(_ shot: URL) -> some View {
        VStack(spacing: 18 * scale) {
            if Screenshots.isClip(shot) {
                ClipPlayer(url: shot)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                    .shadow(color: .black.opacity(0.5), radius: 30 * scale)
            } else if let image = NSImage(contentsOf: shot) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                    .shadow(color: .black.opacity(0.5), radius: 30 * scale)
            }
            HStack {
                Text(Gallery.taken(shot))
                    .font(.display(15 * scale, .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(model.galleryIndex + 1) / \(shots.count)")
                    .font(.display(15 * scale, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(48 * scale)
        .onTapGesture { model.galleryViewing = false }
    }

    /// The moment in the file name (…-yyyyMMdd-HHmmss), as the Mac writes dates.
    static func taken(_ shot: URL) -> String {
        let parts = shot.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count >= 3 else { return shot.lastPathComponent }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyyMMddHHmmss"
        guard let date = parser.date(from: String(parts[1] + parts[2])) else { return shot.lastPathComponent }
        return date.formatted(date: .long, time: .shortened)
    }
}

/// One screenshot, small: read at a size that fits the grid, off the main thread.
struct Thumbnail: View {
    let url: URL
    let focused: Bool
    let accent: Color
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @State private var image: NSImage?

    nonisolated static func load(_ url: URL) -> NSImage? {
        if Screenshots.isClip(url) {
            // A clip shows a frame from its first second.
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 520, height: 520)
            guard let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 520] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image = previewRender ? Thumbnail.load(url) : image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomLeading) {
            if Screenshots.isClip(url) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9 * scale)
                    .padding(.vertical, 5 * scale)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(8 * scale)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
        .overlay(RoundedRectangle(cornerRadius: 10 * scale).strokeBorder(focused ? Color.white : .white.opacity(0.1), lineWidth: focused ? 3 * scale : 1))
        .scaleEffect(focused ? 1.03 : 1)
        .animation(Motion.focus, value: focused)
        .task(id: url) {
            let url = url
            image = await Task.detached(priority: .userInitiated) { Thumbnail.load(url) }.value
        }
    }
}

/// A clip playing from the start, looping, with the system's controls.
struct ClipPlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.player = ClipPlayer.player(for: url)
        view.player?.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player?.pause()
            view.player = ClipPlayer.player(for: url)
            view.player?.play()
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }

    private static func player(for url: URL) -> AVPlayer {
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        objc_setAssociatedObject(player, &loopKey, looper, .OBJC_ASSOCIATION_RETAIN)
        return player
    }
}

private nonisolated(unsafe) var loopKey = 0
