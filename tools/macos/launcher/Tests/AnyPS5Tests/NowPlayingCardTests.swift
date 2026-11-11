@testable import AnyPS5
import AnyPS5Core
import XCTest

/// The players, as the tests say them: no AppleScript, no Spotify, no Music.
final class FakePlayers: NowPlayingSource, @unchecked Sendable {
    var readings: [NowPlayingReading] = []
    var denied: Set<NowPlayingPlayer> = []
    var reads = 0
    var sent: [String] = []
    var forgotten = 0

    func read(_ done: @escaping @Sendable ([NowPlayingReading], Set<NowPlayingPlayer>) -> Void) {
        reads += 1
        done(readings, denied)
    }

    func send(_ command: NowPlayingCommand, to player: NowPlayingPlayer) { sent.append("\(command.rawValue) \(player.name)") }
    func forgetDenials() { forgotten += 1 }
}

/// Now playing in the launcher: the quick menu's card and its keys, the two switches in
/// Settings › Behaviour and who sees the second, what friends are told, and a friend's line.
@MainActor
final class NowPlayingCardTests: XCTestCase {
    let playing = NowPlayingReading(player: .spotify, state: .playing, title: "Around the World", artist: "Daft Punk")
    let paused = NowPlayingReading(player: .music, state: .paused, title: "Teardrop", artist: "Massive Attack")
    let robin = TogetherUser(id: "u1", handle: "robin", displayName: "Robin", avatar: nil)

    func model(_ configure: (inout Preferences) -> Void = { _ in }) throws -> (AppModel, FakePlayers) {
        let model = try LauncherFixture.model(configure: configure)
        let players = FakePlayers()
        model.nowPlaying.source = players
        return (model, players)
    }

    func behaviour(_ model: AppModel) throws -> [PanelRow] {
        model.open(.settings)
        return try XCTUnwrap(model.panelCategories().first { $0.id == "behaviour" }, "no Behaviour").rows
    }

    /// Lets the answers the fake gave on another turn of the main actor arrive.
    func settle(_ model: AppModel, until done: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(done(), "it never came")
    }

    func testTheCardSitsJustBeforeCloseGameOnlyWhileSomethingPlaysOrIsPaused() throws {
        let (model, _) = try model()
        model.overlay = .quickMenu
        XCTAssertFalse(model.quickMenuRows().contains { $0.track != nil }, "no media session, no card")
        model.nowPlayingRead([playing], denied: [])
        var rows = model.quickMenuRows()
        XCTAssertEqual(rows.last?.title, "Close Game")
        let card = try XCTUnwrap(rows.dropLast().last)
        XCTAssertEqual(card.track, NowPlayingTrack(title: "Around the World", artist: "Daft Punk", player: "Spotify", playerID: "com.spotify.client", playing: true))
        XCTAssertEqual(card.title, "Now playing")
        XCTAssertEqual(card.detail, "Now playing in Spotify")
        XCTAssertFalse(card.destructive)
        XCTAssertEqual(rows.map(\.id), Array(rows.indices), "the rows' numbers run on")
        model.nowPlayingRead([paused], denied: [])
        rows = model.quickMenuRows()
        XCTAssertEqual(rows.dropLast().last?.detail, "Paused in Music")
        model.nowPlayingRead([NowPlayingReading(player: .music, state: .stopped)], denied: [])
        XCTAssertFalse(model.quickMenuRows().contains { $0.track != nil })
    }

    func testTheSwitchTurnedOffTakesTheCardAway() throws {
        let (model, players) = try model { $0.nowPlayingCard = false }
        model.overlay = .quickMenu
        XCTAssertNil(model.nowPlaying.every, "nobody is asked for a card that is off")
        XCTAssertEqual(players.reads, 0)
        model.nowPlayingRead([playing], denied: [])
        XCTAssertFalse(model.quickMenuRows().contains { $0.track != nil })
        XCTAssertNil(model.nowPlayingTrack)
    }

