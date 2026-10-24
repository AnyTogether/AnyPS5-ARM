import AnyPS5Core
import AppKit
import SwiftUI

/// Messages on AnyTogether: the conversations (and friends to start one with) on the left, the
/// thread on the right with quick replies a controller can send and a field to type in. The
/// socket's events keep both and the top bar's unread count current.
extension AppModel {
    /// Something the list on the left holds: a conversation, or a friend without one yet.
    enum MessageTarget: Identifiable, Equatable {
        case conversation(TogetherConversation)
        case friend(TogetherFriend)

        var id: String {
            switch self {
            case .conversation(let conversation): return conversation.id
            case .friend(let friend): return "friend-" + friend.userId
            }
        }
    }

    static var quickReplies: [String] {
        [T.text(.quickHello), "GG", T.text(.quickOnMyWay), T.text(.quickJoinMe), T.text(.quickOneSec)]
    }

    var messageTargets: [MessageTarget] {
        guard let inbox else { return [] }
        let talking = Set(inbox.conversations.filter { $0.kind == "direct" }.flatMap { $0.others(than: inbox.me).map(\.userId) })
        return inbox.conversations.map(MessageTarget.conversation) + togetherFriends.filter { !talking.contains($0.userId) }.map(MessageTarget.friend)
    }

    /// The conversation selected on the left, when it is one.
    var selectedConversation: TogetherConversation? {
        let targets = messageTargets
        guard targets.indices.contains(messagesIndex), case .conversation(let conversation) = targets[messagesIndex] else { return nil }
        return conversation
    }

    var unreadMessages: Int { inbox?.unread ?? 0 }

    func loadInbox() {
        guard let user = togetherUser else { return }
        Task {
            guard let list = try? await together.conversations() else { return }
            var next = TogetherInbox(me: user.id, conversations: list)
            next.threads = inbox?.threads ?? [:]
            withAnimation(Motion.overlay) { inbox = next }
            if overlay == .messages, let conversation = selectedConversation, inbox?.threads[conversation.id] == nil { loadThread(conversation.id) }
        }
    }

    func loadThread(_ id: String) {
        Task {
            guard let page = try? await together.messages(in: id) else { return }
            inbox?.threads[id] = page.messages
            if messagesInThread, selectedConversation?.id == id { markThreadRead() }
        }
    }

    func openMessages() {
        messagesIndex = 0
        messagesInThread = false
        composing = false
        messageFocus = AppModel.quickReplies.count
        loadInbox()
        if togetherFriends.isEmpty { refreshFriends() }
        open(.messages)
    }

    func messagesCommand(_ command: Command) {
        if composing {
            if command == .back { composing = false }
            return
        }
        let targets = messageTargets
        if !messagesInThread {
            switch command {
            case .up, .down:
                let next = min(targets.count - 1, max(0, messagesIndex + (command == .down ? 1 : -1)))
                guard !targets.isEmpty, next != messagesIndex else { return }
                messagesIndex = next
                Sounds.shared.play(.move)
                if let conversation = selectedConversation, inbox?.threads[conversation.id] == nil { loadThread(conversation.id) }
            case .right, .select:
                enterThread()
            case .back, .options:
                closeOverlay()
            default:
                break
            }
            return
        }
        let count = AppModel.quickReplies.count + 1
        switch command {
        case .left:
            if messageFocus == 0 { leaveThread() } else { messageFocus -= 1; Sounds.shared.play(.move) }
        case .right:
            if messageFocus < count - 1 { messageFocus += 1; Sounds.shared.play(.move) }
        case .select:
            if messageFocus < AppModel.quickReplies.count {
                sendMessage(AppModel.quickReplies[messageFocus])
            } else {
                composing = true
            }
        case .back, .up:
            leaveThread()
        case .options:
            closeOverlay()
        default:
            break
        }
    }

