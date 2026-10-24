import AnyPS5Core
import CoreMedia
import CoreVideo
import Foundation
import WebRTC

/// The host's side of share play: the captured game as one WebRTC video track (H.264 on the
/// Mac's media engine through WebRTC's VideoToolbox encoder, 720p60, following WebRTC's
/// bandwidth estimate), sent to each viewer on a peer connection of its own; the game's sound on
/// a lossy data channel ("audio"); and each viewer's pad on another ("pad"), handed to `onPad`
/// (SharePadRouter decides whether it reaches the game). The host always makes the offers.
@MainActor
public final class SharePlayHost: NSObject {
    /// How a viewer's connection is doing, for the host's list.
    public struct Link: Equatable, Sendable {
        public var state: RTCPeerConnectionState
        /// Round trip in milliseconds, nil until measured.
        public var roundTrip: Double?
        /// What WebRTC's bandwidth estimate lets the host send to them, bit/s.
        public var sendRate: Double?
        /// Through the relay rather than directly.
        public var relayed: Bool?
        public var framesPerSecond: Double?
        public var frameHeight: Int?

        public init(state: RTCPeerConnectionState, roundTrip: Double? = nil, sendRate: Double? = nil, relayed: Bool? = nil, framesPerSecond: Double? = nil, frameHeight: Int? = nil) {
            self.state = state
            self.roundTrip = roundTrip
            self.sendRate = sendRate
            self.relayed = relayed
            self.framesPerSecond = framesPerSecond
            self.frameHeight = frameHeight
        }
    }

    fileprivate final class Peer: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
        let userId: String
        let device: String
        var connection: RTCPeerConnection!
        var pad: RTCDataChannel?
        var audio: RTCDataChannel?
        var sender: RTCRtpSender?
        var queued: [RTCIceCandidate] = []
        var link = Link(state: .new)
        weak var host: SharePlayHost?

        init(userId: String, device: String) {
            self.userId = userId
            self.device = device
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            let signal = ShareSignal.candidate(sdp: candidate.sdp, mid: candidate.sdpMid, index: candidate.sdpMLineIndex)
            Task { @MainActor [weak self] in
                guard let self, let host = self.host else { return }
                host.send(self.userId, self.device, signal)
            }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
            Task { @MainActor [weak self] in
                guard let self, let host = self.host else { return }
                self.link.state = newState
                host.stateChanged(self)
            }
        }

