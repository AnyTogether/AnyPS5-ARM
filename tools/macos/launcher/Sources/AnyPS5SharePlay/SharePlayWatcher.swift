import AnyPS5Core
import Foundation
import WebRTC

/// A viewer's side of share play: answers the host's offer, shows the game's video track
/// through `renderer`, asks for the game's sound as an Opus track (it plays through
/// ShareWebRTC.audioDevice, which SharePlaySpeaker pulls) and meanwhile hands on the PCM packets
/// from the "audio" channel (from hosts that send nothing else), and sends pad
/// packets on the "pad" channel while the host lets this viewer play. Asks the host for an offer
/// when it starts and again when its link breaks.
@MainActor
public final class SharePlayWatcher: NSObject {
    private final class Link: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
        weak var watcher: SharePlayWatcher?
        let channels = Locked<[RTCDataChannel]>([])

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            let signal = ShareSignal.candidate(sdp: candidate.sdp, mid: candidate.sdpMid, index: candidate.sdpMLineIndex)
            Task { @MainActor [weak self] in self?.watcher?.toHost(signal) }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
            Task { @MainActor [weak self] in self?.watcher?.stateChanged(newState, of: peerConnection) }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
            guard let track = transceiver.receiver.track as? RTCVideoTrack else { return }
            Task { @MainActor [weak self] in self?.watcher?.show(track) }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
            guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
            Task { @MainActor [weak self] in self?.watcher?.show(track) }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            // The channel's wrapper must be kept, or its messages stop with it.
            channels.withLock { $0.append(dataChannel) }
            dataChannel.delegate = self
            Task { @MainActor [weak self] in self?.watcher?.opened(dataChannel) }
        }

        func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
            guard dataChannel.readyState == .open else { return }
            Task { @MainActor [weak self] in self?.watcher?.opened(dataChannel) }
        }

        func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
            guard buffer.isBinary, let watcher else { return }
            if dataChannel.label == ShareWebRTC.audioLabel { watcher.onSound(buffer.data) }
            if dataChannel.label == ShareWebRTC.padLabel { watcher.onPadOutput(buffer.data) }
        }
    }

    public let hostId: String
    public let hostDevice: String
    private let send: (_ to: String, _ device: String, _ signal: ShareSignal) -> Void
    private let renderer: RTCVideoRenderer
    /// StreamPacket audio from the host; called on WebRTC's thread.
    nonisolated let onSound: @Sendable (Data) -> Void
    /// The game's answers on this viewer's pad; called on WebRTC's thread.
    nonisolated let onPadOutput: @Sendable (Data) -> Void
    private let changed: (RTCPeerConnectionState) -> Void
    private var configuration: RTCConfiguration
    private var connection: RTCPeerConnection?
    private let link = Link()
    private var queued: [RTCIceCandidate] = []
    private var pad: RTCDataChannel?
    private var video: RTCVideoTrack?
    /// What this viewer tells the host it plays, best first; empty sends no hello (PCM only).
    private let codecs: [ShareAudioCodec]
    private weak var greeted: RTCDataChannel?
    public private(set) var state: RTCPeerConnectionState = .new

    public init(hostId: String, hostDevice: String, iceServers: [TogetherIceServer], renderer: RTCVideoRenderer,
                send: @escaping (_ to: String, _ device: String, _ signal: ShareSignal) -> Void,
                onSound: @escaping @Sendable (Data) -> Void = { _ in }, onPadOutput: @escaping @Sendable (Data) -> Void = { _ in },
                changed: @escaping (RTCPeerConnectionState) -> Void = { _ in }, audio codecs: [ShareAudioCodec] = [.opus, .pcm]) {
        self.codecs = codecs
        self.hostId = hostId
        self.hostDevice = hostDevice
        self.renderer = renderer
        self.send = send
        self.onSound = onSound
        self.onPadOutput = onPadOutput
        self.changed = changed
        configuration = ShareWebRTC.configuration(iceServers)
        super.init()
        link.watcher = self
    }

    /// Asks the host for an offer (after joining).
    public func start() { toHost(.renegotiate) }

    /// A pad packet to the host; dropped while the channel is not open.
    @discardableResult
    public func sendPad(_ packet: Data) -> Bool {
        guard let pad, pad.readyState == .open else { return false }
        return pad.sendData(RTCDataBuffer(data: packet, isBinary: true))
    }

    public var padOpen: Bool { pad?.readyState == .open }

    public func receive(_ signal: ShareSignal, from userId: String, device: String) {
        guard userId == hostId else { return }
        Task { await handle(signal) }
    }

    public func renew(_ iceServers: [TogetherIceServer]) {
        configuration = ShareWebRTC.configuration(iceServers)
        connection?.setConfiguration(configuration)
    }

    public func close(sayBye: Bool = true) {
        if sayBye, connection != nil { toHost(.bye) }
        video?.remove(renderer)
        video = nil
        connection?.close()
        connection = nil
        pad = nil
        link.channels.value = []
        state = .closed
    }

    private func handle(_ signal: ShareSignal) async {
        switch signal {
        case .offer(let sdp):
            if connection == nil || state == .failed || state == .closed { makeConnection() }
            guard let connection else { return }
            do {
                try await connection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
                let queued = self.queued
                self.queued = []
                for candidate in queued { try? await connection.add(candidate) }
                let made = try await connection.answer(for: ShareWebRTC.noConstraints)
                // Stereo asked for, or WebRTC decodes the game's sound as mono.
                let answer = RTCSessionDescription(type: .answer, sdp: ShareAudioSDP.stereoOpus(made.sdp))
                do { try await connection.setLocalDescription(answer) } catch { try await connection.setLocalDescription(made) }
                toHost(.answer(sdp: connection.localDescription?.sdp ?? made.sdp))
            } catch {}
        case .candidate(let sdp, let mid, let index):
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: index, sdpMid: mid)
            if let connection, connection.remoteDescription != nil { try? await connection.add(candidate) } else { queued.append(candidate) }
        case .bye:
            close(sayBye: false)
            changed(.closed)
        case .answer, .renegotiate:
            break
        }
    }

    private func makeConnection() {
        connection?.close()
        link.channels.value = []
        queued = []
        connection = ShareWebRTC.factory.peerConnection(with: configuration, constraints: ShareWebRTC.noConstraints, delegate: link)
    }

    fileprivate func toHost(_ signal: ShareSignal) { send(hostId, hostDevice, signal) }

    fileprivate func show(_ track: RTCVideoTrack) {
        guard track !== video else { return }
        video?.remove(renderer)
        video = track
        track.add(renderer)
    }

    fileprivate func opened(_ channel: RTCDataChannel) {
        if channel.label == ShareWebRTC.padLabel { pad = channel }
        // Once per channel, as soon as it is open.
        if channel.label == ShareWebRTC.audioLabel, !codecs.isEmpty, channel.readyState == .open, channel !== greeted {
            let hello = ShareAudioHello(codecs: codecs).text
            if channel.sendData(RTCDataBuffer(data: Data(hello.utf8), isBinary: false)) { greeted = channel }
        }
    }

    /// What the game's sound arrives as, from the statistics; nil without an audio track.
    public struct AudioStatistics: Sendable, Equatable {
        /// "audio/opus".
        public var codec: String?
        public var channels: Int?
        /// When measured, seconds.
        public var time: Double
        public var bytes: Double
        public var packets: Double
        /// Seconds the jitter buffer held the samples it gave out, summed, and how many.
        public var bufferDelay: Double
        public var bufferEmitted: Double
        public var concealed: Double
        public var samples: Double

        /// The average hold since `earlier` (or since the start), milliseconds.
        public func bufferMs(since earlier: AudioStatistics? = nil) -> Double? {
            let emitted = bufferEmitted - (earlier?.bufferEmitted ?? 0)
            return emitted > 0 ? (bufferDelay - (earlier?.bufferDelay ?? 0)) / emitted * 1000 : nil
        }
    }

    public func audioStatistics(_ done: @escaping @Sendable (AudioStatistics?) -> Void) {
        guard let connection else { return done(nil) }
        connection.statistics { report in
            guard let inbound = report.statistics.values.first(where: { $0.type == "inbound-rtp" && ($0.values["kind"] as? String) == "audio" }) else {
                return done(nil)
            }
            func number(_ key: String) -> Double { (inbound.values[key] as? NSNumber)?.doubleValue ?? 0 }
            let codec = (inbound.values["codecId"] as? String).flatMap { report.statistics[$0] }
            done(AudioStatistics(codec: codec?.values["mimeType"] as? String, channels: (codec?.values["channels"] as? NSNumber)?.intValue,
                                 time: inbound.timestamp_us / 1_000_000, bytes: number("bytesReceived"), packets: number("packetsReceived"), bufferDelay: number("jitterBufferDelay"),
                                 bufferEmitted: number("jitterBufferEmittedCount"), concealed: number("concealedSamples"),
                                 samples: number("totalSamplesReceived")))
        }
    }


    fileprivate func stateChanged(_ newState: RTCPeerConnectionState, of peerConnection: RTCPeerConnection) {
        guard peerConnection === connection else { return }
        state = newState
        changed(newState)
        // A broken link: the host is asked for a fresh offer (an ICE restart, through the relay
        // if it must).
        if newState == .failed { toHost(.renegotiate) }
    }

    /// The video codec the connection settled on ("video/H264"), from the statistics.
    public func videoCodec(_ done: @escaping @Sendable (String?) -> Void) {
        guard let connection else { return done(nil) }
        connection.statistics { report in
            let inbound = report.statistics.values.first { $0.type == "inbound-rtp" && ($0.values["kind"] as? String) == "video" }
            let codec = (inbound?.values["codecId"] as? String).flatMap { report.statistics[$0]?.values["mimeType"] as? String }
            done(codec)
        }
    }

    /// Round trip and the picture's rate and size, for the viewer's indicator.
    public func statistics(_ done: @escaping @Sendable (_ roundTripMs: Double?, _ fps: Double?, _ height: Int?) -> Void) {
        guard let connection else { return done(nil, nil, nil) }
        connection.statistics { report in
            var roundTrip: Double?, fps: Double?, height: Int?
            for statistic in report.statistics.values {
                if statistic.type == "candidate-pair", (statistic.values["nominated"] as? NSNumber)?.boolValue == true {
                    roundTrip = (statistic.values["currentRoundTripTime"] as? NSNumber).map { $0.doubleValue * 1000 } ?? roundTrip
                }
                if statistic.type == "inbound-rtp", (statistic.values["kind"] as? String) == "video" {
                    fps = (statistic.values["framesPerSecond"] as? NSNumber)?.doubleValue
                    height = (statistic.values["frameHeight"] as? NSNumber)?.intValue
                }
            }
            done(roundTrip, fps, height)
        }
    }
}
