import AnyPS5Core
import AppKit
import SwiftUI

/// The party's text chat, beside its voice on the party screen: the same thread, bubbles,
/// reactions, replies, edits, unsending and reports as Messages (MessagesView.swift,
/// MessageActions.swift), on the party's own conversation. It is never in the inbox's list, its
/// unread count or its banners; while the party screen shows it, it is read to its end.
extension AppModel {
    /// The signed-in user, as the threads know them.
    var chatMe: String? { inbox?.me ?? togetherUser?.id }

    /// The party's chat as a conversation, while the user is in a party that has one (an older
    /// server's party has none: then there is no chat).
    var partyChatConversation: TogetherConversation? {
        guard let party, let chat = partyChat, chat.partyId == party.id, party.conversationId == chat.id else { return nil }
        return chat.conversation(for: party)
    }

    /// Whether the party screen shows the chat (a parent's rules may keep messages off).
    var partyChatShown: Bool { overlay == .party && partyChatConversation != nil && familyAllows(.messages) }

    /// The conversation the thread's actions act on: the party's chat on the party screen, else
    /// the one selected in Messages.
    var chatConversation: TogetherConversation? { partyChatShown ? partyChatConversation : selectedConversation }

    /// What is typed in the thread on screen: the party's field, or Messages'.
    var chatDraft: String {
        get { partyChatShown ? partyDraft : messageDraft }
        set { if partyChatShown { partyDraft = newValue } else { messageDraft = newValue } }
    }

    /// Others' messages in the party's chat since the party screen was last shown.
    var partyChatUnread: Int { overlay == .party || !familyAllows(.messages) ? 0 : (partyChat?.unread ?? 0) }

    /// A conversation's messages loaded so far, oldest first.
    func thread(of conversationId: String) -> [TogetherMessage]? {
        conversationId == partyChat?.id ? partyChat?.messages : inbox?.threads[conversationId]
    }

    func conversation(withId id: String) -> TogetherConversation? {
        id == partyChat?.id ? partyChatConversation : inbox?.conversations.first { $0.id == id }
    }

    /// A message sent, edited or unsent here, where it belongs.
    func storeMessage(_ message: TogetherMessage) {
        if message.conversationId == partyChat?.id {
            partyChat?.apply(message, me: chatMe ?? "", open: true)
        } else {
            _ = inbox?.apply(message, open: message.conversationId)
        }
    }

    func storeReactions(_ conversationId: String, seq: Int, _ reactions: [TogetherReactionCount]) {
        if conversationId == partyChat?.id { partyChat?.react(seq, reactions: reactions) } else { inbox?.react(conversationId, seq: seq, reactions: reactions) }
    }

    /// Who wrote a message (or reacted): a member's name; in a party's chat someone who left goes
    /// by the name they had in the party this session, else "Former member".
    func authorName(_ userId: String?, in conversation: TogetherConversation, unknown: String = "") -> String {
        if let name = conversation.members.first(where: { $0.userId == userId })?.displayName { return name }
        guard conversation.partyId != nil else { return unknown }
        return partyChat?.name(of: userId, members: conversation.members) ?? TChat.text(.formerMember)
    }

    // MARK: Keeping it current

    /// The party changed: its chat follows (a new party's read from the start, none without a party).
    func syncPartyChat() {
        guard let party, let id = party.conversationId else {
            guard partyChat != nil else { return }
            partyChat = nil
            partyDraft = ""
            partyChatFocused = false
            if overlay == .party {
                composing = false
                resetMessageActions()
            }
            return
        }
        if partyChat?.id != id || partyChat?.partyId != party.id {
            partyChat = TogetherPartyChat(id: id, partyId: party.id)
            partyDraft = ""
            partyChatFocused = false
            loadPartyChat()
        }
        partyChat?.saw(party.members)
    }

    /// The newest messages, for someone who just joined or opened the launcher.
    func loadPartyChat() {
        guard persists, togetherUser != nil, let id = partyChat?.id else { return }
        let client = together
        Task {
            guard let page = try? await client.messages(in: id, limit: TogetherPartyChat.page), partyChat?.id == id else { return }
            withAnimation(Motion.focus) { partyChat?.loaded(page.messages, more: page.more) }
            if partyChatShown { readPartyChat() }
        }
    }

    /// What came while the socket was away, a page at a time (the history first if it is not read yet).
    func catchUpPartyChat() {
        guard persists, togetherUser != nil, let chat = partyChat else { return }
        guard chat.messages != nil, let newest = chat.newestSeq else { return loadPartyChat() }
        let client = together, id = chat.id
        Task {
            var after = newest
            for _ in 0 ..< 10 {
                guard let page = try? await client.messages(in: id, after: after, limit: TogetherPartyChat.page), partyChat?.id == id else { return }
                let open = partyChatShown
                withAnimation(Motion.focus) { for message in page.messages { partyChat?.apply(message, me: chatMe ?? "", open: open) } }
                guard page.more, let last = page.messages.last?.seq, last > after else { break }
                after = last
            }
            if partyChatShown { readPartyChat() }
        }
    }

