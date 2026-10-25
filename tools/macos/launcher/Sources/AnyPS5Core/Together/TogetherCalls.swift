import Foundation

/// Someone in a call, on the device (session) they are in it on.
public struct TogetherCallPeer: Codable, Equatable, Hashable, Sendable {
    public let userId: String
    public let device: String
    /// They muted themselves (false where the server does not say).
    public let muted: Bool
    /// They hear nobody (and are muted).
    public let deafened: Bool

    public init(userId: String, device: String, muted: Bool = false, deafened: Bool = false) {
        self.userId = userId
        self.device = device
        self.muted = muted
        self.deafened = deafened
    }

    enum CodingKeys: String, CodingKey { case userId, device, muted, deafened }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        device = try container.decode(String.self, forKey: .device)
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        deafened = try container.decodeIfPresent(Bool.self, forKey: .deafened) ?? false
    }
}

/// A call: the party's voice, or a friend.
public struct TogetherCall: Decodable, Equatable, Sendable {
    public let id: String
    /// "party" or "direct".
    public let kind: String?
    public let partyId: String?
    public let startedBy: String?
    /// Who was called, in a direct call.
    public let calleeId: String?
    public let `in`: [TogetherCallPeer]
}

/// A friend calling: rings on every device of the user until one answers or declines.
public struct TogetherRinging: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { callId }
    public let callId: String
    public let from: TogetherPerson
    /// The caller's device.
    public let device: String

    public init(callId: String, from: TogetherPerson, device: String) {
        self.callId = callId
        self.from = from
        self.device = device
    }
}

/// Someone in a call muted or unmuted, deafened or undeafened themselves.
public struct TogetherMuteChange: Decodable, Equatable, Sendable {
    public let callId: String
    public let partyId: String?
    public let userId: String
    public let muted: Bool
    /// False where the server does not say.
    public let deafened: Bool

    public init(callId: String, partyId: String?, userId: String, muted: Bool, deafened: Bool = false) {
        self.callId = callId
        self.partyId = partyId
        self.userId = userId
        self.muted = muted
        self.deafened = deafened
    }

    enum CodingKeys: String, CodingKey { case callId, partyId, userId, muted, deafened }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        partyId = try container.decodeIfPresent(String.self, forKey: .partyId)
        userId = try container.decode(String.self, forKey: .userId)
        muted = try container.decode(Bool.self, forKey: .muted)
        deafened = try container.decodeIfPresent(Bool.self, forKey: .deafened) ?? false
    }
}

/// The user's microphone in a call, and deafening as Discord does it: deafened hears nobody and
/// sends nothing; undeafening gives the microphone back as it was; unmuting undeafens.
public struct TogetherVoiceMic: Equatable, Sendable {
    /// What the others are told.
    public struct State: Equatable, Sendable {
        public let muted: Bool
        public let deafened: Bool

        public init(muted: Bool, deafened: Bool) {
            self.muted = muted
            self.deafened = deafened
        }
    }

    /// The open microphone's switch.
    public private(set) var on: Bool
    public private(set) var deafened = false
    /// The switch as it was when deafened.
    private var onBefore: Bool

    public init(on: Bool = true) {
        self.on = on
        onBefore = on
    }

    /// The microphone on or off; on while deafened undeafens.
    public mutating func set(on: Bool) {
        self.on = on
        if on { deafened = false }
    }

    public mutating func deafen() {
        guard !deafened else { return }
        onBefore = on
        on = false
        deafened = true
    }

    public mutating func undeafen() {
        guard deafened else { return }
        deafened = false
        on = onBefore
    }

    public mutating func toggleDeafen() {
        if deafened { undeafen() } else { deafen() }
    }

    /// Muted as the others see it: deafened, or the open microphone off (push-to-talk is not muted).
    public func muted(pushToTalk: Bool) -> Bool { deafened || (!pushToTalk && !on) }

    /// Whether the microphone sends now.
    public func sending(pushToTalk: Bool, held: Bool) -> Bool { !deafened && (pushToTalk ? held : on) }

