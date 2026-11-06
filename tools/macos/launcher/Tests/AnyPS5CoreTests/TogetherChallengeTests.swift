import XCTest
@testable import AnyPS5Core

/// Challenges as AnyTogether answers them (packages/shared/src/challenges.ts): the lists, one with
/// its standings, joining and leaving, the rule that an older server's 404 hides them, how long
/// is left, and the three notifications.
final class TogetherChallengeTests: TogetherSignedInCase {
    static func person(_ id: String) -> [String: Any] { ["userId": id, "handle": "h\(id)", "displayName": "N\(id)", "avatar": NSNull()] }
    static func standing(_ rank: Int, _ user: Any, _ value: Int, me: Bool = false) -> [String: Any] { ["rank": rank, "user": user, "value": value, "me": me] }

    static func view(_ id: String = "c1", metric: String = "points", state: String = "active", joined: Bool = false, extra: [String: Any] = [:]) -> [String: Any] {
        var view: [String: Any] = [
            "id": id, "title": "Weekend sprint", "description": NSNull(),
            "game": ["titleId": "PPSA01234", "names": ["en": "Stray", "tr": "Stray"], "iconUrl": NSNull()],
            "metric": metric, "audience": "friends", "community": NSNull(), "creator": person("f1"),
            "startsAt": "2026-11-05T10:00:00.000Z", "endsAt": "2026-11-08T10:00:00.000Z",
            "state": state, "final": false, "entrants": 4, "joined": joined, "mine": false, "canCancel": false,
            "leader": standing(1, person("f1"), 420), "myStanding": joined ? ["rank": 2, "value": 300] : NSNull(),
            "createdAt": "2026-11-04T10:00:00.000Z",
        ]
        view.merge(extra) { _, new in new }
        return view
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: Any) throws -> T {
        try JSONDecoder.together.decode(type, from: JSONSerialization.data(withJSONObject: json))
    }

    func testAGamesChallenges() async throws {
        FakeTogether.handler = { _, _ in (200, ["challenges": [Self.view(), Self.view("c2", metric: "time", state: "upcoming")]]) }
        let list = try await client.challenges(titleId: "PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/challenges?titleId=PPSA01234")
        XCTAssertEqual(list.map(\.id), ["c1", "c2"])
        let first = list[0]
        XCTAssertEqual(first.title, "Weekend sprint")
        XCTAssertNil(first.description)
        XCTAssertEqual(first.game.name(in: "tr"), "Stray")
        XCTAssertEqual(first.metric, .points)
        XCTAssertEqual(first.audience, .friends)
        XCTAssertEqual(first.state, .active)
        XCTAssertEqual(first.creator?.handle, "hf1")
        XCTAssertEqual(first.leader?.user?.displayName, "Nf1")
        XCTAssertEqual(first.leader?.value, 420)
        XCTAssertNil(first.myStanding)
        XCTAssertEqual(first.entrants, 4)
        XCTAssertEqual(first.endsAt, ISO8601DateFormatter().date(from: "2026-11-08T10:00:00Z"))
        XCTAssertEqual(list[1].metric, .time)
        XCTAssertEqual(list[1].state, .upcoming)
    }

    func testMineAndEnded() async throws {
        FakeTogether.handler = { _, _ in (200, ["challenges": [Self.view(joined: true)]]) }
        let mine = try await client.myChallenges()
        XCTAssertEqual(last(), "GET /api/v1/me/challenges")
        XCTAssertEqual(mine.first?.myStanding, .init(rank: 2, value: 300))
        XCTAssertEqual(mine.first?.joined, true)
        _ = try await client.challenges(titleId: nil, ended: true)
        XCTAssertEqual(last(), "GET /api/v1/challenges?state=ended")
    }

    /// Fields a later server adds, a metric or state this launcher does not know, a community and
    /// a hidden leader (user null): read, not a failure; one item that cannot be read at all is
    /// left out of the list, not the whole list.
    func testDecodingToleratesTheFuture() async throws {
        let community: [String: Any] = ["id": "k1", "name": "Souls fans", "icon": "flame", "iconUrl": "https://cdn.test/k1.png"]
        let odd = Self.view("c3", metric: "speedrun", state: "paused", extra: [
            "audience": "community", "community": community, "creator": NSNull(), "leader": Self.standing(1, NSNull(), 90),
            "description": "Most points by Sunday", "prize": ["kind": "badge"], "rules": [1, 2, 3],
        ])
        var broken = Self.view("c4")
        broken["title"] = NSNull()
        FakeTogether.handler = { _, _ in (200, ["challenges": [odd, broken, Self.view("c5")], "cursor": "x"]) }
        let list = try await client.challenges(titleId: "PPSA01234")
        XCTAssertEqual(list.map(\.id), ["c3", "c5"])
        let first = list[0]
        XCTAssertEqual(first.metric, .other)
        XCTAssertEqual(first.metricName, "speedrun")
        XCTAssertEqual(first.state, .other)
        XCTAssertEqual(first.audience, .community)
        XCTAssertEqual(first.community?.name, "Souls fans")
        XCTAssertNil(first.creator)
        XCTAssertNil(first.leader?.user)
        XCTAssertEqual(first.leader?.value, 90)
        XCTAssertEqual(first.description, "Most points by Sunday")
    }

