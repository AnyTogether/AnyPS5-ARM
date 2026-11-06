import AnyPS5Core
import AppKit
import SwiftUI

/// Reactions, replies, receipts, the message and conversation menus, and pinned and muted
/// conversations drawn offscreen for `--render-preview`, with made-up friends.
@MainActor
enum ChatPreviews {
    static func run(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let ago = { (minutes: Double) in Date().addingTimeInterval(-minutes * 60) }
        let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
        let sol = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)
        let lines: [(String, String, Int?)] = [("f1", "Are you still on the Silksong boss?", nil), ("u1", "Yes, third try. The second phase is brutal", nil),
                                               ("f1", "Dash through the spikes, not over them", nil), ("u1", "Oh! Trying that now", 3), ("f1", "GG when you get it 🏆", nil),
                                               ("u1", "Got it!", nil)]
        var thread = lines.enumerated().map { index, line in
            TogetherMessage(id: "m\(index)", conversationId: "c1", seq: index + 1, authorId: line.0, text: line.1, replyTo: line.2, createdAt: ago(Double(lines.count - index) * 2))
        }
        thread[2].reactions = [TogetherReactionCount(reaction: .fire, count: 2, userIds: ["u1", "f1"]), TogetherReactionCount(reaction: .love, count: 1, userIds: ["u1"])]
        thread[4].reactions = [TogetherReactionCount(reaction: .gg, count: 1, userIds: ["u1"])]
        thread.insert(TogetherMessage(id: "m-gone", conversationId: "c1", seq: 0, authorId: "f1", text: nil, deletedAt: ago(20), createdAt: ago(30)), at: 0)
        let receipts = [TogetherReceipt(userId: "f1", readSeq: 6, deliveredSeq: 6)]
        var inbox = TogetherInbox(me: "u1", conversations: [
            TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, mira], lastSeq: 6, readSeq: 6, unread: 0, lastMessage: thread.last, updatedAt: ago(2),
                                 pinned: true, receipts: receipts),
            TogetherConversation(id: "c3", kind: "group", title: "Souls club", members: [robin, mira, sol], lastSeq: 40, readSeq: 37, unread: 3,
                                 lastMessage: TogetherMessage(id: "g40", conversationId: "c3", seq: 40, authorId: "f2", text: "Who has the platinum?", createdAt: ago(30)), updatedAt: ago(30),
                                 pinned: true, muted: true, receipts: [TogetherReceipt(userId: "f1", readSeq: 40, deliveredSeq: nil), TogetherReceipt(userId: "f2", readSeq: 39, deliveredSeq: nil)]),
            TogetherConversation(id: "c2", kind: "direct", title: nil, members: [robin, sol], lastSeq: 3, readSeq: 1, unread: 2,
                                 lastMessage: TogetherMessage(id: "k3", conversationId: "c2", seq: 3, authorId: "f2", text: "Party tonight?", createdAt: ago(180)), updatedAt: ago(180)),
        ])
        inbox.threads["c1"] = thread
        let render = { (name: String, configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.togetherFriends = [TogetherFriend(userId: "f5", handle: "theo", displayName: "Theo", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil))]
                model.previewMessages(inbox, index: 0, inThread: true)
                configure(model)
            }
        }
        render("chat-thread") { _ in }
        render("chat-picked") { model in model.messageActions.picked = 3 }
        render("chat-menu") { model in
            model.messageActions.picked = 6
            model.messageActions.menu = .init(target: .message(conversation: "c1", seq: 6), row: 0, column: 1)
        }
        render("chat-menu-theirs") { model in
            model.messageActions.picked = 5
            model.messageActions.menu = .init(target: .message(conversation: "c1", seq: 5), row: 1)
        }
        render("chat-unsend") { model in
            model.messageActions.picked = 6
            model.messageActions.menu = .init(target: .unsend(conversation: "c1", seq: 6), row: 1)
        }
        render("chat-reply") { model in
            model.messageActions.replyTo = 5
            model.messageDraft = "On my way to the next one"
        }
        render("chat-edit") { model in
            model.messageActions.editing = 6
            model.messageDraft = "Got it! First try after the tip"
        }
        render("chat-list") { model in
            model.messagesInThread = false
            model.messagesIndex = 1
        }
        render("chat-conversation-menu") { model in
            model.messagesInThread = false
            model.messagesIndex = 1
            model.messageActions.menu = .init(target: .conversation("c3"), row: 1)
        }
        partyChat(preferences, found, root, still, output)
        render("chat-settings") { model in
            model.togetherProfile = TogetherOwnProfile(handle: "robin", displayName: "Robin", bio: nil, avatar: nil, country: "TR", handleChangeAt: nil, privacy: .standard, readReceipts: false)
            model.overlay = .settings
            model.panelCategory = model.panelCategories().firstIndex { $0.id == "together" } ?? 0
            model.panelInRows = true
            model.panelRow = model.panelCategories()[model.panelCategory].rows.firstIndex { $0.id == "privacy-read-receipts" } ?? 0
        }
    }

    /// The party screen with its chat beside the voice: a lively one (Kenji left, Ana was never
    /// seen in the party here), an empty one, the chat focused with a reply and someone typing,
    /// a message's menu and the reasons to report it; the party's button with something unread.
    static func partyChat(_ preferences: Preferences, _ found: [Game], _ root: URL, _ still: NSImage?, _ output: URL) {
        let ago = { (minutes: Double) in Date().addingTimeInterval(-minutes * 60) }
        let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
        let sol = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)
        let kenji = TogetherPerson(userId: "f3", handle: "kenji", displayName: "Kenji", avatar: nil)
        let lines: [(String, String, Int?)] = [("f9", "Anyone up for the raid later?", nil), ("f3", "I'm out for tonight, have fun", nil),
                                               ("f1", "Boss is at 20%, keep the adds off me", nil), ("f2", "On it. Rezzing in 3", nil),
                                               ("u1", "Swap to fire, it's weak to it", 3), ("f1", "GG!! First clear 🔥", nil)]
        var thread = lines.enumerated().map { index, line in
            TogetherMessage(id: "p\(index)", conversationId: "pc1", seq: index + 1, authorId: line.0, text: line.1, replyTo: line.2, createdAt: ago(Double(lines.count - index) * 3))
        }
        thread[4].reactions = [TogetherReactionCount(reaction: .fire, count: 2, userIds: ["f1", "f2"])]
        thread[5].reactions = [TogetherReactionCount(reaction: .gg, count: 3, userIds: ["u1", "f2", "f1"])]
        let party = TogetherParty(id: "p1", leaderId: "u1", privacy: "friends", members: [robin, mira, sol], invited: [],
                                  call: .init(id: "call1", in: ["u1", "f1", "f2"]), conversationId: "pc1")
        let friends = [TogetherFriend(userId: "f5", handle: "theo", displayName: "Theo", avatar: nil, presence: .init(state: "online", titleId: nil, since: nil))]
        let render = { (name: String, messages: [TogetherMessage], configure: (AppModel) -> Void) in
            PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("\(name).png")) { model in
                model.togetherUser = SocialPreviews.me
                model.togetherFriends = friends
                model.previewParty(party)
                model.previewPartyChat(messages, seen: [kenji])
                model.previewVoice(call: "call1", speaking: ["f1"])
                model.overlay = .party; model.panelInRows = true; model.panelRow = 0
                configure(model)
            }
        }
        render("party-chat", thread) { _ in }
        render("party-chat-empty", []) { model in model.previewVoice(call: "call1", speaking: []) }
        render("party-chat-focused", thread) { model in
            model.partyChatFocused = true
            model.messageActions.replyTo = 6
            model.partyDraft = "Next one at 9?"
            model.typing.typing("f2", in: "pc1")
        }
        render("party-chat-picked", thread) { model in
            model.partyChatFocused = true
            model.messageActions.picked = 4
        }
        render("party-chat-menu", thread) { model in
            model.partyChatFocused = true
            model.messageActions.picked = 4
            model.messageActions.menu = .init(target: .message(conversation: "pc1", seq: 4), row: 2)
        }
        render("party-chat-report", thread) { model in
            model.partyChatFocused = true
            model.messageActions.picked = 4
            model.messageActions.menu = .init(target: .report(conversation: "pc1", seq: 4), row: 1)
        }
        PreviewRenderer.render(preferences, found, root, still, output.appendingPathComponent("home-party-unread.png")) { model in
            model.togetherUser = SocialPreviews.me
            model.previewParty(party)
            model.previewPartyChat(Array(thread.prefix(4)))
            model.partyChat?.apply(thread[5], me: "u1", open: false)
            model.focus = .top(4)
        }
    }
}