    public func state(pushToTalk: Bool) -> State { State(muted: muted(pushToTalk: pushToTalk), deafened: deafened) }
}

/// Fresh relay credentials, for a call that outlives the ones it was given.
public struct TogetherIceRenewal: Decodable, Equatable, Sendable {
    public let iceServers: [TogetherIceServer]
    public let expiresAt: Date?
}

/// A STUN or TURN server, as a peer connection takes it.
public struct TogetherIceServer: Decodable, Equatable, Sendable {
    public let urls: [String]
    public let username: String?
    public let credential: String?
}

/// What joining a call gives: the call, and the servers to reach the others through.
public struct TogetherCallJoin: Decodable, Equatable, Sendable {
    public let call: TogetherCall
    public let iceServers: [TogetherIceServer]
    public let expiresAt: Date?

    /// Whoever joins later makes the offers: to everyone already in the call.
    public func peersToCall(me: String) -> [TogetherCallPeer] { call.in.filter { $0.userId != me } }
}

/// WebRTC signalling, relayed by the gateway between members of one call.
public enum TogetherSignalKind: String, Codable, Sendable {
    case offer, answer, candidate, bye, renegotiate
}

/// A signal from a peer: an offer or answer carries a session description, a candidate an ICE
/// candidate, in the shapes a browser's toJSON() gives them.
public struct TogetherSignal: Decodable, Sendable {
    public struct Description: Codable, Equatable, Sendable {
        public let type: String
        public let sdp: String

        public init(type: String, sdp: String) {
            self.type = type
            self.sdp = sdp
        }
    }

    public struct Candidate: Codable, Equatable, Sendable {
        public let candidate: String
        public let sdpMid: String?
        public let sdpMLineIndex: Int32?

        public init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32?) {
            self.candidate = candidate
            self.sdpMid = sdpMid
            self.sdpMLineIndex = sdpMLineIndex
        }
    }

    public let call: String
    public let from: String
    public let device: String
    public let kind: TogetherSignalKind
    public let description: Description?
    public let candidate: Candidate?

    enum CodingKeys: String, CodingKey { case call, from, device, kind, data }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        call = try container.decode(String.self, forKey: .call)
        from = try container.decode(String.self, forKey: .from)
        device = try container.decode(String.self, forKey: .device)
        kind = try container.decode(TogetherSignalKind.self, forKey: .kind)
        description = kind == .offer || kind == .answer ? try? container.decode(Description.self, forKey: .data) : nil
        candidate = kind == .candidate ? try? container.decode(Candidate.self, forKey: .data) : nil
    }
}

extension TogetherClient {
    /// Into the party's voice call (made when no one is in it yet).
    public func joinCall(party partyId: String) async throws -> TogetherCallJoin {
        try JSONDecoder.together.decode(TogetherCallJoin.self, from: try await authorized("POST", "calls", ["partyId": partyId]))
    }

    public func leaveCall(_ callId: String) async throws {
        _ = try await authorized("POST", "calls/\(callId)/leave", [:])
    }

    /// Leaving as the app quits: true once the server has it, false when it did not answer in time.
    public func leaveCall(_ callId: String, within deadline: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await self.leaveCall(callId)) != nil }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Calls a friend: it rings on their devices; the call is joined already, waiting for them.
    public func call(friend userId: String) async throws -> TogetherCallJoin {
        try JSONDecoder.together.decode(TogetherCallJoin.self, from: try await authorized("POST", "calls", ["userId": userId]))
    }

    /// A ringing call answered on this device (refused with "conflict" when another device did first).
    public func answerCall(_ callId: String) async throws -> TogetherCallJoin {
        try JSONDecoder.together.decode(TogetherCallJoin.self, from: try await authorized("POST", "calls/\(callId)/answer", [:]))
    }

    /// A ringing call declined: it ends for the caller too.
    public func declineCall(_ callId: String) async throws {
        _ = try await authorized("POST", "calls/\(callId)/decline", [:])
    }

    /// Muted or not, deafened or not, as every member of the call sees it; `deafened` nil leaves
    /// it to the server (unmuting undeafens there).
    public func setMuted(_ muted: Bool, deafened: Bool? = nil, in callId: String) async throws {
        var body: [String: Any] = ["muted": muted]
        if let deafened { body["deafened"] = deafened }
        _ = try await authorized("POST", "calls/\(callId)/mute", body)
    }

    /// New relay credentials for a long call.
    public func iceServers() async throws -> TogetherIceRenewal {
        try JSONDecoder.together.decode(TogetherIceRenewal.self, from: try await authorized("GET", "ice-servers", nil))
    }
}