    /// Read to the newest message, here and on the server.
    func readPartyChat() {
        guard let id = partyChat?.id, let seq = partyChat?.readToEnd(), persists else { return }
        let client = together
        Task { try? await client.markRead(id, upTo: seq) }
    }

    /// The party screen opening: the chat caught up and read, the focus on the party's rows.
    func openPartyChat() {
        partyChatFocused = false
        composing = false
        resetMessageActions()
        messageFocus = AppModel.quickReplies.count
        guard partyChat != nil else { return }
        catchUpPartyChat()
        readPartyChat()
    }

    /// A socket event of the party's chat, handled here and nowhere else: true when it was one.
    func partyChatEvent(_ event: TogetherSocket.Event) -> Bool {
        guard let chat = partyChat else { return false }
        switch event.type {
        case "message.created", "message.updated", "message.deleted":
            guard let message = event.decode(TogetherMessage.self), message.conversationId == chat.id else { return false }
            if event.type == "message.created", let author = message.authorId { typing.wrote(author, in: chat.id) }
            let shown = partyChatShown && NSApp?.isActive == true
            withAnimation(Motion.focus) { _ = partyChat?.apply(message, me: chatMe ?? "", open: shown) }
            if message.deletedAt != nil { forgetRemoved(message) }
            if shown, event.type == "message.created" { readPartyChat() }
            return true
        case "message.reactions":
            guard let changed = event.decode(TogetherMessageReactions.self), changed.conversationId == chat.id else { return false }
            withAnimation(Motion.focus) { partyChat?.react(changed.seq, reactions: changed.reactions) }
            return true
        case "conversation.read", "conversation.delivered", "conversation.updated":
            return event.data["conversationId"] == chat.id
        default:
            // Typing goes on as in any conversation.
            return false
        }
    }

    // MARK: The controller

    /// ← from the party's rows: into the chat, on its field.
    @discardableResult
    func enterPartyChat() -> Bool {
        guard partyChatShown else { return false }
        withAnimation(Motion.focus) { partyChatFocused = true }
        messageFocus = AppModel.quickReplies.count
        Sounds.shared.play(.move)
        return true
    }

    func leavePartyChat() {
        composing = false
        withAnimation(Motion.focus) {
            messageActions.picked = nil
            partyChatFocused = false
        }
        Sounds.shared.play(.back)
    }

    /// The chat's commands while it has the focus: the quick replies and the field (← →, → past
    /// the field back to the rows), ↑ into the messages to react, reply, edit, unsend or report.
    func partyChatCommand(_ command: Command) {
        if messageActions.menu != nil { return menuCommand(command) }
        if composing {
            if command == .back { composing = false }
            return
        }
        if let picked = messageActions.picked {
            switch command {
            case .up: pickMessage(-1)
            case .down: pickMessage(1)
            case .select, .options: openMessageMenu(picked)
            case .back, .left:
                withAnimation(Motion.focus) { messageActions.picked = nil }
                Sounds.shared.play(.back)
            case .right: leavePartyChat()
            default: break
            }
            return
        }
        let count = AppModel.quickReplies.count + 1
        switch command {
        case .left:
            if messageFocus > 0 { messageFocus -= 1; Sounds.shared.play(.move) }
        case .right:
            if messageFocus < count - 1 { messageFocus += 1; Sounds.shared.play(.move) } else { leavePartyChat() }
        case .select:
            if messageFocus < AppModel.quickReplies.count { sendMessage(AppModel.quickReplies[messageFocus]) } else { composing = true }
        case .up:
            pickMessage(-1)
        case .back:
            if messageActions.replyTo != nil || messageActions.editing != nil { cancelReplyOrEdit() } else { leavePartyChat() }
        default:
            break
        }
    }

    func previewPartyChat(_ messages: [TogetherMessage], seen: [TogetherPerson] = []) {
        guard let party, let id = party.conversationId else { return }
        var chat = partyChat ?? TogetherPartyChat(id: id, partyId: party.id)
        chat.saw(seen + party.members)
        chat.loaded(messages, more: false)
        partyChat = chat
    }
}

// MARK: Views

/// The party screen: the chat beside the party's rows (voice first), and a message's menu over both.
struct PartyScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SidePanel(title: T.text(.partyTitle), subtitle: model.partySubtitle, beside: model.partyChatShown ? AnyView(PartyChatColumn()) : nil)
            .overlay {
                if let menu = model.messageActions.menu, model.partyChatShown {
                    HStack(spacing: 0) {
                        Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.closeMessageMenu() }
                        MessageMenuSheet(menu: menu)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
    }
}

