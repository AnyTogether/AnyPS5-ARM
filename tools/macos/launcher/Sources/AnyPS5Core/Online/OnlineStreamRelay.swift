import Foundation

/// Carries the game's streams (stream P2P sockets) between the engine's bridge and the other
/// players' launchers. The engine numbers the streams it opens and the launcher those it opens to
/// the engine (`OnlineWire.launcherStream` set); between launchers a stream is named by the number
/// its opener's engine gave it and by who opened it. The transport (`OnlinePeerTransport.sendStream`)
/// carries the messages to the player reliably and in order.
///
/// A message between launchers: u8 op (1 open, 2 accept, 3 data, 4 close), u8 flags (bit 0: the
/// sender opened this stream), u32 stream (the opener's number), then for open u16 source port,
/// u16 source virtual port, u16 destination port, u16 destination virtual port; for data the
/// bytes (at most `maxChunk`); for close u8 reason. Little-endian. The sender's virtual address is
/// whoever the connection is with, as for datagrams.
public final class OnlineStreamRelay: @unchecked Sendable {
    public enum Op: UInt8, Sendable { case open = 1, accept = 2, data = 3, close = 4 }

    public static let headerSize = 6
    /// The most game bytes in one message between launchers.
    public static let maxChunk = 16 * 1024

    /// One message between launchers.
    public struct Message: Equatable, Sendable {
        public var op: Op
        public var senderOpened: Bool
        public var stream: UInt32
        public var sourcePort: UInt16 = 0
        public var sourceVport: UInt16 = 0
        public var destinationPort: UInt16 = 0
        public var destinationVport: UInt16 = 0
        public var data = Data()
        public var reason: OnlineWire.StreamCloseReason = .closed

        public init(op: Op, senderOpened: Bool, stream: UInt32, sourcePort: UInt16 = 0, sourceVport: UInt16 = 0, destinationPort: UInt16 = 0,
                    destinationVport: UInt16 = 0, data: Data = Data(), reason: OnlineWire.StreamCloseReason = .closed) {
            self.op = op
            self.senderOpened = senderOpened
            self.stream = stream
            self.sourcePort = sourcePort
            self.sourceVport = sourceVport
            self.destinationPort = destinationPort
            self.destinationVport = destinationVport
            self.data = data
            self.reason = reason
        }

        public var bytes: Data {
            let writer = OnlineWire.Writer()
            writer.u8(op.rawValue).u8(senderOpened ? 1 : 0).u32(stream)
            switch op {
            case .open: writer.u16(sourcePort).u16(sourceVport).u16(destinationPort).u16(destinationVport)
            case .data: writer.raw(data)
            case .close: writer.u8(reason.rawValue)
            case .accept: break
            }
            return writer.data
        }

        public init?(_ bytes: Data) {
            var reader = OnlineWire.Reader(bytes)
            guard let op = Op(rawValue: reader.u8()) else { return nil }
            let flags = reader.u8()
            let stream = reader.u32()
            self.init(op: op, senderOpened: flags & 1 != 0, stream: stream)
            switch op {
            case .open:
                sourcePort = reader.u16()
                sourceVport = reader.u16()
                destinationPort = reader.u16()
                destinationVport = reader.u16()
                guard senderOpened else { return nil }
            case .data:
                data = Data(bytes.dropFirst(OnlineStreamRelay.headerSize))
            case .close:
                reason = OnlineWire.StreamCloseReason(rawValue: reader.u8()) ?? .reset
            case .accept:
                break
            }
            guard reader.ok, stream != 0 else { return nil }
        }
    }

    private struct Key: Hashable {
        var peer: UInt32
        var stream: UInt32
        /// This launcher's engine opened the stream.
        var mine: Bool
    }

    private struct Route {
        var key: Key
        var engineEnded = false
        var peerEnded = false
    }

    private let toEngine: @Sendable (OnlineWire.Stream) -> Void
    private let toPeer: @Sendable (UInt32, Data) -> Bool
    private let lock = NSLock()
    private var routes: [UInt32: Route] = [:]
    private var engineIds: [Key: UInt32] = [:]
    private var lastLauncherId: UInt32 = 0

    /// `toEngine` hands a frame to the game (the bridge); `toPeer` sends a message to a player
    /// (false when they cannot be reached now).
    public init(toEngine: @escaping @Sendable (OnlineWire.Stream) -> Void, toPeer: @escaping @Sendable (UInt32, Data) -> Bool) {
        self.toEngine = toEngine
        self.toPeer = toPeer
    }

    /// Streams open now.
    public var count: Int { lock.withLock { routes.count } }

