import AnyPS5Core
import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Photos, clips and voice notes on AnyTogether: shown in messages and on profiles, and the
/// gallery's screenshots and clips sent into a chat or pinned to the user's own gallery.
extension AppModel {
    /// Where the share list sends the gallery's focused screenshot or clip.
    enum ShareTarget: Identifiable {
        /// A post on AnyTogether's Captures (CaptureShare.swift).
        case post
        case conversation(TogetherConversation)
        case gallery
        case finder

        var id: String {
            switch self {
            case .post: return "post"
            case .conversation(let conversation): return "chat-" + conversation.id
            case .gallery: return "gallery"
            case .finder: return "finder"
            }
        }
    }

    var shareTargets: [ShareTarget] {
        let chats = (inbox?.conversations ?? []).prefix(6).map(ShareTarget.conversation)
        return [.post] + chats + [.gallery, .finder]
    }

    /// The words a message shows in a list or a notice: its text, or what its media is.
    func messageWords(_ message: TogetherMessage) -> String? {
        guard message.deletedAt == nil else { return nil }
        guard let attachment = message.attachment else { return message.text }
        let kind = TCloud.kind(attachment.kind)
        return message.words.map { "\(kind) · \($0)" } ?? kind
    }

    // MARK: Sharing from the gallery

    func openShareMenu() {
        guard galleryShots.indices.contains(galleryIndex) else { return }
        guard cloudAvailable else {
            NSWorkspace.shared.activateFileViewerSelecting([galleryShots[galleryIndex]])
            return
        }
        if inbox == nil { loadInbox() }
        cloud.shareIndex = 0
        withAnimation(Motion.overlay) { cloud.sharing = true }
        Sounds.shared.play(.select)
    }

    func closeShareMenu() {
        withAnimation(Motion.overlay) { cloud.sharing = false }
        Sounds.shared.play(.back)
    }

    func shareCommand(_ command: Command) {
        let targets = shareTargets
        switch command {
        case .up, .down:
            let next = min(targets.count - 1, max(0, cloud.shareIndex + (command == .down ? 1 : -1)))
            guard next != cloud.shareIndex else { return }
            cloud.shareIndex = next
            Sounds.shared.play(.move)
        case .select:
            guard targets.indices.contains(cloud.shareIndex) else { return }
            share(targets[cloud.shareIndex])
        case .back, .options, .left:
            closeShareMenu()
        default:
            break
        }
    }

    func share(_ target: ShareTarget) {
        guard galleryShots.indices.contains(galleryIndex) else { return }
        let shot = galleryShots[galleryIndex]
        if case .post = target { return openPostDraft() }
        withAnimation(Motion.overlay) { cloud.sharing = false }
        switch target {
        case .conversation(let conversation): sendShot(shot, to: conversation)
        case .gallery: shareShotToGallery(shot)
        case .finder: NSWorkspace.shared.activateFileViewerSelecting([shot])
        case .post: break
        }
    }

    /// A screenshot or clip into a conversation: made small enough, uploaded, sent.
    func sendShot(_ file: URL, to conversation: TogetherConversation) {
        guard familyPermits(.mediaSharing), !cloud.working else { return }
        cloud.working = true
        show(TCloud.text(.sending), symbol: "paperplane")
        let name = conversation.name(for: inbox?.me ?? "")
        Task {
            defer { cloud.working = false }
            do {
                let media = try await uploadShot(file)
                let sent = try await together.send(media: media.id, in: conversation.id)
                _ = inbox?.apply(sent, open: nil)
                Sounds.shared.play(.select)
                show(TCloud.format(.sentTo, name), symbol: "checkmark.circle.fill")
            } catch {
                show(cloudMessage(error), symbol: "exclamationmark.bubble.fill")
            }
        }
    }

    /// A screenshot or clip pinned to the end of the user's profile gallery.
    func shareShotToGallery(_ file: URL) {
        guard familyPermits(.mediaSharing), !cloud.working else { return }
        let max = cloud.info?.galleryMax ?? 12
        cloud.working = true
        show(TCloud.text(.preparing), symbol: "photo.stack")
        Task {
            defer { cloud.working = false }
            do {
                // Full already: nothing goes up only to be deleted unpinned a day later.
                guard try await together.myGallery().count < max else { return show(TCloud.format(.galleryFull, max), symbol: "photo.stack") }
                let media = try await uploadShot(file)
                guard try await together.pinToGallery(media.id, max: max) else { return show(TCloud.format(.galleryFull, max), symbol: "photo.stack") }
                Sounds.shared.play(.select)
                show(TCloud.text(.addedToGallery), symbol: "photo.stack.fill")
            } catch {
                show(cloudMessage(error), symbol: "exclamationmark.icloud")
            }
        }
    }