        func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
            if dataChannel.label == ShareWebRTC.audioLabel { host?.audioChannels(changed: self, channel: dataChannel) }
        }

        /// A viewer's pad packet, as it comes (WebRTC's own thread): straight on, no hop.
        func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
            guard dataChannel.label == ShareWebRTC.padLabel, buffer.isBinary else { return }
            host?.onPad(userId, buffer.data)
        }
    }

    nonisolated(unsafe) private let video: RTCVideoSource
    nonisolated(unsafe) private let capturer: RTCVideoCapturer
    private let track: RTCVideoTrack
    private var configuration: RTCConfiguration
    private var peers: [String: Peer] = [:]
    private let send: (_ to: String, _ device: String, _ signal: ShareSignal) -> Void
    /// A viewer's pad packet; called on WebRTC's thread.
    nonisolated let onPad: @Sendable (_ userId: String, _ packet: Data) -> Void
    private let changed: () -> Void
    /// Open sound channels, for the capture's thread.
    private let sound = Locked<[String: RTCDataChannel]>([:])
    private var encoding = SharePlayRoster.encoding(viewers: 1)
    private var statsTimer: Timer?

    nonisolated var soundChannels: [String: Int] { sound.value.mapValues(\.readyState.rawValue) }

    /// Every viewer's connection now, by user ID.
    public var links: [String: Link] { peers.mapValues(\.link) }

    public init(iceServers: [TogetherIceServer], send: @escaping (_ to: String, _ device: String, _ signal: ShareSignal) -> Void,
                onPad: @escaping @Sendable (_ userId: String, _ packet: Data) -> Void, changed: @escaping () -> Void = {}) {
        configuration = ShareWebRTC.configuration(iceServers)
        self.send = send
        self.onPad = onPad
        self.changed = changed
        video = ShareWebRTC.factory.videoSource(forScreenCast: false)
        capturer = RTCVideoCapturer(delegate: video)
        track = ShareWebRTC.factory.videoTrack(with: video, trackId: "game")
        super.init()
        video.adaptOutputFormat(toWidth: 1280, height: 720, fps: 60)
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.measure() }
        }
    }

    // MARK: Picture and sound

    /// A captured frame (NV12 or BGRA), from the capture's own thread.
    public nonisolated func push(_ pixels: CVPixelBuffer, timeNs: Int64) {
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels), rotation: ._0, timeStampNs: timeNs)
        video.capturer(capturer, didCapture: frame)
    }

    /// The game's sound as StreamPacket audio, to every viewer whose sound channel is open; a
    /// viewer whose channel is backed up skips it rather than fall behind.
    public nonisolated func push(sound packet: Data) {
        let buffer = RTCDataBuffer(data: packet, isBinary: true)
        for channel in sound.value.values where channel.readyState == .open && channel.bufferedAmount < 64 * 1024 {
            channel.sendData(buffer)
        }
    }

    /// The game's answer on a viewer's pad (vibration, light bar).
    public func sendPadOutput(_ data: Data, to userId: String) {
        guard let channel = peers[userId]?.pad, channel.readyState == .open else { return }
        channel.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

    // MARK: Viewers

    /// Calls a viewer on `device` (again, if they were on another device or their link broke).
    public func call(_ userId: String, device: String) {
        if let known = peers[userId], known.device == device, known.link.state != .failed, known.link.state != .closed { return }
        if peers[userId] != nil { hangUp(userId, sayBye: false) }
        guard let peer = open(userId: userId, device: device) else { return }
        Task { await offer(peer) }
    }

    public func hangUp(_ userId: String, sayBye: Bool = true) {
        guard let peer = peers.removeValue(forKey: userId) else { return }
        if sayBye { send(peer.userId, peer.device, .bye) }
        sound.withLock { $0[userId] = nil }
        peer.connection.close()
        retune()
        changed()
    }

    public func receive(_ signal: ShareSignal, from userId: String, device: String) {
        Task { await handle(signal, from: userId, device: device) }
    }

    /// New relay credentials: every connection takes them and restarts ICE with them.
    public func renew(_ iceServers: [TogetherIceServer]) {
        configuration = ShareWebRTC.configuration(iceServers)
        for peer in peers.values {
            peer.connection.setConfiguration(configuration)
            Task { await offer(peer, restart: true) }
        }
    }

    public func close() {
        for userId in Array(peers.keys) { hangUp(userId) }
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func handle(_ signal: ShareSignal, from userId: String, device: String) async {
        switch signal {
        case .renegotiate:
            // A viewer that joined (or whose link broke) asks: a new connection to that device,
            // or a fresh offer with an ICE restart on the one it has.
            if let peer = peers[userId], peer.device == device, peer.link.state != .failed, peer.link.state != .closed {
                await offer(peer, restart: peer.link.state != .new)
            } else {
                call(userId, device: device)
            }
        case .answer(let sdp):
            guard let peer = peers[userId], peer.device == device, peer.connection.signalingState == .haveLocalOffer else { return }
            let tuned = SharePlayRoster.tuneVideo(sdp, startKbps: encoding.startKbps, maxKbps: encoding.maxBitrate / 1000)
            do {
                try await peer.connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: tuned))
            } catch {
                try? await peer.connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
            }
            await flush(peer)
        case .candidate(let sdp, let mid, let index):
            guard let peer = peers[userId], peer.device == device else { return }
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: index, sdpMid: mid)
            if peer.connection.remoteDescription != nil { try? await peer.connection.add(candidate) } else { peer.queued.append(candidate) }
        case .bye:
            if peers[userId]?.device == device { hangUp(userId, sayBye: false) }
        case .offer:
            // The host makes the offers; a viewer's is not taken.
            break
        }
    }

    private func open(userId: String, device: String) -> Peer? {
        let peer = Peer(userId: userId, device: device)
        peer.host = self
        guard let connection = ShareWebRTC.factory.peerConnection(with: configuration, constraints: ShareWebRTC.noConstraints, delegate: peer) else { return nil }
        peer.connection = connection
        let initial = RTCRtpTransceiverInit()
        initial.direction = .sendOnly
        initial.streamIds = ["game"]
        if let transceiver = connection.addTransceiver(with: track, init: initial) {
            try? transceiver.setCodecPreferences(ShareWebRTC.videoCodecs(), error: ())
            peer.sender = transceiver.sender
        }
        peer.pad = connection.dataChannel(forLabel: ShareWebRTC.padLabel, configuration: ShareWebRTC.lossy())
        peer.audio = connection.dataChannel(forLabel: ShareWebRTC.audioLabel, configuration: ShareWebRTC.lossy())
        peer.pad?.delegate = peer
        peer.audio?.delegate = peer
        peers[userId] = peer
        retune()
        changed()
        return peer
    }

    private func offer(_ peer: Peer, restart: Bool = false) async {
        do {
            let constraints = RTCMediaConstraints(mandatoryConstraints: restart ? ["IceRestart": "true"] : nil, optionalConstraints: nil)
            let offer = try await peer.connection.offer(for: constraints)
            guard peer.connection.signalingState == .stable || peer.connection.signalingState == .haveLocalOffer else { return }
            try await peer.connection.setLocalDescription(offer)
            send(peer.userId, peer.device, .offer(sdp: offer.sdp))
        } catch {}
    }

    private func flush(_ peer: Peer) async {
        let queued = peer.queued
        peer.queued = []
        for candidate in queued { try? await peer.connection.add(candidate) }
    }

    fileprivate func stateChanged(_ peer: Peer) {
        changed()
    }

    fileprivate nonisolated func audioChannels(changed peer: Peer, channel: RTCDataChannel) {
        let userId = peer.userId
        sound.withLock { $0[userId] = channel.readyState == .open ? channel : nil }
    }

    /// Each viewer's stream as the number of viewers allows (720p60, or 540p30 from three on).
    private func retune() {
        encoding = SharePlayRoster.encoding(viewers: max(1, peers.count))
        for peer in peers.values {
            guard let sender = peer.sender else { continue }
            let parameters = sender.parameters
            for encoding in parameters.encodings {
                encoding.maxBitrateBps = NSNumber(value: self.encoding.maxBitrate)
                encoding.maxFramerate = NSNumber(value: self.encoding.maxFramerate)
                encoding.scaleResolutionDownBy = NSNumber(value: self.encoding.scaleDown)
            }
            // Bit rate goes first; the picture shrinks or slows only when the estimate stays low.
            parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.balanced.rawValue)
            sender.parameters = parameters
            peer.connection.setBweMinBitrateBps(NSNumber(value: 600_000), currentBitrateBps: NSNumber(value: self.encoding.startKbps * 1000),
                                                maxBitrateBps: NSNumber(value: self.encoding.maxBitrate))
        }
    }

    /// Round trip, send rate, path and frame rate of each viewer, from WebRTC's statistics.
    private func measure() {
        for peer in peers.values where peer.link.state == .connected {
            peer.connection.statistics { [weak self] report in
                var link = Link(state: .connected)
                var pairs: [String: RTCStatistics] = [:]
                var candidates: [String: RTCStatistics] = [:]
                for statistic in report.statistics.values {
                    switch statistic.type {
                    case "candidate-pair": pairs[statistic.id] = statistic
                    case "local-candidate", "remote-candidate": candidates[statistic.id] = statistic
                    case "outbound-rtp" where (statistic.values["kind"] as? String) == "video":
                        link.framesPerSecond = (statistic.values["framesPerSecond"] as? NSNumber)?.doubleValue
                        link.frameHeight = (statistic.values["frameHeight"] as? NSNumber)?.intValue
                    default: break
                    }
                }
                if let pair = pairs.values.first(where: { ($0.values["nominated"] as? NSNumber)?.boolValue == true && ($0.values["state"] as? String) == "succeeded" }) {
                    link.roundTrip = (pair.values["currentRoundTripTime"] as? NSNumber).map { $0.doubleValue * 1000 }
                    link.sendRate = (pair.values["availableOutgoingBitrate"] as? NSNumber)?.doubleValue
                    let local = (pair.values["localCandidateId"] as? String).flatMap { candidates[$0] }
                    link.relayed = (local?.values["candidateType"] as? String) == "relay"
                }
                Task { @MainActor [weak self] in
                    guard let self, let current = self.peers[peer.userId], current === peer else { return }
                    link.state = current.link.state
                    current.link = link
                    self.changed()
                }
            }
        }
    }
}
