import Foundation

/// AnyTogether's optional media server (an SFU, LiveKit) for groups bigger than a peer-to-peer
/// mesh holds: a share play with more than four viewers, a party call with more than eight voices.
/// The host publishes once to it and it forwards to everyone. A server without one (production
/// today) says so, and everything stays the mesh as before.
public enum TogetherMediaRoute: String, Codable, Equatable, Sendable {
    /// Peer to peer: the host streams to each viewer, every voice talks to every other.
    case mesh
    /// Through the media server.
    case sfu

    /// A route this launcher does not know is the mesh, as a missing one is.
    public init(from decoder: Decoder) throws {
        self = TogetherMediaRoute(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .mesh
    }
}

/// What a client joins the media server's room with: LiveKit's URL and a short-lived token.
public struct TogetherSfuAccess: Decodable, Equatable, Sendable {
    /// The LiveKit server's WebSocket URL (wss://…).
    public let url: String
    public let token: String
    /// "share-<share play ID>" or "call-<call ID>".
    public let room: String
    /// The user's identity in the room: their user ID.
    public let identity: String
    /// Until when the token works for joining (a connected client keeps its place).
    public let expiresAt: Date?

    public init(url: String, token: String, room: String, identity: String, expiresAt: Date? = nil) {
        self.url = url
        self.token = token
        self.room = room
        self.identity = identity
        self.expiresAt = expiresAt
    }
}

/// What the server holds (GET /media-server): a media server or not, and the biggest share play
/// and party it takes.
public struct TogetherMediaLimits: Decodable, Equatable, Sendable {
    public let sfu: Bool
    public let maxShareViewers: Int
    public let maxPartySize: Int

    public init(sfu: Bool, maxShareViewers: Int, maxPartySize: Int) {
        self.sfu = sfu
        self.maxShareViewers = maxShareViewers
        self.maxPartySize = maxPartySize
    }

    /// A server without a media server, or one that did not answer: the mesh's limits.
    public static let mesh = TogetherMediaLimits(sfu: false, maxShareViewers: SharePlayRoster.maxViewers, maxPartySize: TogetherParty.maxSize)
}

/// A party call moved to the media server (the gateway's "call.media").
public struct TogetherCallMedia: Decodable, Equatable, Sendable {
    public let callId: String
    public let partyId: String?
    public let media: TogetherMediaRoute

    public init(callId: String, partyId: String?, media: TogetherMediaRoute) {
        self.callId = callId
        self.partyId = partyId
        self.media = media
    }
}

/// The track names the host publishes in a share play's room.
public enum SfuTrackNames {
    public static let video = "game"
    public static let audio = "game-audio"
}

/// Who watches through the media server and who keeps the direct connection to the host, and
/// how many the host may let watch.
public enum SharePlayMedia {
    /// The host's "how many may watch" choices: up to the server's limit with a media server, the
    /// mesh's 1-4 without one (or when the server did not say); never below who watches now nor
    /// below the share play's own limit.
    public static func viewerChoices(_ limits: TogetherMediaLimits?, watching: Int = 0, current: Int = 1) -> ClosedRange<Int> {
        let top = max(SharePlayRoster.maxViewers, limits?.sfu == true ? limits?.maxShareViewers ?? 0 : 0, current)
        return min(top, max(1, watching)) ... top
    }

    /// The saved choice within what the server takes now.
    public static func clampViewers(_ count: Int, _ limits: TogetherMediaLimits?) -> Int {
        min(viewerChoices(limits).upperBound, max(1, count))
    }

    /// The viewers the host keeps a direct (mesh) connection with: everyone on the mesh; through
    /// the media server, those holding a pad, and older viewer apps without a pad that asked for
    /// one (`asked`) and were served.
    public static func meshViewers(_ share: TogetherSharePlay, asked: Set<String>) -> [TogetherSharePlay.Viewer] {
        guard share.media == .sfu else { return share.viewers }
        return share.viewers.filter { $0.slot != nil || asked.contains($0.user.userId) }
    }

