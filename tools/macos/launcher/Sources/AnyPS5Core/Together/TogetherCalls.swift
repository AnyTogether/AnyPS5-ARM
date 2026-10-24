import Foundation

/// Someone in a call, on the device (session) they are in it on.
public struct TogetherCallPeer: Codable, Equatable, Hashable, Sendable {
    public let userId: String
    public let device: String

    public init(userId: String, device: String) {
        self.userId = userId
        self.device = device
    }
}

/// A call: the party's voice, or a friend.
public struct TogetherCall: Decodable, Equatable, Sendable {
    public let id: String
    public let partyId: String?
    public let `in`: [TogetherCallPeer]
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