    /// Uploads a screenshot (PNG as it is, or a smaller JPEG) or a clip (H.264, made smaller
    /// past the limit) with a poster grabbed from its first second.
    func uploadShot(_ file: URL) async throws -> TogetherMedia {
        let limits = cloud.info?.media ?? TogetherStorageInfo.MediaLimits()
        if Screenshots.isClip(file) {
            let ready = try await MediaPrep.clip(file, maxBytes: limits.clip)
            defer { if ready != file { try? FileManager.default.removeItem(at: ready) } }
            let data = try Data(contentsOf: ready, options: .mappedIfSafe)
            let media = try await together.uploadMedia(kind: "clip", data: data, contentType: "video/mp4").media
            if let poster = await MediaPrep.poster(ready), poster.count <= limits.poster {
                return (try? await together.setPoster(media.id, data: poster, contentType: "image/jpeg")) ?? media
            }
            return media
        }
        let ready = try await Task.detached { try MediaPrep.image(file, maxBytes: limits.image, maxPixels: limits.pixels) }.value
        return try await together.uploadMedia(kind: "image", data: ready.data, contentType: ready.contentType).media
    }

    // MARK: Profiles

    /// The profile's gallery, where the server keeps files.
    func loadProfileGallery(_ handle: String) {
        cloud.galleryTask?.cancel()
        cloud.profileGallery = nil
        guard cloud.enabled else { return }
        cloud.galleryTask = Task {
            let gallery = (try? await together.gallery(of: handle)) ?? .failed
            guard !Task.isCancelled else { return }
            withAnimation(Motion.overlay) { cloud.profileGallery = gallery }
        }
    }

    func view(_ media: TogetherMedia) {
        guard media.kind != "voice" else { return }
        withAnimation(Motion.overlay) { cloud.viewing = media }
        Sounds.shared.play(.select)
    }

    func closeViewer() {
        withAnimation(Motion.overlay) { cloud.viewing = nil }
        Sounds.shared.play(.back)
    }
}

// MARK: Pictures from links

/// Pictures behind AnyTogether's signed links, decoded once at the size shown and kept.
@MainActor
final class RemoteImages: ObservableObject {
    static let shared = RemoteImages()
    private let cache = NSCache<NSString, NSImage>()
    private var loading: Set<String> = []
    @Published private(set) var generation = 0

    /// The cache key leaves out the signature, so a refreshed link finds the same picture.
    static func key(_ url: String) -> String { url.components(separatedBy: "?").first ?? url }

    func image(_ url: String?, now: Bool = false) -> NSImage? {
        guard let url, let link = URL(string: url) else { return nil }
        let key = RemoteImages.key(url)
        if let image = cache.object(forKey: key as NSString) { return image }
        if now || link.isFileURL {
            // Offscreen previews cannot wait; files are at hand anyway.
            guard let image = (try? Data(contentsOf: link)).flatMap(NSImage.init(data:)) else { return nil }
            cache.setObject(image, forKey: key as NSString)
            return image
        }
        guard !loading.contains(key) else { return nil }
        loading.insert(key)
        Task {
            let data = try? await URLSession.shared.data(from: link).0
            loading.remove(key)
            if let data, let image = NSImage(data: data) {
                cache.setObject(image, forKey: key as NSString)
                generation += 1
            }
        }
        return nil
    }
}

struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fill
    @ObservedObject private var images = RemoteImages.shared
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        let image = images.image(url, now: previewRender)
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: contentMode).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: image != nil)
    }
}

// MARK: Attachments

