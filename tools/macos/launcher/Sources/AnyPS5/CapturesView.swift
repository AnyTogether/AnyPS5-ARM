import AnyPS5Core
import AppKit
import SwiftUI

/// Captures on AnyTogether: the screenshots and clips the user, friends and players they met
/// posted, newest first and read a page at a time as the focus goes down; likes at once, and a
/// post's comments in a sheet with one level of replies.
extension AppModel {
    /// What can be done on a focused post, left to right.
    enum CaptureAction: Equatable { case like, comments, view, delete }

    /// How close to the end of the list the next, older page is read.
    static let capturesPrefetch = 3

    func captureActions(_ post: TogetherPost) -> [CaptureAction] {
        [.like, .comments, .view] + (post.mine ? [.delete] : [])
    }

    var focusedCapture: TogetherPost? {
        captures.feed.items.indices.contains(captures.index) ? captures.feed.items[captures.index] : nil
    }

    // MARK: The feed

    func openCaptures() {
        guard togetherUser != nil else { return }
        captures.follow(togetherUser?.id)
        if let overlay, overlay != .captures, overlay != .profile {
            captures.back = ProfileReturn(overlay: overlay, category: panelCategory, row: panelRow, inRows: panelInRows)
        }
        captures.index = 0
        captures.action = 0
        captures.armedPost = nil
        captures.thread = nil
        withAnimation(Motion.overlay) { overlay = .captures }
        Sounds.shared.play(.select)
        loadCaptures()
    }

