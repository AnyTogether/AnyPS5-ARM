import AnyPS5Core
import CShareAudio
import Foundation
import WebRTC

/// Game packets between the players of an AnyTogether game session over WebRTC data channels:
/// one peer connection to each other player, the offers, answers and ICE candidates carried as
/// `game_session.signal` through the realtime gateway, STUN and TURN from the session's ICE
/// servers. The player with the smaller user ID offers, so two launchers never offer at once; a
/// player who comes in later asks the others for an offer ("renegotiate"), in case theirs went
/// out before it was listening.
///
/// One unordered channel without resends (`game`) carries datagrams: a 9-byte header (source
/// port, source virtual port, destination port, destination virtual port, kind; little-endian)
/// and the game's bytes. The sender's virtual address is not in the packet: it is the address of
/// whoever the connection is with, so nobody can speak for another player.
public final class OnlinePeerMesh: NSObject, OnlinePeerTransport, @unchecked Sendable {
    public static let label = "game"
    static let headerSize = 9

    /// Its own factory, apart from share play's and the party voice's; its audio device is never
    /// started (no connection here has audio), so no real device is opened.
    static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return ShareAudioFactory(ShareAudioDevice())
    }()

    static let noConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    /// The state of the connection to one player, for the launcher's UI and tests.
    public enum PeerState: String, Sendable { case connecting, connected, failed, closed }

    fileprivate final class Peer: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
        let userId: String
        let address: UInt32
        let offerer: Bool
        var device: String
        /// Set right after the peer is made, with the peer as its delegate (held weakly by it;
        /// the mesh holds the peer).
        var connection: RTCPeerConnection!
        var channel: RTCDataChannel?
        /// Candidates wait until the other side's description is set.
        var queued: [RTCIceCandidate] = []
        var haveRemote = false
        var state: PeerState = .connecting
        weak var mesh: OnlinePeerMesh?

        init(userId: String, address: UInt32, device: String, offerer: Bool) {
            self.userId = userId
            self.address = address
            self.device = device
            self.offerer = offerer
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            mesh?.signal(self, kind: "candidate", ["candidate": candidate.sdp, "sdpMid": candidate.sdpMid.map { $0 as Any } ?? NSNull(), "sdpMLineIndex": candidate.sdpMLineIndex])
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
            mesh?.connectionChanged(self, newState)
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            guard dataChannel.label == OnlinePeerMesh.label else { return }
            dataChannel.delegate = self
            mesh?.opened(self, dataChannel)
        }

        func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
            guard dataChannel.readyState == .open else { return }
            mesh?.opened(self, dataChannel)
        }

        func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
            guard buffer.isBinary else { return }
            mesh?.received(buffer.data, from: self)
        }
    }

    private let context: OnlinePeerContext
    private let fixedIceServers: [TogetherIceServer]?
    private let lock = NSLock()
    private var session: OnlinePeerSession?
    private var peers: [String: Peer] = [:]
    private var byAddress: [UInt32: Peer] = [:]
    private var iceServers: (session: String, servers: [TogetherIceServer])?
    private var stopped = false
    private var counters = (sent: 0, received: 0, dropped: 0)

    /// `iceServers` replaces asking AnyTogether for them (tests pass [] for host candidates only).
    public init(context: OnlinePeerContext, iceServers: [TogetherIceServer]? = nil) {
        self.context = context
        self.fixedIceServers = iceServers
    }

    deinit { stop() }

    /// Each player's connection, by user ID.
    public var states: [String: PeerState] { lock.withLock { peers.mapValues(\.state) } }

    /// Datagrams sent, received and dropped (no open channel to their player) so far.
    public var traffic: (sent: Int, received: Int, dropped: Int) { lock.withLock { counters } }

    // MARK: OnlinePeerTransport

    public func update(_ next: OnlinePeerSession?) {
        let (gone, wanted, askOffer, previous) = lock.withLock { () -> ([Peer], [(String, UInt32, String)], [(String, String)], OnlinePeerSession?) in
            guard !stopped else { return ([], [], [], nil) }
            let previous = session
            session = next
            var gone: [Peer] = []
            if next?.id != previous?.id || next == nil {
                gone = Array(peers.values)
                peers = [:]
                byAddress = [:]
            }
            guard let next else { return (gone, [], [], previous) }
            for (userId, peer) in peers where next.addresses[userId] != peer.address || (next.devices[userId].map { $0 != peer.device } ?? false) {
                // Gone from the session, or their launcher started again.
                gone.append(peer)
                peers[userId] = nil
                byAddress[peer.address] = nil
            }
            var wanted: [(String, UInt32, String)] = []
            var askOffer: [(String, String)] = []
            for (userId, address) in next.addresses where userId != next.me && peers[userId] == nil {
                guard let device = next.devices[userId] else { continue }
                if next.me < userId { wanted.append((userId, address, device)) } else if previous?.devices[userId] != device || previous?.id != next.id {
                    askOffer.append((userId, device))
                }
            }
            return (gone, wanted, askOffer, previous)
        }
        // Leaving the session (or for another) says goodbye to everyone in it; a player who left
        // or whose launcher started again needs none.
        let leaving = previous != nil && (next == nil || next?.id != previous?.id)
        for peer in gone { close(peer, sayBye: leaving, in: previous?.id) }
        guard let next else { return }
        for (userId, device) in askOffer { context.signal(userId, device, next.id, "renegotiate", Data("null".utf8)) }
        if !wanted.isEmpty {
            Task {
                let servers = await self.servers(for: next.id)
                for (userId, address, device) in wanted { self.offer(to: userId, address: address, device: device, sessionId: next.id, servers: servers) }
            }
        }
    }

    @discardableResult
    public func send(_ datagram: OnlineWire.Datagram) -> Bool {
        let channel = lock.withLock { byAddress[datagram.peer]?.channel }
        guard let channel, channel.readyState == .open else {
            lock.withLock { counters.dropped += 1 }
            return false
        }
        let writer = OnlineWire.Writer()
        writer.u16(datagram.localPort).u16(datagram.localVport).u16(datagram.peerPort).u16(datagram.peerVport).u8(datagram.kind.rawValue).raw(datagram.data)
        let sent = channel.sendData(RTCDataBuffer(data: writer.data, isBinary: true))
        lock.withLock { if sent { counters.sent += 1 } else { counters.dropped += 1 } }
        return sent
    }

    public func receive(_ signal: OnlinePeerSignal) {
        let known = lock.withLock { () -> (session: OnlinePeerSession, address: UInt32, peer: Peer?)? in
            guard !stopped, let session, let address = session.addresses[signal.from], signal.from != session.me else { return nil }
            return (session, address, peers[signal.from])
        }
        guard let known else { return }
        let json = (try? JSONSerialization.jsonObject(with: signal.json, options: .fragmentsAllowed)) as? [String: Any] ?? [:]
        switch signal.kind {
        case "offer":
            guard let sdp = json["sdp"] as? String else { return }
            Task { await self.answer(signal.from, address: known.address, device: signal.device, sdp: sdp, session: known.session) }
        case "answer":
            guard let sdp = json["sdp"] as? String, let peer = known.peer, peer.offerer else { return }
            Task {
                do {
                    try await peer.connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
                    await self.flush(peer)
                } catch {
                    self.failed(peer)
                }
            }
        case "candidate":
            guard let sdp = json["candidate"] as? String, let peer = known.peer else { return }
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32((json["sdpMLineIndex"] as? NSNumber)?.intValue ?? 0), sdpMid: json["sdpMid"] as? String)
            // Never a WebRTC call under the lock: its delegate calls take the lock on WebRTC's thread.
            let ready = lock.withLock { () -> Bool in
                if !peer.haveRemote {
                    peer.queued.append(candidate)
                    return false
                }
                return true
            }
            if ready { Task { try? await peer.connection.add(candidate) } }
        case "bye":
            guard let peer = known.peer else { return }
            lock.withLock {
                if peers[peer.userId] === peer { peers[peer.userId] = nil }
                if byAddress[peer.address] === peer { byAddress[peer.address] = nil }
            }
            close(peer, sayBye: false)
        case "renegotiate":
            // They are listening now: whoever offers offers again.
            guard known.session.me < signal.from else { return }
            if let peer = known.peer {
                lock.withLock {
                    if peers[peer.userId] === peer { peers[peer.userId] = nil }
                    if byAddress[peer.address] === peer { byAddress[peer.address] = nil }
                }
                close(peer, sayBye: false)
            }
            Task {
                let servers = await self.servers(for: known.session.id)
                self.offer(to: signal.from, address: known.address, device: signal.device, sessionId: known.session.id, servers: servers)
            }
        default:
            break
        }
    }

    public func stop() {
        let all = lock.withLock { () -> [Peer] in
            stopped = true
            defer {
                peers = [:]
                byAddress = [:]
            }
            return Array(peers.values)
        }
        let sessionId = lock.withLock { session?.id }
        for peer in all { close(peer, sayBye: true, in: sessionId) }
    }

    // MARK: Negotiation

    private func servers(for sessionId: String) async -> [TogetherIceServer] {
        if let fixedIceServers { return fixedIceServers }
        if let kept = lock.withLock({ iceServers }), kept.session == sessionId { return kept.servers }
        struct Servers: Decodable { let iceServers: [TogetherIceServer] }
        let servers = (try? await context.service.call("GET", "game-sessions/\(sessionId)/ice-servers", nil))
            .flatMap { try? JSONDecoder().decode(Servers.self, from: $0).iceServers } ?? []
        lock.withLock { iceServers = (sessionId, servers) }
        return servers
    }

    private func configuration(_ servers: [TogetherIceServer]) -> RTCConfiguration {
        let configuration = RTCConfiguration()
        configuration.iceServers = servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.continualGatheringPolicy = .gatherContinually
        return configuration
    }

    private func makePeer(_ userId: String, address: UInt32, device: String, offerer: Bool, servers: [TogetherIceServer]) -> Peer? {
        let peer = Peer(userId: userId, address: address, device: device, offerer: offerer)
        guard let connection = OnlinePeerMesh.factory.peerConnection(with: configuration(servers), constraints: OnlinePeerMesh.noConstraints, delegate: peer) else { return nil }
        peer.connection = connection
        peer.mesh = self
        return peer
    }

    private func offer(to userId: String, address: UInt32, device: String, sessionId: String, servers: [TogetherIceServer]) {
        guard let peer = makePeer(userId, address: address, device: device, offerer: true, servers: servers) else { return }
        let placed = lock.withLock { () -> Bool in
            guard !stopped, session?.id == sessionId, peers[userId] == nil else { return false }
            peers[userId] = peer
            byAddress[address] = peer
            return true
        }
        guard placed else { return peer.connection.close() }
        let options = RTCDataChannelConfiguration()
        options.isOrdered = false
        options.maxRetransmits = 0
        let channel = peer.connection.dataChannel(forLabel: OnlinePeerMesh.label, configuration: options)
        channel?.delegate = peer
        lock.withLock { peer.channel = channel }
        Task {
            do {
                let made = try await peer.connection.offer(for: OnlinePeerMesh.noConstraints)
                try await peer.connection.setLocalDescription(made)
                self.signal(peer, kind: "offer", ["type": "offer", "sdp": peer.connection.localDescription?.sdp ?? made.sdp])
            } catch {
                self.failed(peer)
            }
        }
    }

    private func answer(_ userId: String, address: UInt32, device: String, sdp: String, session: OnlinePeerSession) async {
        let servers = await servers(for: session.id)
        guard let peer = makePeer(userId, address: address, device: device, offerer: false, servers: servers) else { return }
        let replaced = lock.withLock { () -> Peer?? in
            guard !stopped, self.session?.id == session.id else { return .none }
            let old = peers[userId]
            peers[userId] = peer
            byAddress[address] = peer
            return .some(old)
        }
        guard case .some(let old) = replaced else { return peer.connection.close() }
        if let old { close(old, sayBye: false) }
        do {
            try await peer.connection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
            await flush(peer)
            let made = try await peer.connection.answer(for: OnlinePeerMesh.noConstraints)
            try await peer.connection.setLocalDescription(made)
            signal(peer, kind: "answer", ["type": "answer", "sdp": peer.connection.localDescription?.sdp ?? made.sdp])
        } catch {
            failed(peer)
        }
    }

    private func flush(_ peer: Peer) async {
        let queued = lock.withLock { () -> [RTCIceCandidate] in
            defer { peer.queued = [] }
            peer.haveRemote = true
            return peer.queued
        }
        for candidate in queued { try? await peer.connection.add(candidate) }
    }

    fileprivate func signal(_ peer: Peer, kind: String, _ data: [String: Any]) {
        guard let sessionId = lock.withLock({ session?.id }), let json = try? JSONSerialization.data(withJSONObject: data) else { return }
        context.signal(peer.userId, peer.device, sessionId, kind, json)
    }

    fileprivate func opened(_ peer: Peer, _ channel: RTCDataChannel) {
        lock.withLock { peer.channel = channel }
    }

    fileprivate func connectionChanged(_ peer: Peer, _ state: RTCPeerConnectionState) {
        lock.withLock {
            switch state {
            case .connected: peer.state = .connected
            case .failed: peer.state = .failed
            case .closed: peer.state = .closed
            default: break
            }
        }
    }

    private func failed(_ peer: Peer) {
        lock.withLock { peer.state = .failed }
    }

    fileprivate func received(_ data: Data, from peer: Peer) {
        guard data.count >= OnlinePeerMesh.headerSize else { return }
        var reader = OnlineWire.Reader(data)
        let sourcePort = reader.u16(), sourceVport = reader.u16(), destinationPort = reader.u16(), destinationVport = reader.u16()
        guard let kind = OnlineWire.DatagramKind(rawValue: reader.u8()), reader.ok else { return }
        let current = lock.withLock { () -> Bool in
            guard byAddress[peer.address] === peer else { return false }
            counters.received += 1
            return true
        }
        guard current else { return }
        context.deliver(OnlineWire.Datagram(peer: peer.address, peerPort: sourcePort, peerVport: sourceVport, localPort: destinationPort, localVport: destinationVport,
                                            kind: kind, data: Data(data.dropFirst(OnlinePeerMesh.headerSize))))
    }

    private func close(_ peer: Peer, sayBye: Bool, in sessionId: String? = nil) {
        if sayBye, let sessionId = sessionId ?? lock.withLock({ session?.id }) { context.signal(peer.userId, peer.device, sessionId, "bye", Data("null".utf8)) }
        lock.withLock { peer.state = .closed }
        peer.mesh = nil
        peer.connection.close()
    }
}
