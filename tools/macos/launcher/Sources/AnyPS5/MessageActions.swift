import AnyPS5Core
import AppKit
import SwiftUI

/// What the open thread's actions hold: the message picked with the controller, the menu open
/// over the messages (a message's, the question before unsending it, or a conversation's), the
/// message being answered and the one being edited.
struct MessageActions: Equatable {
    /// The seq of the message picked in the open thread; nil while the quick replies and the field
    /// have the focus.
    var picked: Int?
    var menu: Menu?
    var replyTo: Int?
    var editing: Int?

    struct Menu: Equatable {
        enum Target: Equatable {
            case message(conversation: String, seq: Int)
            case unsend(conversation: String, seq: Int)
            case conversation(String)
        }

        var target: Target
        var row = 0
        /// The reaction focused while the reactions row is.
        var column = 0
    }

    enum Row: Equatable {
        case reactions, reply, edit, unsend, confirmUnsend, cancel
        /// What choosing it makes the conversation: pinned or not, muted or not.
        case pin(Bool), mute(Bool)
    }
}

extension AppModel {
    /// The open thread's messages, oldest first.
    var openThread: [TogetherMessage] {
        selectedConversation.flatMap { inbox?.threads[$0.id] } ?? []
    }

    func resetMessageActions() {
        messageActions = MessageActions()
    }

    // MARK: Picking a message

    /// The message before (-1) or after (+1) the one picked, skipping unsent ones; from the field,
    /// -1 picks the newest. Past the newest the field has the focus again. False when nothing moved.
    @discardableResult
    func pickMessage(_ step: Int) -> Bool {
        let seqs = openThread.filter { $0.deletedAt == nil }.map(\.seq)
        guard !seqs.isEmpty else { return false }
        let next: Int?
        if let picked = messageActions.picked, let at = seqs.firstIndex(of: picked) {
            let index = at + step
            guard index >= 0 else { return false }
            next = index < seqs.count ? seqs[index] : nil
        } else {
            guard step < 0 else { return false }
            next = seqs.last
        }
        withAnimation(Motion.focus) { messageActions.picked = next }
        Sounds.shared.play(.move)
        return true
    }

    /// The thread's commands while a message is picked.
    func pickedCommand(_ command: Command) {
        switch command {
        case .up:
            pickMessage(-1)
        case .down:
            pickMessage(1)
        case .select, .options:
            if let seq = messageActions.picked { openMessageMenu(seq) }
        case .back, .right:
            withAnimation(Motion.focus) { messageActions.picked = nil }
            Sounds.shared.play(.back)
        case .left:
            leaveThread()
        default:
            break
        }
    }

    // MARK: The menu

    func message(in conversationId: String, seq: Int) -> TogetherMessage? {
        inbox?.threads[conversationId]?.first { $0.seq == seq }
    }

    /// The message a message menu (or its question) is about, while it is still there to act on.
    func menuMessage(_ menu: MessageActions.Menu) -> TogetherMessage? {
        switch menu.target {
        case .message(let conversation, let seq), .unsend(let conversation, let seq):
            return message(in: conversation, seq: seq).flatMap { $0.deletedAt == nil ? $0 : nil }
        case .conversation:
            return nil
        }
    }

    func menuConversation(_ menu: MessageActions.Menu) -> TogetherConversation? {
        let id: String
        switch menu.target {
        case .message(let conversation, _), .unsend(let conversation, _): id = conversation
        case .conversation(let conversation): id = conversation
        }
        return inbox?.conversations.first { $0.id == id }
    }

    func menuRows(_ menu: MessageActions.Menu) -> [MessageActions.Row] {
        switch menu.target {
        case .message:
            guard let message = menuMessage(menu), let me = inbox?.me else { return [] }
            var rows: [MessageActions.Row] = [.reactions, .reply]
            if message.canEdit(by: me) { rows.append(.edit) }
            if message.authorId == me { rows.append(.unsend) }
            return rows
        case .unsend:
            return menuMessage(menu) == nil ? [] : [.confirmUnsend, .cancel]
        case .conversation:
            guard let conversation = menuConversation(menu) else { return [] }
            return [.pin(!conversation.pinned), .mute(!conversation.muted)]
        }
    }

