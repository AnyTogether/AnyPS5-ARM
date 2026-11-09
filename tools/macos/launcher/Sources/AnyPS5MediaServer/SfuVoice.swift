import AnyPS5Core
import Foundation
import LiveKit

/// A party's voice through the media server, once the call moved there (more voices than the mesh
/// holds): the microphone published once to the call's room, with WebRTC's voice processing as on
/// the mesh, and everyone else's voice heard from it. Muting turns the microphone track off;
/// deafened plays nobody. Who is speaking comes from LiveKit's active speakers.
@MainActor
public final class SfuVoice: NSObject {
    public let me: String
    public let call: String
    private let room = Room()
    private let changed: () -> Void
    private var microphone: LocalAudioTrack?
    private var audioClaimed = false
    private let noiseSuppression: Bool

    /// Who is speaking now, by user ID (the user too, while their microphone sends).
    public private(set) var speaking: Set<String> = []
    /// Who is in the room now, by user ID.
    public private(set) var connected: Set<String> = []

    /// Whether the microphone sends: muted, or push-to-talk not held, is false.
    public var talking = false {
        didSet {
            guard talking != oldValue else { return }
            applyTalking()
        }
    }

    /// Deafened: nobody in the call is heard.
    public var deafened = false {
        didSet {
            guard deafened != oldValue else { return }
            applyDeafened()
        }
    }

    public init(me: String, call: String, noiseSuppression: Bool = true, changed: @escaping () -> Void) {
        self.me = me
        self.call = call
        self.noiseSuppression = noiseSuppression
        self.changed = changed
        super.init()
        room.add(delegate: self)
    }

    /// Into the call's room, the microphone published (off until the user talks).
    public func start(_ access: TogetherSfuAccess) async throws {
        audioClaimed = true
        await SfuAudio.shared.voice(true)
        try await room.connect(url: access.url, token: access.token)
        let track = await LocalAudioTrack.createTrack(name: "voice", options: AudioCaptureOptions(noiseSuppression: noiseSuppression))
        microphone = track
        _ = try await room.localParticipant.publish(audioTrack: track, options: AudioPublishOptions(name: "voice", encoding: AudioEncoding(maxBitrate: 32000)))
        applyTalking()
        applyDeafened()
        refresh()
    }

    public func close() async {
        await room.disconnect()
        microphone = nil
        speaking = []
        connected = []
        if audioClaimed {
            audioClaimed = false
            await SfuAudio.shared.voice(false)
        }
    }

    private func applyTalking() {
        guard let microphone else { return }
        let on = talking
        Task { if on { try? await microphone.unmute() } else { try? await microphone.mute() } }
    }

    private func applyDeafened() {
        for participant in room.remoteParticipants.values {
            for case let publication as RemoteTrackPublication in participant.trackPublications.values {
                (publication.track as? RemoteAudioTrack)?.volume = deafened ? 0 : 1
            }
        }
    }

    fileprivate func refresh() {
        applyDeafened()
        let ids = Set(room.remoteParticipants.values.compactMap { $0.identity?.stringValue })
        let speakers = Set(room.activeSpeakers.compactMap { participant -> String? in
            guard let id = participant.identity?.stringValue else { return nil }
            return id == me && !talking ? nil : id
        })
        guard ids != connected || speakers != speaking else { return }
        connected = ids
        speaking = speakers
        changed()
    }
}

extension SfuVoice: RoomDelegate {
    public nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor in self.refresh() }
    }

    public nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in self.refresh() }
    }

    public nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in self.refresh() }
    }

    public nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in self.refresh() }
    }
}