    func loadCaptures() {
        captures.task?.cancel()
        captures.olderTask?.cancel()
        captures.olderTask = nil
        captures.task = Task {
            do {
                let page = try await together.captures()
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) {
                    captures.feed.load(page)
                    captures.failed = false
                    captures.index = min(captures.index, max(0, captures.feed.items.count - 1))
                }
            } catch {
                guard !Task.isCancelled else { return }
                if case .storageDisabled? = TogetherPostRefusal(error) { cloud.info = .disabled }
                withAnimation(Motion.overlay) { captures.failed = !captures.feed.loaded }
            }
        }
    }

    /// The next, older page, once the focus nears the end.
    func loadOlderCaptures() {
        guard let before = captures.feed.next, captures.olderTask == nil else { return }
        captures.olderTask = Task {
            defer { captures.olderTask = nil }
            guard let page = try? await together.captures(before: before), !Task.isCancelled else { return }
            withAnimation(Motion.overlay) { captures.feed.loadOlder(page) }
        }
    }

    func closeCaptures() {
        captures.task?.cancel()
        guard let back = captures.back else { return closeOverlay() }
        captures.back = nil
        withAnimation(Motion.overlay) {
            overlay = back.overlay
            panelCategory = back.category
            panelRow = back.row
            panelInRows = back.inRows
        }
        Sounds.shared.play(.back)
    }

    /// Up and down through the posts, left and right through Like, Comments, View (and Delete on
    /// one's own), ✕ does it, △ opens the author's profile.
    func capturesCommand(_ command: Command) {
        if cloud.viewing != nil {
            if command == .back || command == .select || command == .options { closeViewer() }
            return
        }
        if captures.thread != nil { return commentsCommand(command) }
        let items = captures.feed.items
        switch command {
        case .up, .down:
            let next = min(items.count - 1, max(0, captures.index + (command == .down ? 1 : -1)))
            guard !items.isEmpty, next != captures.index else { return }
            withAnimation(Motion.focus) {
                captures.index = next
                captures.action = 0
                captures.armedPost = nil
            }
            if next >= items.count - Self.capturesPrefetch { loadOlderCaptures() }
            Sounds.shared.play(.move)
        case .left, .right:
            guard let post = focusedCapture else { return }
            let count = captureActions(post).count
            let next = min(count - 1, max(0, captures.action + (command == .right ? 1 : -1)))
            guard next != captures.action else { return }
            withAnimation(Motion.focus) {
                captures.action = next
                captures.armedPost = nil
            }
            Sounds.shared.play(.move)
        case .select:
            guard let post = focusedCapture else { return }
            let actions = captureActions(post)
            guard actions.indices.contains(captures.action) else { return }
            run(actions[captures.action], on: post)
        case .options:
            guard let post = focusedCapture else { return }
            openProfile(post.author.handle, card: post.author)
        case .back:
            if captures.armedPost != nil {
                withAnimation(Motion.focus) { captures.armedPost = nil }
                Sounds.shared.play(.back)
            } else {
                closeCaptures()
            }
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    func run(_ action: CaptureAction, on post: TogetherPost) {
        switch action {
        case .like: toggleLike(post)
        case .comments: openComments(post)
        case .view: viewCapture(post)
        case .delete:
            if captures.armedPost == post.id {
                deleteCapture(post)
            } else {
                withAnimation(Motion.focus) { captures.armedPost = post.id }
                Sounds.shared.play(.move)
            }
        }
    }

    /// The like shows at once, then what the server says; a failure puts the old count back.
    func toggleLike(_ post: TogetherPost) {
        var before: TogetherLikes?
        withAnimation(Motion.focus) { before = captures.feed.toggleLike(post.id) }
        guard let before else { return }
        Sounds.shared.play(.select)
        Task {
            do {
                let now = try await together.setLiked(!before.liked, post: post.id)
                withAnimation(Motion.focus) { captures.feed.setLikes(now, for: post.id) }
            } catch {
                withAnimation(Motion.focus) { captures.feed.setLikes(before, for: post.id) }
                if case .gone? = TogetherPostRefusal(error) { withAnimation(Motion.overlay) { captures.feed.remove(post.id) } }
                show(postMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// A picture or the clip over the whole screen (a clip plays).
    func viewCapture(_ post: TogetherPost) {
        guard let media = post.clip ?? post.shown.first else { return }
        view(media)
    }

    func deleteCapture(_ post: TogetherPost) {
        Task {
            do {
                try await together.deletePost(post.id)
                withAnimation(Motion.overlay) {
                    captures.feed.remove(post.id)
                    captures.armedPost = nil
                    captures.action = 0
                    captures.index = min(captures.index, max(0, captures.feed.items.count - 1))
                }
                show(TCap.text(.deleted), symbol: "trash")
            } catch {
                show(postMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Comments

    func openComments(_ post: TogetherPost) {
        captures.commentsTask?.cancel()
        captures.olderCommentsTask?.cancel()
        captures.olderCommentsTask = nil
        captures.commentsFailed = false
        captures.line = 0
        captures.composer = TCap.quickComments.count
        captures.commentDraft = ""
        captures.commentTyping = false
        captures.replyTo = nil
        captures.armedComment = nil
        withAnimation(Motion.overlay) { captures.thread = TogetherCommentThread(postId: post.id) }
        Sounds.shared.play(.select)
        captures.commentsTask = Task {
            do {
                let page = try await together.comments(on: post.id)
                guard !Task.isCancelled, captures.thread?.postId == post.id else { return }
                withAnimation(Motion.overlay) { captures.thread?.load(page) }
                // The count on the card follows what is there now.
                let seen = captures.thread?.lines.count ?? 0
                if page.next == nil, let shown = captures.feed.items.first(where: { $0.id == post.id })?.comments, shown != seen {
                    captures.feed.addComments(seen - shown, to: post.id)
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(Motion.overlay) { captures.commentsFailed = true }
            }
        }
    }

    func loadOlderComments() {
        guard let thread = captures.thread, let before = thread.next, captures.olderCommentsTask == nil else { return }
        captures.olderCommentsTask = Task {
            defer { captures.olderCommentsTask = nil }
            guard let page = try? await together.comments(on: thread.postId, before: before), !Task.isCancelled, captures.thread?.postId == thread.postId else { return }
            withAnimation(Motion.overlay) { captures.thread?.loadOlder(page) }
        }
    }

    func closeComments() {
        captures.commentsTask?.cancel()
        withAnimation(Motion.overlay) {
            captures.thread = nil
            captures.commentTyping = false
        }
        Sounds.shared.play(.back)
    }

    /// The post the open comments are on.
    var commentsPost: TogetherPost? {
        guard let id = captures.thread?.postId else { return nil }
        return captures.feed.items.first { $0.id == id }
    }

    /// Row 0 is the composer (left and right through the quick comments and the field); below
    /// it the comments: ✕ replies, △ deletes one's own (pressed twice), ○ steps back.
    func commentsCommand(_ command: Command) {
        guard let thread = captures.thread else { return }
        if captures.commentTyping {
            if command == .back { captures.commentTyping = false }
            return
        }
        let lines = thread.lines
        let open = commentsPost?.commentsOff != true
        switch command {
        case .up, .down:
            let first = open ? 0 : 1
            let next = min(lines.count, max(first, captures.line + (command == .down ? 1 : -1)))
            guard next != captures.line, next == 0 || lines.indices.contains(next - 1) else { return }
            withAnimation(Motion.focus) {
                captures.line = next
                captures.armedComment = nil
            }
            if next >= lines.count - Self.capturesPrefetch { loadOlderComments() }
            Sounds.shared.play(.move)
        case .left, .right:
            guard captures.line == 0, open else { return }
            let next = min(TCap.quickComments.count, max(0, captures.composer + (command == .right ? 1 : -1)))
            guard next != captures.composer else { return }
            withAnimation(Motion.focus) { captures.composer = next }
            Sounds.shared.play(.move)
        case .select:
            if captures.line == 0 {
                guard open else { return }
                if captures.composer < TCap.quickComments.count {
                    sendComment(TCap.quickComments[captures.composer])
                } else {
                    captures.commentTyping = true
                    Sounds.shared.play(.select)
                }
            } else if lines.indices.contains(captures.line - 1), open {
                // Replies are one level: answering a reply answers the comment it is under.
                let line = lines[captures.line - 1]
                let top = line.parent.flatMap { thread.comment($0) } ?? line.comment
                withAnimation(Motion.focus) {
                    captures.replyTo = top
                    captures.line = 0
                    captures.composer = TCap.quickComments.count
                }
                captures.commentTyping = true
                Sounds.shared.play(.select)
            }
        case .options:
            guard captures.line > 0, lines.indices.contains(captures.line - 1) else { return }
            let comment = lines[captures.line - 1].comment
            guard comment.canDelete else { return }
            if captures.armedComment == comment.id {
                deleteComment(comment)
            } else {
                withAnimation(Motion.focus) { captures.armedComment = comment.id }
                Sounds.shared.play(.move)
            }
        case .back:
            if captures.armedComment != nil {
                withAnimation(Motion.focus) { captures.armedComment = nil }
                Sounds.shared.play(.back)
            } else if captures.replyTo != nil {
                withAnimation(Motion.focus) { captures.replyTo = nil }
                Sounds.shared.play(.back)
            } else {
                closeComments()
            }
        case .previousGame, .nextGame, .home, .capture:
            break
        }
    }

    func sendComment(_ text: String) {
        guard let thread = captures.thread, !captures.sending else { return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let replyTo = captures.replyTo?.id
        captures.sending = true
        Task {
            defer { captures.sending = false }
            do {
                let comment = try await together.comment(on: thread.postId, text: words, replyTo: replyTo)
                guard captures.thread?.postId == thread.postId else { return }
                withAnimation(Motion.overlay) {
                    captures.thread?.add(comment)
                    captures.feed.addComments(1, to: thread.postId)
                    captures.commentDraft = ""
                    captures.replyTo = nil
                    captures.commentTyping = false
                }
                Sounds.shared.play(.select)
                show(TCap.text(.commentSent), symbol: "text.bubble.fill")
            } catch {
                show(postMessage(error), symbol: "exclamationmark.bubble.fill")
            }
        }
    }

    func deleteComment(_ comment: TogetherComment) {
        guard let postId = captures.thread?.postId else { return }
        Task {
            do {
                try await together.deleteComment(comment.id, on: postId)
                withAnimation(Motion.overlay) {
                    let gone = captures.thread?.remove(comment.id) ?? 0
                    captures.feed.addComments(-gone, to: postId)
                    captures.armedComment = nil
                    captures.line = min(captures.line, captures.thread?.lines.count ?? 0)
                }
                show(TCap.text(.commentDeleted), symbol: "trash")
            } catch {
                show(postMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Previews

    func previewCaptures(_ posts: [TogetherPost], index: Int = 0, action: Int = 0, next: String? = nil, armed: String? = nil) {
        captures.feed.load(TogetherPostPage(items: posts, next: next))
        captures.index = index
        captures.action = action
        captures.armedPost = armed
        overlay = .captures
    }

    func previewComments(_ page: TogetherCommentPage, line: Int = 0, composer: Int? = nil, replyTo: TogetherComment? = nil, draft: String = "", armed: String? = nil) {
        guard let post = focusedCapture else { return }
        var thread = TogetherCommentThread(postId: post.id)
        thread.load(page)
        captures.thread = thread
        captures.line = line
        captures.composer = composer ?? TCap.quickComments.count
        captures.replyTo = replyTo
        captures.commentDraft = draft
        captures.armedComment = armed
    }
}

// MARK: The screen

struct CapturesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let state = model.captures
        ZStack {
            VStack(alignment: .leading, spacing: 30 * scale) {
                header
                if state.feed.loaded && !state.feed.items.isEmpty {
                    ProfileColumn(title: "", count: nil, focusedIndex: state.index, ids: state.feed.items.map(\.id)) {
                        ForEach(Array(state.feed.items.enumerated()), id: \.element.id) { index, post in
                            let focused = state.index == index && state.thread == nil
                            PostCard(post: post, focused: focused, action: focused ? state.action : nil, armed: state.armedPost == post.id)
                                .id(post.id)
                                .onTapGesture { model.captures.index = index }
                        }
                        if state.feed.next != nil {
                            Text(TCap.text(.more)).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.4)).padding(.vertical, 12 * scale)
                        }
                    }
                } else {
                    VStack(spacing: 18 * scale) {
                        if state.feed.loaded {
                            ProfileNotice(symbol: "photo.on.rectangle.angled", text: TCap.text(.empty)).frame(maxWidth: 820 * scale)
                        } else if state.failed {
                            ProfileNotice(symbol: model.cloud.info?.enabled == false ? "icloud.slash" : "wifi.exclamationmark",
                                          text: TCap.text(model.cloud.info?.enabled == false ? .refusedStorage : .failed)).frame(maxWidth: 620 * scale)
                        } else {
                            IndeterminateLine(color: model.accent).frame(width: 260 * scale)
                            Text(TCap.text(.loading)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: 1180 * scale)
            .padding(.horizontal, 80 * scale)
            .padding(.vertical, 56 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if state.thread != nil {
                HStack(spacing: 0) {
                    Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.closeComments() }
                    CommentsSheet()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let media = model.cloud.viewing { MediaViewer(media: media).transition(.opacity) }
        }
        .screenFrost(0.74)
        .environment(\.locale, T.locale)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24 * scale) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28 * scale, weight: .semibold))
                .foregroundStyle(model.accent)
                .frame(width: 72 * scale, height: 72 * scale)
                .background(Circle().fill(model.accent.opacity(0.16)))
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text(TCap.text(.title)).font(.display(40 * scale, .light)).foregroundStyle(.white)
                Text(TCap.text(.subtitle)).font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 22 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                Hint(keys: "← → ↩ / ✕", label: TCap.text(.hintAction))
                Hint(keys: "O / △", label: TCap.text(.hintAuthor))
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
    }
}

/// One post: the capture on the left in viewfinder corners when focused, who posted it from
/// which game, the caption, and Like, Comments, View (Delete on one's own).
struct PostCard: View {
    let post: TogetherPost
    let focused: Bool
    /// The focused action, on the focused post.
    let action: Int?
    var armed = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 26 * scale) {
            media
                .padding(8 * scale)
                .overlay(CaptureCorners(color: .white.opacity(focused ? 0.85 : 0), length: 22 * scale, width: 2.5 * scale))
            VStack(alignment: .leading, spacing: 14 * scale) {
                byline
                if let game = post.game { gameChip(game) }
                if let caption = post.caption, !caption.isEmpty {
                    Text(caption).font(.display(18 * scale)).foregroundStyle(.white.opacity(0.9)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14 * scale)
        .background(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.12 : 0.05)))
        .focusRing(focused, radius: 22 * scale, width: 2)
        .animation(Motion.focus, value: focused)
    }

    // MARK: Media

    @ViewBuilder private var media: some View {
        let shown = post.shown
        Group {
            if let clip = post.clip {
                still(clip)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22 * scale, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58 * scale, height: 58 * scale)
                            .background(Circle().fill(.black.opacity(0.45)).background(Circle().fill(.ultraThinMaterial)))
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let ms = clip.durationMs {
                            Text(VoiceNoteView.clock(Double(ms) / 1000)).font(.display(13 * scale, .semibold)).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, 9 * scale).padding(.vertical, 4 * scale)
                                .background(Capsule().fill(.black.opacity(0.55)))
                                .padding(12 * scale)
                        }
                    }
            } else if shown.count == 1 {
                still(shown[0])
            } else if shown.count == 2 {
                HStack(spacing: 4 * scale) { ForEach(shown) { still($0) } }
            } else if shown.count > 2 {
                Grid(horizontalSpacing: 4 * scale, verticalSpacing: 4 * scale) {
                    GridRow { still(shown[0]); still(shown[1]) }
                    GridRow {
                        still(shown[2])
                        if shown.count > 3 { still(shown[3]) } else { Color.white.opacity(0.04) }
                    }
                }
            } else {
                ZStack {
                    Color.white.opacity(0.05)
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 26 * scale)).foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(width: 480 * scale, height: 270 * scale)
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.viewCapture(post) }
    }

    private func still(_ media: TogetherMedia) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { RemoteImage(url: media.still) }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { model.view(media) }
    }

    // MARK: Words

    private var byline: some View {
        HStack(spacing: 12 * scale) {
            ProfileAvatar(url: post.author.privateAvatar ?? post.author.avatar, name: post.author.displayName, size: 40 * scale, glow: false)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(post.author.privateName ?? post.author.displayName).font(.display(18 * scale, .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6 * scale) {
                    Text(ProfileView.relative(post.createdAt))
                    Text("·")
                    Image(systemName: post.visibility == .public ? "globe" : "person.2.fill").font(.system(size: 11 * scale, weight: .semibold))
                    Text(TCap.text(post.visibility == .public ? .everyone : .friendsOnly))
                }
                .font(.display(13 * scale, .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            }
        }
    }

    private func gameChip(_ game: TogetherActivity.Game) -> some View {
        HStack(spacing: 8 * scale) {
            Group {
                if let icon = model.localIcon(game.titleId) {
                    ArtworkImage(url: icon, maxPixels: 120)
                } else if let remote = game.iconUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: remote) { image in image.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.08) }
                } else {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 11 * scale)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 24 * scale, height: 24 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
            Text(model.gameName(game)).font(.display(14 * scale, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .padding(.leading, 4 * scale)
        .padding(.trailing, 12 * scale)
        .padding(.vertical, 4 * scale)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 10 * scale) {
            ForEach(Array(model.captureActions(post).enumerated()), id: \.offset) { index, kind in
                pill(kind, focused: action == index)
                    .onTapGesture {
                        if let row = model.captures.feed.index(of: post.id) { model.captures.index = row }
                        model.captures.action = index
                        model.run(kind, on: post)
                    }
            }
        }
    }

    private func pill(_ kind: AppModel.CaptureAction, focused: Bool) -> some View {
        let symbol: String
        let title: String
        var tint: Color = .white
        switch kind {
        case .like:
            symbol = post.liked ? "heart.fill" : "heart"
            title = post.likes > 0 ? "\(post.likes)" : TCap.text(.like)
            if post.liked { tint = Color(red: 1, green: 0.42, blue: 0.5) }
        case .comments:
            symbol = post.commentsOff ? "bubble.left.and.exclamationmark.bubble.right" : "bubble.left.and.bubble.right"
            title = post.commentsOff && post.comments == 0 ? TCap.text(.commentsOff) : post.comments > 0 ? "\(post.comments)" : TCap.text(.comments)
        case .view:
            symbol = post.clip != nil ? "play.rectangle" : "arrow.up.left.and.arrow.down.right"
            title = TCap.text(.view)
        case .delete:
            symbol = "trash"
            title = armed ? TCap.text(.deleteAgain) : TCap.text(.delete)
            tint = Color(red: 1, green: 0.55, blue: 0.5)
        }
        return HStack(spacing: 7 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(focused ? (kind == .like && post.liked ? tint : .black) : tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.4), value: kind == .like && post.liked && !Motion.reduced)
            Text(title).font(.display(15 * scale, .semibold)).monospacedDigit()
                .foregroundStyle(focused ? Color.black : .white.opacity(0.85))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16 * scale)
        .frame(height: 40 * scale)
        .background(FocusFill(Capsule(), focused: focused, idle: kind == .like && post.liked ? tint.opacity(0.18) : Color.white.opacity(0.08)))
        .scaleEffect(focused ? 1.05 : 1)
        .animation(Motion.focus, value: focused)
        .animation(Motion.focus, value: post.likes)
        .contentShape(Capsule())
    }
}

// MARK: Comments

/// A post's comments at the side: the composer (quick comments and a field) on top, then the
/// comments newest first with their replies under them.
struct CommentsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        let state = model.captures
        let thread = state.thread
        let lines = thread?.lines ?? []
        let post = model.commentsPost
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                Text(TCap.text(.commentsTitle)).font(.display(28 * scale, .light)).foregroundStyle(.white)
                if let post, post.comments > 0 {
                    Text("\(post.comments)").font(.display(17 * scale, .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                }
            }
            if let post { postLine(post) }
            if post?.commentsOff == true {
                ProfileNotice(symbol: "bubble.left.and.exclamationmark.bubble.right", text: TCap.text(.refusedCommentsOff))
            } else {
                CommentComposer(focused: state.line == 0)
            }
            if let thread, thread.loaded {
                if lines.isEmpty {
                    Text(TCap.text(.commentsEmpty)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.5)).padding(.top, 8 * scale)
                    Spacer(minLength: 0)
                } else {
                    ProfileColumn(title: "", count: nil, focusedIndex: state.line > 0 ? state.line - 1 : nil, ids: lines.map(\.id)) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            CommentRow(line: line, focused: state.line == index + 1, armed: state.armedComment == line.id)
                                .id(line.id)
                                .onTapGesture { model.captures.line = index + 1 }
                        }
                    }
                }
            } else if state.commentsFailed {
                ProfileNotice(symbol: "wifi.exclamationmark", text: TCap.text(.commentsFailed))
                Spacer(minLength: 0)
            } else {
                IndeterminateLine(color: model.accent).frame(width: 200 * scale).padding(.top, 10 * scale)
                Spacer(minLength: 0)
            }
            HStack(spacing: 16 * scale) {
                Hint(keys: "↑ ↓", label: T.text(.hintMove))
                Hint(keys: "↩ / ✕", label: state.line == 0 ? T.text(.hintSelect) : TCap.text(.hintReply))
                if state.line > 0, lines.indices.contains(state.line - 1), lines[state.line - 1].comment.canDelete {
                    Hint(keys: "O / △", label: TCap.text(.hintDelete))
                }
                Hint(keys: "esc / ○", label: T.text(.hintBack))
            }
        }
        .padding(30 * scale)
        .frame(width: 600 * scale)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .panelFrost(classic: 0.94)
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
    }

    /// The post the comments are on, small: its still and caption.
    private func postLine(_ post: TogetherPost) -> some View {
        HStack(spacing: 12 * scale) {
            RemoteImage(url: (post.clip ?? post.shown.first)?.still)
                .frame(width: 96 * scale, height: 54 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(post.author.privateName ?? post.author.displayName).font(.display(14 * scale, .semibold)).foregroundStyle(.white)
                if let caption = post.caption, !caption.isEmpty {
                    Text(caption).font(.display(13 * scale)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The quick comments a controller sends with one press, the field to type in, and who a reply
/// answers.
struct CommentComposer: View {
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @FocusState private var editing: Bool

    var body: some View {
        let state = model.captures
        let quick = TCap.quickComments
        VStack(alignment: .leading, spacing: 10 * scale) {
            if let reply = state.replyTo {
                HStack(spacing: 8 * scale) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 12 * scale, weight: .semibold))
                    Text(TCap.format(.replyingTo, reply.author.privateName ?? reply.author.displayName)).font(.display(13 * scale, .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "xmark").font(.system(size: 11 * scale, weight: .bold)).onTapGesture { model.captures.replyTo = nil }
                }
                .foregroundStyle(model.accent)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 8 * scale) {
                ForEach(Array(quick.enumerated()), id: \.offset) { index, words in
                    let on = focused && state.composer == index && !state.commentTyping
                    Text(words).font(.display(14 * scale, .semibold))
                        .foregroundStyle(on ? Color.black : .white.opacity(0.85))
                        .padding(.horizontal, 13 * scale)
                        .frame(height: 34 * scale)
                        .background(FocusFill(Capsule(), focused: on, idle: Color.white.opacity(0.08)))
                        .scaleEffect(on ? 1.06 : 1)
                        .contentShape(Capsule())
                        .onTapGesture { model.sendComment(words) }
                }
            }
            .animation(Motion.focus, value: state.composer)
            field(focused: focused && state.composer == quick.count)
        }
        .animation(Motion.focus, value: state.replyTo?.id)
    }

    private func field(focused: Bool) -> some View {
        let state = model.captures
        let draft = state.commentDraft
        return HStack(spacing: 12 * scale) {
            Image(systemName: "keyboard").font(.system(size: 15 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            if previewRender {
                Text(draft.isEmpty ? TCap.text(.write) : draft).font(.display(15 * scale))
                    .foregroundStyle(.white.opacity(draft.isEmpty ? 0.4 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(TCap.text(.write), text: Binding(get: { model.captures.commentDraft }, set: { model.captures.commentDraft = String($0.prefix(TogetherPostLimits.comment)) }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.display(15 * scale))
                    .foregroundStyle(.white)
                    .lineLimit(1...3)
                    .focused($editing)
                    .onSubmit { model.sendComment(model.captures.commentDraft) }
                    .onExitCommand { model.captures.commentTyping = false }
            }
            Image(systemName: state.sending ? "ellipsis" : "paperplane.fill").font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.3) : model.accent)
                .onTapGesture { model.sendComment(model.captures.commentDraft) }
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 12 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(focused || state.commentTyping ? 0.12 : 0.06)))
        .focusRing(focused && !state.commentTyping, radius: 14 * scale, width: 2)
        .onChange(of: model.captures.commentTyping) { _, on in editing = on }
        .onChange(of: editing) { _, on in if model.captures.commentTyping != on { model.captures.commentTyping = on } }
        .contentShape(Rectangle())
        .onTapGesture {
            model.captures.line = 0
            model.captures.composer = TCap.quickComments.count
            model.captures.commentTyping = true
        }
    }
}

/// One comment, or a reply indented under one with a thread line.
struct CommentRow: View {
    let line: TogetherCommentThread.Line
    let focused: Bool
    let armed: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let comment = line.comment
        HStack(alignment: .top, spacing: 12 * scale) {
            if line.isReply {
                Capsule().fill(Color.white.opacity(0.14)).frame(width: 2 * scale).padding(.leading, 18 * scale)
            }
            ProfileAvatar(url: comment.author.privateAvatar ?? comment.author.avatar, name: comment.author.displayName, size: (line.isReply ? 28 : 34) * scale, glow: false)
            VStack(alignment: .leading, spacing: 4 * scale) {
                HStack(spacing: 6 * scale) {
                    Text(comment.author.privateName ?? comment.author.displayName).font(.display(14 * scale, .semibold)).foregroundStyle(.white)
                    Text(ProfileView.relative(comment.createdAt)).font(.display(12 * scale, .medium)).foregroundStyle(.white.opacity(0.45))
                }
                Text(comment.text).font(.display(15 * scale)).foregroundStyle(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                if armed {
                    Label(TCap.text(.commentDeleteAgain), systemImage: "trash").font(.display(12 * scale, .semibold)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 10 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(focused ? 0.12 : 0.03)))
        .focusRing(focused, radius: 14 * scale, width: 2)
        .animation(Motion.focus, value: focused)
        .animation(Motion.focus, value: armed)
    }
}
