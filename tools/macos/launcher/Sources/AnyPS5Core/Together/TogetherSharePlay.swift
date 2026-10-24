import Foundation

/// Share play: the game the user runs, streamed to friends who watch it live (WebRTC, one peer
/// connection per viewer); a viewer the host hands a pad plays along as player 2, 3 or 4. The
/// server introduces them and relays the signalling; picture, sound and pads go between them.
public struct TogetherSharePlay: Codable, Equatable, Sendable, Identifiable {
    public struct Viewer: Codable, Equatable, Sendable, Identifiable {
        public var id: String { user.userId }
        public let user: TogetherPerson
        /// The device (session) they watch on: where the host's signals for them go.
        public let device: String
        /// The pad they play with (2-4), nil while they only watch.
        public let slot: Int?
        public let joinedAt: String?

        public init(user: TogetherPerson, device: String, slot: Int?, joinedAt: String?) {
            self.user = user
            self.device = device
            self.slot = slot
            self.joinedAt = joinedAt
        }
    }

    public let id: String
    public let host: TogetherPerson?
    /// The host's device: where a viewer's signals go.
    public let hostDevice: String
    public let titleId: String
    public let title: String?
    public let open: Bool
    public let maxViewers: Int
    public let viewers: [Viewer]
    /// Invited and not here yet; only the host is told.
    public let invited: [TogetherPerson]?
    /// In the public list, and how; nil when it is not listed.
    public let listing: TogetherShareListing?
    /// People who asked to watch; only the host is told.
    public let requests: [TogetherPerson]?

    enum CodingKeys: String, CodingKey {
        case id, host, hostDevice, titleId, title, open, maxViewers, viewers, invited, requests
        case listing = "public"
    }

    public init(id: String, host: TogetherPerson?, hostDevice: String, titleId: String, title: String?, open: Bool, maxViewers: Int, viewers: [Viewer], invited: [TogetherPerson]? = nil,
                listing: TogetherShareListing? = nil, requests: [TogetherPerson]? = nil) {
        self.listing = listing
        self.requests = requests
        self.id = id
        self.host = host
        self.hostDevice = hostDevice
        self.titleId = titleId
        self.title = title
        self.open = open
        self.maxViewers = maxViewers
        self.viewers = viewers
        self.invited = invited
    }
}

/// What starting or joining gives: the share play and the servers to reach each other through.
public struct TogetherSharePlayJoin: Decodable, Equatable, Sendable {
    public let sharePlay: TogetherSharePlay
    public let iceServers: [TogetherIceServer]
    public let expiresAt: Date?
}

/// A friend asking the user to watch.
public struct TogetherShareInvite: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { sharePlayId }
    public let sharePlayId: String
    public let from: TogetherPerson?
    public let titleId: String
    public let title: String?

    public init(sharePlayId: String, from: TogetherPerson?, titleId: String, title: String?) {
        self.sharePlayId = sharePlayId
        self.from = from
        self.titleId = titleId
        self.title = title
    }
}

/// In a friend's presence while they share.
public struct TogetherSharePresence: Decodable, Equatable, Sendable {
    public let sharePlayId: String
    public let titleId: String
    public let title: String?
    /// Open to friends and not full.
    public let open: Bool
    public let viewers: Int
    public let maxViewers: Int

    public init(sharePlayId: String, titleId: String, title: String?, open: Bool, viewers: Int, maxViewers: Int) {
        self.sharePlayId = sharePlayId
        self.titleId = titleId
        self.title = title
        self.open = open
        self.viewers = viewers
        self.maxViewers = maxViewers
    }

    /// A presence with only its share decoded.
    public struct Holder: Decodable { public let share: TogetherSharePresence? }
}

/// Signalling between the host and a viewer, relayed by the gateway.
public struct TogetherShareSignal: Decodable, Sendable {
    public enum Kind: String, Codable, Sendable { case offer, answer, candidate, bye, renegotiate, message }

    public let sharePlayId: String
    public let from: String
    public let device: String
    public let kind: Kind
    public let description: TogetherSignal.Description?
    public let candidate: TogetherSignal.Candidate?

