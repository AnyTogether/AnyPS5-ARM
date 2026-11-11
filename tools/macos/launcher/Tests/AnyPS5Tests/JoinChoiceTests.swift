@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// Being in a party is not being in the same game. A copy made by another engine is rebuilt
/// before it starts instead of starting stale; a join that cannot go on says what differs with
/// both builds whole and the action that fits; Play on a game a friend hosts asks whether to join
/// theirs; and the party says for each member whose game they are in.
@MainActor
final class JoinChoiceTests: XCTestCase {
    let nightly = "0.2.36-arm-nightly.20261110.1-a6fff1ba742d"
    let stable = "0.2.36-arm-f75c475400e3"
    let robin = TogetherUser(id: "me", handle: "robin", displayName: "Robin", avatar: nil)
    let me = TogetherPerson(userId: "me", handle: "robin", displayName: "Robin", avatar: nil)
    let mira = TogetherPerson(userId: "u1", handle: "mira", displayName: "Mira", avatar: nil)
    private let fm = FileManager.default

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A launcher whose one game was unlocked by `built`, with `current` as the engine it uses now.
    private func model(built: String, current: String?) throws -> (AppModel, Game) {
        let model = try LauncherFixture.model(games: 1) { $0.engine = "custom" }
        let game = try XCTUnwrap(model.games.first)
        let root = try XCTUnwrap(model.root(of: game))
        let bundle = Installer.bundle(for: game, root: root)
        try write("eboot", to: bundle.appendingPathComponent("Contents/MacOS/eboot"))
        try write(#"{"source":"\#(game.folder.path)","titleID":"\#(game.titleID)","toolkit":"\#(built)","date":"2026-11-11T08:07:52Z"}"#,
                  to: bundle.appendingPathComponent("Contents/Resources/anyps5-install.json"))
        model.preview(games: model.games, root: root)
        if let current {
            let engine = fm.temporaryDirectory.appendingPathComponent("AnyPS5-tests-engine-\(UUID().uuidString)")
            try write(current, to: engine.appendingPathComponent("version.txt"))
            model.previewEngines(installed: [], catalogue: [], checked: nil, custom: Toolkit(root: engine))
        }
        return (model, game)
    }

    private func friend(_ person: TogetherPerson, game: TogetherFriend.Presence.Game?) -> TogetherFriend {
        TogetherFriend(userId: person.userId, handle: person.handle, displayName: person.displayName, avatar: nil,
                       presence: .init(state: game == nil ? "online" : "playing", titleId: game?.titleId, since: nil, game: game))
    }

    // MARK: A stale copy

    func testACopyMadeByAnotherEngineIsRebuiltBeforeItStartsNotOfferedAsItIs() throws {
        let (model, game) = try model(built: nightly, current: stable)
        XCTAssertEqual(model.state(of: game), .installed(outdated: true))
        XCTAssertTrue(model.needsRebuild(game))
        // What the session is told is the engine the copy was made with, whatever the launcher is now.
        XCTAssertEqual(model.engineBuild(for: game), nightly)
        XCTAssertEqual(model.togetherCopies().first?.nextEngineBuild, stable)
        model.primaryAction(game)
        XCTAssertNotEqual(model.overlay, .updateChoice, "no question: it is rebuilt")
        XCTAssertEqual(model.afterRebuild?.id, game.id, "the start waits on the rebuild")
        XCTAssertEqual(model.toast?.text, PT.format(.rebuildingFirst, game.name))
        XCTAssertNil(model.starting, "the stale copy did not start")
        model.cancelUnlock(game)
        XCTAssertNil(model.afterRebuild)
    }

    func testACopyMadeByTheEngineAtHandStartsWithoutARebuild() throws {
        let (model, game) = try model(built: stable, current: stable)
        XCTAssertEqual(model.state(of: game), .installed(outdated: false))
        XCTAssertFalse(model.needsRebuild(game))
        var went = false
        model.rebuildFirst(game) { went = true }
        XCTAssertTrue(went)
        XCTAssertNil(model.afterRebuild)
    }

