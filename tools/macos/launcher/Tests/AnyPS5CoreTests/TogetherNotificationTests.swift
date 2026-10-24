import XCTest
@testable import AnyPS5Core

final class TogetherNotificationTests: TogetherSignedInCase {
    static let ayse: [String: Any] = ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull()]

    static func note(_ id: String, kind: String = "friend_request", read: Bool = false, actor: Any = ayse, subject: Any = NSNull(), data: [String: Any] = [:],
                     updated: String = "2026-10-24T10:00:00.000Z") -> [String: Any] {
        ["id": id, "kind": kind, "actor": actor, "subjectId": subject, "data": data, "read": read, "createdAt": "2026-10-24T10:00:00.000Z", "updatedAt": updated]
    }

    func testTheListWithEachKind() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["notifications": [
                Self.note("0007", kind: "message", subject: "c1", data: ["conversationId": "c1", "title": NSNull(), "group": false, "count": 3, "text": "are you on?"]),
                Self.note("0006", kind: "party_invite", subject: "p1", data: ["partyId": "p1", "size": 2]),
                Self.note("0005", kind: "game_invite", subject: "s1", data: ["sessionId": "s1", "titleId": "PPSA01234"]),
                Self.note("0004", kind: "missed_call", read: true, subject: "call1", data: ["callId": "call1"]),
                Self.note("0003", kind: "warning", actor: NSNull(), data: ["reason": "Be kind"]),
                Self.note("0002", kind: "friend_accepted"),
                Self.note("0001", kind: "something_else"),
            ], "unread": 6, "more": true])
        }
        let page = try await client.notifications()
        XCTAssertEqual(last(), "GET /api/v1/me/notifications")
        XCTAssertEqual(page.unread, 6)
        XCTAssertTrue(page.more)
        XCTAssertEqual(page.notifications.map(\.kind), [.message, .partyInvite, .gameInvite, .missedCall, .warning, .friendAccepted, .other])
        let message = page.notifications[0]
        XCTAssertEqual(message.actor?.handle, "ayse")
        XCTAssertEqual(message.data.count, 3)
        XCTAssertEqual(message.data.text, "are you on?")
        XCTAssertEqual(message.data.conversationId, "c1")
        XCTAssertEqual(message.data.group, false)
        XCTAssertEqual(page.notifications[1].data.size, 2)
        XCTAssertEqual(page.notifications[2].data.titleId, "PPSA01234")
        XCTAssertTrue(page.notifications[3].read)
        XCTAssertNil(page.notifications[4].actor)
        XCTAssertEqual(page.notifications[4].data.reason, "Be kind")
        _ = try await client.notifications(before: "0001", limit: 20)
        XCTAssertEqual(last(), "GET /api/v1/me/notifications?before=0001&limit=20")
    }

    func testMarkingRead() async throws {
        FakeTogether.handler = { _, _ in (200, ["unread": 4]) }
        let left = try await client.readNotification("0007")
        XCTAssertEqual(last(), "POST /api/v1/me/notifications/0007/read")
        XCTAssertEqual(left, 4)
        FakeTogether.handler = { _, _ in (200, ["unread": 0]) }
        let none = try await client.readAllNotifications()
        XCTAssertEqual(last(), "POST /api/v1/me/notifications/read-all")
        XCTAssertEqual(none, 0)
        FakeTogether.handler = { _, _ in (200, ["unread": 2]) }
        let count = try await client.unreadNotifications()
        XCTAssertEqual(last(), "GET /api/v1/me/notifications/unread")
        XCTAssertEqual(count, 2)
    }

    func decode(_ json: [String: Any]) throws -> TogetherNotification {
        try JSONDecoder.together.decode(TogetherNotification.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// The gateway's `notification` and `notification.read`.
    func testEvents() throws {
        let new = TogetherSocket.Event(id: "e1", type: "notification", json: try JSONSerialization.data(withJSONObject: ["notification": Self.note("0009", kind: "message"), "unread": 3]))
        guard case .new(let note, let unread) = try XCTUnwrap(TogetherNotificationEvent(new)) else { return XCTFail("not new") }
        XCTAssertEqual(note.id, "0009")
        XCTAssertEqual(unread, 3)
        let some = TogetherSocket.Event(id: "e2", type: "notification.read", json: try JSONSerialization.data(withJSONObject: ["ids": ["0009"], "unread": 2]))
        XCTAssertEqual(TogetherNotificationEvent(some), .read(ids: ["0009"], unread: 2))
        let all = TogetherSocket.Event(id: "e3", type: "notification.read", json: try JSONSerialization.data(withJSONObject: ["ids": NSNull(), "unread": 0]))
        XCTAssertEqual(TogetherNotificationEvent(all), .read(ids: nil, unread: 0))
        XCTAssertNil(TogetherNotificationEvent(TogetherSocket.Event(id: "e4", type: "feed.item", json: Data("{}".utf8))))
    }

    /// Pages, a new one on top, a gathered message in place, reads from any device.
    func testTheCenterKeepsCount() throws {
        var center = TogetherNotifications()
        center.load(TogetherNotificationPage(notifications: [try decode(Self.note("0005")), try decode(Self.note("0003", read: true))], unread: 1, more: true))
        XCTAssertTrue(center.loaded)
        center.loadOlder(TogetherNotificationPage(notifications: [try decode(Self.note("0001"))], unread: 2, more: false))
        XCTAssertEqual(center.items.map(\.id), ["0005", "0003", "0001"])
        XCTAssertEqual(center.unread, 2)
        XCTAssertFalse(center.more)

        center.apply(.new(try decode(Self.note("0007", kind: "message", data: ["count": 1])), unread: 3))
        center.apply(.new(try decode(Self.note("0007", kind: "message", data: ["count": 2])), unread: 3))
        XCTAssertEqual(center.items.map(\.id), ["0007", "0005", "0003", "0001"])
        XCTAssertEqual(center.items[0].data.count, 2)

        center.apply(.read(ids: ["0005"], unread: 2))
        XCTAssertEqual(center.items.filter { !$0.read }.map(\.id), ["0007", "0001"])
        center.markRead("0007")
        XCTAssertEqual(center.unread, 1)
        center.markRead("0007")
        XCTAssertEqual(center.unread, 1, "reading it twice counts once")
        center.apply(.read(ids: nil, unread: 0))
        XCTAssertTrue(center.items.allSatisfy(\.read))
        XCTAssertEqual(center.unread, 0)
    }

    /// The launcher announces requests, invites and missed calls from their own events; a
    /// notification stands alone for the rest.
    func testWhichKindsToastOnTheirOwn() throws {
        XCTAssertEqual(TogetherNotification.Kind.allKnown.filter(\.toastsOnItsOwn), [.message, .warning, .other])
    }
}
