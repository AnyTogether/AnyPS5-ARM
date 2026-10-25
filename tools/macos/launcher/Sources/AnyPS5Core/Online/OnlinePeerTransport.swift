import Foundation

/// A signal between two players' launchers in a game session (`game_session.signal`): an offer,
/// an answer, an ICE candidate or a goodbye, in the shapes a browser's toJSON() gives them.
public struct OnlinePeerSignal: Sendable, Equatable {
    public var from: String
    public var device: String
    public var kind: String
    /// The signal's data as JSON (`null` for none).
    public var json: Data

    public init(from: String, device: String, kind: String, json: Data) {
        self.from = from
        self.device = device
        self.kind = kind
        self.json = json
    }

    /// From a socket event's data: {sessionId, from, device, kind, data}.
    public init?(event json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let from = object["from"] as? String, let device = object["device"] as? String, let kind = object["kind"] as? String else { return nil }
        let data = object["data"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed) } ?? Data("null".utf8)
        self.init(from: from, device: device, kind: kind, json: data)
    }
}

/// What a transport is told about the session: who this launcher is, every player's virtual
/// address, and the devices their signals go to.
public struct OnlinePeerSession: Sendable, Equatable {
    public var id: String
    public var me: String
    public var addresses: [String: UInt32]
    public var devices: [String: String]

    public init(id: String, me: String, addresses: [String: UInt32], devices: [String: String]) {
        self.id = id
        self.me = me
        self.addresses = addresses
        self.devices = devices
    }

    public var ownAddress: UInt32 { addresses[me] ?? 0 }
}

/// Carries game packets between this launcher and the other players of the session. The
/// WebRTC data channels (AnyPS5Online) are the real one; `OnlinePeerLink` (plain UDP) stays for
/// tests and one network.
public protocol OnlinePeerTransport: AnyObject, Sendable {
    /// The session as it is now; nil when there is none.
    func update(_ session: OnlinePeerSession?)
    /// A packet from the engine to another player; false when they cannot be reached now.
    @discardableResult func send(_ datagram: OnlineWire.Datagram) -> Bool
    /// A signal from another player's launcher.
    func receive(_ signal: OnlinePeerSignal)
    func stop()
}

/// What a transport is made with: where packets for the game go, AnyTogether (for ICE servers),
/// and how to signal another player's launcher.
public struct OnlinePeerContext: Sendable {
    public var deliver: @Sendable (OnlineWire.Datagram) -> Void
    public var service: OnlineSessionService
    /// (to user, their device, session ID, kind, data as JSON)
    public var signal: @Sendable (String, String, String, String, Data) -> Void

    public init(deliver: @escaping @Sendable (OnlineWire.Datagram) -> Void, service: OnlineSessionService,
                signal: @escaping @Sendable (String, String, String, String, Data) -> Void) {
        self.deliver = deliver
        self.service = service
        self.signal = signal
    }
}

/// No transport: packets to other players are dropped (online play without a way to reach them).
public final class OnlineNoTransport: OnlinePeerTransport, @unchecked Sendable {
    public init() {}
    public func update(_ session: OnlinePeerSession?) {}
    public func send(_ datagram: OnlineWire.Datagram) -> Bool { false }
    public func receive(_ signal: OnlinePeerSignal) {}
    public func stop() {}
}

extension OnlinePeerLink: OnlinePeerTransport {
    public func update(_ session: OnlinePeerSession?) { setOwnAddress(session?.ownAddress ?? 0) }
    public func receive(_ signal: OnlinePeerSignal) {}
}