    /// Into the thread: a friend without a conversation gets one first.
    func enterThread() {
        let targets = messageTargets
        guard targets.indices.contains(messagesIndex) else { return }
        switch targets[messagesIndex] {
        case .conversation:
            withAnimation(Motion.focus) { messagesInThread = true }
            messageFocus = AppModel.quickReplies.count
            Sounds.shared.play(.select)
            markThreadRead()
        case .friend(let friend):
            Task {
                do {
                    let conversation = try await together.conversation(with: friend.userId)
                    if inbox?.conversations.contains(where: { $0.id == conversation.id }) == false { inbox?.conversations.insert(conversation, at: 0) }
                    inbox?.threads[conversation.id] = inbox?.threads[conversation.id] ?? []
                    messagesIndex = messageTargets.firstIndex { $0.id == conversation.id } ?? 0
                    withAnimation(Motion.focus) { messagesInThread = true }
                    messageFocus = AppModel.quickReplies.count
                    composing = true
                    loadThread(conversation.id)
                } catch {
                    show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    func leaveThread() {
        composing = false
        withAnimation(Motion.focus) { messagesInThread = false }
        Sounds.shared.play(.back)
    }

    /// The open thread, read to its end (here and on the user's other devices).
    func markThreadRead() {
        guard let conversation = selectedConversation, conversation.unread > 0 || conversation.readSeq < conversation.lastSeq else { return }
        inbox?.read(conversation.id, by: inbox?.me ?? "", upTo: conversation.lastSeq)
        let client = together
        Task { try? await client.markRead(conversation.id, upTo: conversation.lastSeq) }
    }

    func sendMessage(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let conversation = selectedConversation, !text.isEmpty else { return }
        if raw == messageDraft { messageDraft = "" }
        Sounds.shared.play(.select)
        Task {
            do {
                let sent = try await together.send(text, in: conversation.id)
                withAnimation(Motion.focus) { _ = inbox?.apply(sent, open: conversation.id) }
                messagesIndex = 0
            } catch {
                if messageDraft.isEmpty, !AppModel.quickReplies.contains(raw) { messageDraft = raw }
                show(T.text(.messagesFailed), symbol: "exclamationmark.bubble.fill")
            }
        }
    }

    /// A message event from the socket.
    func messageEvent(_ event: TogetherSocket.Event) {
        switch event.type {
        case "message.created", "message.updated", "message.deleted":
            guard let message = event.decode(TogetherMessage.self) else { return }
            let viewing = overlay == .messages && messagesInThread && selectedConversation?.id == message.conversationId && NSApp.isActive
            let selectedID = selectedConversation?.id
            guard inbox?.apply(message, open: viewing ? message.conversationId : nil) == true else { return loadInbox() }
            // The list moved under the selection: keep the same conversation selected.
            if let selectedID, let index = messageTargets.firstIndex(where: { $0.id == selectedID }) { messagesIndex = index }
            if viewing, event.type == "message.created" {
                let client = together
                Task { try? await client.markRead(message.conversationId, upTo: message.seq) }
            }
            guard event.type == "message.created", message.authorId != togetherUser?.id, !viewing, let text = message.text else { return }
            let author = inbox?.conversations.first { $0.id == message.conversationId }?.members.first { $0.userId == message.authorId }?.displayName ?? ""
            Sounds.shared.play(.move)
            show(T.format(.messagesFrom, author, text), symbol: "bubble.left.fill")
            if !NSApp.isActive { TrophyBanner.shared.notice(author, detail: text, symbol: "bubble.left.fill", sounds: preferences.sounds) }
        case "conversation.read":
            let data = event.data
            guard let id = data["conversationId"], let user = data["userId"], let seq = data["upToSeq"].flatMap(Int.init) else { return }
            inbox?.read(id, by: user, upTo: seq)
        case "conversation.updated":
            loadInbox()
        default:
            break
        }
    }

    func previewMessages(_ inbox: TogetherInbox, index: Int, inThread: Bool, focus: Int? = nil) {
        self.inbox = inbox
        messagesIndex = index
        messagesInThread = inThread
        messageFocus = focus ?? AppModel.quickReplies.count
        overlay = .messages
    }
}

struct MessagesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 28 * scale) {
            list.frame(width: 470 * scale)
            thread.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 72 * scale)
        .padding(.vertical, 52 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.74).background(.ultraThinMaterial))
    }

    // MARK: List

