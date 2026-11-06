import AnyPS5Core
import AppKit
import Foundation
import LiveKit

/// A viewer's side of a share play through the media server, while they hold no pad: the host's
/// "game" picture in `view` and its "game-audio" sound out of the speakers (LiveKit plays it);
/// nothing goes back to the host. A pad handed over moves the viewer to the mesh
/// (SharePlayWatcher) and this one closes.
@MainActor
public final class SfuShareWatcher: NSObject {
    /// Round trip to the media server, and the picture's rate and size, for the viewer's line.
    public struct Statistics: Equatable, Sendable {
        public var roundTrip: Double?
        public var fps: Double?
        public var height: Int?
    }

    public let hostId: String
    /// The picture; it shows the host's video track once it comes.
    public let view = VideoView()
    private let room = Room()
    private let changed: (Bool) -> Void
    private var audioClaimed = false
    private var video: RemoteVideoTrack?
    /// 0 (silent) to 1.
    public var volume: Double = 1 {
        didSet { applyVolume() }
    }

    /// Whether the host's picture is showing.
    public private(set) var connected = false {
        didSet { if connected != oldValue { changed(connected) } }
    }

    public init(hostId: String, changed: @escaping (_ connected: Bool) -> Void = { _ in }) {
        self.hostId = hostId
        self.changed = changed
        super.init()
        view.layoutMode = .fit
        room.add(delegate: self)
    }

    /// Into the room with the viewer's token (subscribe only).
    public func start(_ access: TogetherSfuAccess) async throws {
        audioClaimed = true
        await SfuAudio.shared.watching(true)
        try await room.connect(url: access.url, token: access.token, roomOptions: RoomOptions(adaptiveStream: true, dynacast: true, reportRemoteTrackStatistics: true))
        for participant in room.remoteParticipants.values { attach(participant) }
    }

    public func close() async {
        view.track = nil
        video = nil
        connected = false
        await room.disconnect()
        if audioClaimed {
            audioClaimed = false
            await SfuAudio.shared.watching(false)
        }
    }

    /// The host's tracks of `participant`, once subscribed.
    private func attach(_ participant: RemoteParticipant) {
        guard participant.identity?.stringValue == hostId else { return }
        for case let publication as RemoteTrackPublication in participant.trackPublications.values {
            if publication.name == SfuTrackNames.video, let track = publication.track as? RemoteVideoTrack, track !== video {
                video = track
                view.track = track
                connected = true
            }
        }
        applyVolume()
    }

    private func applyVolume() {
        guard let host = room.remoteParticipants.values.first(where: { $0.identity?.stringValue == hostId }) else { return }
        for case let publication as RemoteTrackPublication in host.trackPublications.values where publication.name == SfuTrackNames.audio {
            (publication.track as? RemoteAudioTrack)?.volume = volume
        }
    }

    /// From the picture's statistics (LiveKit measures them about once a second).
    public func statistics() -> Statistics {
        let stats = video?.statistics
        let inbound = stats?.inboundRtpStream.first
        return Statistics(roundTrip: stats?.iceCandidatePair.first(where: { $0.nominated == true })?.currentRoundTripTime.map { $0 * 1000 },
                          fps: inbound?.framesPerSecond, height: inbound?.frameHeight.map { Int($0) })
    }
}

extension SfuShareWatcher: RoomDelegate {
    public nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in self.attach(participant) }
    }

    public nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        guard publication.name == SfuTrackNames.video, participant.identity?.stringValue == hostId else { return }
        Task { @MainActor in
            self.view.track = nil
            self.video = nil
            self.connected = false
        }
    }

    public nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        guard participant.identity?.stringValue == hostId else { return }
        Task { @MainActor in
            self.view.track = nil
            self.video = nil
            self.connected = false
        }
    }
}