extension TogetherSocket {
    /// The frame that sends a signal to one device of a peer in the same call.
    public static func signalFrame(to userId: String, device: String, call: String, kind: TogetherSignalKind, data: Any?) -> Data {
        let frame: [String: Any] = ["op": "signal", "to": userId, "device": device, "call": call, "kind": kind.rawValue, "data": data ?? NSNull()]
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
    }
}

/// The rules of the party voice mesh, the same as the website's: one peer connection per member,
/// the newcomer offers, the polite side gives way when both offer, Opus tuned for speech.
public enum TogetherVoice {
    /// How long a call to the user rings before it counts as not answered.
    public static let ringFor: TimeInterval = 45

    /// When to ask for new relay credentials: ten minutes before these end, but not sooner than
    /// a moment from now; nil when there are none to renew.
    public static func renewal(expiresAt: Date?, now: Date = Date()) -> Date? {
        guard let expiresAt else { return nil }
        return max(expiresAt.addingTimeInterval(-600), now.addingTimeInterval(30))
    }

    /// Two offers at once: the larger user ID is polite and takes the other's.
    public static func polite(me: String, peer: String) -> Bool { me > peer }

    /// Opus for voice: mono, in-band FEC (rides out about 10 % loss), DTX (silence costs almost
    /// nothing), at most 32 kbit/s.
    public static func tuneOpus(_ sdp: String) -> String {
        guard let rtpmap = sdp.range(of: #"a=rtpmap:(\d+) opus/48000/2"#, options: [.regularExpression, .caseInsensitive]) else { return sdp }
        let line = String(sdp[rtpmap])
        let payload = line.dropFirst("a=rtpmap:".count).prefix { $0.isNumber }
        let wanted = [("useinbandfec", "1"), ("usedtx", "1"), ("stereo", "0"), ("maxaveragebitrate", "32000")]
        let prefix = "a=fmtp:\(payload) "
        if let fmtp = sdp.range(of: prefix + #"[^\r\n]*"#, options: .regularExpression) {
            var params: [(String, String)] = sdp[fmtp].dropFirst(prefix.count).split(separator: ";").map { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return (parts[0], parts.count > 1 ? parts[1] : "")
            }
            for (key, value) in wanted {
                if let index = params.firstIndex(where: { $0.0 == key }) { params[index].1 = value } else { params.append((key, value)) }
            }
            return sdp.replacingCharacters(in: fmtp, with: prefix + params.map { "\($0.0)=\($0.1)" }.joined(separator: ";"))
        }
        let added = prefix + wanted.map { "\($0.0)=\($0.1)" }.joined(separator: ";")
        return sdp.replacingCharacters(in: rtpmap, with: line + "\r\n" + added)
    }

    /// Whether someone is speaking: above `level`, and for a moment after.
    public struct Speaking: Sendable {
        public static let level = 0.02
        public static let hold: TimeInterval = 0.35
        public private(set) var speaking = false
        private var quietSince = Date.distantPast

        public init() {}

        @discardableResult
        public mutating func update(level: Double, at now: Date = Date()) -> Bool {
            if level > Speaking.level {
                speaking = true
                quietSince = now
            } else {
                speaking = speaking && now.timeIntervalSince(quietSince) < Speaking.hold
            }
            return speaking
        }
    }
}
