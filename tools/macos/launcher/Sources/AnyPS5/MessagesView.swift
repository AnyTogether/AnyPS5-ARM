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
        /// A group to start: friends picked and a name.
        case newGroup
        case friend(TogetherFriend)

        var id: String {
            switch self {
            case .conversation(let conversation): return conversation.id
            case .newGroup: return "new-group"
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
        return inbox.conversations.map(MessageTarget.conversation) + (togetherFriends.isEmpty ? [] : [.newGroup])
            + togetherFriends.filter { !talking.contains($0.userId) }.map(MessageTarget.friend)
    }

    /// The conversation selected on the left, when it is one.
    var selectedConversation: TogetherConversation? {
        let targets = messageTargets
        guard targets.indices.contains(messagesIndex), case .conversation(let conversation) = targets[messagesIndex] else { return nil }
        return conversation
    }

    var unreadMessages: Int { inbox?.unread ?? 0 }

    /// Whether the row selected on the left is the new group.
    var selectingNewGroup: Bool {
        let targets = messageTargets
        return targets.indices.contains(messagesIndex) && targets[messagesIndex] == .newGroup
    }

    /// `expecting`: a message came for a conversation the list lacks; read again still without it
    /// (a party's chat), its messages do not read the list again.
    func loadInbox(expecting: String? = nil) {
        guard let user = togetherUser else { return }
        Task {
            guard let list = try? await together.conversations() else { return }
            var next = TogetherInbox(me: user.id, conversations: list)
            if let inbox { next.carry(from: inbox) }
            next.listed(list, expecting: expecting)
            inboxArrived(next)
        }
    }

    /// The list read from the server.
    func inboxArrived(_ next: TogetherInbox) {
        // The list read again may be in another order: the same conversation stays selected.
        let selectedID = inbox == nil ? nil : selectedConversation?.id
        withAnimation(Motion.overlay) { inbox = next }
        keepSelection(selectedID)
        guard overlay == .messages else { return }
        // A notification's conversation the list did not have yet: open now that it does.
        if let pending = pendingConversation, showConversation(pending) { return }
        if let conversation = selectedConversation, inbox?.threads[conversation.id] == nil { loadThread(conversation.id) }
    }

    func loadThread(_ id: String) {
        guard !threadsLoading.contains(id) else { return }
        threadsLoading.insert(id)
        Task {
            defer { threadsLoading.remove(id) }
            guard let page = try? await together.messages(in: id) else { return }
            inbox?.threads[id] = page.messages
            if messagesInThread, selectedConversation?.id == id { markThreadRead() }
        }
    }

    /// Messages, on the list; with `conversation` (a notification's) on that conversation's
    /// thread, ready to answer, as soon as the list has it.
    func openMessages(conversation: String? = nil) {
        messagesIndex = 0
        messagesInThread = false
        composing = false
        resetMessageActions()
        messageFocus = AppModel.quickReplies.count
        pendingConversation = conversation
        loadInbox()
        if togetherFriends.isEmpty { refreshFriends() }
        open(.messages)
        if let conversation { showConversation(conversation) }
    }

    /// Selects the conversation and goes into its thread; false while the list does not have it.
    @discardableResult
    func showConversation(_ id: String) -> Bool {
        guard let index = messageTargets.firstIndex(where: { $0.id == id }) else { return false }
        pendingConversation = nil
        openConversation(at: index)
        return true
    }

    /// A row on the left clicked (or a notification's conversation): selected and entered.
    func openConversation(at index: Int) {
        guard messageTargets.indices.contains(index) else { return }
        if index != messagesIndex {
            composing = false
            resetMessageActions()
        }
        messagesIndex = index
        enterThread()
    }

    func messagesCommand(_ command: Command) {
        if cloud.viewing != nil {
            if command == .back || command == .select || command == .options { closeViewer() }
            return
        }
        if messageActions.menu != nil { return menuCommand(command) }
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
                resetMessageActions()
                Sounds.shared.play(.move)
                if let conversation = selectedConversation, inbox?.threads[conversation.id] == nil { loadThread(conversation.id) }
            case .right, .select:
                enterThread()
            case .options:
                if let conversation = selectedConversation { openConversationMenu(conversation.id) } else { closeOverlay() }
            case .back:
                closeOverlay()
            default:
                break
            }
            return
        }
        if selectingNewGroup { return groupCommand(command) }
        if messageActions.picked != nil { return pickedCommand(command) }
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
        case .up:
            // Up into the messages, the newest first, to react, reply, edit or unsend.
            if !pickMessage(-1) { leaveThread() }
        case .back:
            if messageActions.replyTo != nil || messageActions.editing != nil { cancelReplyOrEdit() } else { leaveThread() }
        case .options:
            if let conversation = selectedConversation { openConversationMenu(conversation.id) }
        default:
            break
        }
    }

    /// Into the thread: a friend without a conversation gets one first.
    func enterThread() {
        let targets = messageTargets
        guard targets.indices.contains(messagesIndex) else { return }
        switch targets[messagesIndex] {
        case .newGroup:
            withAnimation(Motion.focus) { messagesInThread = true }
            groupFocus = 0
            Sounds.shared.play(.select)
        case .conversation(let conversation):
            resetMessageActions()
            // A thread not read yet (only the first one is, with the list) is asked for now,
            // else it would wait on its loading line for good.
            if inbox?.threads[conversation.id] == nil { loadThread(conversation.id) }
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

    /// The new group's rows: its name, each friend to pick, then Create.
    private func groupCommand(_ command: Command) {
        let last = togetherFriends.count + 1
        switch command {
        case .up, .down:
            let next = min(last, max(0, groupFocus + (command == .down ? 1 : -1)))
            guard next != groupFocus else { return }
            groupFocus = next
            Sounds.shared.play(.move)
        case .select:
            if groupFocus == 0 {
                composing = true
            } else if groupFocus == last {
                startGroup()
            } else {
                let friend = togetherFriends[groupFocus - 1]
                if groupPicked.contains(friend.userId) { groupPicked.remove(friend.userId) } else { groupPicked.insert(friend.userId) }
                Sounds.shared.play(.move)
            }
        case .back, .left:
            leaveThread()
        case .options:
            closeOverlay()
        default:
            break
        }
    }

    /// The group with the friends picked, opened to write in.
    func startGroup() {
        guard familyPermits(.messages) else { return }
        let members = togetherFriends.map(\.userId).filter(groupPicked.contains)
        guard !members.isEmpty else { return show(T.text(.messagesGroupPick), symbol: "person.2.badge.plus") }
        let title = groupName
        Task {
            do {
                let group = try await together.startGroup(with: members, title: title)
                if inbox?.conversations.contains(where: { $0.id == group.id }) == false { inbox?.conversations.insert(group, at: 0) }
                inbox?.threads[group.id] = inbox?.threads[group.id] ?? []
                groupPicked = []
                groupName = ""
                messagesIndex = messageTargets.firstIndex { $0.id == group.id } ?? 0
                withAnimation(Motion.focus) { messagesInThread = true }
                messageFocus = AppModel.quickReplies.count
                composing = true
                Sounds.shared.play(.select)
                show(T.format(.messagesGroupMade, group.name(for: inbox?.me ?? "")), symbol: "person.3.fill")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The user types in the open thread: its other members see so.
    func sayTyping() {
        guard composing, !chatDraft.isEmpty, let conversation = chatConversation else { return }
        togetherSocket?.typing(in: conversation.id)
    }

    /// "Ayşe is typing…" for the conversation, or nil.
    func typingText(_ conversation: TogetherConversation) -> String? {
        let names = typing.who(in: conversation.id).compactMap { id in conversation.members.first { $0.userId == id }?.displayName }
        switch names.count {
        case 0: return nil
        case 1: return T.format(.messagesTyping, names[0])
        default: return T.format(.messagesTypingMany, names.joined(separator: ", "))
        }
    }

    func leaveThread() {
        composing = false
        if messageActions.editing != nil { messageDraft = "" }
        resetMessageActions()
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
        // The field's text while editing says the message again; a quick reply is still a new one.
        if messageActions.editing != nil, raw == chatDraft { return saveEdit(raw) }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let conversation = chatConversation, !text.isEmpty else { return }
        if raw == chatDraft { chatDraft = "" }
        let replyTo = messageActions.replyTo
        withAnimation(Motion.focus) { messageActions.replyTo = nil }
        Sounds.shared.play(.select)
        Task {
            do {
                let sent = try await together.send(text, in: conversation.id, replyTo: replyTo)
                withAnimation(Motion.focus) { storeMessage(sent) }
                if conversation.partyId == nil { keepSelection(conversation.id) }
            } catch {
                if messageActions.replyTo == nil, chatConversation?.id == conversation.id { messageActions.replyTo = replyTo }
                // The words go back to the field they were typed in.
                if !AppModel.quickReplies.contains(raw) {
                    if conversation.partyId != nil { if partyDraft.isEmpty { partyDraft = raw } } else if messageDraft.isEmpty { messageDraft = raw }
                }
                if let problem = error as? TogetherProblem, problem.code == "link_blocked" {
                    show(T.text(.togetherLinkBlocked), symbol: "link.badge.plus")
                } else {
                    show(sendRefusal(error), symbol: "exclamationmark.bubble.fill")
                }
            }
        }
    }

    /// Why a message was not sent: the family's rules, a muted account, too many at once, else
    /// that it was not sent.
    func sendRefusal(_ error: Error) -> String {
        if let family = familyMessage(error) { return family }
        switch (error as? TogetherProblem)?.code {
        case "account_muted": return JS.text(.accountMuted)
        case "rate_limited": return T.text(.togetherTooMany)
        default: return T.text(.messagesFailed)
        }
    }

    /// A message event from the socket.
    func messageEvent(_ event: TogetherSocket.Event) {
        // The party's chat is the party screen's: never in the list, its count or its banners.
        if partyChatEvent(event) { return }
        switch event.type {
        case "message.created", "message.updated", "message.deleted":
            guard let message = event.decode(TogetherMessage.self) else { return }
            let viewing = overlay == .messages && messagesInThread && selectedConversation?.id == message.conversationId && NSApp.isActive
            let selectedID = selectedConversation?.id
            if event.type == "message.created", let author = message.authorId { typing.wrote(author, in: message.conversationId) }
            let known = inbox?.apply(message, open: viewing ? message.conversationId : nil) == true
            if message.deletedAt != nil { forgetRemoved(message) }
            guard known else {
                // A new conversation, or one the list never has (another device's party chat):
                // read again once, not for each of its messages.
                if inbox?.needsList(for: message.conversationId) ?? true { loadInbox(expecting: message.conversationId) }
                return
            }
            // The list moved under the selection: keep the same conversation selected.
            keepSelection(selectedID)
            if viewing, event.type == "message.created" {
                let client = together
                Task { try? await client.markRead(message.conversationId, upTo: message.seq) }
            }
            // It reached this device: its sender sees it delivered (an open thread is being read).
            if event.type == "message.created", inbox?.acknowledges(message, open: viewing ? message.conversationId : nil) == true {
                let client = together
                Task { try? await client.markDelivered(message.conversationId, upTo: message.seq) }
            }
            guard event.type == "message.created", message.authorId != togetherUser?.id, !viewing, let text = messageWords(message) else { return }
            let conversation = inbox?.conversations.first { $0.id == message.conversationId }
            guard conversation?.muted != true else { return }
            let author = conversation?.members.first { $0.userId == message.authorId }?.displayName ?? ""
            if !doNotDisturb { Sounds.shared.play(.move) }
            show(T.format(.messagesFrom, author, text), symbol: "bubble.left.fill")
            if !NSApp.isActive, !doNotDisturb { TrophyBanner.shared.notice(author, detail: text, symbol: "bubble.left.fill", sounds: preferences.sounds) }
        case "message.reactions":
            guard let changed = event.decode(TogetherMessageReactions.self) else { return }
            withAnimation(Motion.focus) { inbox?.react(changed.conversationId, seq: changed.seq, reactions: changed.reactions) }
        case "conversation.read":
            let data = event.data
            guard let id = data["conversationId"], let user = data["userId"], let seq = data["upToSeq"].flatMap(Int.init) else { return }
            inbox?.read(id, by: user, upTo: seq, unread: data["unread"].flatMap(Int.init))
        case "conversation.delivered":
            let data = event.data
            guard let id = data["conversationId"], let user = data["userId"], let seq = data["upToSeq"].flatMap(Int.init) else { return }
            inbox?.delivered(id, by: user, upTo: seq)
        case "messages.settings":
            guard let on = event.data["readReceipts"].map({ $0 == "1" || $0 == "true" }) else { return }
            togetherProfile?.readReceipts = on
            loadInbox()
        case "conversation.updated":
            if let id = event.data["conversationId"], inbox?.unlisted.contains(id) == true { return }
            loadInbox()
        case "typing":
            let data = event.data
            guard let id = data["conversationId"], let user = data["userId"], user != togetherUser?.id else { return }
            typing.typing(user, in: id)
            typingExpiry?.cancel()
            typingExpiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TogetherTyping.shows + 0.1))
                guard !Task.isCancelled else { return }
                self?.typing.expire()
            }
        default:
            break
        }
    }

    func previewGroup(picked: Set<String>, name: String, focus: Int) {
        groupPicked = picked
        groupName = name
        groupFocus = focus
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
        .screenFrost(0.74)
        .overlay {
            if let menu = model.messageActions.menu {
                HStack(spacing: 0) {
                    Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.closeMessageMenu() }
                    MessageMenuSheet(menu: menu)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay {
            if let media = model.cloud.viewing { MediaViewer(media: media).transition(.opacity) }
        }
    }

    // MARK: List

    private var list: some View {
        let targets = model.messageTargets
        let firstFriend = targets.firstIndex { if case .conversation = $0 { return false } else { return true } }
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
                        .onTapGesture { model.openConversation(at: index) }
                        .contextMenu {
                            if case .conversation(let conversation) = target {
                                Button(TChat.text(conversation.pinned ? .unpin : .pin)) { model.setPinned(conversation, !conversation.pinned) }
                                Button(TChat.text(conversation.muted ? .unmute : .mute)) { model.setMuted(conversation, !conversation.muted) }
                            }
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
                        if model.messageActions.picked != nil {
                            Hint(keys: "↑ ↓", label: T.text(.hintMove))
                            Hint(keys: "↩ / ✕", label: TChat.text(.hintActions))
                        } else {
                            Hint(keys: "← → ↑ ↓", label: T.text(.hintMove))
                            Hint(keys: "↩ / ✕", label: T.text(model.messagesInThread ? .messagesSend : .hintSelect))
                            Hint(keys: "O / △", label: TChat.text(.hintActions))
                        }
                        Hint(keys: "esc / ○", label: T.text(.hintBack))
                    }
                }
                messages(conversation, me: me)
                    .frame(maxHeight: .infinity)
                if let typing = model.typingText(conversation) {
                    TypingLine(text: typing).transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                composer
            }
            .padding(24 * scale)
            .glass(24 * scale, opacity: 0.25)
        } else if model.selectingNewGroup {
            GroupComposer()
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
                    let focused = inThread && !model.composing && model.messageActions.picked == nil && model.messageFocus == index
                    Button { model.sendMessage(reply) } label: {
                        Text(reply).font(.display(14 * scale, .semibold))
                            .foregroundStyle(focused ? Color.black : .white)
                            .padding(.horizontal, 14 * scale).padding(.vertical, 8 * scale)
                            .background(FocusFill(Capsule(), focused: focused, idle: Color.white.opacity(0.1)))
                            .scaleEffect(focused ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .animation(Motion.focus, value: focused)
                }
            }
            ReplyBar()
            ComposerField(focused: inThread && model.messageActions.picked == nil && model.messageFocus == replies.count)
        }
    }
}

/// The field a message is typed in; Return sends, Escape leaves it.
struct ComposerField: View {
    let focused: Bool
    var placeholder = T.text(.messagesWrite)
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @FocusState private var editing: Bool
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: "keyboard").font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            if previewRender {
                // A text field does not draw offscreen.
                Text(model.chatDraft.isEmpty ? placeholder : model.chatDraft).font(.display(16 * scale))
                    .foregroundStyle(.white.opacity(model.chatDraft.isEmpty ? 0.4 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $model.chatDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.display(16 * scale))
                    .foregroundStyle(.white)
                    .lineLimit(1...4)
                    .focused($editing)
                    .onSubmit { model.sendMessage(model.chatDraft) }
                    .onExitCommand { model.composing = false }
                    .onChange(of: model.chatDraft) { _, _ in model.sayTyping() }
            }
            Image(systemName: model.messageActions.editing != nil ? "checkmark.circle.fill" : "paperplane.fill").font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(model.chatDraft.isEmpty ? .white.opacity(0.3) : model.accent)
                .onTapGesture { model.sendMessage(model.chatDraft) }
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(focused || model.composing ? 0.12 : 0.06)))
        .focusRing(focused && !model.composing, radius: 16 * scale, width: 2)
        .onChange(of: model.composing) { _, on in editing = on }
        .onChange(of: editing) { _, on in
            if model.composing != on { model.composing = on }
            // Typing in the party's chat puts the controller's focus there too.
            if on, model.partyChatShown, !model.partyChatFocused { model.partyChatFocused = true }
        }
        .onTapGesture {
            if model.partyChatShown { model.partyChatFocused = true }
            model.composing = true
        }
    }
}