    /// Whether the host answers a viewer's ask for an offer with a mesh connection: always on the
    /// mesh; through the media server, for a pad holder, or (best effort, for viewer apps from
    /// before the media server) while the host has fewer than four direct connections.
    public static func servesAsk(_ share: TogetherSharePlay, from userId: String, meshPeers: Int) -> Bool {
        guard share.media == .sfu else { return true }
        guard let viewer = share.viewers.first(where: { $0.user.userId == userId }) else { return false }
        return viewer.slot != nil || meshPeers < SharePlayRoster.maxViewers
    }

    /// How a viewer watches: from the media server without a pad, straight from the host with one
    /// (and always on the mesh).
    public static func viewerRoute(_ share: TogetherSharePlay, me: String) -> TogetherMediaRoute {
        guard share.media == .sfu else { return .mesh }
        return share.viewers.first { $0.user.userId == me }?.slot == nil ? .sfu : .mesh
    }
}

/// The route of the party's voice call, from whatever said it last: the join answer, the party's
/// view or the gateway's "call.media". It never goes back to the mesh.
public enum PartyMedia {
    public static func route(join: TogetherMediaRoute, party: TogetherMediaRoute?, event: TogetherMediaRoute?) -> TogetherMediaRoute {
        [join, party, event].contains(.sfu) ? .sfu : .mesh
    }
}

extension TogetherClient {
    /// What the server holds; no sign-in needed.
    public func mediaServer() async throws -> TogetherMediaLimits {
        try JSONDecoder.together.decode(TogetherMediaLimits.self, from: try await send("GET", "media-server", nil))
    }

    /// A fresh media server token for a share play that goes through it ("conflict" on the mesh).
    public func sharePlaySfu(_ id: String) async throws -> TogetherSfuAccess {
        try JSONDecoder.together.decode(TogetherSfuAccess.self, from: try await authorized("GET", "share-plays/\(id)/sfu", nil))
    }

    /// A fresh media server token for a call that goes through it ("conflict" on the mesh).
    public func callSfu(_ id: String) async throws -> TogetherSfuAccess {
        try JSONDecoder.together.decode(TogetherSfuAccess.self, from: try await authorized("GET", "calls/\(id)/sfu", nil))
    }
}

/// What LiveKit's one audio engine does: without a device, the host's game sound is fed in by
/// hand (no microphone, no speakers); on the device, it takes the microphone (party voice) and
/// plays what arrives (party voice, watching). Voice and watching come first: while either goes
/// through the media server, the game sound for its viewers waits (pad holders on the mesh keep
/// hearing it).
public struct SfuAudioPlan: Equatable, Sendable {
    /// The engine runs without a device (manual rendering).
    public let deviceless: Bool
    /// The game sound is published to the share play's room.
    public let gameSound: Bool

    public init(deviceless: Bool, gameSound: Bool) {
        self.deviceless = deviceless
        self.gameSound = gameSound
    }

    public static func mode(gameSound: Bool, voice: Bool, watching: Bool) -> SfuAudioPlan {
        let sound = gameSound && !voice && !watching
        return SfuAudioPlan(deviceless: sound, gameSound: sound)
    }
}

/// The game's sound (16-bit stereo, as StreamPacket audio carries it) in blocks of `frames`.
public struct SfuSoundBlocks: Sendable {
    public let frames: Int
    private var held: [Int16] = []

    public init(frames: Int = 960) { self.frames = frames }

    /// Frames waiting for the next block.
    public var pending: Int { held.count / 2 }

    /// Interleaved stereo samples in; whole blocks out.
    public mutating func add(_ samples: [Int16]) -> [[Int16]] {
        held += samples
        var out: [[Int16]] = []
        while held.count >= frames * 2 {
            out.append(Array(held[0 ..< frames * 2]))
            held.removeFirst(frames * 2)
        }
        return out
    }
}