    func testAChallengeWithItsStandings() async throws {
        var detail = Self.view(joined: true)
        detail["standings"] = [Self.standing(1, Self.person("f1"), 420), Self.standing(2, NSNull(), 300), Self.standing(2, Self.person("u1"), 300, me: true), Self.standing(4, Self.person("f2"), 15)]
        detail["around"] = []
        detail["updatedAt"] = "2026-11-06T09:00:00.000Z"
        detail["future"] = ["anything": true]
        FakeTogether.handler = { _, _ in (200, detail) }
        let challenge = try await client.challenge("c1")
        XCTAssertEqual(last(), "GET /api/v1/challenges/c1")
        XCTAssertEqual(challenge.challenge.id, "c1")
        XCTAssertEqual(challenge.standings.map(\.rank), [1, 2, 2, 4])
        XCTAssertNil(challenge.standings[1].user, "a hidden player")
        XCTAssertTrue(challenge.standings[2].me)
        XCTAssertEqual(challenge.lines.count, 4)
        XCTAssertEqual(challenge.lines[2], .standing(challenge.standings[2]))
    }

    /// The reader past the first hundred: a gap, then their neighbours, no one twice.
    func testTheReadersNeighboursPastTheTop() throws {
        var detail = Self.view(joined: true)
        detail["standings"] = (1 ... 100).map { Self.standing($0, Self.person("p\($0)"), 1000 - $0) }
        detail["around"] = [Self.standing(140, Self.person("x"), 30), Self.standing(141, Self.person("u1"), 20, me: true), Self.standing(142, NSNull(), 10)]
        detail["updatedAt"] = "2026-11-06T09:00:00.000Z"
        let challenge = try Self.decode(TogetherChallengeDetail.self, detail)
        let lines = challenge.lines
        XCTAssertEqual(lines.count, 104)
        XCTAssertEqual(lines[100], .gap)
        XCTAssertEqual(lines[102], .standing(challenge.around[1]))

        var near = Self.view(joined: true)
        near["standings"] = [Self.standing(1, Self.person("a"), 9), Self.standing(2, Self.person("b"), 8)]
        near["around"] = [Self.standing(2, Self.person("b"), 8), Self.standing(3, Self.person("u1"), 7, me: true)]
        near["updatedAt"] = "2026-11-06T09:00:00.000Z"
        let joinsTheTop = try Self.decode(TogetherChallengeDetail.self, near)
        XCTAssertEqual(joinsTheTop.lines.map(\.rank), [1, 2, 3])
    }

