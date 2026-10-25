import AnyPS5Core
import CShareAudio
import Foundation
import WebRTC

/// A share play signal as the host and the viewer hand it on: what the gateway carries
/// (`share_play.signal`), in the shapes a browser's toJSON() gives.
public enum ShareSignal: Sendable, Equatable {
    case offer(sdp: String)
    case answer(sdp: String)
    case candidate(sdp: String, mid: String?, index: Int32)
    case bye
    /// A viewer asking the host for a (new) offer: after joining, or when its connection broke.
    case renegotiate

    public init?(_ signal: TogetherShareSignal) {
        switch signal.kind {
        case .offer: guard let sdp = signal.description?.sdp else { return nil }; self = .offer(sdp: sdp)
        case .answer: guard let sdp = signal.description?.sdp else { return nil }; self = .answer(sdp: sdp)
        case .candidate:
            guard let candidate = signal.candidate else { return nil }
            self = .candidate(sdp: candidate.candidate, mid: candidate.sdpMid, index: candidate.sdpMLineIndex ?? 0)
        case .bye: self = .bye
        case .renegotiate: self = .renegotiate
        case .message: return nil
        }
    }

    public var kind: TogetherShareSignal.Kind {
        switch self {
        case .offer: .offer
        case .answer: .answer
        case .candidate: .candidate
        case .bye: .bye
        case .renegotiate: .renegotiate
        }
    }

    /// The signal's data as JSON for the gateway frame.
    public var data: Any? {
        switch self {
        case .offer(let sdp): ["type": "offer", "sdp": sdp]
        case .answer(let sdp): ["type": "answer", "sdp": sdp]
        case .candidate(let sdp, let mid, let index): ["candidate": sdp, "sdpMid": mid.map { $0 as Any } ?? NSNull(), "sdpMLineIndex": index]
        case .bye, .renegotiate: nil
        }
    }
}

/// The WebRTC pieces both sides share: one factory (H.264 on VideoToolbox first), the
/// configuration, and the data channels' names and options.
public enum ShareWebRTC {
    /// Pads: viewer → host 80-byte input packets, host → viewer 32-byte answers.
    public static let padLabel = "pad"
    /// The game's sound: host → viewer, StreamPacket audio (5 ms of 16-bit stereo at 48 kHz),
    /// until the viewer's hello (viewer → host, text) gets them the Opus track instead.
    public static let audioLabel = "audio"

    /// The factory's audio device: the game's sound goes in where a microphone would, what the
    /// viewer receives comes out to whoever pulls it. No real device is ever opened.
    public static let audioDevice = ShareAudioDevice()

    /// Its own factory, apart from the party voice's, with `audioDevice` for its sound.
    public static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return ShareAudioFactory(audioDevice)
    }()

    /// The game's sound as one audio track every Opus viewer's connection sends: straight from
    /// `audioDevice`, none of WebRTC's voice processing (echo cancelling would also fold it to
    /// mono; gain control and noise suppression would pump and eat the music).
    public static let gameAudio: RTCAudioTrack = {
        let off = ["googEchoCancellation": "false", "googAutoGainControl": "false", "googNoiseSuppression": "false",
                   "googHighpassFilter": "false"]
        let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: off, optionalConstraints: nil))
        return factory.audioTrack(with: source, trackId: "game-audio")
    }()

    public static func configuration(_ iceServers: [TogetherIceServer]) -> RTCConfiguration {
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.continualGatheringPolicy = .gatherContinually
        return configuration
    }

    /// Unordered and never sent again: a late pad state or sound is worse than none.
    public static func lossy() -> RTCDataChannelConfiguration {
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = false
        configuration.maxRetransmits = 0
        return configuration
    }

    /// H.264 first (High, then Constrained Baseline: both on the Mac's media engine and in every
    /// browser), then whatever else the factory has, as a fallback.
    public static func videoCodecs() -> [RTCRtpCodecCapability] {
        let all = factory.rtpSenderCapabilities(forKind: kRTCMediaStreamTrackKindVideo).codecs
        func rank(_ codec: RTCRtpCodecCapability) -> Int {
            guard codec.name.uppercased() == "H264" else { return ["RTX", "RED", "ULPFEC", "FLEXFEC-03"].contains(codec.name.uppercased()) ? 3 : 2 }
            let profile = codec.parameters["profile-level-id"] ?? ""
            let packetized = codec.parameters["packetization-mode"] == "1"
            return profile.hasPrefix("64") && packetized ? 0 : packetized ? 1 : 2
        }
        return all.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// Opus first (the game's sound track is always Opus), then the rest as WebRTC orders them.
    public static func audioCodecs() -> [RTCRtpCodecCapability] {
        let all = factory.rtpSenderCapabilities(forKind: kRTCMediaStreamTrackKindAudio).codecs
        return all.filter { $0.name.lowercased() == "opus" } + all.filter { $0.name.lowercased() != "opus" }
    }

    static let noConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
}