    func testWhatWaitsOnARebuildGoesOnOnlyWhenItSucceeded() throws {
        let (model, game) = try model(built: nightly, current: stable)
        var went = 0
        model.afterRebuild = (game.id, { went += 1 })
        model.rebuildDone("another", succeeded: true)
        XCTAssertEqual(went, 0)
        model.rebuildDone(game.id, succeeded: false)
        XCTAssertEqual(went, 0)
        XCTAssertNil(model.afterRebuild)
        model.afterRebuild = (game.id, { went += 1 })
        model.rebuildDone(game.id, succeeded: true)
        XCTAssertEqual(went, 1)
    }

    // MARK: The message

    private func block(_ advice: EngineAdvice, host: String, yours: String, rebuild: (() -> Void)? = nil) -> JoinBlock {
        JoinBlock(kind: .engine(advice), hostName: "Mira", gameName: "Greenhollow", host: host, yours: yours, rebuild: rebuild)
    }

    func testTheMessageNamesTheEngineBuildAndShowsBothBuildsWhole() throws {
        let model = try LauncherFixture.model(games: 1)
        let rows = model.joinBlockedRows(block(.updateHost, host: nightly, yours: stable))
        XCTAssertEqual(rows.first?.title, "Different engine build")
        XCTAssertEqual(rows.first?.detail, "Mira and you run Greenhollow on different builds of the AnyPS5 engine, so the two games cannot connect\nThis AnyPS5 is newer. Ask Mira to update AnyPS5 and start the game again")
        XCTAssertEqual(rows.first?.wraps, true)
        let host = try XCTUnwrap(rows.first { $0.id == "blocked-host" }), you = try XCTUnwrap(rows.first { $0.id == "blocked-you" })
        XCTAssertEqual([host.title, host.detail], ["Mira", nightly])
        XCTAssertEqual([you.title, you.detail], ["You", stable])
        XCTAssertTrue(host.wraps && you.wraps, "each build on lines of its own, never cut")
        // The launcher that is current is never told to update.
        XCTAssertFalse(rows.contains { $0.id == "blocked-update" || $0.id == "blocked-rebuild" })
        XCTAssertEqual(rows.last?.id, "blocked-close")
    }

    func testEachVariantOffersTheActionThatFits() throws {
        let model = try LauncherFixture.model(games: 1)
        var rebuilt = false
        let stale = model.joinBlockedRows(block(.rebuild, host: stable, yours: nightly) { rebuilt = true })
        XCTAssertEqual(stale.first?.detail?.components(separatedBy: "\n").last, "Your copy was made with another engine. Rebuild it and you can join")
        let rebuild = try XCTUnwrap(stale.first { $0.id == "blocked-rebuild" })
        XCTAssertEqual(rebuild.title, "Rebuild and join")
        XCTAssertFalse(stale.contains { $0.id == "blocked-update" })
        model.open(.joinBlocked)
        guard case .action(_, let run) = rebuild.kind else { return XCTFail("not an action") }
        run()
        XCTAssertTrue(rebuilt)
        XCTAssertNil(model.overlay)

        let older = model.joinBlockedRows(block(.updateYours, host: stable, yours: "0.2.35-arm-0123456789ab"))
        XCTAssertEqual(older.first?.detail?.components(separatedBy: "\n").last, "Mira plays on a newer AnyPS5. Update this one, then join")
        XCTAssertEqual(older.first { $0.id == "blocked-update" }?.title, "Check for Updates")

        let channel = model.joinBlockedRows(block(.hostNightly, host: "0.2.37-arm-nightly.20261112.1-0123456789ab", yours: stable))
        XCTAssertEqual(channel.first?.detail?.components(separatedBy: "\n").last, "Mira plays on a nightly build newer than this release. Use the same update channel on both")
        XCTAssertFalse(channel.contains { $0.id == "blocked-update" })

        let same = model.joinBlockedRows(block(.sameEngine, host: "0.2.36-arm-0123456789ab", yours: stable))
        XCTAssertEqual(same.first?.detail?.components(separatedBy: "\n").last, "The two engines are not the same build. Use the same engine on both")
        XCTAssertFalse(same.contains { $0.id == "blocked-update" })
    }