    func testLeftAndRightSkipAndSelectPlaysOrPausesOnTheCard() throws {
        let (model, players) = try model()
        model.overlay = .quickMenu
        model.nowPlayingRead([playing], denied: [])
        let card = try XCTUnwrap(model.quickMenuRows().firstIndex { $0.track != nil })
        model.menuIndex = card
        XCTAssertTrue(model.gameMenuCommand(.left))
        XCTAssertTrue(model.gameMenuCommand(.right))
        XCTAssertTrue(model.gameMenuCommand(.select))
        XCTAssertEqual(players.sent, ["previous Spotify", "next Spotify", "playPause Spotify"])
        XCTAssertEqual(model.menuIndex, card, "the focus stays on the card")
        XCTAssertEqual(model.overlay, .quickMenu, "play or pause does not resume the game")
        // Up and down move as on every row.
        _ = model.gameMenuCommand(.down)
        XCTAssertEqual(model.menuIndex, card + 1)
        _ = model.gameMenuCommand(.up)
        _ = model.gameMenuCommand(.up)
        XCTAssertEqual(model.menuIndex, card - 1)
        // Off the card, left and right send nothing.
        _ = model.gameMenuCommand(.left)
        XCTAssertEqual(players.sent.count, 3)
    }

    func testTheFocusKeepsItsRowWhenTheCardComesAndNeverLandsOnCloseGameWhenItGoes() throws {
        let (model, _) = try model()
        model.overlay = .quickMenu
        model.menuIndex = model.quickMenuRows().count - 1
        XCTAssertEqual(model.quickMenuRows()[model.menuIndex].title, "Close Game")
        model.nowPlayingRead([playing], denied: [])
        XCTAssertEqual(model.quickMenuRows()[model.menuIndex].title, "Close Game", "still on Close Game, one row down")
        model.menuIndex -= 1
        XCTAssertNotNil(model.quickMenuRows()[model.menuIndex].track)
        model.nowPlayingRead([], denied: [])
        XCTAssertNotEqual(model.quickMenuRows()[model.menuIndex].title, "Close Game", "the card went: the row above it")
        model.menuIndex = 0
        model.nowPlayingRead([playing], denied: [])
        XCTAssertEqual(model.menuIndex, 0, "Resume stays Resume")
    }

    func testTheQuickMenuAsksThePlayersAndClosingItStops() async throws {
        let (model, players) = try model()
        players.readings = [playing]
        XCTAssertEqual(players.reads, 0, "nothing is asked before the card is wanted")
        XCTAssertNil(model.nowPlaying.every)
        model.overlay = .quickMenu
        XCTAssertEqual(model.nowPlaying.every, AppModel.nowPlayingMenuEvery)
        try await settle(model) { model.nowPlayingTrack != nil }
        XCTAssertEqual(players.reads, 1)
        model.overlay = nil
        XCTAssertNil(model.nowPlaying.every, "no timer while the game plays")
    }

    func testSharingKeepsASlowWatchWithTheMenuClosed() async throws {
        let (model, players) = try model { $0.nowPlayingShare = true }
        players.readings = [playing]
        model.followNowPlaying()
        XCTAssertNil(model.nowPlaying.every, "signed out: nothing to share, nobody asked")
        model.togetherUser = robin
        model.followNowPlaying()
        XCTAssertEqual(model.nowPlaying.every, AppModel.nowPlayingShareEvery)
        try await settle(model) { model.nowPlayingListening != nil }
        XCTAssertEqual(model.nowPlayingListening, TogetherListening(title: "Around the World", artist: "Daft Punk"))
        model.overlay = .quickMenu
        XCTAssertEqual(model.nowPlaying.every, AppModel.nowPlayingMenuEvery)
        model.overlay = nil
        XCTAssertEqual(model.nowPlaying.every, AppModel.nowPlayingShareEvery)
    }