    func testJoinAndLeave() async throws {
        FakeTogether.handler = { _, _ in (200, Self.view(joined: true)) }
        let joined = try await client.joinChallenge("c1")
        XCTAssertEqual(last(), "POST /api/v1/challenges/c1/join")
        XCTAssertEqual(body().map { $0.isEmpty }, true, "body {}")
        XCTAssertTrue(joined.joined)
        FakeTogether.handler = { _, _ in (200, Self.view()) }
        let left = try await client.leaveChallenge("c1")
        XCTAssertEqual(last(), "POST /api/v1/challenges/c1/leave")
        XCTAssertFalse(left.joined)
        FakeTogether.handler = { _, _ in (409, ["code": "full", "status": 409, "title": "This challenge is full"]) }
        do {
            _ = try await client.joinChallenge("c1")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "full")
        }
    }

    /// The leaderboard's strip: a game's challenges, or the reader's own on the overall board; an
    /// older server without challenges answers 404 (JSON or not), and then there are none.
    func testTheStripAndAnOlderServer() async throws {
        FakeTogether.handler = { _, _ in (200, ["challenges": [Self.view()]]) }
        let game = try await client.challengeStrip(titleId: "PPSA01234")
        XCTAssertEqual(last(), "GET /api/v1/challenges?titleId=PPSA01234")
        XCTAssertEqual(game.count, 1)
        _ = try await client.challengeStrip(titleId: nil)
        XCTAssertEqual(last(), "GET /api/v1/me/challenges")

        FakeTogether.handler = { _, _ in (404, ["code": "not_found", "status": 404, "title": "Not found"]) }
        let none = try await client.challengeStrip(titleId: "PPSA01234")
        XCTAssertEqual(none, [])
        FakeTogether.handler = { _, _ in (404, FakeTogether.Raw(data: Data("404 Not Found".utf8), headers: ["content-type": "text/plain"])) }
        let plain = try await client.challengeStrip(titleId: nil)
        XCTAssertEqual(plain, [])

        // Any other trouble is still an error.
        FakeTogether.handler = { _, _ in (500, ["code": "internal", "status": 500, "title": "Oops"]) }
        do {
            _ = try await client.challengeStrip(titleId: nil)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.status, 500)
        }
    }

    // MARK: Time

    func testWhatTheClockSays() throws {
        let challenge = try Self.decode(TogetherChallenge.self, Self.view())
        let start = challenge.startsAt, end = challenge.endsAt
        XCTAssertEqual(challenge.clock(now: start.addingTimeInterval(-3 * 3600)), .startsIn(3 * 3600))
        XCTAssertEqual(challenge.clock(now: end.addingTimeInterval(-2 * 86400)), .endsIn(2 * 86400))
        XCTAssertEqual(challenge.clock(now: end.addingTimeInterval(60)), .finishing, "ended, results not final yet")
        let final = try Self.decode(TogetherChallenge.self, Self.view(state: "ended", extra: ["final": true]))
        XCTAssertEqual(final.clock(now: end.addingTimeInterval(7200)), .ended)
        let cancelled = try Self.decode(TogetherChallenge.self, Self.view(state: "cancelled"))
        XCTAssertEqual(cancelled.clock(now: start), .cancelled)

        // The window's progress, start to end.
        XCTAssertEqual(challenge.progress(now: start.addingTimeInterval(-60)), 0)
        XCTAssertEqual(challenge.progress(now: start.addingTimeInterval(end.timeIntervalSince(start) / 4)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(challenge.progress(now: end.addingTimeInterval(60)), 1)
    }

    /// "2 days", "36 hours", "90 minutes": the largest unit that reads as two or more, down to a
    /// minute.
    func testTimeLeftReadsInOneUnit() {
        typealias Span = TogetherChallenge.Span
        XCTAssertEqual(Span(seconds: 2 * 86400), Span(amount: 2, unit: .days))
        XCTAssertEqual(Span(seconds: 6.9 * 86400), Span(amount: 6, unit: .days))
        XCTAssertEqual(Span(seconds: 36 * 3600), Span(amount: 36, unit: .hours))
        XCTAssertEqual(Span(seconds: 2 * 3600), Span(amount: 2, unit: .hours))
        XCTAssertEqual(Span(seconds: 90 * 60), Span(amount: 90, unit: .minutes))
        XCTAssertEqual(Span(seconds: 5 * 60 + 40), Span(amount: 5, unit: .minutes))
        XCTAssertEqual(Span(seconds: 20), Span(amount: 1, unit: .minutes))
        XCTAssertEqual(Span(seconds: -5), Span(amount: 1, unit: .minutes))
    }

    // MARK: Notifications

    func testTheThreeNotifications() throws {
        let data: [String: Any] = ["challengeId": "c1", "title": "Weekend sprint", "titleId": "PPSA01234", "gameNames": ["en": "Stray"], "metric": "points", "endsAt": "2026-11-08T10:00:00.000Z"]
        var ended = data
        ended.merge(["rank": 1, "value": 420, "entrants": 4, "winner": ["displayName": "Robin", "handle": "robin", "value": 420]]) { _, new in new }
        var lost = data
        lost.merge(["rank": 3, "value": 0, "entrants": 4, "winner": NSNull()]) { _, new in new }
        let note = { (id: String, kind: String, actor: Any, data: [String: Any]) -> [String: Any] in
            ["id": id, "kind": kind, "actor": actor, "subjectId": "c1", "data": data, "read": false, "createdAt": "2026-11-06T09:00:00.000Z", "updatedAt": "2026-11-06T09:00:00.000Z"]
        }
        let page = try Self.decode(TogetherNotificationPage.self, ["notifications": [
            note("3", "challenge_ended", NSNull(), ended), note("2", "challenge_started", Self.person("f1"), data), note("1", "challenge_invite", Self.person("f1"), data),
            note("0", "challenge_ended", NSNull(), lost),
        ], "unread": 4, "more": false])
        let notes = page.notifications
        XCTAssertEqual(notes.map(\.kind), [.challengeEnded, .challengeStarted, .challengeInvite, .challengeEnded])
        XCTAssertEqual(notes[2].data.challengeId, "c1")
        XCTAssertEqual(notes[2].data.title, "Weekend sprint")
        XCTAssertEqual(notes[2].data.metric, "points")
        XCTAssertEqual(notes[2].data.gameNames?["en"], "Stray")
        XCTAssertEqual(notes[2].data.challengeEndsAt, ISO8601DateFormatter().date(from: "2026-11-08T10:00:00Z"))
        XCTAssertEqual(notes[0].data.rank, 1)
        XCTAssertEqual(notes[0].data.entrants, 4)
        XCTAssertEqual(notes[0].data.winner?.handle, "robin")
        XCTAssertEqual(notes[0].data.winner?.value, 420)
        XCTAssertTrue(notes[0].data.wonChallenge)
        XCTAssertFalse(notes[3].data.wonChallenge)
        XCTAssertNil(notes[3].data.winner)
        XCTAssertEqual(notes[0].challengeId, "c1")
        // No event of their own announces them: each gets its toast.
        XCTAssertTrue(notes.allSatisfy { $0.kind.toastsOnItsOwn })
        XCTAssertTrue(TogetherNotification.Kind.allKnown.contains(.challengeEnded))
    }
}
