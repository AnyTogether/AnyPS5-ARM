import Foundation

/// What a music player on this Mac is playing, for the quick menu's Now playing card and, when
/// the user chose so, for friends on AnyTogether.
///
/// macOS has no public way to ask what any app plays (MediaRemote is private), so the launcher
/// reads the two players that can be scripted, and only while they run. Windows and Linux read
/// the system's media session and work with any player.
public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String?
    /// The player's name as the card says it ("Spotify", "Music") and the app it is.
    public var player: String
    public var playerID: String
    public var playing: Bool
    /// The cover as the player gave it (PNG or JPEG), when it has one.
    public var artwork: Data?

    public init(title: String, artist: String? = nil, player: String, playerID: String, playing: Bool, artwork: Data? = nil) {
        self.title = title
        self.artist = artist
        self.player = player
        self.playerID = playerID
        self.playing = playing
        self.artwork = artwork
    }
}

/// The players the Mac launcher can read, by bundle identifier.
public enum NowPlayingPlayer: String, CaseIterable, Sendable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    /// The app's name in English, for when the Mac does not say it.
    public var name: String { self == .spotify ? "Spotify" : "Music" }

    /// The notification the player posts to every app when its track or state changes (public,
    /// and no permission is needed to hear it).
    public var changeNotification: String { self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo" }
}

public enum NowPlayingCommand: String, Sendable, CaseIterable {
    case previous, playPause, next
}

/// What one player said when asked.
public struct NowPlayingReading: Equatable, Sendable {
    public enum State: String, Sendable { case playing, paused, stopped }

    public var player: NowPlayingPlayer
    public var state: State
    public var title: String
    public var artist: String
    public var artwork: Data?
    /// The app's name as this Mac shows it ("Müzik" in Turkish); nil for the English one.
    public var name: String?

    public init(player: NowPlayingPlayer, state: State, title: String = "", artist: String = "", artwork: Data? = nil, name: String? = nil) {
        self.name = name
        self.player = player
        self.state = state
        self.title = title
        self.artist = artist
        self.artwork = artwork
    }

    /// The reading as a track; nil when the player is stopped or names no title.
    public var track: NowPlayingTrack? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state != .stopped, !title.isEmpty else { return nil }
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return NowPlayingTrack(title: title, artist: artist.isEmpty ? nil : artist, player: name ?? player.name, playerID: player.rawValue, playing: state == .playing, artwork: artwork)
    }
}

/// Where the launcher reads the players from: AppleScript in the app, a fake in the tests.
public protocol NowPlayingSource: AnyObject {
    /// Asks the players that run (never starting one) and answers on any thread: what each said,
    /// and the players macOS did not let the launcher ask.
    func read(_ done: @escaping @Sendable (_ readings: [NowPlayingReading], _ denied: Set<NowPlayingPlayer>) -> Void)
    func send(_ command: NowPlayingCommand, to player: NowPlayingPlayer)
    /// A refusal is remembered so the player is not asked in a loop; this forgets it (the switch
    /// turned off and on again).
    func forgetDenials()
}

/// The title and artist friends see, as the gateway's heartbeat carries them.
public struct TogetherListening: Equatable, Sendable, Decodable {
    public static let limit = 120

    public let title: String
    public let artist: String?

    /// Each trimmed and cut to 120 UTF-16 units without splitting a character; nil without a title.
    public init?(title: String, artist: String? = nil) {
        let title = Self.clean(title)
        guard !title.isEmpty else { return nil }
        self.title = title
        let artist = artist.map(Self.clean) ?? ""
        self.artist = artist.isEmpty ? nil : artist
    }

    enum CodingKeys: String, CodingKey { case title, artist }

    /// From a friend's presence: one without a title decodes as none.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let title = Self.clean((try? values.decode(String.self, forKey: .title)) ?? "")
        guard !title.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .title, in: values, debugDescription: "no title") }
        self.title = title
        let artist = Self.clean((try? values.decodeIfPresent(String.self, forKey: .artist)) ?? "")
        self.artist = artist.isEmpty ? nil : artist
    }

    static func clean(_ text: String) -> String {
        var kept = ""
        var units = 0
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            units += character.utf16.count
            if units > limit { break }
            kept.append(character)
        }
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `listening` in the heartbeat's presence: the artist left out when there is none.
    public var json: [String: String] {
        var json = ["title": title]
        if let artist { json["artist"] = artist }
        return json
    }
}

/// The track the card shows and what friends may be told, from what the players say over time.
public struct NowPlayingState: Equatable, Sendable {
    /// A track paused for longer than this is no longer what the user listens to.
    public static let pausedFor: TimeInterval = 60

    public private(set) var track: NowPlayingTrack?
    /// Since when the track is paused; far in the past for one never seen playing here, so a
    /// song left paused hours ago is not told to anyone.
    public private(set) var pausedSince: Date?
    /// When each player was found playing, or last changed what it says.
    private var active: [NowPlayingPlayer: Date] = [:]
    private var last: [NowPlayingPlayer: NowPlayingReading] = [:]

    public init() {}

    /// The player to show: one that plays, else the one active most recently (several playing:
    /// the most recent of them too). Stopped players and those without a title are not shown.
    public static func choose(_ readings: [NowPlayingReading], active: [NowPlayingPlayer: Date]) -> NowPlayingReading? {
        let shown = readings.filter { $0.track != nil }
        func recent(_ list: [NowPlayingReading]) -> NowPlayingReading? {
            // The players' own order (Spotify, Music) settles a tie.
            list.enumerated().max { a, b in
                let first = active[a.element.player] ?? .distantPast, second = active[b.element.player] ?? .distantPast
                return first == second ? a.offset > b.offset : first < second
            }?.element
        }
        return recent(shown.filter { $0.state == .playing }) ?? recent(shown)
    }

    /// What the players said at `now` (all of them that run); true when the track changed.
    @discardableResult
    public mutating func update(_ readings: [NowPlayingReading], now: Date = Date()) -> Bool {
        for reading in readings {
            // The cover arrives after the words: it alone is not the player doing something.
            var words = reading
            words.artwork = nil
            // Active: found playing, or saying something else than before.
            if let before = last[reading.player] {
                if before != words { active[reading.player] = now }
            } else if reading.state == .playing {
                active[reading.player] = now
            }
            last[reading.player] = words
        }
        for player in NowPlayingPlayer.allCases where !readings.contains(where: { $0.player == player }) {
            last[player] = nil
            active[player] = nil
        }
        let next = Self.choose(readings, active: active)?.track
        let before = track
        if let next {
            if next.playing {
                pausedSince = nil
            } else if let before, before.playerID == next.playerID {
                // A pause seen happening counts from now; one already counting goes on.
                if before.playing { pausedSince = now }
            } else {
                // Found paused: nobody knows since when, so it is old.
                pausedSince = .distantPast
            }
        } else {
            pausedSince = nil
        }
        track = next
        return next != before
    }

    /// What friends are told at `now`: the track while it plays and for a minute after it paused.
    public func listening(now: Date = Date()) -> TogetherListening? {
        guard let track else { return nil }
        if !track.playing {
            guard let pausedSince, now.timeIntervalSince(pausedSince) <= Self.pausedFor else { return nil }
        }
        return TogetherListening(title: track.title, artist: track.artist)
    }

    /// When `listening` stops being told without anything else changing (the pause's minute ends).
    public func listeningEnds(now: Date = Date()) -> Date? {
        guard let track, !track.playing, let pausedSince, listening(now: now) != nil else { return nil }
        return pausedSince.addingTimeInterval(Self.pausedFor)
    }
}