    func openMessageMenu(_ seq: Int) {
        guard let conversation = selectedConversation, let message = message(in: conversation.id, seq: seq), message.deletedAt == nil else { return }
        withAnimation(Motion.overlay) { messageActions.menu = .init(target: .message(conversation: conversation.id, seq: seq)) }
        Sounds.shared.play(.select)
    }

    func openConversationMenu(_ conversationId: String) {
        withAnimation(Motion.overlay) { messageActions.menu = .init(target: .conversation(conversationId)) }
        Sounds.shared.play(.select)
    }

    func closeMessageMenu(sound: Bool = true) {
        guard messageActions.menu != nil else { return }
        withAnimation(Motion.overlay) { messageActions.menu = nil }
        if sound { Sounds.shared.play(.back) }
    }

    /// Unsending asks first (Cancel focused); going back from the question returns to the message's menu.
    func askUnsend() {
        guard let menu = messageActions.menu, case .message(let conversation, let seq) = menu.target else { return }
        withAnimation(Motion.focus) { messageActions.menu = .init(target: .unsend(conversation: conversation, seq: seq), row: 1) }
        Sounds.shared.play(.select)
    }

    /// The question straight away, from a message's context menu.
    func askUnsend(_ message: TogetherMessage) {
        withAnimation(Motion.overlay) { messageActions.menu = .init(target: .unsend(conversation: message.conversationId, seq: message.seq), row: 1) }
        Sounds.shared.play(.select)
    }

    func menuCommand(_ command: Command) {
        guard var menu = messageActions.menu else { return }
        let rows = menuRows(menu)
        guard !rows.isEmpty else { return closeMessageMenu() }
        menu.row = min(menu.row, rows.count - 1)
        switch command {
        case .up, .down:
            let next = min(rows.count - 1, max(0, menu.row + (command == .down ? 1 : -1)))
            guard next != menu.row else { return }
            menu.row = next
            messageActions.menu = menu
            Sounds.shared.play(.move)
        case .left, .right:
            guard rows[menu.row] == .reactions else { return }
            let next = min(TogetherMessageReaction.allCases.count - 1, max(0, menu.column + (command == .right ? 1 : -1)))
            guard next != menu.column else { return }
            menu.column = next
            messageActions.menu = menu
            Sounds.shared.play(.move)
        case .select:
            perform(rows[menu.row], in: menu)
        case .back:
            if case .unsend(let conversation, let seq) = menu.target {
                let back = MessageActions.Menu(target: .message(conversation: conversation, seq: seq))
                withAnimation(Motion.focus) { messageActions.menu = MessageActions.Menu(target: back.target, row: max(0, menuRows(back).count - 1)) }
                Sounds.shared.play(.back)
            } else {
                closeMessageMenu()
            }
        case .options:
            closeMessageMenu()
        default:
            break
        }
    }

    /// A row of the menu chosen (with the controller, the keyboard or a click).
    func perform(_ row: MessageActions.Row, in menu: MessageActions.Menu, reaction: TogetherMessageReaction? = nil) {
        let message = menuMessage(menu)
        let conversation = menuConversation(menu)
        switch row {
        case .reactions:
            guard let message else { return }
            closeMessageMenu(sound: false)
            toggleReaction(reaction ?? TogetherMessageReaction.allCases[min(menu.column, TogetherMessageReaction.allCases.count - 1)], on: message)
        case .reply:
            guard let message else { return }
            closeMessageMenu(sound: false)
            startReply(message)
        case .edit:
            guard let message else { return }
            closeMessageMenu(sound: false)
            startEditing(message)
        case .unsend:
            askUnsend()
        case .confirmUnsend:
            guard let message else { return }
            closeMessageMenu(sound: false)
            unsend(message)
        case .cancel:
            menuCommand(.back)
        case .pin(let on):
            guard let conversation else { return }
            closeMessageMenu(sound: false)
            setPinned(conversation, on)
        case .mute(let on):
            guard let conversation else { return }
            closeMessageMenu(sound: false)
            setMuted(conversation, on)
        }
    }

    // MARK: Reacting

    /// Adds the reaction, or takes it back when the user already gave it.
    func toggleReaction(_ reaction: TogetherMessageReaction, on message: TogetherMessage) {
        guard let me = inbox?.me, message.deletedAt == nil, familyPermits(.messages) else { return }
        let on = !message.hasReacted(reaction, by: me)
        Sounds.shared.play(.select)
        Task {
            do {
                let reactions = try await together.react(reaction, to: message.seq, in: message.conversationId, on: on)
                withAnimation(Motion.focus) { inbox?.react(message.conversationId, seq: message.seq, reactions: reactions) }
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.bubble.fill")
            }
        }
    }