    enum CodingKeys: String, CodingKey { case sharePlayId, from, device, kind, data }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sharePlayId = try container.decode(String.self, forKey: .sharePlayId)
        from = try container.decode(String.self, forKey: .from)
        device = try container.decode(String.self, forKey: .device)
        kind = try container.decode(Kind.self, forKey: .kind)
        description = kind == .offer || kind == .answer ? try? container.decode(TogetherSignal.Description.self, forKey: .data) : nil
        candidate = kind == .candidate ? try? container.decode(TogetherSignal.Candidate.self, forKey: .data) : nil
    }
}

extension TogetherSocket {
    /// The frame that sends a share play signal to one device of the host or a viewer.
    public static func shareSignalFrame(to userId: String, device: String, share: String, kind: TogetherShareSignal.Kind, data: Any?) -> Data {
        let frame: [String: Any] = ["op": "signal", "to": userId, "device": device, "share": share, "kind": kind.rawValue, "data": data ?? NSNull()]
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
    }
}

extension TogetherClient {
    /// Shares the game this launcher runs (ending any share play the user had).
    public func startSharePlay(titleId: String, title: String?, open: Bool, maxViewers: Int, listing: TogetherShareListing? = nil) async throws -> TogetherSharePlayJoin {
        var body: [String: Any] = ["titleId": titleId, "open": open, "maxViewers": maxViewers]
        if let listing { body["public"] = listing.body }
        if let title, !title.isEmpty { body["title"] = String(title.prefix(80)) }
        return try JSONDecoder.together.decode(TogetherSharePlayJoin.self, from: try await authorized("POST", "share-plays", body))
    }

    public func mySharePlay() async throws -> (hosting: TogetherSharePlay?, watching: TogetherSharePlay?, invites: [TogetherShareInvite]) {
        struct Mine: Decodable { let hosting: TogetherSharePlay?; let watching: TogetherSharePlay?; let invites: [TogetherShareInvite] }
        let mine = try JSONDecoder.together.decode(Mine.self, from: try await authorized("GET", "me/share-play", nil))
        return (mine.hosting, mine.watching, mine.invites)
    }

    public func sharePlay(_ id: String) async throws -> TogetherSharePlay {
        try JSONDecoder.together.decode(TogetherSharePlay.self, from: try await authorized("GET", "share-plays/\(id)", nil))
    }

    public func updateSharePlay(_ id: String, open: Bool? = nil, maxViewers: Int? = nil) async throws -> TogetherSharePlay {
        var body: [String: Any] = [:]
        if let open { body["open"] = open }
        if let maxViewers { body["maxViewers"] = maxViewers }
        return try JSONDecoder.together.decode(TogetherSharePlay.self, from: try await authorized("PATCH", "share-plays/\(id)", body))
    }

    public func endSharePlay(_ id: String) async throws {
        _ = try await authorized("DELETE", "share-plays/\(id)", nil)
    }

    public func inviteToSharePlay(_ userIds: [String], share id: String) async throws {
        _ = try await authorized("POST", "share-plays/\(id)/invites", ["userIds": userIds])
    }

    /// Hands a viewer pad 2, 3 or 4, or takes it back (nil); "conflict" when another has that pad.
    public func setSharePad(_ userId: String, slot: Int?, in id: String) async throws -> TogetherSharePlay {
        try JSONDecoder.together.decode(TogetherSharePlay.self, from: try await authorized("PUT", "share-plays/\(id)/viewers/\(userId)/slot", ["slot": slot.map { $0 as Any } ?? NSNull()]))
    }

    public func removeShareViewer(_ userId: String, from id: String) async throws {
        _ = try await authorized("DELETE", "share-plays/\(id)/viewers/\(userId)", nil)
    }

    public func shareIceServers(_ id: String) async throws -> TogetherIceRenewal {
        try JSONDecoder.together.decode(TogetherIceRenewal.self, from: try await authorized("GET", "share-plays/\(id)/ice-servers", nil))
    }

