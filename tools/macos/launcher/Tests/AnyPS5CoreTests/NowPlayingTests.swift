@testable import AnyPS5Core
import XCTest

/// Now playing's rules without any player: which player shows, what friends are told and for how
/// long after a pause, how the title and artist are cut, and the heartbeat's `listening`.
final class NowPlayingTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func reading(_ player: NowPlayingPlayer, _ state: NowPlayingReading.State, _ title: String = "Around the World", artist: String = "Daft Punk") -> NowPlayingReading {
        NowPlayingReading(player: player, state: state, title: title, artist: artist)
    }

    func testAStoppedPlayerOrOneWithoutATitleShowsNothing() {
        XCTAssertNil(reading(.spotify, .stopped).track)
        XCTAssertNil(reading(.music, .playing, "  ").track)
        let track = reading(.music, .paused, " Teardrop ", artist: " ").track
        XCTAssertEqual(track, NowPlayingTrack(title: "Teardrop", artist: nil, player: "Music", playerID: "com.apple.Music", playing: false))
        XCTAssertEqual(NowPlayingReading(player: .music, state: .playing, title: "Teardrop", name: "Müzik").track?.player, "Müzik", "the Mac's own name for the app")
    }

    func testThePlayingPlayerShowsElseTheOneActiveLast() {
        var state = NowPlayingState()
        state.update([reading(.spotify, .paused, "One"), reading(.music, .playing, "Two")], now: start)
        XCTAssertEqual(state.track?.title, "Two", "the one that plays")
        // Music pauses: it was active last, so it stays.
        state.update([reading(.spotify, .paused, "One"), reading(.music, .paused, "Two")], now: start + 5)
        XCTAssertEqual(state.track?.title, "Two")
        // Spotify changes its track while paused: now it was active last.
        state.update([reading(.spotify, .paused, "Three"), reading(.music, .paused, "Two")], now: start + 10)
        XCTAssertEqual(state.track?.title, "Three")
        // Both play: the one that started last.
        state.update([reading(.spotify, .playing, "Three"), reading(.music, .paused, "Two")], now: start + 15)
        state.update([reading(.spotify, .playing, "Three"), reading(.music, .playing, "Two")], now: start + 20)
        XCTAssertEqual(state.track?.title, "Two")
        // Music quits: Spotify alone.
        XCTAssertTrue(state.update([reading(.spotify, .playing, "Three")], now: start + 25))
        XCTAssertEqual(state.track?.playerID, "com.spotify.client")
        XCTAssertTrue(state.update([], now: start + 30))
        XCTAssertNil(state.track)
    }

    func testTwoPausedPlayersNeverSeenActiveShowTheFirst() {
        XCTAssertEqual(NowPlayingState.choose([reading(.spotify, .paused, "One"), reading(.music, .paused, "Two")], active: [:])?.title, "One")
        XCTAssertNil(NowPlayingState.choose([reading(.spotify, .stopped), reading(.music, .playing, "")], active: [:]))
    }

    func testACoverArrivingLaterIsAChangeButNotActivity() {
        var state = NowPlayingState()
        state.update([reading(.spotify, .paused, "One"), reading(.music, .paused, "Two")], now: start)
        state.update([reading(.spotify, .paused, "One"), reading(.music, .paused, "Three")], now: start + 1)
        XCTAssertEqual(state.track?.title, "Three")
        var withCover = reading(.spotify, .paused, "One")
        withCover.artwork = Data([1, 2, 3])
        XCTAssertFalse(state.update([withCover, reading(.music, .paused, "Three")], now: start + 2), "Music still shows")
        XCTAssertEqual(state.track?.title, "Three")
    }

    func testFriendsAreToldWhilePlayingAndForAMinuteAfterAPause() {
        var state = NowPlayingState()
        XCTAssertNil(state.listening(now: start))
        state.update([reading(.spotify, .playing)], now: start)
        XCTAssertEqual(state.listening(now: start + 3600), TogetherListening(title: "Around the World", artist: "Daft Punk"), "playing has no end")
        XCTAssertNil(state.listeningEnds(now: start))
        state.update([reading(.spotify, .paused)], now: start + 100)
        XCTAssertNotNil(state.listening(now: start + 160))
        XCTAssertEqual(state.listeningEnds(now: start + 110), start + 160)
        XCTAssertNil(state.listening(now: start + 161), "paused for over a minute")
        XCTAssertNil(state.listeningEnds(now: start + 161))
        // Still paused a while later: the minute counts from the pause, not from the last look.
        state.update([reading(.spotify, .paused)], now: start + 150)
        XCTAssertNil(state.listening(now: start + 161))
        state.update([reading(.spotify, .playing)], now: start + 200)
        XCTAssertNotNil(state.listening(now: start + 200))
    }

    func testATrackFoundPausedIsNotTold() {
        var state = NowPlayingState()
        state.update([reading(.music, .paused)], now: start)
        XCTAssertNotNil(state.track, "the card shows it")
        XCTAssertNil(state.listening(now: start), "nobody knows since when it is paused")
    }

    func testTitleAndArtistAreTrimmedAndCutTo120Units() throws {
        let long = String(repeating: "a", count: 200)
        let listening = try XCTUnwrap(TogetherListening(title: "  \(long)\n", artist: " \(long) "))
        XCTAssertEqual(listening.title.utf16.count, 120)
        XCTAssertEqual(listening.artist?.utf16.count, 120)
        XCTAssertNil(TogetherListening(title: " \n "))
        XCTAssertNil(TogetherListening(title: "Song", artist: "  ")?.artist)
        // A character of two units is never split: 119 units and no half of the 60th emoji.
        let emoji = try XCTUnwrap(TogetherListening(title: "a" + String(repeating: "🎵", count: 80)))
        XCTAssertEqual(emoji.title.utf16.count, 119)
        XCTAssertEqual(emoji.title.count, 60)
        XCTAssertEqual(TogetherListening(title: "Song", artist: "Band")?.json, ["title": "Song", "artist": "Band"])
        XCTAssertEqual(TogetherListening(title: "Song")?.json, ["title": "Song"])
    }

    func presence(_ data: Data) throws -> [String: Any] {
        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(frame["op"] as? String, "heartbeat")
        return try XCTUnwrap(frame["presence"] as? [String: Any])
    }

    func testTheHeartbeatCarriesListeningOnlyWhenThereIsSome() throws {
        let plain = try presence(TogetherSocket.heartbeatFrame(presence: .online))
        XCTAssertEqual(plain["state"] as? String, "online")
        XCTAssertNil(plain["listening"], "left out, not null")
        XCTAssertEqual(plain.count, 1)
        let since = Date(timeIntervalSince1970: 1_800_000_000)
        let game = try presence(TogetherSocket.heartbeatFrame(presence: .inGame(titleID: "PPSA01234", since: since), listening: TogetherListening(title: "Song", artist: "Band")))
        XCTAssertEqual(game["state"] as? String, "in_game")
        XCTAssertEqual(game["titleId"] as? String, "PPSA01234")
        XCTAssertEqual(game["listening"] as? [String: String], ["title": "Song", "artist": "Band"])
        let noArtist = try presence(TogetherSocket.heartbeatFrame(presence: .away, listening: TogetherListening(title: "Song")))
        XCTAssertEqual(noArtist["listening"] as? [String: String], ["title": "Song"])
    }

    func testAFriendsPresenceReadsListeningAndSurvivesABadOne() throws {
        func friend(_ presence: String) throws -> TogetherFriend {
            try JSONDecoder().decode(TogetherFriend.self, from: Data(#"{"userId":"u2","handle":"sam","displayName":"Sam","presence":\#(presence)}"#.utf8))
        }
        XCTAssertEqual(try friend(#"{"state":"online","listening":{"title":"Song","artist":"Band"}}"#).presence?.listening, TogetherListening(title: "Song", artist: "Band"))
        XCTAssertEqual(try friend(#"{"state":"in_game","titleId":"PPSA01234","listening":{"title":"Song"}}"#).presence?.listening, TogetherListening(title: "Song"))
        let old = try friend(#"{"state":"online"}"#)
        XCTAssertNil(old.presence?.listening)
        XCTAssertEqual(old.presence?.state, "online")
        for bad in [#"{"state":"online","listening":null}"#, #"{"state":"online","listening":"Song"}"#, #"{"state":"online","listening":{"artist":"Band"}}"#, #"{"state":"online","listening":{"title":"  "}}"#] {
            let read = try friend(bad)
            XCTAssertNil(read.presence?.listening, bad)
            XCTAssertEqual(read.presence?.online, true, bad)
        }
    }

    func testThePlayersAreNamedByTheirIdentifiers() {
        XCTAssertEqual(NowPlayingPlayer.allCases.map(\.rawValue), ["com.spotify.client", "com.apple.Music"])
        XCTAssertEqual(NowPlayingPlayer.spotify.changeNotification, "com.spotify.client.PlaybackStateChanged")
        XCTAssertEqual(NowPlayingPlayer.music.changeNotification, "com.apple.Music.playerInfo")
    }
}