    /// A stream frame from the engine.
    public func fromEngine(_ frame: OnlineWire.Stream) {
        switch frame {
        case .open(let id, let peer, let peerPort, let peerVport, let localPort, let localVport):
            let key = Key(peer: peer, stream: id, mine: true)
            let fresh = lock.withLock { () -> Bool in
                guard id & OnlineWire.launcherStream == 0, routes[id] == nil, engineIds[key] == nil else { return false }
                routes[id] = Route(key: key)
                engineIds[key] = id
                return true
            }
            guard fresh else { return }
            let message = Message(op: .open, senderOpened: true, stream: id, sourcePort: localPort, sourceVport: localVport, destinationPort: peerPort, destinationVport: peerVport)
            if !toPeer(peer, message.bytes) {
                forget(id)
                toEngine(.close(stream: id, .reset))
            }
        case .accept(let id):
            guard let key = lock.withLock({ routes[id]?.key }) else { return }
            send(id, key, Message(op: .accept, senderOpened: key.mine, stream: key.stream))
        case .data(let id, let data):
            guard let key = lock.withLock({ routes[id]?.key }) else { return }
            var offset = 0
            repeat {
                let chunk = data.subdata(in: data.startIndex + offset ..< data.startIndex + min(data.count, offset + OnlineStreamRelay.maxChunk))
                if !send(id, key, Message(op: .data, senderOpened: key.mine, stream: key.stream, data: chunk)) { return }
                offset += chunk.count
            } while offset < data.count
        case .close(let id, let reason):
            guard let key = lock.withLock({ routes[id]?.key }) else { return }
            _ = toPeer(key.peer, Message(op: .close, senderOpened: key.mine, stream: key.stream, reason: reason).bytes)
            ended(id, byEngine: true, reason: reason)
        }
    }

    /// A message from another player's launcher.
    public func fromPeer(_ peer: UInt32, _ bytes: Data) {
        guard let message = Message(bytes) else { return }
        let key = Key(peer: peer, stream: message.stream, mine: !message.senderOpened)
        if message.op == .open {
            let id = lock.withLock { () -> UInt32? in
                guard engineIds[key] == nil else { return nil }
                var id = lastLauncherId
                repeat {
                    id = (id &+ 1) & ~OnlineWire.launcherStream
                } while id == 0 || routes[id | OnlineWire.launcherStream] != nil
                lastLauncherId = id
                id |= OnlineWire.launcherStream
                routes[id] = Route(key: key)
                engineIds[key] = id
                return id
            }
            guard let id else { return }
            toEngine(.open(stream: id, peer: peer, peerPort: message.sourcePort, peerVport: message.sourceVport, localPort: message.destinationPort,
                           localVport: message.destinationVport))
            return
        }
        guard let id = lock.withLock({ engineIds[key] }) else {
            // A stream this side no longer knows: the other side learns it is gone.
            if message.op != .close { _ = toPeer(peer, Message(op: .close, senderOpened: !message.senderOpened, stream: message.stream, reason: .reset).bytes) }
            return
        }
        switch message.op {
        case .accept: toEngine(.accept(stream: id))
        case .data: toEngine(.data(stream: id, message.data))
        case .close:
            toEngine(.close(stream: id, message.reason))
            ended(id, byEngine: false, reason: message.reason)
        case .open: break
        }
    }

    /// A player's connection is gone: their streams break.
    public func peerGone(_ peer: UInt32) {
        let gone = lock.withLock { () -> [UInt32] in
            let ids = routes.filter { $0.value.key.peer == peer }.map(\.key)
            for id in ids { removeLocked(id) }
            return ids
        }
        for id in gone { toEngine(.close(stream: id, .reset)) }
    }

    /// The game's connection is gone (or a new game connected): every stream breaks for the players.
    public func engineGone() {
        let gone = lock.withLock { () -> [Key] in
            defer {
                routes = [:]
                engineIds = [:]
            }
            return routes.values.map(\.key)
        }
        for key in gone { _ = toPeer(key.peer, Message(op: .close, senderOpened: key.mine, stream: key.stream, reason: .reset).bytes) }
    }

    @discardableResult
    private func send(_ id: UInt32, _ key: Key, _ message: Message) -> Bool {
        if toPeer(key.peer, message.bytes) { return true }
        // The player cannot be reached (or the channel is full): the stream breaks on both sides.
        forget(id)
        toEngine(.close(stream: id, .reset))
        _ = toPeer(key.peer, Message(op: .close, senderOpened: key.mine, stream: key.stream, reason: .reset).bytes)
        return false
    }

    /// A stream is forgotten once both sides ended it, or at once when it was refused or broke.
    private func ended(_ id: UInt32, byEngine: Bool, reason: OnlineWire.StreamCloseReason) {
        lock.withLock {
            guard var route = routes[id] else { return }
            if byEngine { route.engineEnded = true } else { route.peerEnded = true }
            if reason != .closed || (route.engineEnded && route.peerEnded) {
                removeLocked(id)
            } else {
                routes[id] = route
            }
        }
    }

    private func forget(_ id: UInt32) { lock.withLock { removeLocked(id) } }

    private func removeLocked(_ id: UInt32) {
        guard let route = routes.removeValue(forKey: id) else { return }
        engineIds[route.key] = nil
    }
}
