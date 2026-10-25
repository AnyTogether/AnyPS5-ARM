import AnyPS5Core
import AVFoundation
import Foundation
import WebRTC

/// Voice in a party as the website does it: a peer-to-peer mesh, one peer connection per member,
/// Opus tuned for speech and the WebRTC audio processing (echo cancellation, noise suppression,
/// gain). Whoever joins later makes the offers; when two offer at once the polite side (the larger
/// user ID) gives way. Signals go through the AnyTogether gateway (TogetherSocket.signal).
@MainActor
final class PartyVoice: NSObject {
    private final class Peer {
        let userId: String
        let device: String
        let connection: RTCPeerConnection
        var queued: [RTCIceCandidate] = []
        var makingOffer = false
        var ring = TogetherVoice.Speaking()
        var state: RTCPeerConnectionState = .new

        init(userId: String, device: String, connection: RTCPeerConnection) {
            self.userId = userId
            self.device = device
            self.connection = connection
        }
    }

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    let me: String
    let call: String
    private var configuration: RTCConfiguration
    private let send: (_ to: String, _ device: String, _ kind: TogetherSignalKind, _ data: Any?) -> Void
    private let changed: () -> Void
    private var peers: [String: Peer] = [:]
    private let track: RTCAudioTrack
    private var localRing = TogetherVoice.Speaking()
    private var timer: Timer?

    /// Who is speaking now, by user ID (the user too, while their microphone sends).
    private(set) var speaking: Set<String> = []
    /// Members with a connection that works.
    var connected: Set<String> { Set(peers.values.filter { $0.state == .connected }.map(\.userId)) }

    /// Whether the microphone sends: muted, or push-to-talk not held, is false.
    var talking = false {
        didSet { track.isEnabled = talking }
    }

    /// Deafened: no member is heard. Every remote audio track is turned off (and its volume to
    /// nothing), on the connections there are and on each one made or renegotiated later.
    var deafened = false {
        didSet {
            guard deafened != oldValue else { return }
            for peer in peers.values { silence(peer.connection) }
        }
    }

    /// The remote audio of one connection, heard or not as `deafened` says.
    private func silence(_ connection: RTCPeerConnection) {
        for receiver in connection.receivers {
            guard let audio = receiver.track as? RTCAudioTrack else { continue }
            if audio.isEnabled == deafened { audio.isEnabled = !deafened }
            let volume: Double = deafened ? 0 : 1
            if audio.source.volume != volume { audio.source.volume = volume }
        }
    }