    func testTheSwitchesComeAfterDiscordsRowsCardOnAndSharingOffByDefault() throws {
        let (model, _) = try model()
        model.togetherUser = robin
        let rows = try behaviour(model)
        let ids = rows.map(\.id)
        let discord = try XCTUnwrap(ids.firstIndex(of: "discordJoin"))
        XCTAssertEqual(Array(ids[(discord + 1)...(discord + 2)]), ["nowPlayingCard", "nowPlayingShare"])
        let card = try XCTUnwrap(rows.first { $0.id == "nowPlayingCard" })
        XCTAssertEqual(card.title, "Now playing in the quick menu")
        XCTAssertEqual(card.detail?.contains("Spotify or Music"), true, "the Mac says which players it can read")
        guard case .toggle(let cardOn, let setCard) = card.kind else { return XCTFail("not a toggle") }
        XCTAssertTrue(cardOn)
        let share = try XCTUnwrap(rows.first { $0.id == "nowPlayingShare" })
        XCTAssertEqual(share.title, "Show friends what I'm listening to")
        guard case .toggle(let shareOn, let setShare) = share.kind else { return XCTFail("not a toggle") }
        XCTAssertFalse(shareOn)
        setCard(false)
        XCTAssertEqual(model.preferences.nowPlayingCard, false)
        setCard(true)
        XCTAssertNil(model.preferences.nowPlayingCard, "the default is not kept")
        setShare(true)
        XCTAssertEqual(model.preferences.nowPlayingShare, true)
        setShare(false)
        XCTAssertNil(model.preferences.nowPlayingShare)
        XCTAssertTrue(AppModel.personalKeys.isSuperset(of: ["nowPlayingCard", "nowPlayingShare"]), "each profile's own")
    }

    func testTheFriendsSwitchIsNotListedSignedOutOrUnderFamilyLimits() throws {
        let (model, _) = try model { $0.nowPlayingShare = true }
        model.nowPlayingRead([playing], denied: [])
        XCTAssertFalse(try behaviour(model).contains { $0.id == "nowPlayingShare" }, "signed out")
        XCTAssertTrue(try behaviour(model).contains { $0.id == "nowPlayingCard" }, "the card needs no account")
        XCTAssertNil(model.nowPlayingListening, "and nothing is told")
        model.togetherUser = robin
        XCTAssertTrue(try behaviour(model).contains { $0.id == "nowPlayingShare" })
        XCTAssertNotNil(model.nowPlayingListening)
        model.family = .locked
        XCTAssertFalse(try behaviour(model).contains { $0.id == "nowPlayingShare" }, "a child's profile")
        XCTAssertNil(model.nowPlayingListening, "the switch left on tells nothing under family limits")
        XCTAssertNotNil(model.nowPlayingTrack, "the card stays")
    }

    func testFriendsAreToldOnlyWithTheSwitchOnAndNotAMinuteAfterAPause() throws {
        let (model, _) = try model()
        model.togetherUser = robin
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        model.nowPlayingRead([playing], denied: [], now: start)
        XCTAssertNil(model.nowPlayingListening, "off by default")
        model.preferences.nowPlayingShare = true
        XCTAssertEqual(model.nowPlayingListening, TogetherListening(title: "Around the World", artist: "Daft Punk"))
        var pausedNow = playing
        pausedNow.state = .paused
        model.nowPlayingRead([pausedNow], denied: [], now: Date().addingTimeInterval(-30))
        XCTAssertNotNil(model.nowPlayingListening, "paused half a minute ago")
        model.nowPlayingRead([playing], denied: [], now: Date().addingTimeInterval(-200))
        model.nowPlayingRead([pausedNow], denied: [], now: Date().addingTimeInterval(-100))
        XCTAssertNil(model.nowPlayingListening, "paused for over a minute")
        XCTAssertNotNil(model.nowPlayingTrack, "the card still shows it")
        model.nowPlayingRead([], denied: [])
        XCTAssertNil(model.nowPlayingListening)
    }

