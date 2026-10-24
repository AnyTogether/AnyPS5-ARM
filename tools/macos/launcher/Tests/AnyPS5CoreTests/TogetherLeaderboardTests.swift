import XCTest
@testable import AnyPS5Core

final class TogetherLeaderboardTests: TogetherSignedInCase {
    static func person(_ id: String) -> [String: Any] { ["userId": id, "handle": "h\(id)", "displayName": "N\(id)", "avatar": NSNull()] }
    static func entry(_ rank: Int, _ id: String, _ value: Int) -> [String: Any] { ["rank": rank, "user": person(id), "value": value] }

    static func board(_ board: String = "points", scope: String = "friends", entries: [[String: Any]], me: [String: Any], around: [[String: Any]] = [], total: Int? = nil,
                      game: Any = NSNull()) -> [String: Any] {
        ["board": board, "scope": scope, "game": game, "entries": entries, "me": me, "around": around, "total": total ?? entries.count, "updatedAt": "2026-10-24T10:00:00.000Z"]
    }

    func testOverallPointsAmongFriends() async throws {
        FakeTogether.handler = { _, _ in
            (200, Self.board(entries: [Self.entry(1, "f1", 4200), Self.entry(2, "u1", 1830), Self.entry(2, "f2", 1830)], me: ["rank": 2, "value": 1830, "listed": true]))
        }
        let board = try await client.pointsLeaderboard(scope: .friends)
        XCTAssertEqual(last(), "GET /api/v1/leaderboards/points?scope=friends")
        XCTAssertEqual(board.entries.map(\.rank), [1, 2, 2])
        XCTAssertEqual(board.entries.first?.user.handle, "hf1")
        XCTAssertEqual(board.me, .init(rank: 2, value: 1830, listed: true))
        XCTAssertNil(board.game)
        XCTAssertEqual(board.lines(me: "u1"), [.entry(board.entries[0], me: false), .entry(board.entries[1], me: true), .entry(board.entries[2], me: false)])
    }

    func testAGamesBoardByTimeForEveryone() async throws {
        FakeTogether.handler = { _, _ in
            (200, Self.board("time", scope: "global", entries: [Self.entry(1, "f1", 90000), Self.entry(2, "f2", 3600)], me: ["rank": 41, "value": 600, "listed": true],
                             around: [Self.entry(40, "x", 700), Self.entry(41, "u1", 600), Self.entry(42, "y", 500)], total: 300,
                             game: ["titleId": "PPSA01234", "names": ["en": "Stray"], "iconUrl": NSNull()]))
        }
        let board = try await client.gameLeaderboard("PPSA01234", by: .time, scope: .global)
        XCTAssertEqual(last(), "GET /api/v1/games/PPSA01234/leaderboard?by=time&scope=global")
        XCTAssertEqual(board.board, "time")
        XCTAssertEqual(board.scope, .global)
        XCTAssertEqual(board.total, 300)
        XCTAssertEqual(board.game?.name(in: "en"), "Stray")
        // The top, a gap, then the people around this user.
        let lines = board.lines(me: "u1")
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines[2], .gap)
        XCTAssertEqual(lines[4], .entry(board.around[1], me: true))
    }

    /// Not on the board (private, or nothing yet): a line says where they would be.
    func testNotListed() throws {
        let json = Self.board(scope: "global", entries: [Self.entry(1, "f1", 50)], me: ["rank": 3, "value": 20, "listed": false])
        let board = try JSONDecoder.together.decode(TogetherLeaderboard.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(board.lines(me: "u1").last, .unlisted(rank: 3, value: 20))
        let nothing = try JSONDecoder.together.decode(TogetherLeaderboard.self, from: JSONSerialization.data(withJSONObject: Self.board(entries: [], me: ["rank": NSNull(), "value": 0, "listed": false])))
        XCTAssertEqual(nothing.lines(me: "u1"), [.unlisted(rank: nil, value: 0)])
    }

    /// Around this user right after the top: no gap, and no one twice.
    func testAroundJoinsTheTop() throws {
        let json = Self.board(entries: [Self.entry(1, "a", 9), Self.entry(2, "b", 8)], me: ["rank": 3, "value": 7, "listed": true],
                              around: [Self.entry(2, "b", 8), Self.entry(3, "u1", 7), Self.entry(4, "c", 6)])
        let board = try JSONDecoder.together.decode(TogetherLeaderboard.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(board.lines(me: "u1").map(\.rank), [1, 2, 3, 4])
    }

    func testGamesToPickABoardFrom() async throws {
        FakeTogether.handler = { _, _ in (200, ["games": [["titleId": "PPSA01234", "names": ["en": "Stray"], "iconUrl": NSNull(), "players": 12, "mine": true]]]) }
        let games = try await client.leaderboardGames()
        XCTAssertEqual(last(), "GET /api/v1/leaderboards/games")
        XCTAssertEqual(games.first?.players, 12)
        XCTAssertEqual(games.first?.mine, true)
    }

    func testAGameNoOneHasPlayed() async throws {
        FakeTogether.handler = { _, _ in (404, ["code": "not_found", "status": 404, "title": "No such game"]) }
        do {
            _ = try await client.gameLeaderboard("PPSA00001", by: .points, scope: .friends)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.status, 404)
        }
    }
}