/// The media of a message as a bubble: a photo, a clip's poster with its length, a voice note
/// to play, or why it is not there.
struct AttachmentBubble: View {
    let attachment: TogetherAttachment
    let mine: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        if let media = attachment.media, media.hidden != true {
            switch media.kind {
            case "voice": VoiceNoteView(media: media, mine: mine)
            default: still(media)
            }
        } else {
            Label(TCloud.text(attachment.blocked ? .unavailable : .removed), systemImage: attachment.blocked ? "nosign" : "photo.badge.exclamationmark")
                .font(.display(14 * scale, .medium))
                .italic()
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 14 * scale)
                .padding(.vertical, 10 * scale)
                .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4 * scale, 3 * scale])))
        }
    }

    private func still(_ media: TogetherMedia) -> some View {
        let aspect = min(2.2, max(0.6, media.aspect ?? 16 / 9))
        let width = (aspect >= 1 ? 340 : 230) * scale
        return RemoteImage(url: media.still)
            .frame(width: width, height: width / aspect)
            .overlay {
                if media.kind == "clip" {
                    ZStack {
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                        Image(systemName: "play.fill")
                            .font(.system(size: 20 * scale, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52 * scale, height: 52 * scale)
                            .background(Circle().fill(.black.opacity(0.45)).background(Circle().fill(.ultraThinMaterial)))
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if media.kind == "clip", let ms = media.durationMs {
                    Text(VoiceNoteView.clock(Double(ms) / 1000)).font(.display(12 * scale, .semibold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 8 * scale).padding(.vertical, 4 * scale)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(10 * scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(mine ? model.accent.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1.5 * scale))
            .contentShape(Rectangle())
            .onTapGesture { model.view(media) }
    }
}

/// Plays a voice note from its link: one at a time, its place shown as it goes.
@MainActor
final class VoicePlayer: ObservableObject {
    static weak var current: VoicePlayer?
    @Published private(set) var playing = false
    @Published private(set) var progress = 0.0
    private var player: AVPlayer?
    private var observer: Any?
    private var ended: AnyCancellable?

    func toggle(_ url: String?) {
        if playing {
            player?.pause()
            playing = false
            return
        }
        if VoicePlayer.current !== self { VoicePlayer.current?.stop() }
        VoicePlayer.current = self
        if player == nil, let url, let link = URL(string: url) {
            let player = AVPlayer(url: link)
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, let duration = self.player?.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
                    self.progress = min(1, time.seconds / duration)
                }
            }
            ended = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem).sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.playing = false
                    self?.progress = 0
                    self?.player?.seek(to: .zero)
                }
            }
            self.player = player
        }
        player?.play()
        playing = true
    }

    func stop() {
        player?.pause()
        playing = false
    }

    deinit {
        if let observer { player?.removeTimeObserver(observer) }
    }
}

