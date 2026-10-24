import XCTest
@testable import AnyPS5Core

final class TogetherFeedTests: TogetherSignedInCase {
    static let ayse: [String: Any] = ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull()]
    static let mert: [String: Any] = ["userId": "f2", "handle": "mert", "displayName": "Mert", "avatar": "https://cdn.test/m.webp"]

    static func item(_ id: String, kind: String = "trophy", counts: [String: Int] = [:], mine: Any = NSNull(), extra: [String: Any] = [:]) -> [String: Any] {
        var item: [String: Any] = [
            "id": id, "kind": kind, "createdAt": "2026-10-24T10:00:00.000Z", "actor": ayse,
            "game": ["titleId": "PPSA01234", "names": ["en": "Stray", "tr": "Stray TR"], "iconUrl": NSNull()],
            "highlight": NSNull(), "reactions": ["counts": counts, "mine": mine],
        ]
        if kind == "trophy" {
            item["trophies"] = [["trophyId": 3, "grade": "gold", "hidden": false, "texts": ["en": ["name": "Night Walker"]], "rarity": 0.031, "rarityLabel": "very_rare"],
                                ["trophyId": 9, "grade": "bronze", "hidden": true, "texts": NSNull(), "rarity": NSNull(), "rarityLabel": NSNull()]]
            item["trophyCount"] = 4
            item["highlight"] = "rare"
        }
        return item.merging(extra) { _, new in new }
    }

    func testTheFeedWithEveryKind() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["items": [
                Self.item("0007", counts: ["fire": 2, "heart": 1], mine: "fire"),
                Self.item("0006", kind: "platinum", extra: ["highlight": "platinum", "trophies": [["trophyId": 0, "grade": "platinum", "hidden": false, "texts": ["en": ["name": "All of it"]], "rarity": 0.008, "rarityLabel": "ultra_rare"]], "trophyCount": 1]),
                Self.item("0005", kind: "first_play"),
                Self.item("0004", kind: "long_session", extra: ["seconds": 9000]),
                Self.item("0003", kind: "friendship", extra: ["game": NSNull(), "friend": Self.mert]),
                Self.item("0002", kind: "milestone", extra: ["game": NSNull(), "milestone": ["kind": "hours", "value": 100]]),
                Self.item("0001", kind: "something_new", extra: ["game": NSNull()]),
            ], "next": "0001"])
        }
        let page = try await client.feed()
        XCTAssertEqual(last(), "GET /api/v1/me/feed")
        XCTAssertEqual(page.next, "0001")
        XCTAssertEqual(page.items.map(\.kind), [.trophy, .platinum, .firstPlay, .longSession, .friendship, .milestone, .other])
        let trophy = page.items[0]
        XCTAssertEqual(trophy.actor.handle, "ayse")
        XCTAssertEqual(trophy.game?.name(in: "tr"), "Stray TR")
        XCTAssertEqual(trophy.trophyCount, 4)
        XCTAssertEqual(trophy.trophies?.first?.name(in: "tr"), "Night Walker")
        XCTAssertNil(trophy.trophies?.last?.name(in: "en"), "a hidden trophy has no name")
        XCTAssertEqual(trophy.highlight, "rare")
        XCTAssertEqual(trophy.reactions.counts, [.fire: 2, .heart: 1])
        XCTAssertEqual(trophy.reactions.mine, .fire)
        XCTAssertEqual(trophy.reactions.total, 3)
        XCTAssertEqual(page.items[3].seconds, 9000)
        XCTAssertEqual(page.items[4].friend?.handle, "mert")
        XCTAssertEqual(page.items[5].milestone, .init(kind: "hours", value: 100))
    }

    func testOlderPagesAndSomeonesActivity() async throws {
        FakeTogether.handler = { _, _ in (200, ["items": [Self.item("0001")], "next": NSNull()]) }
        let older = try await client.feed(before: "0002")
        XCTAssertEqual(last(), "GET /api/v1/me/feed?before=0002")
        XCTAssertNil(older.next)
        _ = try await client.activity(of: "@ayse", limit: 10)
        XCTAssertEqual(last(), "GET /api/v1/users/ayse/activity?limit=10")
    }

    func testReactingAndTakingItBack() async throws {
        FakeTogether.handler = { _, _ in (200, ["counts": ["clap": 1], "mine": "clap"]) }
        let set = try await client.react(to: "0007", with: .clap)
        XCTAssertEqual(last(), "PUT /api/v1/activities/0007/reaction")
        XCTAssertEqual(body()?["reaction"] as? String, "clap")
        XCTAssertEqual(set.mine, .clap)
        FakeTogether.handler = { _, _ in (200, ["counts": [:], "mine": NSNull()]) }
        let gone = try await client.react(to: "0007", with: nil)
        XCTAssertEqual(last(), "DELETE /api/v1/activities/0007/reaction")
        XCTAssertNil(gone.mine)
        XCTAssertEqual(gone.total, 0)
    }

    /// Choosing a reaction shows at once: a new one, another one in its place, the same one taken back.
    func testReactionsChangeAtOnce() {
        var reactions = TogetherActivity.Reactions(counts: [.fire: 2], mine: nil)
        reactions = reactions.choosing(.heart)
        XCTAssertEqual(reactions, .init(counts: [.fire: 2, .heart: 1], mine: .heart))
        reactions = reactions.choosing(.fire)
        XCTAssertEqual(reactions, .init(counts: [.fire: 3], mine: .fire))
        reactions = reactions.choosing(.fire)
        XCTAssertEqual(reactions, .init(counts: [.fire: 2], mine: nil))
        XCTAssertEqual(TogetherReaction.allCases.map(\.emoji), ["🔥", "👏", "😮", "❤️"])
    }

    func decode(_ json: [String: Any]) throws -> TogetherActivity {
        try JSONDecoder.together.decode(TogetherActivity.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// A page replaces what was read, older pages add to the end, and a `feed.item` replaces the
    /// item with its ID or comes in at its place by ID (newest first).
    func testTheFeedKeepsOneOfEachNewestFirst() throws {
        var feed = TogetherFeed()
        XCTAssertFalse(feed.loaded)
        feed.load(TogetherFeedPage(items: [try decode(Self.item("0005")), try decode(Self.item("0003"))], next: "0003"))
        XCTAssertTrue(feed.loaded)
        XCTAssertEqual(feed.items.map(\.id), ["0005", "0003"])
        feed.loadOlder(TogetherFeedPage(items: [try decode(Self.item("0003")), try decode(Self.item("0001"))], next: nil))
        XCTAssertEqual(feed.items.map(\.id), ["0005", "0003", "0001"])
        XCTAssertNil(feed.next)

        feed.upsert(try decode(Self.item("0003", extra: ["trophyCount": 9])))
        XCTAssertEqual(feed.items.map(\.id), ["0005", "0003", "0001"])
        XCTAssertEqual(feed.items[1].trophyCount, 9)
        feed.upsert(try decode(Self.item("0007")))
        feed.upsert(try decode(Self.item("0004")))
        XCTAssertEqual(feed.items.map(\.id), ["0007", "0005", "0004", "0003", "0001"])

        feed.setReactions(.init(counts: [.wow: 1], mine: .wow), for: "0004")
        XCTAssertEqual(feed.items[2].reactions.mine, .wow)
        XCTAssertEqual(feed.index(of: "0004"), 2)
    }

    /// A `feed.item` event's data is the item itself.
    func testAFeedEventCarriesTheItem() throws {
        let frame: [String: Any] = ["op": "event", "id": "e1", "type": "feed.item", "data": Self.item("0009", counts: ["wow": 1])]
        let event = try XCTUnwrap(TogetherSocket.event(frame))
        let item = try XCTUnwrap(TogetherActivity.from(event))
        XCTAssertEqual(item.id, "0009")
        XCTAssertEqual(item.reactions.counts[.wow], 1)
        XCTAssertNil(TogetherActivity.from(TogetherSocket.Event(id: "e2", type: "party.updated", json: Data("{}".utf8))))
    }
}
