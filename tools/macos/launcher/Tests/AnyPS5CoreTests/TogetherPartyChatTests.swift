import XCTest
@testable import AnyPS5Core

/// The party's chat: a group conversation tied to the party, read beside its voice and kept out
/// of the inbox's list and unread count.
final class TogetherPartyChatTests: TogetherSignedInCase {
    typealias M = TogetherMessagesTests
    typealias P = TogetherPartyTests

    static func chatMessage(_ seq: Int, from author: String = "f1", text: String? = "hi") -> TogetherMessage {
        M.decoded(M.message(seq, in: "pc1", from: author, text: text))
    }

    static let robin = TogetherPerson(userId: "u1", handle: "robin", displayName: "Robin", avatar: nil)
    static let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)
    static let sol = TogetherPerson(userId: "f2", handle: "sol", displayName: "Sol", avatar: nil)

    // MARK: Decoding

    func testThePartySaysItsChatAndAnOlderServerDoesNot() {
        var json = P.party(members: [P.member("u1", "Utku"), P.member("f1", "Ayşe")])
        let older: TogetherParty = M.decoded(json)
        XCTAssertNil(older.conversationId, "an older server, or someone outside the party: no chat")
        json["conversationId"] = "pc1"
        let party: TogetherParty = M.decoded(json)
        XCTAssertEqual(party.conversationId, "pc1")
        XCTAssertEqual(party.with(members: [], call: nil).conversationId, "pc1", "kept when the party changes here")
        XCTAssertEqual(party.with(joinCode: nil).conversationId, "pc1")

        var conversation = TogetherChatTests.conversation("pc1", kind: "group")
        XCTAssertNil((M.decoded(conversation) as TogetherConversation).partyId)
        conversation["partyId"] = "p1"
        XCTAssertEqual((M.decoded(conversation) as TogetherConversation).partyId, "p1")
    }

    // MARK: Calls

    func testTheHistoryNewestFirstOlderAndAfterAReconnect() async throws {
        FakeTogether.handler = { _, _ in (200, ["messages": [M.message(3, in: "pc1"), M.message(4, in: "pc1")], "more": true]) }
        let page = try await client.messages(in: "pc1", limit: TogetherPartyChat.page)
        XCTAssertEqual(last(), "GET /api/v1/conversations/pc1/messages?limit=40")
        XCTAssertEqual(page.messages.map(\.seq), [3, 4])
        XCTAssertTrue(page.more)
        _ = try await client.messages(in: "pc1", before: 3, limit: 40)
        XCTAssertEqual(last(), "GET /api/v1/conversations/pc1/messages?limit=40&before=3")
        _ = try await client.messages(in: "pc1", after: 4, limit: 40)
        XCTAssertEqual(last(), "GET /api/v1/conversations/pc1/messages?limit=40&after=4")
    }

    func testAPartyChatAsTheMessagesRoutesTakeIt() async throws {
        FakeTogether.handler = { _, _ in (201, M.message(5, in: "pc1", from: "u1")) }
        let sent = try await client.send("hi all", in: "pc1", replyTo: 4)
        XCTAssertEqual(last(), "POST /api/v1/conversations/pc1/messages")
        XCTAssertEqual(body()?["text"] as? String, "hi all")
        XCTAssertEqual(body()?["replyTo"] as? Int, 4)
        XCTAssertNotNil(body()?["clientId"] as? String)
        XCTAssertNil(body()?["attachments"], "text only")
        XCTAssertEqual(sent.conversationId, "pc1")

        FakeTogether.handler = { _, _ in (429, ["code": "rate_limited", "status": 429, "title": "Slow down"]) }
        do {
            _ = try await client.send("again", in: "pc1")
            XCTFail("the message limit answers 429")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "rate_limited")
        }
        FakeTogether.handler = { _, _ in (403, ["code": "account_muted", "status": 403, "title": "This account is muted for now"]) }
        do {
            _ = try await client.send("again", in: "pc1")
            XCTFail("a muted account is refused")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "account_muted")
        }
    }

    // MARK: The inbox leaves it out

    /// The party's chat is never in the list: its messages count nowhere and do not make the
    /// list be read again and again.
    func testTheInboxDoesNotAskForAConversationItsListLacksTwice() async throws {
        FakeTogether.handler = { _, _ in (200, ["conversations": [M.conversation(), TogetherChatTests.conversation("pc1", kind: "group", extra: ["partyId": "p1"])]]) }
        let list = try await client.conversations()
        XCTAssertEqual(list.map(\.id), ["c1"], "a party's chat belongs to the party screen, even from a server that lists it")

        var inbox = TogetherInbox(me: "u1", conversations: list)
        let party = Self.chatMessage(9)
        XCTAssertFalse(inbox.apply(party, open: nil))
        XCTAssertEqual(inbox.unread, 2, "not counted")
        XCTAssertTrue(inbox.needsList(for: "pc1"), "unknown: maybe a new conversation, the list is read again")
        inbox.listed(list, expecting: "pc1")
        XCTAssertFalse(inbox.needsList(for: "pc1"), "the list read again still lacks it: not asked for again")
        XCTAssertTrue(inbox.needsList(for: "c9"))
        XCTAssertFalse(inbox.needsList(for: "c1"), "listed already")

        // A list read again carries what it knows not to ask for.
        var next = TogetherInbox(me: "u1", conversations: list)
        next.carry(from: inbox)
        XCTAssertFalse(next.needsList(for: "pc1"))
        // One that does turn up in a later list is a conversation like any other.
        next.listed(list, expecting: "c9")
        XCTAssertFalse(next.needsList(for: "c9"))
        var later = TogetherInbox(me: "u1", conversations: list + [M.decoded(TogetherChatTests.conversation("c9"))])
        later.carry(from: next)
        later.listed(later.conversations, expecting: "c9")
        XCTAssertFalse(later.needsList(for: "c9"))
        XCTAssertTrue(later.apply(M.decoded(M.message(6, in: "c9")), open: nil))
        XCTAssertFalse(later.needsList(for: "pc1"), "the party's chat stays left out")
    }

    // MARK: The chat itself

    func testHistoryThenWhatTheSocketSays() {
        var chat = TogetherPartyChat(id: "pc1", partyId: "p1")
        XCTAssertNil(chat.messages, "not read yet")
        // A message comes over the socket while the history is on its way: both are kept.
        XCTAssertTrue(chat.apply(Self.chatMessage(5), me: "u1", open: true))
        chat.loaded([Self.chatMessage(3), Self.chatMessage(4, from: "u1")], more: true)
        XCTAssertEqual(chat.messages?.map(\.seq), [3, 4, 5])
        XCTAssertTrue(chat.more)
        XCTAssertEqual(chat.unread, 0, "a new member has nothing unread")

        // Edited and unsent ones keep their place.
        XCTAssertFalse(chat.apply(Self.chatMessage(4, from: "u1", text: "fixed"), me: "u1", open: true))
        XCTAssertEqual(chat.messages?.first { $0.seq == 4 }?.text, "fixed")
        XCTAssertFalse(chat.apply(Self.chatMessage(3, text: nil), me: "u1", open: true))
        XCTAssertNotNil(chat.messages?.first { $0.seq == 3 }?.deletedAt)
        // One older than the history read, while older ones are there: not shown alone at the top.
        XCTAssertFalse(chat.apply(Self.chatMessage(1, text: nil), me: "u1", open: true))
        XCTAssertEqual(chat.messages?.map(\.seq), [3, 4, 5])
        // Another conversation's message is not this chat's.
        XCTAssertFalse(chat.apply(M.decoded(M.message(6, in: "c1")), me: "u1", open: true))
        XCTAssertEqual(chat.newestSeq, 5)

        chat.react(4, reactions: [TogetherReactionCount(reaction: .gg, count: 1, userIds: ["f1"])])
        XCTAssertEqual(chat.messages?.first { $0.seq == 4 }?.reactions.map(\.reaction), [.gg])
    }

    /// Older pages above the newest 40: one at a time, stopping at the first message.
    func testOlderPages() {
        var chat = TogetherPartyChat(id: "pc1", partyId: "p1")
        XCTAssertNil(chat.startOlder(), "nothing read yet")
        chat.loaded([Self.chatMessage(50), Self.chatMessage(51)], more: true)
        XCTAssertEqual(chat.startOlder(), 50, "before the oldest one read")
        XCTAssertNil(chat.startOlder(), "one page at a time")
        chat.olderFailed()
        XCTAssertEqual(chat.startOlder(), 50, "a failed read can be tried again")
        chat.loadedOlder([Self.chatMessage(48), Self.chatMessage(49)], more: true)
        XCTAssertEqual(chat.messages?.map(\.seq), [48, 49, 50, 51])
        XCTAssertEqual(chat.startOlder(), 48)
        chat.loadedOlder([Self.chatMessage(47)], more: false)
        XCTAssertEqual(chat.messages?.first?.seq, 47)
        XCTAssertNil(chat.startOlder(), "the start of the chat")
    }

    /// Shown beside the voice, it is read to its end; others' messages that came while it was not
    /// shown are unread until it is again.
    func testReadToTheEndWhileShown() {
        var chat = TogetherPartyChat(id: "pc1", partyId: "p1")
        chat.loaded([Self.chatMessage(1), Self.chatMessage(2)], more: false)
        XCTAssertEqual(chat.readToEnd(), 2, "the newest one told to the server")
        XCTAssertNil(chat.readToEnd(), "told already")
        chat.apply(Self.chatMessage(3), me: "u1", open: false)
        chat.apply(Self.chatMessage(4, from: "u1"), me: "u1", open: false)
        chat.apply(Self.chatMessage(5, text: nil), me: "u1", open: false)
        XCTAssertEqual(chat.unread, 1, "not the user's own, not an unsent one")
        chat.apply(Self.chatMessage(6), me: "u1", open: false)
        XCTAssertEqual(chat.unread, 2)
        chat.apply(Self.chatMessage(6, text: nil), me: "u1", open: false)
        XCTAssertEqual(chat.unread, 1, "unsent before it was read")
        chat.apply(Self.chatMessage(7), me: "u1", open: true)
        XCTAssertEqual(chat.unread, 1, "on screen: not unread")
        XCTAssertEqual(chat.readToEnd(), 7)
        XCTAssertEqual(chat.unread, 0)
    }

    /// Someone who left keeps the name the launcher saw them with in the party; someone it never
    /// saw there is a former member (nil here).
    func testWhoWroteAMessageAfterTheyLeft() {
        var chat = TogetherPartyChat(id: "pc1", partyId: "p1")
        chat.saw([Self.robin, Self.mira, Self.sol])
        let party = TogetherParty(id: "p1", leaderId: "u1", privacy: "invite", members: [Self.robin, Self.mira], invited: [], call: nil, conversationId: "pc1")
        XCTAssertEqual(chat.name(of: "f1", members: party.members), "Mira")
        XCTAssertEqual(chat.name(of: "f2", members: party.members), "Sol", "left the party, seen in it this session")
        XCTAssertNil(chat.name(of: "f9", members: party.members), "never seen: a former member")
        XCTAssertNil(chat.name(of: nil, members: party.members))

        chat.loaded([Self.chatMessage(1, from: "f2"), Self.chatMessage(2)], more: false)
        let conversation = chat.conversation(for: party)
        XCTAssertEqual(conversation.id, "pc1")
        XCTAssertEqual(conversation.kind, "group")
        XCTAssertEqual(conversation.partyId, "p1")
        XCTAssertEqual(conversation.members.map(\.userId), ["u1", "f1", "f2"], "the party, then those seen in it who left")
        XCTAssertEqual(conversation.lastSeq, 2)
        XCTAssertNil(conversation.receipts, "no receipts beside the voice")
    }
}