struct VoiceNoteView: View {
    let media: TogetherMedia
    let mine: Bool
    @StateObject private var player = VoicePlayer()
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    /// 0:07, 1:00.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        let seconds = Double(media.durationMs ?? 0) / 1000
        HStack(spacing: 12 * scale) {
            Image(systemName: player.playing ? "pause.fill" : "play.fill")
                .font(.system(size: 14 * scale, weight: .bold))
                .foregroundStyle(mine ? model.accent : .black)
                .frame(width: 36 * scale, height: 36 * scale)
                .background(Circle().fill(Color.white))
                .contentTransition(.symbolEffect(.replace))
            // Bars standing for the sound, filled as it plays.
            HStack(spacing: 3 * scale) {
                ForEach(0 ..< 24, id: \.self) { bar in
                    let height = 6 + 16 * abs(sin(Double(bar) * 1.7 + Double(media.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7)))
                    Capsule().fill(Color.white.opacity(Double(bar) / 24 < player.progress ? 1 : 0.38))
                        .frame(width: 3 * scale, height: height * scale)
                }
            }
            Text(Self.clock(player.playing ? seconds * player.progress : seconds)).font(.display(13 * scale, .semibold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.leading, 8 * scale)
        .padding(.trailing, 16 * scale)
        .padding(.vertical, 8 * scale)
        .background(Capsule().fill(mine ? model.accent.opacity(0.85) : Color.white.opacity(0.1)))
        .contentShape(Capsule())
        .onTapGesture { player.toggle(media.url) }
        .onDisappear { player.stop() }
    }
}

/// A photo or clip over the whole screen; a click or Escape closes it.
struct MediaViewer: View {
    let media: TogetherMedia
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 18 * scale) {
                Group {
                    if media.kind == "clip", let url = media.url.flatMap(URL.init(string:)), !previewRender {
                        ClipPlayer(url: url).aspectRatio(media.aspect ?? 16 / 9, contentMode: .fit)
                    } else {
                        RemoteImage(url: media.kind == "clip" ? media.still : media.url ?? media.thumb, contentMode: .fit)
                            .aspectRatio(media.aspect ?? 16 / 9, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
                .shadow(color: .black.opacity(0.5), radius: 30 * scale)
                HStack {
                    if let date = media.createdAt {
                        Text(TCloud.date(date)).font(.display(15 * scale, .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Hint(keys: "esc / ○", label: TCloud.text(.close))
                }
            }
            .padding(56 * scale)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.closeViewer() }
    }
}

// MARK: The gallery's share list

/// Over the gallery: the newest conversations, the user's gallery and Finder.
struct ShareMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let targets = model.shareTargets
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text(TCloud.text(.share)).font(.display(26 * scale, .light)).foregroundStyle(.white)
            if model.inbox?.conversations.isEmpty ?? false {
                Text(TCloud.text(.noChats)).font(.display(13 * scale)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6 * scale) {
                ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                    row(target, focused: index == model.cloud.shareIndex)
                        .onTapGesture {
                            model.cloud.shareIndex = index
                            model.share(target)
                        }
                }
            }
            .padding(.top, 10 * scale)
            Spacer(minLength: 0)
            HStack(spacing: 18 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
        .padding(30 * scale)
        .frame(width: 440 * scale)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .panelFrost(classic: 0.94)
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
    }

    private func row(_ target: AppModel.ShareTarget, focused: Bool) -> some View {
        let me = model.inbox?.me ?? ""
        return HStack(spacing: 14 * scale) {
            switch target {
            case .conversation(let conversation):
                let other = conversation.others(than: me).first
                ProfileAvatar(url: conversation.kind == "direct" ? other?.avatar : nil, name: conversation.name(for: me), size: 36 * scale, glow: false)
                Text(TCloud.format(.sendToChat, conversation.name(for: me))).font(.display(16 * scale, .medium)).lineLimit(1)
            case .post:
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 17 * scale, weight: .medium)).frame(width: 36 * scale)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(TCap.text(.shareToTogether)).font(.display(16 * scale, .semibold))
                    Text(TCap.text(.shareToTogetherDetail)).font(.display(12 * scale)).opacity(0.6).lineLimit(1)
                }
            case .gallery:
                Image(systemName: "photo.stack").font(.system(size: 17 * scale, weight: .medium)).frame(width: 36 * scale)
                Text(TCloud.text(.shareToGallery)).font(.display(16 * scale, .medium))
            case .finder:
                Image(systemName: "folder").font(.system(size: 17 * scale, weight: .medium)).frame(width: 36 * scale)
                Text(TCloud.text(.showInFinder)).font(.display(16 * scale, .medium))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(focused ? Color.black : .white)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 9 * scale)
        .background(FocusFill(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(0.06)))
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
        .contentShape(Rectangle())
    }
}

// MARK: A profile's gallery

/// The pinned photos and clips under a profile's card, as the owner's setting shows them.
struct ProfileGalleryStrip: View {
    let gallery: TogetherSection<[TogetherMedia]>
    let mine: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        switch gallery {
        case .shown(let items) where items.isEmpty:
            if mine { label(symbol: "photo.stack", text: TCloud.text(.profileGalleryEmpty)) }
        case .shown(let items):
            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(TCloud.text(.profileGallery)).font(.display(13 * scale, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 12 * scale) {
                    ForEach(items.prefix(8)) { media in
                        RemoteImage(url: media.still)
                            .frame(width: 150 * scale, height: 84 * scale)
                            .overlay {
                                if media.kind == "clip" {
                                    Image(systemName: "play.fill").font(.system(size: 13 * scale, weight: .bold)).foregroundStyle(.white)
                                        .padding(8 * scale).background(Circle().fill(.black.opacity(0.5)))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                            .onTapGesture { model.view(media) }
                    }
                    if items.count > 8 {
                        Text("+\(items.count - 8)").font(.display(17 * scale, .semibold)).foregroundStyle(.white.opacity(0.7)).frame(width: 60 * scale)
                    }
                }
            }
        case .private:
            label(symbol: "lock.fill", text: TCloud.text(.profileGalleryPrivate))
        case .failed:
            EmptyView()
        }
    }

    private func label(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.5))
    }
}
