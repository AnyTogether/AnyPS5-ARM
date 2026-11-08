@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// A tester's report of 7 November 2026 on AnyPS5 Desktop, the same on the Mac and the website:
/// Find players says how many are online now, and a game's name in recent activity opens the
/// game's hub.
@MainActor
final class OnlineNowAndActivityGameTests: XCTestCase {
    static let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)

    func testTheOnlineCountSaysOneOrManyAndNothingWithoutOne() throws {
        let model = try LauncherFixture.model()
        XCTAssertNil(model.onlineNowText)
        model.discover.online = 0
        XCTAssertNil(model.onlineNowText, "nobody counted: no line")
        model.discover.online = 1
        XCTAssertEqual(model.onlineNowText, FP.format(.onlineNowOne, "1"))
        model.discover.online = 12
        XCTAssertEqual(model.onlineNowText, FP.format(.onlineNowMany, "12"))
    }

    func testAnActivityLineLinksTheGameToItsHub() throws {
        let model = try LauncherFixture.model()
        model.togetherUser = SocialPreviews.me
        let game = try XCTUnwrap(model.games.first)
        let item = TogetherActivity(id: "a1", kind: .firstPlay, createdAt: Date(), actor: Self.mira,
                                    game: .init(titleId: game.titleID, names: ["en": "Server name"]))
        let line = model.activityLine(item)
        XCTAssertEqual(String(line.characters), " " + model.activityText(item))
        let linked = line.runs.compactMap { run in run.link.map { (String(line[run.range].characters), $0) } }
        XCTAssertEqual(linked.map(\.0), [game.name], "only the game's name, as this Mac names it")
        XCTAssertEqual(linked.first?.1, AppModel.hubLink(game.titleID))

        model.openActivityGame(item)
        XCTAssertEqual(model.overlay, .gameHub)
        XCTAssertEqual(model.discover.hubTitle, game.titleID)
        XCTAssertEqual(model.discover.hubName, game.name)
    }

    func testAnItemWithoutAGameHasNoLink() throws {
        let model = try LauncherFixture.model()
        let item = TogetherActivity(id: "a2", kind: .milestone, createdAt: Date(), actor: Self.mira, milestone: .init(kind: "hours", value: 100))
        XCTAssertTrue(model.activityLine(item).runs.allSatisfy { $0.link == nil })
    }

    func testSelectOnAProfilesActivityItemOpensItsGamesHubAndBackReturns() throws {
        let model = try LauncherFixture.model()
        model.togetherUser = SocialPreviews.me
        let game = try XCTUnwrap(model.games.first)
        model.overlay = .profile
        model.social.profileActivity = [
            TogetherActivity(id: "a2", kind: .milestone, createdAt: Date(), actor: Self.mira, milestone: .init(kind: "hours", value: 100)),
            TogetherActivity(id: "a1", kind: .firstPlay, createdAt: Date(), actor: Self.mira, game: .init(titleId: game.titleID, names: [:])),
        ]
        model.profileColumn = 2
        model.profileIndex = 0
        model.profileCommand(.select)
        XCTAssertEqual(model.overlay, .profile, "a milestone has no game")
        model.profileIndex = 1
        model.profileCommand(.select)
        XCTAssertEqual(model.overlay, .gameHub)
        XCTAssertEqual(model.discover.hubTitle, game.titleID)
        model.backFromDiscover()
        XCTAssertEqual(model.overlay, .profile)
        XCTAssertEqual(model.profileColumn, 2)
        XCTAssertEqual(model.profileIndex, 1)
    }
}