    func testAGameVersionIsNamedAsOneAndMayBeTriedAnyway() throws {
        let model = try LauncherFixture.model(games: 1)
        var tried = false
        let rows = model.joinBlockedRows(JoinBlock(kind: .gameVersion(youUpdate: true), hostName: "Mira", gameName: "Greenhollow", host: "01.044.000", yours: "01.008.000",
                                                   tryAnyway: { tried = true }))
        XCTAssertEqual(rows.first?.title, "Different game version")
        XCTAssertEqual(rows.first?.detail, "Mira and you have different versions of Greenhollow\nYou need Greenhollow version 01.044.000; you have 01.008.000. Add the update to your library")
        XCTAssertEqual(rows.first { $0.id == "blocked-host" }?.detail, "01.044.000")
        XCTAssertEqual(rows.first { $0.id == "blocked-you" }?.detail, "01.008.000")
        guard case .action(_, let run)? = rows.first(where: { $0.id == "blocked-try-anyway" })?.kind else { return XCTFail("no Try Anyway") }
        run()
        XCTAssertTrue(tried)
        let host = AppModel.joinBlockTexts(JoinBlock(kind: .gameVersion(youUpdate: false), hostName: "Mira", gameName: "Greenhollow", host: "01.008.000", yours: "01.044.000"))
        XCTAssertEqual(host.advice, "Mira has version 01.008.000; you have 01.044.000. Ask them to update")
    }

    func testTheEngineAdviceComesFromTheTwoBuildsAndTheEngineAtHand() throws {
        let (model, game) = try model(built: nightly, current: stable)
        XCTAssertEqual(model.engineBlock(hostName: "Mira", titleId: game.titleID, host: stable, yours: nightly, rebuild: {}).kind, .engine(.rebuild))
        XCTAssertNotNil(model.engineBlock(hostName: "Mira", titleId: game.titleID, host: stable, yours: nightly, rebuild: {}).rebuild)
        XCTAssertEqual(model.engineBlock(hostName: "Mira", titleId: game.titleID, host: "0.2.37-arm-0123456789ab", yours: nightly).kind, .engine(.updateYours))
        XCTAssertNil(model.engineBlock(hostName: "Mira", titleId: game.titleID, host: "0.2.37-arm-0123456789ab", yours: nightly, rebuild: {}).rebuild, "a rebuild would not reach the host's")
        let offer = PlayTogetherOffer(sessionId: "s1", hostId: "u1", hostName: "Mira", titleId: game.titleID, gameVersion: "01.000", engineBuild: "0.2.35-arm-0123456789ab",
                                      versionRule: "exact", players: 1, capacity: 4)
        XCTAssertEqual(model.verdictText(.engine(have: nightly, need: offer.engineBuild, youUpdate: false), offer: offer),
                       "Different engine build\nThis AnyPS5 is newer. Ask Mira to update AnyPS5 and start the game again")
    }

    // MARK: Join theirs, or start your own

    func testPlayOnAGameAFriendHostsAsksToJoinTheirsFirst() throws {
        let (model, game) = try model(built: stable, current: stable)
        model.togetherUser = robin
        model.togetherFriends = [friend(mira, game: .init(sessionId: "s2", titleId: game.titleID, joinable: true, players: 1, capacity: 4, kind: "online", hostId: "u1"))]
        model.previewParty(TogetherParty(id: "p1", leaderId: "me", privacy: "invite", members: [me, mira], invited: [], call: nil))
        model.primaryAction(game)
        XCTAssertEqual(model.overlay, .joinOrHost)
        XCTAssertNil(model.starting, "no second session is opened without a word")
        let choice = try XCTUnwrap(model.joinChoice)
        XCTAssertEqual(choice.other, JoinableGame(sessionId: "s2", titleId: game.titleID, personId: "u1", together: false))
        XCTAssertEqual(PT.format(.askJoin, choice.name), "Mira is playing this. Join their game, or start your own?")
        let rows = model.panelCategories().first?.rows ?? []
        XCTAssertEqual(rows.map(\.id), ["choice-join", "choice-own"], "Join is first, the default")
        XCTAssertEqual(model.focusedRow(in: rows), 0)
        XCTAssertEqual(rows[0].title, "Join Mira's \(game.name)")
        XCTAssertEqual(rows[1].title, "Start my own game")
        XCTAssertEqual(rows[1].detail, "A separate session. Mira will not be in it")
        XCTAssertEqual(PT.format(.separate, "Mira"), "You started a separate game. Mira is not in it")
    }