    /// Watching a friend's share play on this device.
    public func joinSharePlay(_ id: String) async throws -> TogetherSharePlayJoin {
        try JSONDecoder.together.decode(TogetherSharePlayJoin.self, from: try await authorized("POST", "share-plays/\(id)/join", [:]))
    }

    public func leaveSharePlay(_ id: String) async throws {
        _ = try await authorized("POST", "share-plays/\(id)/leave", [:])
    }

    public func declineSharePlay(_ id: String) async throws {
        _ = try await authorized("POST", "share-plays/\(id)/decline", [:])
    }
}

/// The host's bookkeeping as the share play changes: whom to call, whom to hang up on, who holds
/// which pad, and the video settings it puts in the viewers' answers.
public enum SharePlayRoster {
    /// Pads a viewer can be handed: player 1 is the host.
    public static let pads = 2 ... 4
    /// The host uploads a stream per viewer.
    public static let maxViewers = 4

    /// Viewers to call (new, or on another device than before) and to hang up on (gone, or
    /// moved to another device: the old connection goes first).
    public static func plan(from before: [TogetherSharePlay.Viewer], to after: [TogetherSharePlay.Viewer]) -> (call: [TogetherSharePlay.Viewer], hangUp: [String]) {
        let old = Dictionary(before.map { ($0.user.userId, $0.device) }, uniquingKeysWith: { _, last in last })
        let new = Dictionary(after.map { ($0.user.userId, $0.device) }, uniquingKeysWith: { _, last in last })
        let call = after.filter { old[$0.user.userId] != $0.device }
        let hangUp = old.compactMap { userId, device in new[userId] == device ? nil : userId }
        return (call, hangUp)
    }

