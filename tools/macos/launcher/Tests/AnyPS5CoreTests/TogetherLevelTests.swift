import XCTest
@testable import AnyPS5Core

/// Trophy levels, the showcase, comparing trophies and appearing offline, against the shapes
/// AnyTogether sends (and the ones an older server sends without them).
final class TogetherLevelTests: TogetherSignedInCase {
    static let trophyLevel: [String: Any] = ["level": 12, "tier": "bronze", "frame": 1, "points": 700, "levelPoints": 660, "nextLevelPoints": 720, "progress": 66]

    static func own(level: Any? = trophyLevel, appearOffline: Any? = false) -> [String: Any] {
        var profile: [String: Any] = ["handle": "utku", "displayName": "Utku", "bio": NSNull(), "avatar": NSNull(), "country": "TR", "handleChangeAt": NSNull(),
                                      "privacy": ["library": "friends", "trophies": "friends", "friends": "friends", "presence": "friends", "search": "everyone"],
                                      "cover": NSNull(), "accent": NSNull(), "showcase": ["trophies": [["titleId": "PPSA01234", "trophyId": 7]], "games": ["PPSA01234"]]]
        if let level { profile["trophyLevel"] = level }
        if let appearOffline { profile["appearOffline"] = appearOffline }
        return ["account": ["id": "u1", "email": "u@example.com"], "profile": profile]
    }

    // MARK: Levels