    // MARK: Replying and editing

    func startReply(_ message: TogetherMessage) {
        withAnimation(Motion.focus) {
            messageActions.editing = nil
            messageActions.replyTo = message.seq
            messageActions.picked = nil
            messagesInThread = true
        }
        messageFocus = AppModel.quickReplies.count
        composing = true
    }

    func startEditing(_ message: TogetherMessage) {
        guard let me = inbox?.me, message.canEdit(by: me) else { return show(TChat.text(.editLimit), symbol: "pencil.slash") }
        withAnimation(Motion.focus) {
            messageActions.replyTo = nil
            messageActions.editing = message.seq
            messageActions.picked = nil
            messagesInThread = true
        }
        messageDraft = message.words ?? ""
        messageFocus = AppModel.quickReplies.count
        composing = true
    }

    /// Leaves the reply or the edit; an edit's text goes with it.
    func cancelReplyOrEdit() {
        if messageActions.editing != nil { messageDraft = "" }
        withAnimation(Motion.focus) {
            messageActions.replyTo = nil
            messageActions.editing = nil
        }
        Sounds.shared.play(.back)
    }

    /// The message being edited, said again.
    func saveEdit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seq = messageActions.editing, let conversation = selectedConversation, !text.isEmpty else { return }
        if message(in: conversation.id, seq: seq)?.words == text {
            messageDraft = ""
            withAnimation(Motion.focus) { messageActions.editing = nil }
            return
        }
        Sounds.shared.play(.select)
        Task {
            do {
                let edited = try await together.edit(seq, in: conversation.id, to: text)
                withAnimation(Motion.focus) {
                    _ = inbox?.apply(edited, open: conversation.id)
                    messageActions.editing = nil
                }
                if messageDraft == raw { messageDraft = "" }
            } catch let problem as TogetherProblem where problem.code == "edit_limit" || (problem.status == 403 && problem.code == "forbidden") {
                withAnimation(Motion.focus) { messageActions.editing = nil }
                show(TChat.text(.editLimit), symbol: "pencil.slash")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.bubble.fill")
            }
        }
    }

    // MARK: Unsending

    func unsend(_ message: TogetherMessage) {
        Sounds.shared.play(.select)
        Task {
            do {
                try await together.unsend(message.seq, in: message.conversationId)
                withAnimation(Motion.focus) { _ = inbox?.apply(message.removed(), open: message.conversationId) }
                forgetRemoved(message)
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.bubble.fill")
            }
        }
    }

    /// A message unsent (here, on another device or by its author): nothing acts on it any more.
    func forgetRemoved(_ message: TogetherMessage) {
        let here = selectedConversation?.id == message.conversationId
        withAnimation(Motion.focus) {
            if here, messageActions.picked == message.seq { messageActions.picked = nil }
            if here, messageActions.replyTo == message.seq { messageActions.replyTo = nil }
            if here, messageActions.editing == message.seq {
                messageActions.editing = nil
                messageDraft = ""
            }
            if let menu = messageActions.menu {
                switch menu.target {
                case .message(let conversation, let seq), .unsend(let conversation, let seq):
                    if conversation == message.conversationId, seq == message.seq { messageActions.menu = nil }
                case .conversation:
                    break
                }
            }
        }
    }

    // MARK: Pinning and muting

    func setPinned(_ conversation: TogetherConversation, _ pinned: Bool) {
        let selectedID = selectedConversation?.id
        Task {
            do {
                let changed = try await together.pin(conversation.id, pinned)
                withAnimation(Motion.layout) { inbox?.update(changed) }
                keepSelection(selectedID)
                Sounds.shared.play(.select)
            } catch let problem as TogetherProblem where problem.code == "full" {
                show(TChat.format(.pinFull, TogetherConversation.maxPinned), symbol: "pin.slash")
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func setMuted(_ conversation: TogetherConversation, _ muted: Bool) {
        Task {
            do {
                let changed = try await together.mute(conversation.id, muted)
                withAnimation(Motion.focus) { inbox?.update(changed) }
                Sounds.shared.play(.select)
            } catch {
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The list moved under the selection: the same conversation stays selected.
    func keepSelection(_ id: String?) {
        if let id, let index = messageTargets.firstIndex(where: { $0.id == id }) { messagesIndex = index }
    }

    // MARK: Read receipts

    /// Settings → AnyTogether → Privacy: whether others see when the user has read their messages.
    func readReceiptsRow() -> PanelRow? {
        guard let profile = togetherProfile else { return nil }
        return PanelRow(id: "privacy-read-receipts", title: TChat.text(.readReceipts), detail: TChat.text(.readReceiptsHint), symbol: "checkmark.message",
                        kind: .toggle(profile.readReceipts) { [weak self] on in self?.setReadReceipts(on) })
    }

    /// Shown changed at once; put back if the server says no.
    func setReadReceipts(_ on: Bool) {
        guard let before = togetherProfile?.readReceipts, before != on else { return }
        togetherProfile?.readReceipts = on
        Task {
            do {
                let kept = try await together.setReadReceipts(on)
                togetherProfile?.readReceipts = kept
                loadInbox()
            } catch {
                togetherProfile?.readReceipts = before
                show(togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }
}

// MARK: Views

/// The side sheet over Messages: a message's reactions and actions, the question before
/// unsending, or a conversation's pin and mute.
struct MessageMenuSheet: View {
    let menu: MessageActions.Menu
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    private static let danger = Color(red: 1, green: 0.6, blue: 0.55)

    var body: some View {
        let rows = model.menuRows(menu)
        let focusedRow = min(menu.row, max(0, rows.count - 1))
        VStack(alignment: .leading, spacing: 18 * scale) {
            header
            VStack(alignment: .leading, spacing: 8 * scale) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if row == .reactions {
                        reactions(focused: index == focusedRow)
                    } else {
                        action(row, focused: index == focusedRow)
                            .onTapGesture { model.perform(row, in: menu) }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 18 * scale) {
                Hint(keys: rows.contains(.reactions) ? "← → ↑ ↓" : "↑ ↓", label: T.text(.hintMove))
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

    @ViewBuilder private var header: some View {
        let me = model.inbox?.me ?? ""
        switch menu.target {
        case .message, .unsend:
            if let message = model.menuMessage(menu), let conversation = model.menuConversation(menu) {
                let mine = message.authorId == me
                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text(mine ? TL.text(.compareYou) : conversation.members.first { $0.userId == message.authorId }?.displayName ?? "")
                        .font(.display(13 * scale, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                    Text(model.messageWords(message) ?? "")
                        .font(.display(16 * scale)).foregroundStyle(.white).lineLimit(4)
                        .padding(.horizontal, 14 * scale).padding(.vertical, 10 * scale)
                        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(mine ? model.accent.opacity(0.85) : Color.white.opacity(0.1)))
                    if case .unsend = menu.target {
                        Text(TChat.text(.unsendConfirm)).font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8 * scale)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .conversation:
            if let conversation = model.menuConversation(menu) {
                let other = conversation.others(than: me).first
                HStack(spacing: 14 * scale) {
                    ProfileAvatar(url: conversation.kind == "direct" ? other?.avatar : nil, name: conversation.name(for: me), size: 46 * scale, glow: false)
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text(conversation.name(for: me)).font(.display(20 * scale, .semibold)).foregroundStyle(.white).lineLimit(1)
                        ConversationMarks(conversation: conversation, focused: false, labelled: true).foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private func reactions(focused: Bool) -> some View {
        let me = model.inbox?.me ?? ""
        let message = model.menuMessage(menu)
        let all = TogetherMessageReaction.allCases
        let column = min(menu.column, all.count - 1)
        return VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(spacing: 8 * scale) {
                ForEach(Array(all.enumerated()), id: \.offset) { index, reaction in
                    let on = focused && index == column
                    let given = message?.hasReacted(reaction, by: me) == true
                    Text(reaction.glyph)
                        .font(reaction == .gg ? .display(15 * scale, .heavy) : .system(size: 22 * scale))
                        .foregroundStyle(on ? Color.black : .white)
                        .frame(width: 46 * scale, height: 46 * scale)
                        .background(FocusFill(Circle(), focused: on, idle: given ? model.accent.opacity(0.55) : Color.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(given && !on ? model.accent : .clear, lineWidth: 1.5))
                        .scaleEffect(on ? 1.12 : 1)
                        .animation(Motion.focus, value: on)
                        .contentShape(Circle())
                        .onTapGesture { model.perform(.reactions, in: menu, reaction: reaction) }
                        .help(TChat.name(reaction))
                }
            }
            Text(focused ? TChat.name(all[column]) : TChat.text(.react))
                .font(.display(13 * scale, .semibold)).foregroundStyle(.white.opacity(focused ? 0.8 : 0.45))
                .contentTransition(.opacity)
                .animation(Motion.focus, value: column)
        }
        .padding(.bottom, 8 * scale)
    }

    private func action(_ row: MessageActions.Row, focused: Bool) -> some View {
        let (title, symbol, danger) = describe(row)
        return HStack(spacing: 14 * scale) {
            Image(systemName: symbol).font(.system(size: 16 * scale, weight: .semibold)).frame(width: 24 * scale)
            Text(title).font(.display(16 * scale, .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(focused ? Color.black : (danger ? Self.danger : .white))
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 11 * scale)
        .background(FocusFill(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(0.06)))
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
        .contentShape(Rectangle())
    }

    private func describe(_ row: MessageActions.Row) -> (String, String, Bool) {
        switch row {
        case .reactions: return (TChat.text(.react), "face.smiling", false)
        case .reply: return (TChat.text(.reply), "arrowshape.turn.up.left", false)
        case .edit: return (TChat.text(.edit), "pencil", false)
        case .unsend: return (TChat.text(.unsend), "arrow.uturn.backward", true)
        case .confirmUnsend: return (TChat.text(.unsend), "arrow.uturn.backward", true)
        case .cancel: return (T.text(.cancel), "xmark", false)
        case .pin(let on): return (TChat.text(on ? .pin : .unpin), on ? "pin" : "pin.slash", false)
        case .mute(let on): return (TChat.text(on ? .mute : .unmute), on ? "bell.slash" : "bell", false)
        }
    }
}

/// A conversation's pinned and muted marks, as small symbols (with words in its menu).
struct ConversationMarks: View {
    let conversation: TogetherConversation
    let focused: Bool
    var labelled = false
    @Environment(\.scale) private var scale

    /// Read so the view is drawn again in another language (its texts come from T).
    @Environment(\.languageCode) private var languageCode

    var body: some View {
        let _ = languageCode
        if conversation.pinned || conversation.muted {
            HStack(spacing: 8 * scale) {
                if conversation.pinned { mark("pin.fill", TChat.text(.pinned)) }
                if conversation.muted { mark("bell.slash.fill", TChat.text(.muted)) }
            }
            .opacity(focused ? 0.6 : 0.5)
        }
    }

    private func mark(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: symbol).font(.system(size: 11 * scale, weight: .semibold))
            if labelled { Text(label).font(.display(13 * scale, .medium)) }
        }
        .help(label)
    }
}

/// Over the field: the message being answered or edited, with a way out.
struct ReplyBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let actions = model.messageActions
        if let conversation = model.selectedConversation, let seq = actions.editing ?? actions.replyTo {
            let target = model.message(in: conversation.id, seq: seq)
            let editing = actions.editing != nil
            HStack(spacing: 12 * scale) {
                Image(systemName: editing ? "pencil" : "arrowshape.turn.up.left.fill")
                    .font(.system(size: 13 * scale, weight: .semibold)).foregroundStyle(model.accent)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(editing ? TChat.text(.editing) : TChat.format(.replyingTo, author(target, in: conversation)))
                        .font(.display(13 * scale, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    Text(target.flatMap { model.messageWords($0) } ?? (target == nil ? TChat.text(.earlierMessage) : T.text(.messagesDeleted)))
                        .font(.display(13 * scale)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 8 * scale)
                Hint(keys: "esc / ○", label: T.text(.cancel))
                    .opacity(model.composing ? 0 : 1)
                Image(systemName: "xmark.circle.fill").font(.system(size: 16 * scale)).foregroundStyle(.white.opacity(0.45))
                    .onTapGesture { model.cancelReplyOrEdit() }
            }
            .padding(.leading, 14 * scale).padding(.trailing, 10 * scale).padding(.vertical, 9 * scale)
            .background(
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(0.06))
                    .overlay(alignment: .leading) { Capsule().fill(model.accent).frame(width: 3 * scale).padding(.vertical, 8 * scale) }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func author(_ message: TogetherMessage?, in conversation: TogetherConversation) -> String {
        guard let message else { return conversation.name(for: model.inbox?.me ?? "") }
        if message.authorId == model.inbox?.me { return TL.text(.compareYou) }
        return conversation.members.first { $0.userId == message.authorId }?.displayName ?? ""
    }
}

/// The message a reply answers, small above the reply's own bubble.
struct ReplyQuote: View {
    let quote: TogetherQuote
    let conversation: TogetherConversation
    let mine: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 8 * scale) {
            Capsule().fill(Color.white.opacity(0.35)).frame(width: 2.5 * scale)
            VStack(alignment: .leading, spacing: 1 * scale) {
                if case .message(let message) = quote {
                    Text(message.authorId == model.inbox?.me ? TL.text(.compareYou) : conversation.members.first { $0.userId == message.authorId }?.displayName ?? "")
                        .font(.display(11 * scale, .semibold)).foregroundStyle(.white.opacity(0.6))
                }
                Text(words).font(.display(13 * scale)).italic(quote != quoteMessage).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10 * scale).padding(.vertical, 6 * scale)
        .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var quoteMessage: TogetherQuote? {
        if case .message = quote { return quote }
        return nil
    }

    private var words: String {
        switch quote {
        case .message(let message): return model.messageWords(message) ?? ""
        case .removed: return T.text(.messagesDeleted)
        case .earlier: return TChat.text(.earlierMessage)
        }
    }
}

/// A message's reactions under its bubble: a glyph with how many gave it, the user's own lit;
/// clicking one gives it or takes it back.
struct ReactionChips: View {
    let message: TogetherMessage
    let conversation: TogetherConversation
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let me = model.inbox?.me ?? ""
        HStack(spacing: 6 * scale) {
            ForEach(message.reactions, id: \.reaction) { reaction in
                let mine = reaction.userIds.contains(me)
                HStack(spacing: 4 * scale) {
                    Text(reaction.reaction.glyph).font(reaction.reaction == .gg ? .display(11 * scale, .heavy) : .system(size: 13 * scale))
                    if reaction.count > 1 { Text("\(reaction.count)").font(.display(12 * scale, .semibold)).monospacedDigit() }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * scale).frame(minHeight: 24 * scale)
                .background(Capsule().fill(mine ? model.accent.opacity(0.45) : Color.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(mine ? model.accent : Color.white.opacity(0.08), lineWidth: 1))
                .contentShape(Capsule())
                .onTapGesture { model.toggleReaction(reaction.reaction, on: message) }
                .help(TChat.format(.reactedBy, TChat.name(reaction.reaction), names(reaction.userIds, me: me)))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(Motion.focus, value: message.reactions)
    }

    private func names(_ ids: [String], me: String) -> String {
        ids.map { id in id == me ? TL.text(.compareYou) : conversation.members.first { $0.userId == id }?.displayName ?? "?" }.joined(separator: ", ")
    }
}

/// Where the user's newest message has got, beside its time.
struct ReceiptLabel: View {
    let state: TogetherReceipt.State
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        let (text, symbol) = describe
        HStack(spacing: 4 * scale) {
            Image(systemName: symbol).font(.system(size: 10 * scale, weight: .bold))
            Text(text)
        }
        .foregroundStyle(lit ? AnyShapeStyle(model.accent) : AnyShapeStyle(Color.white.opacity(0.4)))
        .contentTransition(.opacity)
        .animation(Motion.focus, value: state)
    }

    private var lit: Bool {
        switch state {
        case .read: return true
        case .seen(_, let everyone): return everyone
        default: return false
        }
    }

    private var describe: (String, String) {
        switch state {
        case .sent: return (TChat.text(.receiptSent), "checkmark")
        case .delivered: return (TChat.text(.receiptDelivered), "checkmark.circle")
        case .read: return (TChat.text(.receiptRead), "checkmark.circle.fill")
        case .seen(_, true): return (TChat.text(.seenByEveryone), "eye.fill")
        case .seen(let count, _) where count > 0: return (TChat.format(.seenBy, count), "eye")
        case .seen: return (TChat.text(.receiptSent), "checkmark")
        }
    }
}