    func testNobodyPlayingItOrNoRoomAsksNothing() throws {
        let (model, game) = try model(built: stable, current: stable)
        model.togetherUser = robin
        XCTAssertNil(model.joinableGame(for: game))
        model.togetherFriends = [friend(mira, game: .init(sessionId: "s2", titleId: game.titleID, joinable: true, players: 4, capacity: 4))]
        XCTAssertNil(model.joinableGame(for: game), "full")
        model.togetherFriends = [friend(mira, game: .init(sessionId: "s2", titleId: "PPSA99999", joinable: true, players: 1, capacity: 4))]
        XCTAssertNil(model.joinableGame(for: game), "another title")
        model.togetherFriends = [friend(mira, game: .init(sessionId: "s2", titleId: game.titleID, joinable: true, players: 1, capacity: 4))]
        model.togetherUser = nil
        XCTAssertNil(model.joinableGame(for: game), "signed out")
    }

    // MARK: Who is in whose game

    func testThePartySaysForEachMemberWhoseGameTheyAreInWithJoinRightThere() throws {
        let (model, game) = try model(built: stable, current: stable)
        model.togetherUser = robin
        let party = TogetherParty(id: "p1", leaderId: "me", privacy: "invite", members: [me, mira], invited: [], call: nil)
        model.previewParty(party)
        model.togetherFriends = [friend(mira, game: .init(sessionId: "s2", titleId: game.titleID, joinable: true, players: 1, capacity: 4, kind: "online", hostId: "u1"))]
        model.previewGameSession(TogetherGameSession(id: "s1", host: me, titleId: game.titleID, gameVersion: "01.000", engineBuild: stable, capacity: 4, joinable: true, players: [me]), invites: [])

        var rows = model.partyRows()
        let member = try XCTUnwrap(rows.firstIndex { $0.id == "party-member-u1" })
        XCTAssertTrue(try XCTUnwrap(rows[member].detail).hasSuffix("In another game of \(game.name)"), rows[member].detail ?? "")
        XCTAssertEqual(rows[member + 1].id, "party-member-join-u1", "Join right under the member")
        XCTAssertEqual(rows[member + 1].title, "Join Mira's \(game.name)")
        XCTAssertEqual(rows.first { $0.id == "together-about" }?.detail, "A party is voice and chat. A game session is what connects your games")
        XCTAssertEqual(model.partyGameRows().map(\.id), ["party-game-u1"], "the quick menu has the same member, as the Join")
        XCTAssertEqual(model.partyGameRows().first?.title, "Join Mira's \(game.name)")

        // Mira joined the user's session.
        model.previewGameSession(TogetherGameSession(id: "s1", host: me, titleId: game.titleID, gameVersion: "01.000", engineBuild: stable, capacity: 4, joinable: true, players: [me, mira]), invites: [])
        rows = model.partyRows()
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.id == "party-member-u1" }?.detail).hasSuffix("In your game"))
        XCTAssertFalse(rows.contains { $0.id == "party-member-join-u1" })
        XCTAssertEqual(model.partyGameRows().first?.detail, "In your game")

        // Mira plays nothing.
        model.togetherFriends = [friend(mira, game: nil)]
        model.previewGameSession(nil, invites: [])
        XCTAssertTrue(try XCTUnwrap(model.partyRows().first { $0.id == "party-member-u1" }?.detail).hasSuffix("Not in a game"))
        XCTAssertEqual(AppModel.memberGameText(.other(sessionId: "s2", titleId: "T", hostId: "u1", joinable: true, together: false, sameTitle: false)) { _ in "Greenhollow" }, "Playing Greenhollow")
    }
}
