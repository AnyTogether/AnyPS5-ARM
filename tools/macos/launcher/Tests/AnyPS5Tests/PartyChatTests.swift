@testable import AnyPS5
import AnyPS5Core
import XCTest

/// The party's chat on the party screen: its messages never reach the inbox's list, count or
/// banners; the thread's actions act on it there; someone who left keeps a name.
@MainActor
final class PartyChatTests: XCTestCase {
    let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
    let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
    let sol = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)

    func message(_ seq: Int, in conversation: String = "pc1", from author: String = "f1", text: String? = "hi") -> TogetherMessage {
        TogetherMessage(id: "m\(conversation)\(seq)", conversationId: conversation, seq: seq, authorId: author, text: text,
                        deletedAt: text == nil ? Date() : nil, createdAt: Date().addingTimeInterval(Double(seq - 100)))
    }

    func event(_ type: String, _ data: [String: Any]) throws -> TogetherSocket.Event {
        TogetherSocket.Event(id: UUID().uuidString, type: type, json: try JSONSerialization.data(withJSONObject: data))
    }

    func messageJSON(_ seq: Int, in conversation: String = "pc1", from author: String = "f1") -> [String: Any] {
        ["id": "m\(conversation)\(seq)", "conversationId": conversation, "seq": seq, "authorId": author, "text": "gg", "replyTo": NSNull(),
         "editedAt": NSNull(), "deletedAt": NSNull(), "createdAt": "2026-11-06T10:00:00.000Z"]
    }

    func model(chat: Bool = true) throws -> AppModel {
        let model = try LauncherFixture.model()
        model.togetherUser = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)
        let direct = TogetherConversation(id: "c1", kind: "direct", title: nil, members: [robin, mira], lastSeq: 3, readSeq: 1, unread: 2,
                                          lastMessage: message(3, in: "c1"), updatedAt: Date())
        model.inbox = TogetherInbox(me: "u1", conversations: [direct])
        model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [robin, mira, sol], invited: [], call: nil,
                                         conversationId: chat ? "pc1" : nil))
        model.previewPartyChat([message(1), message(2, from: "u1")])
        return model
    }

    func testAnOlderServersPartyHasNoChat() throws {
        let model = try model(chat: false)
        XCTAssertNil(model.partyChat)
        model.overlay = .party
        XCTAssertFalse(model.partyChatShown)
        XCTAssertNil(model.partyChatConversation)
        XCTAssertNil(model.chatConversation?.partyId, "the thread's actions stay Messages'")
    }

    /// A message of the party's chat goes to the chat alone: the inbox's count, its list and its
    /// banners stay as they were, and nothing makes the list be read again.
    func testItsMessagesNeverReachTheInbox() throws {
        let model = try model()
        let before = model.inbox
        model.messageEvent(try event("message.created", messageJSON(3)))
        XCTAssertEqual(model.partyChat?.messages?.map(\.seq), [1, 2, 3])
        XCTAssertEqual(model.inbox, before, "not counted, not listed")
        XCTAssertEqual(model.unreadMessages, 2)
        XCTAssertNil(model.toast, "no banner for it")
        XCTAssertEqual(model.partyChat?.unread, 1, "the party screen is not open")
        XCTAssertEqual(model.partyChatUnread, 1, "the party's button shows a dot")
        model.messageEvent(try event("message.reactions", ["conversationId": "pc1", "seq": 3, "reactions": [["reaction": "gg", "count": 1, "userIds": ["f2"]]]]))
        XCTAssertEqual(model.partyChat?.messages?.last?.reactions.map(\.reaction), [.gg])
        model.messageEvent(try event("conversation.updated", ["conversationId": "pc1"]))
        XCTAssertEqual(model.inbox, before)

        model.overlay = .party
        XCTAssertEqual(model.partyChatUnread, 0, "shown: no dot")
    }

    /// On the party screen the thread's actions act on the party's chat; in Messages on the
    /// conversation selected there, each with its own draft.
    func testTheThreadOnScreenIsThePartysChat() throws {
        let model = try model()
        model.messageDraft = "for Mira"
        model.overlay = .party
        XCTAssertTrue(model.partyChatShown)
        XCTAssertEqual(model.chatConversation?.id, "pc1")
        XCTAssertEqual(model.chatConversation?.partyId, "p1")
        XCTAssertEqual(model.chatDraft, "")
        model.chatDraft = "for the party"
        XCTAssertEqual(model.partyDraft, "for the party")
        XCTAssertEqual(model.messageDraft, "for Mira")
        XCTAssertEqual(model.openThread.map(\.seq), [1, 2])

        // Picked with the controller, a reply goes to the party's field.
        XCTAssertTrue(model.pickMessage(-1))
        XCTAssertEqual(model.messageActions.picked, 2)
        model.startReply(model.message(in: "pc1", seq: 1)!)
        XCTAssertEqual(model.messageActions.replyTo, 1)
        XCTAssertTrue(model.partyChatFocused)

        model.previewMessages(model.inbox!, index: 0, inThread: true)
        XCTAssertFalse(model.partyChatShown)
        XCTAssertEqual(model.chatConversation?.id, "c1")
        XCTAssertEqual(model.chatDraft, "for Mira")
    }

    func testSomeoneElsesMessageCanBeReportedForAReason() throws {
        let model = try model()
        model.overlay = .party
        let theirs = MessageActions.Menu(target: .message(conversation: "pc1", seq: 1))
        XCTAssertEqual(model.menuRows(theirs), [.reactions, .reply, .report])
        let mine = MessageActions.Menu(target: .message(conversation: "pc1", seq: 2))
        XCTAssertFalse(model.menuRows(mine).contains(.report), "not one's own")
        model.messageActions.menu = theirs
        model.askReport()
        guard let asked = model.messageActions.menu else { return XCTFail("the reasons are asked") }
        XCTAssertEqual(asked.target, .report(conversation: "pc1", seq: 1))
        XCTAssertEqual(model.menuRows(asked), TogetherReportReason.allCases.map(MessageActions.Row.reason) + [.cancel])
        model.menuCommand(.back)
        XCTAssertEqual(model.messageActions.menu?.target, .message(conversation: "pc1", seq: 1), "back to the message's menu")
    }

    /// Someone who left the party keeps the name it had in it this session; someone the launcher
    /// never saw in it is a former member.
    func testWhoWroteAfterTheyLeft() throws {
        let model = try model()
        model.previewParty(TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [robin, mira], invited: [], call: nil, conversationId: "pc1"))
        let conversation = try XCTUnwrap(model.partyChatConversation)
        XCTAssertEqual(model.authorName("f2", in: conversation), "Sol")
        XCTAssertEqual(model.authorName("f9", in: conversation), "Former member")
        XCTAssertEqual(model.authorName("f9", in: model.inbox!.conversations[0], unknown: "?"), "?", "not a party's chat: as before")
    }

    /// The controller: ← from the party's rows into the chat, → past its field back to them.
    func testTheControllerGoesIntoTheChatAndBack() throws {
        let model = try model()
        model.overlay = .party
        model.panelInRows = true
        model.panelRow = 0
        XCTAssertTrue(model.handle(.left))
        XCTAssertTrue(model.partyChatFocused)
        XCTAssertEqual(model.messageFocus, AppModel.quickReplies.count, "on the field")
        XCTAssertTrue(model.handle(.right))
        XCTAssertFalse(model.partyChatFocused)
        XCTAssertEqual(model.overlay, .party)

        // The party ended: no chat, the focus back on the rows.
        _ = model.handle(.left)
        model.previewParty(nil)
        XCTAssertNil(model.partyChat)
        XCTAssertFalse(model.partyChatFocused)
    }

    func testTheNewTextsAreInEnglishAndTurkish() {
        T.texts = T.load([T.sourceFolder])
        for key in [TChat.Key.partyChat, .partyChatPlaceholder, .partyChatEmpty, .formerMember, .report, .reportTitle, .reportLead, .reportSent] {
            XCTAssertNotEqual(T.string(key.rawValue), key.rawValue, key.rawValue)
        }
        XCTAssertEqual(TogetherReportReason.allCases.map(TChat.name).count, Set(TogetherReportReason.allCases.map(TChat.name)).count)
    }
}