    private var list: some View {
        let targets = model.messageTargets
        let firstFriend = targets.firstIndex { if case .friend = $0 { return true } else { return false } }
        return VStack(alignment: .leading, spacing: 18 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
                Text(T.text(.messagesTitle)).font(.display(34 * scale, .light)).foregroundStyle(.white)
                if model.unreadMessages > 0 {
                    Text("\(model.unreadMessages)").font(.display(14 * scale, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8 * scale).padding(.vertical, 2 * scale)
                        .background(Capsule().fill(model.accent))
                }
            }
            if model.inbox == nil {
                IndeterminateLine(color: model.accent).frame(width: 200 * scale).padding(.top, 20 * scale)
            } else if targets.isEmpty {
                ProfileNotice(symbol: "bubble.left.and.bubble.right", text: T.text(.messagesNone))
            }
            ProfileColumn(title: "", count: nil, focusedIndex: model.messagesIndex, ids: targets.map(\.id)) {
                ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                    if index == firstFriend {
                        Text(T.text(.messagesStart)).font(.display(14 * scale, .semibold)).textCase(.uppercase).tracking(0.6)
                            .foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14 * scale).padding(.horizontal, 8 * scale)
                    }
                    ConversationRow(target: target, focused: index == model.messagesIndex && !model.messagesInThread, selected: index == model.messagesIndex)
                        .id(target.id)
                        .onTapGesture {
                            model.messagesIndex = index
                            model.enterThread()
                        }
                }
            }
        }
    }

    // MARK: Thread

    @ViewBuilder private var thread: some View {
        let targets = model.messageTargets
        if let conversation = model.selectedConversation, let me = model.inbox?.me {
            VStack(alignment: .leading, spacing: 16 * scale) {
                HStack(spacing: 16 * scale) {
                    let other = conversation.others(than: me).first
                    ProfileAvatar(url: conversation.kind == "direct" ? other?.avatar : nil, name: conversation.name(for: me), size: 52 * scale, glow: false)
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text(conversation.name(for: me)).font(.display(22 * scale, .semibold)).foregroundStyle(.white).lineLimit(1)
                        if let other, conversation.kind == "direct" {
                            let presence = model.togetherFriends.first { $0.userId == other.userId }?.presence
                            Text("@\(other.handle) · \(model.presenceText(presence))").font(.display(14 * scale)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    Spacer()
                    HStack(spacing: 22 * scale) {
                        Hint(keys: "← → ↑ ↓", label: T.text(.hintMove))
                        Hint(keys: "↩ / ✕", label: T.text(model.messagesInThread ? .messagesSend : .hintSelect))
                        Hint(keys: "esc / ○", label: T.text(.hintBack))
                    }
                }
                messages(conversation, me: me)
                    .frame(maxHeight: .infinity)
                composer
            }
            .padding(24 * scale)
            .glass(24 * scale, opacity: 0.25)
        } else if targets.indices.contains(model.messagesIndex), case .friend(let friend) = targets[model.messagesIndex] {
            VStack(spacing: 18 * scale) {
                ProfileAvatar(url: friend.avatar, name: friend.displayName, size: 96 * scale)
                Text(friend.displayName).font(.display(26 * scale, .light)).foregroundStyle(.white)
                Text(T.text(.messagesSayHello)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(24 * scale, opacity: 0.25)
        } else {
            Text(T.text(.messagesPick)).font(.display(16 * scale, .medium)).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glass(24 * scale, opacity: 0.25)
        }
    }

    @ViewBuilder private func messages(_ conversation: TogetherConversation, me: String) -> some View {
        let thread = model.inbox?.threads[conversation.id]
        if let thread, thread.isEmpty {
            Text(T.text(.messagesEmptyThread)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let thread {
            MessageList(messages: thread, conversation: conversation, me: me)
        } else {
            IndeterminateLine(color: model.accent).frame(width: 200 * scale).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var composer: some View {
        let inThread = model.messagesInThread
        let replies = AppModel.quickReplies
        return VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 10 * scale) {
                ForEach(Array(replies.enumerated()), id: \.offset) { index, reply in
                    let focused = inThread && !model.composing && model.messageFocus == index
                    Button { model.sendMessage(reply) } label: {
                        Text(reply).font(.display(14 * scale, .semibold))
                            .foregroundStyle(focused ? Color.black : .white)
                            .padding(.horizontal, 14 * scale).padding(.vertical, 8 * scale)
                            .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.1)))
                            .scaleEffect(focused ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .animation(Motion.focus, value: focused)
                }
            }
            ComposerField(focused: inThread && model.messageFocus == replies.count)
        }
    }
}

/// The field a message is typed in; Return sends, Escape leaves it.
struct ComposerField: View {
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: "keyboard").font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            TextField(T.text(.messagesWrite), text: $model.messageDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.display(16 * scale))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .focused($editing)
                .onSubmit { model.sendMessage(model.messageDraft) }
                .onExitCommand { model.composing = false }
            Image(systemName: "paperplane.fill").font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(model.messageDraft.isEmpty ? .white.opacity(0.3) : model.accent)
                .onTapGesture { model.sendMessage(model.messageDraft) }
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(focused || model.composing ? 0.12 : 0.06)))
        .focusRing(focused && !model.composing, radius: 16 * scale, width: 2)
        .onChange(of: model.composing) { _, on in editing = on }
        .onChange(of: editing) { _, on in if model.composing != on { model.composing = on } }
        .onTapGesture { model.composing = true }
    }
}

