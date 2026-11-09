import AnyPS5Core
import SwiftUI

/// A message on its way or that did not get there, as on Windows and Linux: it shows dimmed as soon
/// as it is sent; if it does not get there it stays in its thread with a red edge, and Enter on the
/// empty field or a click on it tries again with the same id (the server keeps one message per id,
/// so a try that did get there is not sent twice).
struct UnsentMessage: Identifiable, Equatable {
    let id: UUID
    let conversationId: String
    let text: String
    let replyTo: Int?
    var sending = false
}

extension AppModel {
    /// The messages of a conversation on their way or that did not get there, oldest first. One
    /// the thread already has (the socket can bring it back before the answer) is not shown twice.
    func unsent(in conversationId: String) -> [UnsentMessage] {
        let bubbles = unsentMessages.filter { $0.conversationId == conversationId }
        guard bubbles.contains(where: \.sending), let thread = thread(of: conversationId) else { return bubbles }
        let arrived = Set(thread.suffix(100).map(\.id))
        return bubbles.filter { !$0.sending || !arrived.contains($0.id.uuidString.lowercased()) }
    }

    /// Those of the open conversation.
    var openUnsent: [UnsentMessage] { chatConversation.map { unsent(in: $0.id) } ?? [] }

    /// The number a picked message that did not get there goes by: below zero, so never a
    /// server's seq.
    static func unsentSeq(at index: Int) -> Int { -1 - index }

    /// Enter on the composer's empty field: the newest message that did not get there goes again.
    /// False when there is none to send.
    @discardableResult
    func retryNewestUnsent() -> Bool {
        guard chatDraft.isEmpty, messageActions.editing == nil, let message = openUnsent.last(where: { !$0.sending }) else { return false }
        retryMessage(message)
        return true
    }

    func retryMessage(_ message: UnsentMessage) {
        guard let conversation = conversation(withId: message.conversationId), !message.sending,
              let index = unsentMessages.firstIndex(where: { $0.id == message.id }) else { return }
        unsentMessages[index].sending = true
        Sounds.shared.play(.select)
        deliver(unsentMessages[index], in: conversation, raw: nil)
    }

    /// Sends a message, the first time (`raw`, the words as typed) or again (the bubble's own). It
    /// is off the thread once sent; if not, it stays with a red edge.
    func deliver(_ message: UnsentMessage, in conversation: TogetherConversation, raw: String?) {
        Task {
            do {
                try await deliverNow(message, in: conversation)
                withAnimation(Motion.focus) { unsentMessages.removeAll { $0.id == message.id } }
            } catch {
                undelivered(message, error, in: conversation, raw: raw)
            }
        }
    }

    private func deliverNow(_ message: UnsentMessage, in conversation: TogetherConversation) async throws {
        if sendsSealed(conversation) { return try await sendSealed(message, in: conversation) }
        do {
            let sent: TogetherMessage
            if let sendText {
                sent = try await sendText(message)
            } else {
                sent = try await together.send(message.text, in: conversation.id, replyTo: message.replyTo, id: message.id)
            }
            withAnimation(Motion.focus) { storeMessage(sent) }
            if conversation.partyId == nil { keepSelection(conversation.id) }
        } catch let problem as TogetherProblem where problem.code == "e2ee_required" {
            // Encrypted on the server's side (both people have a device): sealed instead.
            await e2eeRequired(conversation)
            try await sendSealed(message, in: conversation)
        }
    }

    /// End-to-end encrypted: sealed on this Mac under the bubble's own id, never plain.
    private func sendSealed(_ message: UnsentMessage, in conversation: TogetherConversation) async throws {
        let sent = try await sealAndSend(TogetherE2EE.Payload(text: message.text), in: conversation, replyTo: message.replyTo, id: message.id)
        withAnimation(Motion.focus) { _ = inbox?.apply(sent, open: conversation.id) }
        keepSelection(conversation.id)
    }

    /// Nobody on the other side can read it: its words go back to the field when it was just
    /// typed, nothing is kept to resend. Anything else: the toast and a bubble to try again.
    private func undelivered(_ message: UnsentMessage, _ error: Error, in conversation: TogetherConversation, raw: String?) {
        if case E2EERefusal.noDevice = error, let raw {
            withAnimation(Motion.focus) { unsentMessages.removeAll { $0.id == message.id } }
            showSealedFailure(error, in: conversation)
            if messageActions.replyTo == nil, chatConversation?.id == conversation.id {
                messageActions.replyTo = message.replyTo
                if chatDraft.isEmpty, !AppModel.quickReplies.contains(raw) { chatDraft = raw }
            }
            return
        }
        var failed = message
        failed.sending = false
        withAnimation(Motion.focus) {
            if let index = unsentMessages.firstIndex(where: { $0.id == message.id }) { unsentMessages[index] = failed } else { unsentMessages.append(failed) }
        }
        if error is E2EERefusal {
            showSealedFailure(error, in: conversation)
        } else if let problem = error as? TogetherProblem, problem.code == "link_blocked" {
            show(T.text(.togetherLinkBlocked), symbol: "link.badge.plus")
        } else {
            show(sendRefusal(error), symbol: "exclamationmark.bubble.fill")
        }
    }
}

/// The bubble of a message on its way, dimmed, or one that did not get there: the user's words on
/// a red edge and how to send it again.
struct UnsentBubble: View {
    let message: UnsentMessage
    let focused: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    private let red = Color(red: 1, green: 0.42, blue: 0.4)

    var body: some View {
        HStack {
            Spacer(minLength: 120 * scale)
            VStack(alignment: .trailing, spacing: 4 * scale) {
                Button { model.retryMessage(message) } label: {
                    Text(message.text)
                        .font(.display(16 * scale))
                        .foregroundStyle(.white.opacity(message.sending ? 0.7 : 1))
                        .padding(.horizontal, 14 * scale)
                        .padding(.vertical, 9 * scale)
                        .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(model.accent.opacity(message.sending ? 0.45 : 0.85)))
                        .overlay {
                            if !message.sending {
                                RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(red, lineWidth: 1.5 * scale)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(message.sending)
                .focusRing(focused, radius: 18 * scale, width: 2)
                if !message.sending {
                    Text(TChat.text(.retry))
                        .font(.display(11 * scale, .medium))
                        .foregroundStyle(red)
                }
            }
        }
        .id(message.id)
    }
}