    func testMyLevelAndPresenceModeFromMe() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(appearOffline: true)) }
        let mine = try await client.myProfile()
        XCTAssertEqual(mine.trophyLevel?.level, 12)
        XCTAssertEqual(mine.trophyLevel?.tier, .bronze)
        XCTAssertEqual(mine.trophyLevel?.frame, 1)
        XCTAssertEqual(mine.trophyLevel?.points, 700)
        XCTAssertEqual(mine.trophyLevel?.pointsToNext, 20)
        XCTAssertEqual(mine.trophyLevel?.progress, 66)
        XCTAssertEqual(mine.trophyLevel?.fraction ?? 0, 0.66, accuracy: 0.001)
        XCTAssertTrue(mine.appearOffline)
    }

    /// A name, handle or picture changed on the website: reading the own profile again (the
    /// launcher does when it comes back in front) puts them in the session's user.
    func testANameChangedOnTheWebsiteReplacesTheKeptOne() async throws {
        var changed = Self.own()
        var profile = changed["profile"] as! [String: Any]
        profile["handle"] = "utku_h"
        profile["displayName"] = "Utku H"
        profile["avatar"] = "https://anytogether.test/a.jpg"
        changed["profile"] = profile
        FakeTogether.handler = { _, _ in (200, changed) }
        _ = try await client.myProfile()
        XCTAssertEqual(client.user?.handle, "utku_h")
        XCTAssertEqual(client.user?.displayName, "Utku H")
        XCTAssertEqual(client.user?.avatar, "https://anytogether.test/a.jpg")
    }

    /// An older server sends neither: no level, and online.
    func testAnOlderServerHasNoLevelAndNoPresenceMode() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(level: nil, appearOffline: nil)) }
        let mine = try await client.myProfile()
        XCTAssertNil(mine.trophyLevel)
        XCTAssertFalse(mine.appearOffline)
        XCTAssertEqual(mine.handle, "utku")
    }

    /// A level of a shape this launcher does not expect is left out, not a failed profile.
    func testABrokenLevelLeavesTheProfileWhole() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own(level: "twelve", appearOffline: "yes")) }
        let mine = try await client.myProfile()
        XCTAssertNil(mine.trophyLevel)
        XCTAssertFalse(mine.appearOffline)
    }

    func testTheTopLevel() throws {
        let json: [String: Any] = ["level": 999, "tier": "platinum", "frame": 10, "points": 4_000_000, "levelPoints": 3_996_000, "nextLevelPoints": NSNull(), "progress": 100]
        let top = try JSONDecoder.together.decode(TogetherTrophyLevel.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(top.isTop)
        XCTAssertNil(top.pointsToNext)
        XCTAssertEqual(top.fraction, 1)
    }

    /// A tier this launcher does not know, or a frame left out, are worked out from the level.
    func testTierAndFrameFollowTheLevel() throws {
        let json: [String: Any] = ["level": 412, "tier": "obsidian"]
        let badge = try JSONDecoder.together.decode(TogetherLevelBadge.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(badge.tier, .gold)
        XCTAssertEqual(badge.frame, 5)
        XCTAssertEqual(TogetherLevelBadge.Tier(level: 1), .bronze)
        XCTAssertEqual(TogetherLevelBadge.Tier(level: 100), .silver)
        XCTAssertEqual(TogetherLevelBadge.Tier(level: 299), .silver)
        XCTAssertEqual(TogetherLevelBadge.Tier(level: 600), .platinum)
        XCTAssertEqual(TogetherLevelBadge(level: 999).frame, 10)
        XCTAssertEqual(TogetherLevelBadge(level: 99).frame, 1)
    }

    func testSomeoneElsesLevelOrNoneWhenTheirTrophiesArePrivate() async throws {
        FakeTogether.handler = { request, _ in
            var person: [String: Any] = ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull(), "bio": NSNull(), "country": NSNull(), "friendship": "friends",
                                         "visible": ["library": true, "trophies": true, "friends": true, "presence": true], "connections": [], "cover": NSNull(), "accent": "mint"]
            switch request.url!.path {
            case "/api/v1/users/ayse": person["trophyLevel"] = ["level": 140, "tier": "silver", "frame": 2, "points": 9000, "levelPoints": 8940, "nextLevelPoints": 9030, "progress": 66]
            default: person["trophyLevel"] = NSNull()
            }
            return (200, person)
        }
        let ayse = try await client.profile("ayse")
        XCTAssertEqual(ayse.trophyLevel?.level, 140)
        XCTAssertEqual(ayse.trophyLevel?.tier, .silver)
        XCTAssertEqual(ayse.trophyLevel?.frame, 2)
        let hidden = try await client.profile("mert")
        XCTAssertNil(hidden.trophyLevel)
    }

    func testFriendsCarryTheirLevel() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["friends": [
                ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull(), "presence": ["state": "online", "titleId": NSNull(), "since": NSNull()],
                 "level": ["level": 312, "tier": "gold", "frame": 4]],
                ["userId": "f2", "handle": "mert", "displayName": "Mert", "avatar": NSNull(), "presence": NSNull(), "level": NSNull()],
                ["userId": "f3", "handle": "kral", "displayName": "Kral", "avatar": NSNull(), "presence": NSNull()],
            ]])
        }
        let friends = try await client.friends()
        XCTAssertEqual(friends.map { $0.level?.level }, [312, nil, nil])
        XCTAssertEqual(friends[0].level?.tier, .gold)
        XCTAssertEqual(friends[0].presence?.online, true)
    }

    // MARK: Level up

    static func levelUp(_ user: String, level: Int = 13) -> TogetherSocket.Event {
        let data: [String: Any] = ["userId": user, "handle": user == "u1" ? "utku" : "ayse", "displayName": user == "u1" ? "Utku" : "Ayşe", "level": level, "tier": level >= 100 ? "silver" : "bronze", "frame": level / 100 + 1]
        return TogetherSocket.event(["op": "event", "id": "e1", "type": "level.up", "data": data])!
    }

    func testALevelUpEvent() throws {
        let up = try XCTUnwrap(TogetherLevelUp(Self.levelUp("u1")))
        XCTAssertEqual(up.badge, TogetherLevelBadge(level: 13, tier: .bronze, frame: 1))
        XCTAssertTrue(up.isMine("u1"))
        XCTAssertFalse(up.isMine("f1"))
        XCTAssertFalse(up.isMine(nil))
        XCTAssertNil(TogetherLevelUp(TogetherSocket.event(["op": "event", "id": "e2", "type": "presence.updated", "data": ["userId": "u1"]])!))
        XCTAssertNil(TogetherLevelUp(TogetherSocket.event(["op": "event", "id": "e3", "type": "level.up", "data": ["userId": "u1"]])!), "no level, nothing to show")
    }

    /// A friend's level up changes their badge in the list; someone not in it changes nothing.
    func testAFriendsLevelUpUpdatesTheList() throws {
        var friends = [TogetherFriend(userId: "f1", handle: "ayse", displayName: "Ayşe", avatar: nil, presence: nil, level: TogetherLevelBadge(level: 12)),
                       TogetherFriend(userId: "f2", handle: "mert", displayName: "Mert", avatar: nil, presence: nil)]
        let up = try XCTUnwrap(TogetherLevelUp(Self.levelUp("f1", level: 100)))
        XCTAssertTrue(friends.apply(up))
        XCTAssertEqual(friends[0].level, TogetherLevelBadge(level: 100, tier: .silver, frame: 2))
        XCTAssertNil(friends[1].level)
        XCTAssertFalse(friends.apply(try XCTUnwrap(TogetherLevelUp(Self.levelUp("f9")))))
    }

    /// The user's own level up moves the badge at once; the points come with the next read.
    func testMyLevelUpMovesMyBadge() async throws {
        FakeTogether.handler = { _, _ in (200, Self.own()) }
        var mine = try await client.myProfile()
        mine.apply(try XCTUnwrap(TogetherLevelUp(Self.levelUp("u1", level: 13))))
        XCTAssertEqual(mine.trophyLevel?.level, 13)
        XCTAssertEqual(mine.trophyLevel?.points, 700)
        FakeTogether.handler = { _, _ in (200, Self.own(level: nil)) }
        var old = try await client.myProfile()
        old.apply(try XCTUnwrap(TogetherLevelUp(Self.levelUp("u1", level: 13))))
        XCTAssertEqual(old.trophyLevel?.level, 13, "a level where there was none")
        XCTAssertEqual(old.trophyLevel?.progress, 0)
    }

    func testALevelUpNotification() throws {
        let json: [String: Any] = ["notifications": [
            TogetherNotificationTests.note("0009", kind: "level_up", actor: ["userId": "u1", "handle": "utku", "displayName": "Utku", "avatar": NSNull()], subject: "level",
                                           data: ["level": 13, "tier": "bronze", "frame": 1]),
        ], "unread": 1, "more": false]
        let page = try JSONDecoder.together.decode(TogetherNotificationPage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(page.notifications.first?.kind, .levelUp)
        XCTAssertEqual(page.notifications.first?.data.level, 13)
        XCTAssertEqual(page.notifications.first?.data.tier, "bronze")
        XCTAssertEqual(page.notifications.first?.data.frame, 1)
        XCTAssertEqual(page.notifications.first?.data.levelBadge, TogetherLevelBadge(level: 13, tier: .bronze, frame: 1))
        // The level.up event brings its own banner.
        XCTAssertFalse(TogetherNotification.Kind.levelUp.toastsOnItsOwn)
        XCTAssertTrue(TogetherNotification.Kind.allKnown.contains(.levelUp))
    }

    // MARK: Showcase

    func testAShowcase() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["trophies": [["titleId": "PPSA01234", "gameNames": ["en": "Stray"], "trophyId": 7, "grade": "gold", "hidden": false, "texts": ["en": ["name": "Bound"]],
                                 "earnedAt": "2026-10-23T21:00:00.000Z", "rarity": 0.03, "rarityLabel": "very_rare"]],
                   "games": [["titleId": "PPSA01234", "names": ["en": "Stray"], "iconUrl": NSNull(), "secondsPlayed": 7200, "trophiesEarned": 12, "trophiesTotal": 48, "progress": 25],
                             ["titleId": "PPSA05678", "names": ["en": "Astro Bot"], "iconUrl": "https://cdn.test/a.webp", "secondsPlayed": 60, "trophiesEarned": NSNull(),
                              "trophiesTotal": NSNull(), "progress": NSNull()]]])
        }
        let showcase = try await client.showcase(of: "@ayse")
        XCTAssertEqual(last(), "GET /api/v1/users/ayse/showcase")
        XCTAssertEqual(showcase.trophies?.first?.name(in: "en"), "Bound")
        XCTAssertEqual(showcase.trophies?.first?.grade, "gold")
        XCTAssertEqual(showcase.games?.map(\.titleId), ["PPSA01234", "PPSA05678"])
        XCTAssertEqual(showcase.games?.first?.progress, 25)
        XCTAssertNil(showcase.games?.last?.trophiesEarned)
        XCTAssertFalse(showcase.isEmpty)
        XCTAssertFalse(showcase.isPrivate)
    }

    /// null is private to the reader; empty is nothing pinned.
    func testAPrivateOrEmptyShowcase() throws {
        let hidden = try JSONDecoder.together.decode(TogetherShowcase.self, from: Data(#"{"trophies":null,"games":null}"#.utf8))
        XCTAssertTrue(hidden.isPrivate)
        let half = try JSONDecoder.together.decode(TogetherShowcase.self, from: Data(#"{"trophies":null,"games":[]}"#.utf8))
        XCTAssertFalse(half.isPrivate)
        XCTAssertTrue(half.isEmpty)
        let empty = try JSONDecoder.together.decode(TogetherShowcase.self, from: Data(#"{"trophies":[],"games":[]}"#.utf8))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.isPrivate)
    }

    // MARK: Compare

    static let side: [String: Any] = ["earned": 12, "total": 48, "progress": 25, "points": 450]

    func testComparingGames() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["games": [
                ["titleId": "PPSA01234", "names": ["en": "Stray"], "iconUrl": NSNull(), "mine": Self.side, "theirs": ["earned": 30, "total": 48, "progress": 62, "points": 1200]],
                ["titleId": "PPSA05678", "names": ["en": "Astro Bot"], "iconUrl": NSNull(), "mine": NSNull(), "theirs": ["earned": 3, "total": NSNull(), "progress": NSNull(), "points": 45]],
            ]])
        }
        let games = try await client.compareGames(with: "ayse")
        XCTAssertEqual(last(), "GET /api/v1/users/ayse/trophies/compare")
        XCTAssertEqual(games.map(\.titleId), ["PPSA01234", "PPSA05678"])
        XCTAssertTrue(games[0].both)
        XCTAssertEqual(games[0].mine?.earned, 12)
        XCTAssertEqual(games[0].theirs?.progress, 62)
        XCTAssertFalse(games[1].both)
        XCTAssertNil(games[1].mine)
        XCTAssertNil(games[1].theirs?.total)
    }

    func testComparingOneGamesTrophies() async throws {
        let person = { (id: String, handle: String, level: Int) -> [String: Any] in
            ["userId": id, "handle": handle, "displayName": handle.capitalized, "avatar": NSNull(), "level": ["level": level, "tier": "bronze", "frame": 1]]
        }
        FakeTogether.handler = { _, _ in
            (200, ["titleId": "PPSA01234", "game": ["names": ["en": "Stray"], "iconUrl": NSNull()], "setHash": String(repeating: "a", count: 64),
                   "me": person("u1", "utku", 12), "them": person("f1", "ayse", 40),
                   "trophies": [
                       ["id": 0, "grade": "platinum", "hidden": false, "texts": ["en": ["name": "All of it", "detail": "Every trophy"]], "rarity": 0.01, "rarityLabel": "ultra_rare",
                        "mine": NSNull(), "theirs": "2026-10-20T10:00:00.000Z"],
                       ["id": 1, "grade": "bronze", "hidden": false, "texts": ["en": ["name": "First steps"]], "rarity": 0.9, "rarityLabel": "common",
                        "mine": "2026-10-01T10:00:00Z", "theirs": "2026-10-02T10:00:00.000Z"],
                       ["id": 2, "grade": "gold", "hidden": true, "texts": NSNull(), "rarity": NSNull(), "rarityLabel": NSNull(), "mine": NSNull(), "theirs": NSNull()],
                   ],
                   "totals": ["mine": 1, "theirs": 2, "both": 1, "total": 3]])
        }
        let view = try await client.compareTrophies(with: "ayse", titleId: "PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/users/ayse/trophies/compare?titleId=PPSA01234")
        XCTAssertEqual(view.game?.name(in: "en"), "Stray")
        XCTAssertEqual(view.me.level?.level, 12)
        XCTAssertEqual(view.them.handle, "ayse")
        XCTAssertEqual(view.trophies.map(\.id), [0, 1, 2])
        XCTAssertNil(view.trophies[0].mine)
        XCTAssertNotNil(view.trophies[0].theirs)
        XCTAssertEqual(view.trophies[0].name(in: "en"), "All of it")
        XCTAssertEqual(view.trophies[0].detail(in: "en"), "Every trophy")
        XCTAssertNil(view.trophies[2].name(in: "en"), "a hidden trophy neither has keeps its name")
        XCTAssertEqual(view.totals, .init(mine: 1, theirs: 2, both: 1, total: 3))
    }

    func testComparingWithSomeoneWhoKeepsTrophiesPrivate() async throws {
        FakeTogether.handler = { _, _ in (403, ["code": "forbidden", "status": 403, "title": "This is private", "details": ["section": "trophies"]]) }
        do {
            _ = try await client.compareGames(with: "mert")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertTrue(problem.isPrivate)
        }
    }

    // MARK: Appear offline

    func testAppearingOffline() async throws {
        FakeTogether.handler = { _, body in
            let asked = (try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any])?["appearOffline"] as? Bool ?? false
            return (200, ["appearOffline": asked])
        }
        let on = try await client.setAppearOffline(true)
        XCTAssertTrue(on)
        XCTAssertEqual(last(), "PATCH /api/v1/me/presence")
        XCTAssertEqual(body()?["appearOffline"] as? Bool, true)
        XCTAssertEqual(body()?.count, 1)
        let off = try await client.setAppearOffline(false)
        XCTAssertFalse(off)
    }

    /// A server without it yet answers 404, which the launcher reads as "not available".
    func testAServerWithoutAppearOffline() async throws {
        FakeTogether.handler = { _, _ in (404, ["code": "not_found", "status": 404, "title": "Not found"]) }
        do {
            _ = try await client.setAppearOffline(true)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.status, 404)
        }
    }

    func testThePresenceModeEvent() {
        let on = TogetherSocket.event(["op": "event", "id": "e1", "type": "presence.mode", "data": ["appearOffline": true]])!
        XCTAssertEqual(TogetherPresenceMode(on), TogetherPresenceMode(appearOffline: true))
        let off = TogetherSocket.event(["op": "event", "id": "e2", "type": "presence.mode", "data": ["appearOffline": false]])!
        XCTAssertEqual(TogetherPresenceMode(off)?.appearOffline, false)
        XCTAssertNil(TogetherPresenceMode(TogetherSocket.event(["op": "event", "id": "e3", "type": "presence.updated", "data": ["appearOffline": true]])!))
        XCTAssertNil(TogetherPresenceMode(TogetherSocket.event(["op": "event", "id": "e4", "type": "presence.mode", "data": [:]])!))
    }
}