struct ConversationRow: View {
    let target: AppModel.MessageTarget
    let focused: Bool
    let selected: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let me = model.inbox?.me ?? ""
        HStack(spacing: 14 * scale) {
            switch target {
            case .conversation(let conversation):
                let other = conversation.others(than: me).first
                ProfileAvatar(url: conversation.kind == "direct" ? other?.avatar : nil, name: conversation.name(for: me), size: 46 * scale, glow: false)
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(conversation.name(for: me)).font(.display(17 * scale, conversation.unread > 0 ? .bold : .semibold)).lineLimit(1)
                    Text(preview(conversation, me: me)).font(.display(13 * scale)).opacity(conversation.unread > 0 ? 0.85 : 0.55).lineLimit(1)
                }
                Spacer(minLength: 8 * scale)
                VStack(alignment: .trailing, spacing: 6 * scale) {
                    Text(MessageList.time(conversation.updatedAt)).font(.display(12 * scale, .medium)).opacity(0.5)
                    if conversation.unread > 0 {
                        Text("\(conversation.unread)").font(.display(12 * scale, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7 * scale).frame(minHeight: 20 * scale)
                            .background(Capsule().fill(model.accent))
                    }
                }
            case .friend(let friend):
                ProfileAvatar(url: friend.avatar, name: friend.displayName, size: 46 * scale, glow: false)
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(friend.displayName).font(.display(17 * scale, .semibold)).lineLimit(1)
                    Text("@\(friend.handle) · \(model.presenceText(friend.presence))").font(.display(13 * scale)).opacity(0.55).lineLimit(1)
                }
                Spacer(minLength: 8 * scale)
                Image(systemName: "square.and.pencil").font(.system(size: 15 * scale, weight: .semibold)).opacity(0.6)
            }
        }
        .foregroundStyle(focused ? Color.black : .white)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 11 * scale)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(focused ? Color.white : Color.white.opacity(selected ? 0.12 : 0.05)))
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
    }

    private func preview(_ conversation: TogetherConversation, me: String) -> String {
        guard let last = conversation.lastMessage else { return T.text(.messagesSayHello) }
        let text = last.text ?? T.text(.messagesDeleted)
        return last.authorId == me ? T.format(.messagesYou, text) : text
    }
}

/// A thread's messages as bubbles: the user's on the right in the accent, the others' on the
/// left with who wrote them in a group; the newest at the bottom.
struct MessageList: View {
    let messages: [TogetherMessage]
    let conversation: TogetherConversation
    let me: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        if previewRender {
            Color.clear.overlay(alignment: .bottom) { bubbles }.clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) { bubbles }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: messages.last?.seq) { _, _ in
                        guard let last = messages.last else { return }
                        withAnimation(Motion.focus) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
            }
        }
    }

    private var bubbles: some View {
        LazyVStack(spacing: 8 * scale) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                let mine = message.authorId == me
                let first = index == 0 || messages[index - 1].authorId != message.authorId
                HStack {
                    if mine { Spacer(minLength: 120 * scale) }
                    VStack(alignment: mine ? .trailing : .leading, spacing: 4 * scale) {
                        if first, !mine, conversation.kind == "group" {
                            Text(conversation.members.first { $0.userId == message.authorId }?.displayName ?? "")
                                .font(.display(12 * scale, .semibold)).foregroundStyle(.white.opacity(0.55))
                        }
                        Text(message.text ?? T.text(.messagesDeleted))
                            .font(.display(16 * scale))
                            .italic(message.text == nil)
                            .foregroundStyle(.white.opacity(message.text == nil ? 0.5 : 1))
                            .padding(.horizontal, 14 * scale)
                            .padding(.vertical, 9 * scale)
                            .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(mine ? model.accent.opacity(0.85) : Color.white.opacity(0.1)))
                            .textSelection(.enabled)
                        if index == messages.count - 1 || messages[index + 1].authorId != message.authorId {
                            Text(MessageList.time(message.createdAt) + (message.editedAt != nil ? " · " + T.text(.messagesEdited) : ""))
                                .font(.display(11 * scale, .medium)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    if !mine { Spacer(minLength: 120 * scale) }
                }
                .id(message.id)
                .padding(.top, first && index > 0 ? 6 * scale : 0)
            }
        }
        .padding(.vertical, 6 * scale)
    }

    /// "14:05" today, "Mon" this week, "Oct 3" before.
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: T.language == .turkish ? "tr_TR" : "en_US")
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
        } else if let week = calendar.date(byAdding: .day, value: -6, to: Date()), date > week {
            formatter.setLocalizedDateFormatFromTemplate("EEE")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return formatter.string(from: date)
    }
}
