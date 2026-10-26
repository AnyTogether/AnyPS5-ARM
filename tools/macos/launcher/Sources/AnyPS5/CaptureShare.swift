import AnyPS5Core
import AppKit
import AVFoundation
import Combine
import SwiftUI

/// What Captures hold: the post being written over the gallery, the Captures feed and a post's
/// comments. It lives apart from `AppModel`'s own properties and passes its changes on to the
/// model, so the views that watch the model redraw with it.
@MainActor
final class CapturesState: ObservableObject {
    // The post being written over the gallery
    enum DraftRow: Int, CaseIterable { case caption, visibility, post }
    enum Stage: Equatable { case idle, uploading, posting }

    /// The post being written; nil when the sheet is closed.
    @Published var draft: TogetherPostDraft?
    /// The screenshot or clip it shares.
    @Published var draftFile: URL?
    @Published var draftRow = DraftRow.caption
    /// The caption's field has the keyboard.
    @Published var draftTyping = false
    /// A clip's length and size against what a post takes; nil for a picture or until read.
    @Published var clipCheck: TogetherClipCheck?
    @Published var clipMs: Int?
    @Published var stage = Stage.idle
    /// The file already uploaded for this draft, so trying again does not send it twice.
    var uploaded: (file: URL, media: String)?

    // The feed
    @Published var feed = TogetherCaptures()
    @Published var failed = false
    @Published var index = 0
    /// The focused post's focused action (CaptureAction).
    @Published var action = 0
    /// A post's Delete pressed once: the next press deletes.
    @Published var armedPost: String?
    var task: Task<Void, Never>?
    var olderTask: Task<Void, Never>?
    var back: AppModel.ProfileReturn?

    // Comments
    /// The open post's comments; nil when the sheet is closed.
    @Published var thread: TogetherCommentThread?
    @Published var commentsFailed = false
    /// 0 the composer, then the comments' lines from 1.
    @Published var line = 0
    /// In the composer: the quick comments, then the field (the last).
    @Published var composer = 0
    @Published var commentDraft = ""
    @Published var commentTyping = false
    @Published var replyTo: TogetherComment?
    /// A comment's delete pressed once.
    @Published var armedComment: String?
    @Published var sending = false
    var commentsTask: Task<Void, Never>?
    var olderCommentsTask: Task<Void, Never>?

    /// Whose feed this is: another account signed in starts it again.
    private var viewer: String?
    private var forward: AnyCancellable?

    init(owner: AppModel) {
        forward = objectWillChange.sink { [weak owner] _ in owner?.objectWillChange.send() }
    }

    func follow(_ user: String?) {
        guard user != viewer else { return }
        viewer = user
        task?.cancel()
        olderTask?.cancel()
        commentsTask?.cancel()
        feed = TogetherCaptures()
        failed = false
        thread = nil
    }
}

extension AppModel {
    // MARK: Writing a post from the gallery

    /// The sheet over the gallery for the focused screenshot or clip: caption, who sees it, Post.
    func openPostDraft() {
        guard galleryShots.indices.contains(galleryIndex), familyPermits(.mediaSharing) else { return }
        let shot = galleryShots[galleryIndex]
        withAnimation(Motion.overlay) { cloud.sharing = false }
        captures.uploaded = nil
        captures.draftFile = shot
        captures.draftRow = .caption
        captures.draftTyping = false
        captures.stage = .idle
        captures.clipCheck = nil
        captures.clipMs = nil
        withAnimation(Motion.overlay) { captures.draft = TogetherPostDraft(titleId: selectedGame?.titleID ?? AppModel.titleId(of: shot)) }
        Sounds.shared.play(.select)
        if Screenshots.isClip(shot) { checkClip(shot) }
    }

    /// The title ID a capture's file name starts with (PPSA01234-20261025-211502.png).
    static func titleId(of shot: URL) -> String? {
        let first = shot.deletingPathExtension().lastPathComponent.split(separator: "-").first.map(String.init)
        return first.flatMap { TogetherPostDraft.isTitleId($0) ? $0 : nil }
    }

    /// Reads the clip's length and size, so a clip a post cannot take is said before it goes up.
    func checkClip(_ file: URL) {
        let maxBytes = cloud.info?.media.clip ?? TogetherPostLimits.clipBytes
        Task {
            let duration = try? await AVURLAsset(url: file).load(.duration)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            let ms = duration.map { $0.seconds.isFinite ? Int(($0.seconds * 1000).rounded()) : 0 }
            guard captures.draftFile == file else { return }
            withAnimation(Motion.focus) {
                captures.clipMs = ms
                captures.clipCheck = TogetherClipCheck.check(durationMs: ms, bytes: bytes, maxBytes: maxBytes)
            }
        }
    }