/// "Ayşe is typing…" with three dots that breathe in turn.
struct TypingLine: View {
    let text: String
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @State private var phase = false

    var body: some View {
        HStack(spacing: 10 * scale) {
            HStack(spacing: 4 * scale) {
                ForEach(0 ..< 3) { dot in
                    Circle().fill(Color.white.opacity(0.7)).frame(width: 6 * scale, height: 6 * scale)
                        .opacity(previewRender ? 0.4 + Double(dot) * 0.25 : (phase ? 1 : 0.3))
                        .animation(Motion.reduced ? nil : .easeInOut(duration: 0.55).repeatForever().delay(Double(dot) * 0.18), value: phase)
                }
            }
            .padding(.horizontal, 10 * scale).padding(.vertical, 8 * scale)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            Text(text).font(.display(13 * scale, .medium)).foregroundStyle(.white.opacity(0.55))
        }
        .onAppear { phase = true }
    }
}

/// A new group: a name, the friends to have in it (picked with ✕), and Create.
struct GroupComposer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender
    @FocusState private var editing: Bool

    var body: some View {
        let friends = model.togetherFriends
        let inside = model.messagesInThread
        VStack(alignment: .leading, spacing: 16 * scale) {
            HStack(spacing: 16 * scale) {
                Image(systemName: "person.3.fill").font(.system(size: 20 * scale, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 52 * scale, height: 52 * scale).background(Circle().fill(model.accent.opacity(0.85)))
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(T.text(.messagesNewGroup)).font(.display(22 * scale, .semibold)).foregroundStyle(.white)
                    Text(T.format(.messagesGroupPicked, model.groupPicked.count)).font(.display(14 * scale)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                HStack(spacing: 22 * scale) {
                    Hint(keys: "↑ ↓", label: T.text(.hintMove))
                    Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
                    Hint(keys: "esc / ○", label: T.text(.hintBack))
                }
            }
            nameField(focused: inside && model.groupFocus == 0)
            ProfileColumn(title: "", count: nil, focusedIndex: inside ? model.groupFocus - 1 : nil, ids: friends.map(\.userId)) {
                ForEach(Array(friends.enumerated()), id: \.element.userId) { index, friend in
                    friendRow(friend, focused: inside && model.groupFocus == index + 1)
                        .id(friend.userId)
                        .onTapGesture {
                            model.groupFocus = index + 1
                            if model.groupPicked.contains(friend.userId) { model.groupPicked.remove(friend.userId) } else { model.groupPicked.insert(friend.userId) }
                        }
                }
            }
            .frame(maxHeight: .infinity)
            createButton(focused: inside && model.groupFocus == friends.count + 1)
        }
        .padding(24 * scale)
        .glass(24 * scale, opacity: 0.25)
    }

    private func nameField(focused: Bool) -> some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: "character.cursor.ibeam").font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            if previewRender {
                // A text field does not draw offscreen.
                Text(model.groupName.isEmpty ? T.text(.messagesGroupName) : model.groupName).font(.display(16 * scale))
                    .foregroundStyle(.white.opacity(model.groupName.isEmpty ? 0.4 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(T.text(.messagesGroupName), text: $model.groupName)
                    .textFieldStyle(.plain)
                    .font(.display(16 * scale))
                    .foregroundStyle(.white)
                    .focused($editing)
                    .onSubmit { model.composing = false }
                    .onExitCommand { model.composing = false }
            }
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(focused || (model.composing && model.groupFocus == 0) ? 0.12 : 0.06)))
        .focusRing(focused && !model.composing, radius: 16 * scale, width: 2)
        .onChange(of: model.composing) { _, on in editing = on && model.groupFocus == 0 }
        .onChange(of: editing) { _, on in if model.composing != on { model.composing = on } }
        .onTapGesture {
            model.groupFocus = 0
            model.composing = true
        }
    }

    private func friendRow(_ friend: TogetherFriend, focused: Bool) -> some View {
        let picked = model.groupPicked.contains(friend.userId)
        return HStack(spacing: 14 * scale) {
            ProfileAvatar(url: friend.avatar, name: friend.displayName, size: 40 * scale, glow: false)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(friend.displayName).font(.display(16 * scale, .semibold)).lineLimit(1)
                Text("@\(friend.handle)").font(.display(13 * scale)).opacity(0.55).lineLimit(1)
            }
            Spacer(minLength: 8 * scale)
            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20 * scale, weight: .semibold))
                .foregroundStyle(picked ? (focused ? Color.black : model.accent) : (focused ? Color.black.opacity(0.4) : .white.opacity(0.35)))
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(focused ? Color.black : .white)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 9 * scale)
        .background(FocusFill(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(picked ? 0.1 : 0.04)))
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
        .animation(Motion.focus, value: picked)
    }

    private func createButton(focused: Bool) -> some View {
        let ready = !model.groupPicked.isEmpty
        return Button { model.startGroup() } label: {
            HStack(spacing: 10 * scale) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 15 * scale, weight: .semibold))
                Text(T.text(.messagesGroupCreate)).font(.display(16 * scale, .semibold))
            }
            .foregroundStyle(focused ? Color.black : .white.opacity(ready ? 1 : 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13 * scale)
            .background(FocusFill(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous), focused: focused, idle: (ready ? model.accent.opacity(0.8) : Color.white.opacity(0.06))))
            .scaleEffect(focused ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .animation(Motion.focus, value: focused)
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
                    HStack(spacing: 8 * scale) {
                        ConversationMarks(conversation: conversation, focused: focused)
                        Text(MessageList.time(conversation.updatedAt)).font(.display(12 * scale, .medium)).opacity(0.5)
                    }
                    if conversation.unread > 0 {
                        // A muted conversation still counts, quietly.
                        Text("\(conversation.unread)").font(.display(12 * scale, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7 * scale).frame(minHeight: 20 * scale)
                            .background(Capsule().fill(conversation.muted ? (focused ? Color.black.opacity(0.35) : Color.white.opacity(0.22)) : model.accent))
                    }
                }
            case .newGroup:
                Image(systemName: "person.3.fill").font(.system(size: 18 * scale, weight: .semibold))
                    .frame(width: 46 * scale, height: 46 * scale)
                    .background(Circle().fill(focused ? Color.black.opacity(0.08) : Color.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(T.text(.messagesNewGroup)).font(.display(17 * scale, .semibold)).lineLimit(1)
                    Text(T.text(.messagesNewGroupDetail)).font(.display(13 * scale)).opacity(0.55).lineLimit(1)
                }
                Spacer(minLength: 8 * scale)
                Image(systemName: "plus").font(.system(size: 15 * scale, weight: .semibold)).opacity(0.6)
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
        .background(FocusFill(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(selected ? 0.12 : 0.05)))
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
    }

    private func preview(_ conversation: TogetherConversation, me: String) -> String {
        guard let last = conversation.lastMessage else { return T.text(.messagesSayHello) }
        let text = model.messageWords(last) ?? T.text(.messagesDeleted)
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
                    .onChange(of: model.messageActions.picked) { _, seq in
                        guard let picked = messages.first(where: { $0.seq == seq }) else { return }
                        withAnimation(Motion.focus) { proxy.scrollTo(picked.id, anchor: .center) }
                    }
            }
        }
    }

    /// Lazy in the window; drawn whole offscreen, where a lazy stack guesses its height.
    @ViewBuilder private var bubbles: some View {
        if previewRender {
            VStack(spacing: 8 * scale) { rows }.padding(.vertical, 6 * scale)
        } else {
            LazyVStack(spacing: 8 * scale) { rows }.padding(.vertical, 6 * scale)
        }
    }

    private var rows: some View {
        let receipt = model.inbox?.receipt(in: conversation.id)
        let picked = model.messageActions.picked
        return ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            let mine = message.authorId == me
            let first = index == 0 || messages[index - 1].authorId != message.authorId
            let runEnd = index == messages.count - 1 || messages[index + 1].authorId != message.authorId
            let receiptHere = receipt?.seq == message.seq ? receipt?.state : nil
            HStack {
                if mine { Spacer(minLength: 120 * scale) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 4 * scale) {
                    if first, !mine, conversation.kind == "group" {
                        Text(model.authorName(message.authorId, in: conversation))
                            .font(.display(12 * scale, .semibold)).foregroundStyle(.white.opacity(0.55))
                    }
                    if message.deletedAt == nil, let quote = TogetherQuote(seq: message.replyTo, in: messages) {
                        ReplyQuote(quote: quote, conversation: conversation, mine: mine)
                    }
                    VStack(alignment: mine ? .trailing : .leading, spacing: 4 * scale) {
                        if let attachment = message.attachment {
                            AttachmentBubble(attachment: attachment, mine: mine)
                            if let caption = message.words { bubble(caption, mine: mine) }
                        } else {
                            bubble(message.deletedAt == nil ? message.text : nil, mine: mine)
                        }
                    }
                    .focusRing(picked == message.seq, radius: 18 * scale, width: 2)
                    .contextMenu { actions(message) }
                    if message.deletedAt == nil, !message.reactions.isEmpty {
                        ReactionChips(message: message, conversation: conversation)
                    }
                    if runEnd || receiptHere != nil {
                        HStack(spacing: 5 * scale) {
                            Text(MessageList.time(message.createdAt) + (message.editedAt != nil && message.deletedAt == nil ? " · " + T.text(.messagesEdited) : ""))
                                .foregroundStyle(.white.opacity(0.4))
                            if let receiptHere {
                                Text("·").foregroundStyle(.white.opacity(0.4))
                                ReceiptLabel(state: receiptHere)
                            }
                        }
                        .font(.display(11 * scale, .medium))
                    }
                }
                .opacity(picked == nil || picked == message.seq ? 1 : 0.55)
                .animation(Motion.focus, value: picked)
                if !mine { Spacer(minLength: 120 * scale) }
            }
            .id(message.id)
            .padding(.top, first && index > 0 ? 6 * scale : 0)
        }
    }

    /// A message's right-click menu: the same actions the controller's menu has.
    @ViewBuilder private func actions(_ message: TogetherMessage) -> some View {
        if message.deletedAt == nil {
            Menu(TChat.text(.react)) {
                ForEach(TogetherMessageReaction.allCases, id: \.self) { reaction in
                    Button((message.hasReacted(reaction, by: me) ? "✓ " : "") + reaction.glyph + "  " + TChat.name(reaction)) { model.toggleReaction(reaction, on: message) }
                }
            }
            Button(TChat.text(.reply)) { model.startReply(message) }
            if message.canEdit(by: me) { Button(TChat.text(.edit)) { model.startEditing(message) } }
            if message.authorId == me { Button(TChat.text(.unsend), role: .destructive) { model.askUnsend(message) } }
            if message.authorId != nil, message.authorId != me {
                Menu(TChat.text(.report)) {
                    ForEach(TogetherReportReason.allCases, id: \.self) { reason in
                        Button(TChat.name(reason)) { model.report(message, reason) }
                    }
                }
            }
        }
    }

    private func bubble(_ text: String?, mine: Bool) -> some View {
        Text(text ?? T.text(.messagesDeleted))
            .font(.display(16 * scale))
            .italic(text == nil)
            .foregroundStyle(.white.opacity(text == nil ? 0.5 : 1))
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 9 * scale)
            .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(mine ? model.accent.opacity(0.85) : Color.white.opacity(0.1)))
            .textSelection(.enabled)
    }

    /// "14:05" today, "Mon" this week, "Oct 3" before.
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = T.locale
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