/// The chat's column: its heading with who is in the party (lit while they speak), the
/// messages, who is typing, and the quick replies and field.
struct PartyChatColumn: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let focused = model.partyChatFocused
        VStack(alignment: .leading, spacing: 14 * scale) {
            header(focused: focused)
            if let conversation = model.partyChatConversation, let me = model.chatMe {
                messages(conversation, me: me)
                    .frame(maxHeight: .infinity)
                if let typing = model.typingText(conversation) {
                    TypingLine(text: typing).transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            composer(focused: focused)
        }
        .padding(.horizontal, 30 * scale)
        .padding(.top, 36 * scale)
        .padding(.bottom, 28 * scale)
        .frame(width: 540 * scale, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .panelFrost()
        .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !model.partyChatFocused { model.enterPartyChat() } }
    }

    private func header(focused: Bool) -> some View {
        HStack(alignment: .center, spacing: 14 * scale) {
            Text(TChat.text(.partyChat)).font(.display(30 * scale, .light)).foregroundStyle(.white)
            VoiceFaces()
            Spacer(minLength: 8 * scale)
            if focused {
                if model.messageActions.picked != nil {
                    Hint(keys: "↑ ↓", label: T.text(.hintMove))
                    Hint(keys: "↩ / ✕", label: TChat.text(.hintActions))
                } else {
                    Hint(keys: "↩ / ✕", label: T.text(.messagesSend))
                    Hint(keys: "↑", label: TChat.text(.hintActions))
                }
            } else {
                Hint(keys: "←", label: TChat.text(.partyChat))
            }
        }
        .frame(height: 40 * scale)
    }

    @ViewBuilder private func messages(_ conversation: TogetherConversation, me: String) -> some View {
        if let thread = model.partyChat?.messages {
            if thread.isEmpty {
                VStack(spacing: 14 * scale) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 24 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .frame(width: 58 * scale, height: 58 * scale)
                        .background(Circle().fill(model.accent.opacity(0.28)))
                        .overlay(Circle().strokeBorder(model.accent.opacity(0.5), lineWidth: 1))
                    Text(TChat.text(.partyChatEmpty)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340 * scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MessageList(messages: thread, conversation: conversation, me: me)
            }
        } else {
            IndeterminateLine(color: model.accent).frame(width: 180 * scale).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func composer(focused: Bool) -> some View {
        let replies = AppModel.quickReplies
        let onChips = focused && !model.composing && model.messageActions.picked == nil
        return VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(spacing: 8 * scale) {
                ForEach(Array(replies.enumerated()), id: \.offset) { index, reply in
                    let on = onChips && model.messageFocus == index
                    Button { model.sendMessage(reply) } label: {
                        Text(reply).font(.display(13 * scale, .semibold)).lineLimit(1)
                            .foregroundStyle(on ? Color.black : .white)
                            .padding(.horizontal, 12 * scale).padding(.vertical, 7 * scale)
                            .background(FocusFill(Capsule(), focused: on, idle: Color.white.opacity(0.1)))
                            .scaleEffect(on ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .animation(Motion.focus, value: on)
                }
            }
            ReplyBar()
            ComposerField(focused: onChips && model.messageFocus == replies.count, placeholder: TChat.text(.partyChatPlaceholder))
        }
    }
}

/// The party's members as small overlapping faces beside the chat's heading, each lit in the
/// accent while they speak in the voice beside it.
struct VoiceFaces: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let members = model.party?.members ?? []
        let inCall = Set(model.party?.call?.in ?? [])
        HStack(spacing: -8 * scale) {
            ForEach(members.prefix(6), id: \.userId) { member in
                let speaking = model.voiceSpeaking.contains(member.userId)
                ProfileAvatar(url: member.avatar, name: member.displayName, size: 26 * scale, glow: false)
                    .overlay(Circle().strokeBorder(speaking ? model.accent : Color.black.opacity(0.45), lineWidth: (speaking ? 2 : 1.5) * scale))
                    .overlay(alignment: .bottomTrailing) {
                        if inCall.contains(member.userId) {
                            Image(systemName: "waveform").font(.system(size: 7 * scale, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 12 * scale, height: 12 * scale)
                                .background(Circle().fill(speaking ? model.accent : Color.black.opacity(0.7)))
                                .offset(x: 2 * scale, y: 2 * scale)
                        }
                    }
                    .scaleEffect(speaking && !Motion.reduced ? 1.08 : 1)
                    .animation(Motion.focus, value: speaking)
                    .help(member.displayName)
            }
        }
    }
}