    func closePostDraft() {
        guard captures.stage == .idle else { return }
        withAnimation(Motion.overlay) {
            captures.draft = nil
            captures.draftTyping = false
        }
        captures.draftFile = nil
        captures.uploaded = nil
        Sounds.shared.play(.back)
    }

    /// Up and down through caption, who sees it and Post; ✕ types, switches or posts; left and
    /// right pick Friends or Public; ○ leaves the field, then the sheet.
    func postDraftCommand(_ command: Command) {
        guard captures.draft != nil else { return }
        if captures.draftTyping {
            switch command {
            case .back: captures.draftTyping = false
            case .select, .down:
                captures.draftTyping = false
                captures.draftRow = .visibility
                Sounds.shared.play(.move)
            default: break
            }
            return
        }
        switch command {
        case .up, .down:
            let next = captures.draftRow.rawValue + (command == .down ? 1 : -1)
            guard let row = CapturesState.DraftRow(rawValue: next) else { return }
            withAnimation(Motion.focus) { captures.draftRow = row }
            Sounds.shared.play(.move)
        case .left, .right:
            guard captures.draftRow == .visibility else { return }
            setDraftVisibility(command == .right ? .public : .friends)
        case .select:
            switch captures.draftRow {
            case .caption:
                captures.draftTyping = true
                Sounds.shared.play(.select)
            case .visibility:
                setDraftVisibility(captures.draft?.visibility == .public ? .friends : .public)
            case .post:
                postCapture()
            }
        case .back, .options:
            closePostDraft()
        default:
            break
        }
    }

    func setDraftVisibility(_ visibility: TogetherPostVisibility) {
        guard captures.draft?.visibility != visibility else { return }
        withAnimation(Motion.focus) { captures.draft?.visibility = visibility }
        Sounds.shared.play(.move)
    }

    var canPostDraft: Bool {
        captures.draft != nil && captures.stage == .idle && captures.clipCheck?.blocks != true
    }

