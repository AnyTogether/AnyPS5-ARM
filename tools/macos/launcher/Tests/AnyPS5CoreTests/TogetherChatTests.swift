import XCTest
@testable import AnyPS5Core

/// Reactions, replies, editing and unsending, receipts, pinned and muted conversations, and the
/// read receipts setting.
final class TogetherChatTests: TogetherSignedInCase {
    typealias M = TogetherMessagesTests

    static func message(_ seq: Int, in conversation: String = "c1", from author: String = "f1", text: String? = "hi", extra: [String: Any] = [:]) -> [String: Any] {
        M.message(seq, in: conversation, from: author, text: text).merging(extra) { $1 }
    }

    static func conversation(_ id: String = "c1", kind: String = "direct", unread: Int = 0, last: Int = 5, extra: [String: Any] = [:]) -> [String: Any] {
        var conversation = M.conversation(id, unread: unread, last: last)
        conversation["kind"] = kind
        if kind == "group" {
            conversation["members"] = [["userId": "u1", "handle": "utku", "displayName": "Utku", "avatar": NSNull()], ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull()],
                                       ["userId": "f2", "handle": "kaan", "displayName": "Kaan", "avatar": NSNull()]]
        }
        return conversation.merging(extra) { $1 }
    }

    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)!
    }

    static func receipt(_ user: String, read: Int?, delivered: Int?) -> [String: Any] {
        ["userId": user, "readSeq": read ?? NSNull(), "deliveredSeq": delivered ?? NSNull()]
    }

    // MARK: Decoding

    func testTheNewFieldsAndAnOlderServerWithoutThem() {
        let reacted: TogetherMessage = M.decoded(Self.message(4, extra: ["editCount": 2, "reactions": [
            ["reaction": "love", "count": 2, "userIds": ["u1", "f1"]], ["reaction": "party", "count": 1, "userIds": ["f1"]], ["reaction": "gg", "count": 1, "userIds": ["f1"]],
        ]]))
        XCTAssertEqual(reacted.editCount, 2)
        XCTAssertEqual(reacted.reactions.map(\.reaction), [.love, .gg], "a reaction this launcher does not know is left out")
        XCTAssertEqual(reacted.reactions.first?.count, 2)
        XCTAssertTrue(reacted.hasReacted(.love, by: "u1"))
        XCTAssertFalse(reacted.hasReacted(.gg, by: "u1"))
        let old: TogetherMessage = M.decoded(M.message(4))
        XCTAssertEqual(old.editCount, 0)
        XCTAssertEqual(old.reactions, [])

        let marked: TogetherConversation = M.decoded(Self.conversation(extra: ["pinned": true, "muted": true, "receipts": [Self.receipt("f1", read: 3, delivered: 5)]]))
        XCTAssertTrue(marked.pinned)
        XCTAssertTrue(marked.muted)
        XCTAssertEqual(marked.receipts, [TogetherReceipt(userId: "f1", readSeq: 3, deliveredSeq: 5)])
        let older: TogetherConversation = M.decoded(M.conversation())
        XCTAssertFalse(older.pinned)
        XCTAssertFalse(older.muted)
        XCTAssertNil(older.receipts, "no receipts from an older server: none are shown")
    }

    func testTheGlyphsInTheirOrder() {
        XCTAssertEqual(TogetherMessageReaction.allCases.map(\.rawValue), ["like", "love", "laugh", "wow", "sad", "fire", "gg"])
        XCTAssertEqual(TogetherMessageReaction.allCases.map(\.glyph), ["👍", "❤️", "😂", "😮", "😢", "🔥", "GG"])
    }

    // MARK: Calls

    func testAReplyNamesTheMessageItQuotes() async throws {
        FakeTogether.handler = { _, _ in (201, Self.message(7, from: "u1", text: "yes", extra: ["replyTo": 4])) }
        let sent = try await client.send("yes", in: "c1", replyTo: 4)
        XCTAssertEqual(last(), "POST /api/v1/conversations/c1/messages")
        XCTAssertEqual(body()?["replyTo"] as? Int, 4)
        XCTAssertEqual(body()?["text"] as? String, "yes")
        XCTAssertEqual(sent.replyTo, 4)
        _ = try await client.send("no", in: "c1")
        XCTAssertNil(body()?["replyTo"], "not a reply: no replyTo")
    }

    func testEditingAndUnsending() async throws {
        FakeTogether.handler = { _, _ in (200, Self.message(6, from: "u1", text: "fixed", extra: ["editCount": 1, "editedAt": "2026-10-24T10:01:00.000Z"])) }
        let edited = try await client.edit(6, in: "c1", to: "fixed")
        XCTAssertEqual(last(), "PATCH /api/v1/conversations/c1/messages/6")
        XCTAssertEqual(body()?["text"] as? String, "fixed")
        XCTAssertEqual(edited.editCount, 1)
        XCTAssertNotNil(edited.editedAt)

        FakeTogether.handler = { _, _ in (409, ["code": "edit_limit", "status": 409, "title": "Edited too often"]) }
        do {
            _ = try await client.edit(6, in: "c1", to: "again")
            XCTFail("the 21st edit is refused")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "edit_limit")
        }

        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.unsend(6, in: "c1")
        XCTAssertEqual(last(), "DELETE /api/v1/conversations/c1/messages/6")
    }

    func testAReactionIsAddedAndTakenBack() async throws {
        FakeTogether.handler = { _, _ in (200, ["conversationId": "c1", "seq": 4, "reactions": [["reaction": "fire", "count": 1, "userIds": ["u1"]]]]) }
        let added = try await client.react(.fire, to: 4, in: "c1", on: true)
        XCTAssertEqual(last(), "PUT /api/v1/conversations/c1/messages/4/reactions/fire")
        XCTAssertEqual(added, [TogetherReactionCount(reaction: .fire, count: 1, userIds: ["u1"])])
        FakeTogether.handler = { _, _ in (200, ["conversationId": "c1", "seq": 4, "reactions": []]) }
        let taken = try await client.react(.fire, to: 4, in: "c1", on: false)
        XCTAssertEqual(last(), "DELETE /api/v1/conversations/c1/messages/4/reactions/fire")
        XCTAssertEqual(taken, [])
    }

    func testDeliveredPinAndMute() async throws {
        FakeTogether.handler = { _, _ in (204, [:]) }
        try await client.markDelivered("c1", upTo: 9)
        XCTAssertEqual(last(), "POST /api/v1/conversations/c1/delivered")
        XCTAssertEqual(body()?["upToSeq"] as? Int, 9)

        FakeTogether.handler = { _, _ in (200, Self.conversation(extra: ["pinned": true])) }
        let pinned = try await client.pin("c1", true)
        XCTAssertEqual(last(), "PUT /api/v1/conversations/c1/pin")
        XCTAssertEqual(body()?["pinned"] as? Bool, true)
        XCTAssertTrue(pinned.pinned)

        FakeTogether.handler = { _, _ in (409, ["code": "full", "status": 409, "title": "Five are pinned"]) }
        do {
            _ = try await client.pin("c2", true)
            XCTFail("a sixth pin is refused")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "full")
        }

        FakeTogether.handler = { _, _ in (200, Self.conversation(extra: ["muted": true])) }
        let muted = try await client.mute("c1", true)
        XCTAssertEqual(last(), "PUT /api/v1/conversations/c1/mute")
        XCTAssertEqual(body()?["muted"] as? Bool, true)
        XCTAssertTrue(muted.muted)
    }

    func testTheReadReceiptsSetting() async throws {
        var own = TogetherAccountTests.own()
        FakeTogether.handler = { [own] _, _ in (200, ["account": ["id": "u1", "email": "u@example.com", "createdAt": "2026-10-01T10:00:00.000Z"], "profile": own]) }
        let standard = try await client.myProfile()
        XCTAssertTrue(standard.readReceipts, "on unless turned off (and from an older server)")
        own["readReceipts"] = false
        FakeTogether.handler = { [own] _, _ in (200, ["account": ["id": "u1", "email": "u@example.com", "createdAt": "2026-10-01T10:00:00.000Z"], "profile": own]) }
        let off = try await client.myProfile()
        XCTAssertFalse(off.readReceipts)

        FakeTogether.handler = { _, _ in (200, ["readReceipts": false]) }
        let kept = try await client.setReadReceipts(false)
        XCTAssertEqual(last(), "PATCH /api/v1/me/read-receipts")
        XCTAssertEqual(body()?["readReceipts"] as? Bool, false)
        XCTAssertFalse(kept)
    }

    // MARK: The inbox

    func testReactionsReachTheThreadAndTheList() {
        var inbox = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation(last: 5))])
        inbox.threads["c1"] = [M.decoded(Self.message(4)), M.decoded(Self.message(5))]
        let love = [TogetherReactionCount(reaction: .love, count: 1, userIds: ["f1"])]
        inbox.react("c1", seq: 5, reactions: love)
        XCTAssertEqual(inbox.threads["c1"]?.last?.reactions, love)
        XCTAssertEqual(inbox.threads["c1"]?.first?.reactions, [])
        XCTAssertEqual(inbox.conversations[0].lastMessage?.reactions, love)
        inbox.react("c9", seq: 5, reactions: [])
        XCTAssertEqual(inbox.threads["c1"]?.last?.reactions, love, "another conversation's event changes nothing here")
    }

    func testDeliveredAndReadMarksFromTheOthersAndFromMe() {
        var inbox = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation(unread: 2, last: 8, extra: ["receipts": [Self.receipt("f1", read: 2, delivered: 4)]]))])
        inbox.delivered("c1", by: "f1", upTo: 6)
        XCTAssertEqual(inbox.conversations[0].receipts, [TogetherReceipt(userId: "f1", readSeq: 2, deliveredSeq: 6)])
        inbox.delivered("c1", by: "f1", upTo: 3)
        XCTAssertEqual(inbox.conversations[0].receipts?.first?.deliveredSeq, 6, "never lowered")
        inbox.read("c1", by: "f1", upTo: 7)
        XCTAssertEqual(inbox.conversations[0].receipts, [TogetherReceipt(userId: "f1", readSeq: 7, deliveredSeq: 7)], "read is delivered too")
        XCTAssertEqual(inbox.conversations[0].unread, 2, "someone else reading leaves the user's count")
        XCTAssertEqual(inbox.conversations[0].readSeq, 6)

        inbox.read("c1", by: "u1", upTo: 7, unread: 1)
        XCTAssertEqual(inbox.conversations[0].readSeq, 7)
        XCTAssertEqual(inbox.conversations[0].unread, 1, "the server's count")
        inbox.read("c1", by: "u1", upTo: 8)
        XCTAssertEqual(inbox.conversations[0].unread, 0, "an older server: worked out")

        var group = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation("g1", kind: "group", extra: ["receipts": [Self.receipt("f1", read: nil, delivered: nil)]]))])
        group.read("g1", by: "f1", upTo: 4)
        XCTAssertEqual(group.conversations[0].receipts, [TogetherReceipt(userId: "f1", readSeq: 4, deliveredSeq: nil)], "a group has no delivered marks")
        var old = TogetherInbox(me: "u1", conversations: [M.decoded(M.conversation())])
        old.read("c1", by: "f1", upTo: 4)
        old.delivered("c1", by: "f1", upTo: 4)
        XCTAssertNil(old.conversations[0].receipts)
    }

    /// The server counts what is unread; a new message from someone else adds one to it, and an
    /// unread one unsent takes it back (or, when the thread is not loaded, asks for the list).
    func testUnreadFollowsNewAndUnsentMessages() {
        var inbox = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation(unread: 1, last: 5)), M.decoded(Self.conversation("c2", unread: 1, last: 3))])
        inbox.conversations[0].unread = 1
        XCTAssertTrue(inbox.apply(M.decoded(Self.message(6)), open: nil))
        XCTAssertEqual(inbox.conversations.first { $0.id == "c1" }?.unread, 2)
        inbox.threads["c1"] = [M.decoded(Self.message(5)), M.decoded(Self.message(6))]
        XCTAssertTrue(inbox.apply(M.decoded(Self.message(6, text: nil)), open: nil))
        XCTAssertEqual(inbox.conversations.first { $0.id == "c1" }?.unread, 1, "the unsent message is not unread any more")
        XCTAssertTrue(inbox.apply(M.decoded(Self.message(6, text: nil)), open: nil))
        XCTAssertEqual(inbox.conversations.first { $0.id == "c1" }?.unread, 1, "a repeat takes nothing more")
        XCTAssertEqual(inbox.threads["c1"]?.last?.deletedAt != nil, true)

        XCTAssertFalse(inbox.apply(M.decoded(Self.message(3, in: "c2", text: nil)), open: nil), "not loaded: read the list again")
        XCTAssertEqual(inbox.conversations.first { $0.id == "c2" }?.lastMessage?.deletedAt != nil, true, "the placeholder shows meanwhile")
        XCTAssertTrue(inbox.apply(M.decoded(Self.message(2, in: "c2", text: nil)), open: nil), "already read: the count stays")
        XCTAssertTrue(inbox.apply(M.decoded(Self.message(7, from: "u1")), open: nil))
        XCTAssertEqual(inbox.conversations.first { $0.id == "c1" }?.unread, 0, "writing reads the thread")
    }

    func testPinnedConversationsStayOnTop() {
        var inbox = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation("c2", extra: ["pinned": true])), M.decoded(Self.conversation("c1")), M.decoded(Self.conversation("c3"))])
        XCTAssertTrue(inbox.apply(M.decoded(Self.message(9, in: "c3", extra: ["createdAt": "2026-10-24T12:00:00.000Z"])), open: nil))
        XCTAssertEqual(inbox.conversations.map(\.id), ["c2", "c3", "c1"], "the newest after the pinned ones")
        inbox.update(M.decoded(Self.conversation("c1", extra: ["pinned": true, "updatedAt": "2026-10-24T11:00:00.000Z"])))
        XCTAssertEqual(inbox.conversations.map(\.id), ["c1", "c2", "c3"])
        XCTAssertEqual(inbox.conversations.filter(\.pinned).count, 2)
        inbox.update(M.decoded(Self.conversation("c1", extra: ["muted": true, "updatedAt": "2026-10-24T11:00:00.000Z"])))
        XCTAssertEqual(inbox.conversations.map(\.id), ["c2", "c3", "c1"])
        XCTAssertTrue(inbox.conversations[2].muted)
        XCTAssertEqual(TogetherConversation.maxPinned, 5)
    }

    /// A direct message from someone else reaching a thread not on screen tells its sender it
    /// was delivered; an open thread is being read, and a group has no delivered marks.
    func testWhatIsAcknowledgedAsDelivered() {
        let inbox = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation()), M.decoded(Self.conversation("g1", kind: "group"))])
        XCTAssertTrue(inbox.acknowledges(M.decoded(Self.message(6)), open: nil))
        XCTAssertTrue(inbox.acknowledges(M.decoded(Self.message(6)), open: "g1"))
        XCTAssertFalse(inbox.acknowledges(M.decoded(Self.message(6)), open: "c1"))
        XCTAssertFalse(inbox.acknowledges(M.decoded(Self.message(6, from: "u1")), open: nil))
        XCTAssertFalse(inbox.acknowledges(M.decoded(Self.message(6, in: "g1")), open: nil))
        XCTAssertFalse(inbox.acknowledges(M.decoded(Self.message(6, in: "c9")), open: nil))
    }

    // MARK: Receipts

    func testReceiptsUnderMyNewestMessage() {
        let thread: [TogetherMessage] = [M.decoded(Self.message(4, from: "u1")), M.decoded(Self.message(5, from: "u1")), M.decoded(Self.message(6, from: "u1", text: nil)), M.decoded(Self.message(7))]
        func direct(read: Int?, delivered: Int?) -> TogetherInbox {
            var inbox = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation(last: 7, extra: ["receipts": [Self.receipt("f1", read: read, delivered: delivered)]]))])
            inbox.threads["c1"] = thread
            return inbox
        }
        XCTAssertEqual(direct(read: nil, delivered: 4).receipt(in: "c1")?.seq, 5, "my newest message that is not unsent")
        XCTAssertEqual(direct(read: nil, delivered: 4).receipt(in: "c1")?.state, .sent)
        XCTAssertEqual(direct(read: 4, delivered: 5).receipt(in: "c1")?.state, .delivered)
        XCTAssertEqual(direct(read: 5, delivered: 5).receipt(in: "c1")?.state, .read)
        XCTAssertEqual(direct(read: 7, delivered: nil).receipt(in: "c1")?.state, .read)

        var group = TogetherInbox(me: "u1", conversations: [M.decoded(Self.conversation("c1", kind: "group", last: 7, extra: ["receipts": [Self.receipt("f1", read: 5, delivered: nil), Self.receipt("f2", read: nil, delivered: nil)]]))])
        group.threads["c1"] = thread
        XCTAssertEqual(group.receipt(in: "c1")?.state, .seen(1, everyone: false))
        group.read("c1", by: "f2", upTo: 7)
        XCTAssertEqual(group.receipt(in: "c1")?.state, .seen(2, everyone: true))
        group.conversations[0].receipts = [TogetherReceipt(userId: "f1", readSeq: nil, deliveredSeq: nil)]
        XCTAssertEqual(group.receipt(in: "c1")?.state, .seen(0, everyone: false))

        var old = TogetherInbox(me: "u1", conversations: [M.decoded(M.conversation())])
        old.threads["c1"] = thread
        XCTAssertNil(old.receipt(in: "c1"), "an older server: nothing")
        var theirs = direct(read: 7, delivered: 7)
        theirs.threads["c1"] = [M.decoded(Self.message(7))]
        XCTAssertNil(theirs.receipt(in: "c1"), "nothing of mine")
    }

    // MARK: Editing, quoting, unsending

    func testWhatMayBeEdited() {
        let now = Self.date("2026-10-24T10:10:00.000Z")
        let mine: TogetherMessage = M.decoded(Self.message(4, from: "u1"))
        XCTAssertTrue(mine.canEdit(by: "u1", at: now))
        XCTAssertFalse(mine.canEdit(by: "f1", at: now), "someone else's")
        XCTAssertFalse(mine.canEdit(by: "u1", at: now.addingTimeInterval(5 * 60)), "15 minutes after it was sent")
        XCTAssertFalse((M.decoded(Self.message(4, from: "u1", extra: ["editCount": 20])) as TogetherMessage).canEdit(by: "u1", at: now), "edited 20 times")
        XCTAssertTrue((M.decoded(Self.message(4, from: "u1", extra: ["editCount": 19])) as TogetherMessage).canEdit(by: "u1", at: now))
        XCTAssertFalse((M.decoded(Self.message(4, from: "u1", text: nil)) as TogetherMessage).canEdit(by: "u1", at: now), "unsent")
        let photo = ["kind": "image", "attachments": [["id": "a1", "kind": "image", "contentType": "image/jpeg", "size": 10, "url": "https://cdn.test/a"]]] as [String: Any]
        XCTAssertFalse((M.decoded(Self.message(4, from: "u1", text: "[photo]", extra: photo)) as TogetherMessage).canEdit(by: "u1", at: now), "a photo without a caption")
        XCTAssertTrue((M.decoded(Self.message(4, from: "u1", text: "boss", extra: photo.merging(["caption": "boss"]) { $1 })) as TogetherMessage).canEdit(by: "u1", at: now))
        XCTAssertEqual(TogetherMessage.editWindow, 15 * 60)
        XCTAssertEqual(TogetherMessage.maxEdits, 20)
    }

    func testAQuoteAsTheThreadKnowsIt() {
        let thread: [TogetherMessage] = [M.decoded(Self.message(3, text: nil)), M.decoded(Self.message(4, text: "dash through"))]
        XCTAssertEqual(TogetherQuote(seq: 4, in: thread), .message(thread[1]))
        XCTAssertEqual(TogetherQuote(seq: 3, in: thread), .removed)
        XCTAssertEqual(TogetherQuote(seq: 1, in: thread), .earlier, "not loaded")
        XCTAssertNil(TogetherQuote(seq: nil, in: thread))
    }

    func testAnUnsentMessageKeepsOnlyItsPlace() {
        let message: TogetherMessage = M.decoded(Self.message(4, from: "u1", extra: ["reactions": [["reaction": "like", "count": 1, "userIds": ["f1"]]]]))
        let gone = message.removed(at: Self.date("2026-10-24T10:05:00.000Z"))
        XCTAssertEqual(gone.seq, 4)
        XCTAssertNil(gone.text)
        XCTAssertNil(gone.words)
        XCTAssertNotNil(gone.deletedAt)
        XCTAssertEqual(gone.reactions, [])
    }
}