    func testARefusalByMacOSIsSaidInTheRowAndTurningTheSwitchOnAsksAgain() async throws {
        let (model, players) = try model()
        XCTAssertEqual(try behaviour(model).first { $0.id == "nowPlayingCard" }?.detail?.hasPrefix("Shows what Spotify or Music is playing"), true)
        model.nowPlayingRead([], denied: [.spotify])
        let row = try XCTUnwrap(try behaviour(model).first { $0.id == "nowPlayingCard" })
        XCTAssertEqual(row.detail, "macOS does not let AnyPS5 read Spotify or Music. Allow it in System Settings, Privacy & Security, Automation, AnyPS5.")
        guard case .toggle(_, let set) = row.kind else { return XCTFail("not a toggle") }
        set(false)
        XCTAssertEqual(players.forgotten, 0)
        XCTAssertEqual(players.reads, 0)
        players.readings = [playing]
        set(true)
        XCTAssertEqual(players.forgotten, 1, "the refusal is forgotten")
        XCTAssertEqual(players.reads, 1, "and the players are asked now, where the user turned it on")
        XCTAssertTrue(model.nowPlaying.denied.isEmpty)
        try await settle(model) { model.nowPlaying.state.track != nil }
    }

    func testAFriendsLineSaysWhatTheyListenTo() throws {
        let (model, _) = try model()
        let online = TogetherFriend.Presence(state: "online", titleId: nil, since: nil, listening: TogetherListening(title: "Around the World", artist: "Daft Punk"))
        XCTAssertEqual(model.presenceText(online), "Online · Listening to Around the World, Daft Punk")
        let noArtist = TogetherFriend.Presence(state: "online", titleId: nil, since: nil, party: .init(id: "p1", size: 2, max: 8, open: true), listening: TogetherListening(title: "Teardrop"))
        XCTAssertEqual(model.presenceText(noArtist), "Online · in a party 2/8 · Listening to Teardrop")
        let playingGame = TogetherFriend.Presence(state: "in_game", titleId: "PPSA00001", since: nil, listening: TogetherListening(title: "Teardrop"))
        XCTAssertEqual(model.presenceText(playingGame), "Playing Game 1 · Listening to Teardrop")
        let offline = TogetherFriend.Presence(state: "offline", titleId: nil, since: nil, listening: TogetherListening(title: "Teardrop"))
        XCTAssertEqual(model.presenceText(offline), "Offline", "offline says nothing more")
        XCTAssertEqual(model.presenceText(TogetherFriend.Presence(state: "online", titleId: nil, since: nil)), "Online")
        T.texts = T.load([T.sourceFolder])
    }

    func testTheScriptsNameTheAppsByIdentifierAndAskOnlyRunningOnes() {
        for player in NowPlayingPlayer.allCases {
            let state = ScriptedPlayers.stateScript(player)
            XCTAssertTrue(state.hasPrefix("if application id \"\(player.rawValue)\" is running then"), "a player that does not run is never started")
            XCTAssertFalse(state.contains("tell application \""), "by identifier, not by name")
            for command in NowPlayingCommand.allCases {
                XCTAssertTrue(ScriptedPlayers.commandScript(command, player).hasPrefix("if application id \"\(player.rawValue)\" is running then"))
            }
        }
        XCTAssertTrue(ScriptedPlayers.stateScript(.spotify).contains("artwork url"))
        XCTAssertFalse(ScriptedPlayers.stateScript(.music).contains("artwork url"))
        XCTAssertTrue(ScriptedPlayers.commandScript(.playPause, .music).contains("to playpause"))
        XCTAssertTrue(ScriptedPlayers.commandScript(.next, .spotify).contains("to next track"))
        XCTAssertTrue(ScriptedPlayers.commandScript(.previous, .spotify).contains("to previous track"))
        XCTAssertNil(ScriptedPlayers.picture(Data(repeating: 0, count: 200)), "bytes that are no picture are no cover")
    }

    func testTheBarsRestWhilePausedAndMoveWithinTheirHeight() {
        for bar in 0..<3 {
            for step in 0..<50 {
                let level = EqualiserBars.level(bar, at: Double(step) * 0.07)
                XCTAssertTrue((0.35...1).contains(level), "\(level)")
            }
        }
        XCTAssertEqual(EqualiserBars.resting.count, 3)
    }
}