    init(me: String, call: String, iceServers: [TogetherIceServer],
         send: @escaping (_ to: String, _ device: String, _ kind: TogetherSignalKind, _ data: Any?) -> Void, changed: @escaping () -> Void) {
        self.me = me
        self.call = call
        self.send = send
        self.changed = changed
        configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        let source = PartyVoice.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        track = PartyVoice.factory.audioTrack(with: source, trackId: "voice")
        super.init()
        track.isEnabled = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.measure() }
        }
    }

    /// Asks for the microphone the first time; false when the user said no.
    static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Calls a member already in the call (the newcomer offers).
    func connect(to peer: TogetherCallPeer) {
        guard peer.userId != me else { return }
        if let known = peers[peer.userId], known.device == peer.device, known.state != .failed { return }
        if peers[peer.userId] != nil { drop(peer.userId, sayBye: false) }
        guard let opened = open(peer) else { return }
        Task { await offer(opened) }
    }

    func receive(_ signal: TogetherSignal) {
        guard signal.call == call else { return }
        Task { await handle(signal) }
    }

    private func handle(_ signal: TogetherSignal) async {
        var peer = peers[signal.from]
        switch signal.kind {
        case .bye:
            drop(signal.from, sayBye: false)
        case .offer:
            guard let description = signal.description else { return }
            if let known = peer, known.device != signal.device {
                drop(signal.from, sayBye: false)
                peer = nil
            }
            guard let target = peer ?? open(TogetherCallPeer(userId: signal.from, device: signal.device)) else { return }
            let collision = target.makingOffer || target.connection.signalingState != .stable
            if collision && !TogetherVoice.polite(me: me, peer: signal.from) { return }
            do {
                if collision { try await target.connection.setLocalDescription(RTCSessionDescription(type: .rollback, sdp: "")) }
                try await target.connection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: description.sdp))
                silence(target.connection)
                await flush(target)
                let answer = try await target.connection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
                let tuned = RTCSessionDescription(type: .answer, sdp: TogetherVoice.tuneOpus(answer.sdp))
                try await target.connection.setLocalDescription(tuned)
                send(target.userId, target.device, .answer, ["type": "answer", "sdp": tuned.sdp])
            } catch {}
        case .answer:
            guard let target = peer, target.device == signal.device, let description = signal.description,
                  target.connection.signalingState == .haveLocalOffer else { return }
            try? await target.connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: description.sdp))
            silence(target.connection)
            await flush(target)
        case .candidate:
            guard let target = peer, target.device == signal.device, let candidate = signal.candidate else { return }
            let ice = RTCIceCandidate(sdp: candidate.candidate, sdpMLineIndex: candidate.sdpMLineIndex ?? 0, sdpMid: candidate.sdpMid)
            if target.connection.remoteDescription != nil {
                try? await target.connection.add(ice)
            } else {
                target.queued.append(ice)
            }
        case .renegotiate:
            if let target = peer { await offer(target, restart: true) }
        }
    }

    /// Someone left the call: their connection goes.
    func drop(_ userId: String, sayBye: Bool = true) {
        guard let peer = peers.removeValue(forKey: userId) else { return }
        if sayBye { send(peer.userId, peer.device, .bye, nil) }
        peer.connection.close()
        speaking.remove(userId)
        changed()
    }

    /// New relay credentials: every connection takes them, and the impolite side restarts ICE so
    /// its relay allocations are made again with them before the old ones stop working.
    func renew(_ iceServers: [TogetherIceServer]) {
        configuration.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        for peer in peers.values {
            peer.connection.setConfiguration(configuration)
            if me < peer.userId { Task { await offer(peer, restart: true) } }
        }
    }

    func close() {
        for userId in Array(peers.keys) { drop(userId) }
        timer?.invalidate()
        timer = nil
        track.isEnabled = false
    }

    private func open(_ target: TogetherCallPeer) -> Peer? {
        guard let connection = PartyVoice.factory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self) else { return nil }
        connection.add(track, streamIds: ["voice"])
        let peer = Peer(userId: target.userId, device: target.device, connection: connection)
        peers[target.userId] = peer
        silence(connection)
        changed()
        return peer
    }

    private func offer(_ peer: Peer, restart: Bool = false) async {
        peer.makingOffer = true
        defer { peer.makingOffer = false }
        do {
            let constraints = RTCMediaConstraints(mandatoryConstraints: restart ? ["IceRestart": "true"] : nil, optionalConstraints: nil)
            let offer = try await peer.connection.offer(for: constraints)
            guard peer.connection.signalingState == .stable else { return }
            let tuned = RTCSessionDescription(type: .offer, sdp: TogetherVoice.tuneOpus(offer.sdp))
            try await peer.connection.setLocalDescription(tuned)
            send(peer.userId, peer.device, .offer, ["type": "offer", "sdp": tuned.sdp])
        } catch {}
    }

    private func flush(_ peer: Peer) async {
        let queued = peer.queued
        peer.queued = []
        for candidate in queued { try? await peer.connection.add(candidate) }
    }

    private func peer(for connection: RTCPeerConnection) -> Peer? { peers.values.first { $0.connection === connection } }

    /// Levels from the connections' statistics, for the speaking rings.
    private func measure() {
        if deafened { for peer in peers.values { silence(peer.connection) } }
        for peer in peers.values {
            peer.connection.statistics { [weak self] report in
                var remote = 0.0, local = 0.0
                for statistic in report.statistics.values {
                    guard (statistic.values["kind"] as? String) == "audio", let level = (statistic.values["audioLevel"] as? NSNumber)?.doubleValue else { continue }
                    if statistic.type == "inbound-rtp" { remote = max(remote, level) }
                    if statistic.type == "media-source" { local = max(local, level) }
                }
                let userId = peer.userId
                Task { @MainActor in self?.levels(userId, remote: remote, local: local) }
            }
        }
        if peers.isEmpty { levels(nil, remote: 0, local: 0) }
    }

    private func levels(_ userId: String?, remote: Double, local: Double) {
        var next = speaking
        if let userId, let peer = peers[userId] {
            if peer.ring.update(level: remote) { next.insert(userId) } else { next.remove(userId) }
        }
        if localRing.update(level: talking ? local : 0) { next.insert(me) } else { next.remove(me) }
        guard next != speaking else { return }
        speaking = next
        changed()
    }
}

extension PartyVoice: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let data: [String: Any] = ["candidate": candidate.sdp, "sdpMid": candidate.sdpMid ?? NSNull(), "sdpMLineIndex": candidate.sdpMLineIndex]
        Task { @MainActor in
            guard let peer = self.peer(for: peerConnection) else { return }
            self.send(peer.userId, peer.device, .candidate, data)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor in
            guard let peer = self.peer(for: peerConnection) else { return }
            peer.state = newState
            // When a path breaks, the impolite side restarts ICE (through the relay if it must).
            if newState == .failed, self.me < peer.userId { await self.offer(peer, restart: true) }
            self.changed()
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    /// A member's audio arriving: silent at once while deafened.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        Task { @MainActor in
            guard self.peer(for: peerConnection) != nil else { return }
            self.silence(peerConnection)
        }
    }
}