    /// Uploads the capture (once), makes the post, and puts it at the top of Captures.
    func postCapture() {
        guard let draft = captures.draft, let file = captures.draftFile, captures.stage == .idle else { return }
        if captures.clipCheck?.blocks == true {
            Sounds.shared.play(.back)
            return show(clipTooLongText, symbol: "film.stack")
        }
        guard familyPermits(.mediaSharing) else { return }
        Sounds.shared.play(.select)
        withAnimation(Motion.focus) { captures.stage = .uploading }
        Task {
            do {
                let media: String
                if let uploaded = captures.uploaded, uploaded.file == file {
                    media = uploaded.media
                } else {
                    media = try await uploadShot(file).id
                    captures.uploaded = (file, media)
                }
                withAnimation(Motion.focus) { captures.stage = .posting }
                let post = try await together.createPost(media: [media], draft: draft)
                withAnimation(Motion.overlay) {
                    if captures.feed.loaded { captures.feed.upsert(post) }
                    captures.stage = .idle
                    captures.draft = nil
                    captures.draftTyping = false
                }
                captures.draftFile = nil
                captures.uploaded = nil
                Sounds.shared.play(.select)
                show(TCap.text(.posted), symbol: "photo.badge.checkmark.fill")
            } catch {
                withAnimation(Motion.focus) { captures.stage = .idle }
                if case .family(.profileVisibility)? = TogetherPostRefusal(error) { captures.draft?.visibility = .friends }
                show(postMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    var clipTooLongText: String {
        TCap.format(.clipTooLong, VoiceNoteView.clock(Double(captures.clipMs ?? 0) / 1000))
    }

    /// A refusal about a post or a comment, in words.
    func postMessage(_ error: Error) -> String {
        switch TogetherPostRefusal(error) {
        case .commentsOff: return TCap.text(.refusedCommentsOff)
        case .linkBlocked: return TCap.text(.refusedLink)
        case .accountMuted: return TCap.text(.refusedMuted)
        case .family(.profileVisibility): return TCap.text(.refusedFamilyFriends)
        case .family: return familyMessage(error) ?? FS.refusal(.mediaSharing)
        case .rateLimited: return TCap.text(.refusedRateLimited)
        case .storageDisabled:
            cloud.info = .disabled
            return TCap.text(.refusedStorage)
        case .clipTooLong: return TCap.text(.clipTooLongDetail)
        case .badMedia: return TCap.text(.refusedBadMedia)
        case .gone: return TCap.text(.refusedGone)
        case .quotaFull, .tooBig, nil: return cloudMessage(error)
        }
    }

    func previewPostDraft(caption: String = "", visibility: TogetherPostVisibility = .friends, row: CapturesState.DraftRow = .caption,
                          clipMs: Int? = nil, check: TogetherClipCheck? = nil, stage: CapturesState.Stage = .idle) {
        captures.draft = TogetherPostDraft(caption: caption, visibility: visibility, titleId: selectedGame?.titleID)
        captures.draftFile = galleryShots.indices.contains(galleryIndex) ? galleryShots[galleryIndex] : nil
        captures.draftRow = row
        captures.clipMs = clipMs
        captures.clipCheck = check
        captures.stage = stage
    }
}

/// Over the gallery: the capture, its caption, Friends or Public, and Post.
struct PostComposer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @FocusState private var editing: Bool

    var body: some View {
        let state = model.captures
        let draft = state.draft ?? TogetherPostDraft()
        VStack(alignment: .leading, spacing: 18 * scale) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(TCap.text(.postTitle)).font(.display(28 * scale, .light)).foregroundStyle(.white)
                Text(model.selectedGame.map { $0.name + " · " + TCap.text(.postSubtitle) } ?? TCap.text(.postSubtitle))
                    .font(.display(14 * scale)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
            }
            if let file = state.draftFile { preview(file) }
            if let check = state.clipCheck, check != .fits { clipNotice(check) }
            captionField(draft)
            visibilityPicker(draft)
            postButton
            Spacer(minLength: 0)
            HStack(spacing: 18 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                Hint(keys: "↩ / ✕", label: state.draftRow == .caption ? TCap.text(.hintType) : T.text(.hintSelect))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
        .padding(30 * scale)
        .frame(width: 520 * scale)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .panelFrost(classic: 0.94)
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
    }

    /// The capture as it will go, in viewfinder corners: a clip with its length.
    private func preview(_ file: URL) -> some View {
        Color.clear
            .frame(height: 250 * scale)
            .overlay { Thumbnail(url: file, focused: false, accent: model.accent) }
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if Screenshots.isClip(file), let ms = model.captures.clipMs {
                    Text(VoiceNoteView.clock(Double(ms) / 1000)).font(.display(12 * scale, .semibold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 8 * scale).padding(.vertical, 4 * scale)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(8 * scale)
                }
            }
            .padding(10 * scale)
            .overlay(CaptureCorners(color: .white.opacity(0.7), length: 18 * scale, width: 2 * scale))
    }

    private func clipNotice(_ check: TogetherClipCheck) -> some View {
        let blocking = check.blocks
        let title: String
        var detail: String?
        switch check {
        case .tooLong:
            title = model.clipTooLongText
            detail = TCap.text(.clipTooLongDetail)
        case .tooBig(let bytes):
            title = TCap.format(.clipTooBig, TCloud.size(bytes), TCloud.size(model.cloud.info?.media.clip ?? TogetherPostLimits.clipBytes))
        case .fits:
            title = ""
        }
        let tint = blocking ? Color(red: 1, green: 0.62, blue: 0.5) : Color.white.opacity(0.75)
        return HStack(alignment: .top, spacing: 12 * scale) {
            Image(systemName: blocking ? "film.stack" : "arrow.down.right.and.arrow.up.left").font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(title).font(.display(15 * scale, .semibold)).foregroundStyle(blocking ? tint : .white.opacity(0.9))
                if let detail { Text(detail).font(.display(13 * scale)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(14 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(tint.opacity(blocking ? 0.12 : 0.06)))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.display(12 * scale, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(.white.opacity(0.5))
    }

    private func captionField(_ draft: TogetherPostDraft) -> some View {
        let focused = model.captures.draftRow == .caption
        let typing = model.captures.draftTyping
        return VStack(alignment: .leading, spacing: 8 * scale) {
            HStack {
                label(TCap.text(.caption))
                Spacer()
                if !draft.caption.isEmpty {
                    Text(TCap.format(.captionCount, draft.caption.count, TogetherPostLimits.caption)).font(.display(12 * scale, .medium)).monospacedDigit()
                        .foregroundStyle(draft.caption.count > TogetherPostLimits.caption ? Color(red: 1, green: 0.6, blue: 0.5) : .white.opacity(0.45))
                }
            }
            HStack(alignment: .top, spacing: 12 * scale) {
                Image(systemName: "text.bubble").font(.system(size: 15 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.55)).padding(.top, 2 * scale)
                if previewRender {
                    Text(draft.caption.isEmpty ? TCap.text(.captionPlaceholder) : draft.caption).font(.display(16 * scale))
                        .foregroundStyle(.white.opacity(draft.caption.isEmpty ? 0.4 : 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(TCap.text(.captionPlaceholder), text: Binding(get: { model.captures.draft?.caption ?? "" }, set: { model.captures.draft?.caption = String($0.prefix(TogetherPostLimits.caption)) }), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.display(16 * scale))
                        .foregroundStyle(.white)
                        .lineLimit(1...4)
                        .focused($editing)
                        .onSubmit {
                            model.captures.draftTyping = false
                            model.captures.draftRow = .post
                        }
                        .onExitCommand { model.captures.draftTyping = false }
                }
            }
            .padding(.horizontal, 16 * scale)
            .padding(.vertical, 14 * scale)
            .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(focused || typing ? 0.12 : 0.06)))
            .focusRing(focused && !typing, radius: 14 * scale, width: 2)
            .contentShape(Rectangle())
            .onTapGesture {
                model.captures.draftRow = .caption
                model.captures.draftTyping = true
            }
        }
        .onChange(of: model.captures.draftTyping) { _, on in editing = on }
        .onChange(of: editing) { _, on in if model.captures.draftTyping != on { model.captures.draftTyping = on } }
        .animation(Motion.focus, value: focused)
    }

    private func visibilityPicker(_ draft: TogetherPostDraft) -> some View {
        let focused = model.captures.draftRow == .visibility
        return VStack(alignment: .leading, spacing: 8 * scale) {
            label(TCap.text(.visibility))
            HStack(spacing: 8 * scale) {
                option(.friends, symbol: "person.2.fill", title: TCap.text(.visibilityFriends), chosen: draft.visibility == .friends, focused: focused)
                option(.public, symbol: "globe", title: TCap.text(.visibilityPublic), chosen: draft.visibility == .public, focused: focused)
            }
            .padding(5 * scale)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .focusRing(focused, radius: 30 * scale, width: 2)
            Text(TCap.text(draft.visibility == .public ? .visibilityPublicDetail : .visibilityFriendsDetail))
                .font(.display(13 * scale)).foregroundStyle(.white.opacity(0.55))
                .contentTransition(.opacity)
        }
        .animation(Motion.focus, value: focused)
        .animation(Motion.focus, value: draft.visibility)
    }

    private func option(_ visibility: TogetherPostVisibility, symbol: String, title: String, chosen: Bool, focused: Bool) -> some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: symbol).font(.system(size: 14 * scale, weight: .semibold))
            Text(title).font(.display(15 * scale, .semibold))
        }
        .foregroundStyle(chosen ? Color.black : .white.opacity(0.8))
        .frame(maxWidth: .infinity)
        .frame(height: 42 * scale)
        .background(FocusFill(Capsule(), focused: chosen, idle: .clear))
        .contentShape(Capsule())
        .onTapGesture {
            model.captures.draftRow = .visibility
            model.setDraftVisibility(visibility)
        }
    }

    private var postButton: some View {
        let state = model.captures
        let focused = state.draftRow == .post
        let busy = state.stage != .idle
        let title = state.stage == .uploading ? TCap.text(.uploading) : state.stage == .posting ? TCap.text(.posting) : TCap.text(.post)
        return VStack(alignment: .leading, spacing: 10 * scale) {
            ConsoleButton(title: title, symbol: busy ? "arrow.up.circle" : "paperplane.fill", focused: focused && model.canPostDraft, prominent: true, minWidth: 460) {
                model.captures.draftRow = .post
                model.postCapture()
            }
            .opacity(model.canPostDraft || busy ? 1 : 0.45)
            .overlay(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).strokeBorder(Color.white.opacity(focused && !model.canPostDraft && !busy ? 0.6 : 0), lineWidth: 2))
            if busy { IndeterminateLine(color: model.accent).frame(maxWidth: .infinity) }
        }
        .padding(.top, 4 * scale)
    }
}

/// A camera's framing marks at the corners of whatever it is drawn over.
struct CaptureCorners: View {
    var color: Color
    var length: CGFloat
    var width: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let l = min(length, size.width / 3, size.height / 3)
            let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, 0, 1, 1), (size.width, 0, -1, 1), (0, size.height, 1, -1), (size.width, size.height, -1, -1)]
            for (x, y, dx, dy) in corners {
                path.move(to: CGPoint(x: x + dx * l, y: y))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + dy * l))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}