    /// Who holds which pad, by user ID.
    public static func pads(_ viewers: [TogetherSharePlay.Viewer]) -> [String: Int] {
        Dictionary(viewers.compactMap { viewer in viewer.slot.map { (viewer.user.userId, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    /// The lowest pad nobody holds, for "Let them play"; nil when all are taken.
    public static func freePad(_ viewers: [TogetherSharePlay.Viewer]) -> Int? {
        let taken = Set(viewers.compactMap(\.slot))
        return pads.first { !taken.contains($0) }
    }

    /// What each viewer's stream may take: 720p60 up to 10 Mbit/s for one or two viewers; from
    /// three on, the host uploads a stream each, so 540p30 up to 5 Mbit/s apiece.
    public struct Encoding: Equatable, Sendable {
        public let maxBitrate: Int
        public let maxFramerate: Int
        /// Of the captured 720p picture: 1 keeps it, 4/3 makes it 540p.
        public let scaleDown: Double
        public let startKbps: Int
    }

    public static func encoding(viewers: Int) -> Encoding {
        viewers >= 3 ? Encoding(maxBitrate: 5_000_000, maxFramerate: 30, scaleDown: 4.0 / 3.0, startKbps: 1500)
            : Encoding(maxBitrate: 10_000_000, maxFramerate: 60, scaleDown: 1, startKbps: 2500)
    }

    /// The viewer's answer with WebRTC's own bit rate hints on each H.264 format: start high
    /// enough that the first picture is sharp, never above `maxKbps`, never starved below 600.
    /// They apply to what the host sends, which follows the remote description.
    public static func tuneVideo(_ sdp: String, startKbps: Int, maxKbps: Int) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"a=rtpmap:(\d+) H264/90000"#, options: .caseInsensitive) else { return sdp }
        let whole = NSRange(sdp.startIndex..., in: sdp)
        let payloads = pattern.matches(in: sdp, range: whole).compactMap { match in Range(match.range(at: 1), in: sdp).map { String(sdp[$0]) } }
        var lines = sdp.components(separatedBy: "\r\n")
        let hints = "x-google-start-bitrate=\(startKbps);x-google-max-bitrate=\(maxKbps);x-google-min-bitrate=600"
        for payload in payloads {
            let prefix = "a=fmtp:\(payload) "
            if let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
                if !lines[index].contains("x-google-start-bitrate") { lines[index] += ";" + hints }
            } else if let rtpmap = lines.firstIndex(where: { $0.hasPrefix("a=rtpmap:\(payload) ") }) {
                lines.insert(prefix + hints, at: rtpmap + 1)
            }
        }
        return lines.joined(separator: "\r\n")
    }
}

/// The game's pad bridges as share play uses them: one held per viewer with a pad.
public protocol SharePadBridges: AnyObject, Sendable {
    func reservePadBridge() -> Int?
    func releasePadBridge(_ bridge: Int)
    func sendPad(_ data: Data, bridge: Int)
}

/// Viewers' pad packets to the game: only from a viewer the host handed a pad, each through a
/// bridge of their own, carrying the pad the host gave (byte 13) so the engine seats them as
/// that player and never as the host's player 1; a pad taken back lets go of every button
/// before its bridge is freed.
public final class SharePadRouter: @unchecked Sendable {
    private let bridges: SharePadBridges
    private let lock = NSLock()
    /// The bridge each viewer with a pad sends through.
    private var held: [String: Int] = [:]
    /// Each viewer's newest packet, to let go of from.
    private var last: [String: Data] = [:]
    /// The pad (2-4) each viewer was given.
    private var pads: [String: Int] = [:]

    /// Where a packet carries the player the launcher holds for a share play guest (2-4); the
    /// engine never seats such a pad as player 1. Phones leave it 0.
    public static let seatByte = 13

    public init(bridges: SharePadBridges) { self.bridges = bridges }

    /// The pads as the share play has them now (user ID → pad 2-4).
    public func update(pads: [String: Int]) {
        let (gone, wanted): ([(String, Int, Data?)], [String]) = lock.withLock {
            self.pads = pads
            let gone = held.filter { pads[$0.key] == nil }.map { ($0.key, $0.value, last[$0.key]) }
            for (userId, _, _) in gone {
                held[userId] = nil
                last[userId] = nil
            }
            return (gone, pads.keys.filter { held[$0] == nil }.sorted { (pads[$0] ?? 0) < (pads[$1] ?? 0) })
        }
        for (_, bridge, packet) in gone {
            if let packet { bridges.sendPad(SharePadRouter.letGo(of: packet), bridge: bridge) }
            bridges.releasePadBridge(bridge)
        }
        for userId in wanted {
            guard let bridge = bridges.reservePadBridge() else { break }
            lock.withLock { held[userId] = bridge }
        }
    }

    /// A packet from a viewer's pad channel: forwarded when it is a well-formed pad packet from a
    /// viewer who holds a pad; true when it went on.
    @discardableResult
    public func receive(_ data: Data, from userId: String) -> Bool {
        guard let session = RemotePacket.inputSession(data), session != 0 else { return false }
        var packet = Data(data)
        guard let bridge: Int = lock.withLock({
            guard let bridge = held[userId], let pad = pads[userId] else { return nil }
            packet[packet.startIndex + SharePadRouter.seatByte] = UInt8(clamping: pad)
            last[userId] = packet
            return bridge
        }) else { return false }
        bridges.sendPad(packet, bridge: bridge)
        return true
    }

    public func bridge(of userId: String) -> Int? { lock.withLock { held[userId] } }

    /// Whose pad a bridge carries, for the game's answers on it.
    public func viewer(onBridge bridge: Int) -> String? { lock.withLock { held.first { $0.value == bridge }?.key } }

    /// Every bridge given back (share play over).
    public func releaseAll() { update(pads: [:]) }

    /// The packet after `packet` with nothing pressed: no buttons, sticks centred, triggers up, no
    /// touch, same session.
    static func letGo(of packet: Data) -> Data {
        var bytes = [UInt8](packet)
        let sequence = (RemotePacket.read(packet, at: 8) as UInt32) &+ 1
        withUnsafeBytes(of: sequence.littleEndian) { for (index, byte) in $0.enumerated() { bytes[8 + index] = byte } }
        for index in 32 ..< 36 { bytes[index] = 0 }
        for index in 36 ..< 40 { bytes[index] = 128 }
        bytes[40] = 0
        bytes[41] = 0
        for index in 44 ..< 56 { bytes[index] = 0 }
        return Data(bytes)
    }
}
