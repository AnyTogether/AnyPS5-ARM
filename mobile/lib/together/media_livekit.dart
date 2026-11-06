import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'media.dart';
import 'phone_audio.dart';
import 'share_play.dart';
import 'share_play_webrtc.dart' show ShareStats;
import 'voice.dart';
import 'voice_mesh.dart';

/// Why LiveKit let go of a room: taken out or the room closed is for good (the server says the
/// rest); anything else is a lost connection, joined again.
String _gone(lk.DisconnectReason? reason) => switch (reason) {
  lk.DisconnectReason.participantRemoved ||
  lk.DisconnectReason.roomDeleted ||
  lk.DisconnectReason.duplicateIdentity => 'closed',
  _ => 'failed',
};

/// Watching a share play from the media server with LiveKit: only the host's "game" picture and
/// "game-audio" sound subscribed (the sound plays as WebRTC plays any), nothing published.
class LiveKitShareRoom implements ShareRoom {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  String _host = '';
  final _picture = ValueNotifier<lk.VideoTrack?>(null);
  final _stats = ShareStats();
  void Function()? _onState;
  bool _leaving = false;

  @override
  String state = 'connecting';

  @override
  set onState(void Function() handler) => _onState = handler;

  void _set(String next) {
    if (_leaving || next == state) return;
    state = next;
    _onState?.call();
  }

  @override
  Future<void> join(SfuAccess access, {required String host}) async {
    _host = host;
    await PhoneAudio.playback();
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: false),
    );
    _room = room;
    final events = room.createListener();
    _events = events;
    events
      ..on<lk.TrackPublishedEvent>((e) => _want(e.participant, e.publication))
      ..on<lk.ParticipantConnectedEvent>((e) {
        for (final publication in e.participant.trackPublications.values) {
          _want(e.participant, publication);
        }
      })
      ..on<lk.TrackSubscribedEvent>((e) {
        final track = e.track;
        if (e.participant.identity != _host ||
            e.publication.name != sfuGameVideo ||
            track is! lk.RemoteVideoTrack) {
          return;
        }
        _picture.value = track;
        _set('connected');
      })
      ..on<lk.TrackUnsubscribedEvent>((e) {
        if (e.track != _picture.value) return;
        _picture.value = null;
        _set('connecting');
      })
      ..on<lk.RoomReconnectingEvent>((_) => _set('connecting'))
      ..on<lk.RoomReconnectedEvent>(
        (_) => _set(_picture.value != null ? 'connected' : 'connecting'),
      )
      ..on<lk.RoomDisconnectedEvent>((e) => _set(_gone(e.reason)));
    await room.connect(
      access.url,
      access.token,
      connectOptions: const lk.ConnectOptions(autoSubscribe: false),
    );
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.trackPublications.values) {
        _want(participant, publication);
      }
    }
  }

  /// The host's game picture and sound; nobody else's, nothing else.
  void _want(
    lk.RemoteParticipant participant,
    lk.RemoteTrackPublication publication,
  ) {
    if (participant.identity != _host) return;
    if (publication.name != sfuGameVideo && publication.name != sfuGameAudio) {
      return;
    }
    publication.subscribe().catchError((_) {});
  }

  @override
  Widget video() => ValueListenableBuilder<lk.VideoTrack?>(
    valueListenable: _picture,
    builder: (context, track, _) => track == null
        ? const SizedBox.expand()
        : lk.VideoTrackRenderer(track, fit: lk.VideoViewFit.contain),
  );

  @override
  Future<ShareQuality> quality() async {
    final receiver = (_picture.value as lk.RemoteVideoTrack?)?.receiver;
    if (receiver == null) return const ShareQuality();
    return _stats.read(await receiver.getStats());
  }

  @override
  Future<void> leave() async {
    _leaving = true;
    _onState = null;
    _picture.value = null;
    final room = _room;
    _room = null;
    await _events?.dispose();
    _events = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
  }
}

/// The party's voice in the media server's room with LiveKit: the microphone published (muted
/// as asked, the platform's echo cancellation, noise suppression and gain as on the mesh),
/// everyone else's voice subscribed, and nobody played while deafened.
class LiveKitVoiceRoom implements VoiceRoom {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  void Function()? _onChange;
  bool _talking = true;
  bool _hearing = true;
  bool _leaving = false;

  @override
  String state = 'connecting';

  @override
  set onChange(void Function() handler) => _onChange = handler;

  void _changed([String? next]) {
    if (_leaving) return;
    if (next != null) state = next;
    _onChange?.call();
  }

  @override
  Future<void> join(
    SfuAccess access, {
    required bool talking,
    required bool hearing,
  }) async {
    _talking = talking;
    _hearing = hearing;
    // Joined again after a lost connection: the old room goes first.
    await _close();
    state = 'connecting';
    await PhoneAudio.voice(true);
    await PhoneAudio.speaker();
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(
          // Muting only stops sending, so it is quick and makes no sound.
          stopAudioCaptureOnMute: false,
        ),
      ),
    );
    _room = room;
    final events = room.createListener();
    _events = events;
    events
      ..on<lk.TrackSubscribedEvent>((e) {
        if (e.track is lk.RemoteAudioTrack && !_hearing) {
          _hear(e.publication, false);
        }
        _changed();
      })
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _changed())
      ..on<lk.ParticipantConnectedEvent>((_) => _changed())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _changed())
      ..on<lk.RoomReconnectingEvent>((_) => _changed('connecting'))
      ..on<lk.RoomReconnectedEvent>((_) => _changed('connected'))
      ..on<lk.RoomDisconnectedEvent>((e) {
        if (_room == room) _changed(_gone(e.reason));
      });
    await room.connect(access.url, access.token);
    if (_talking) {
      await room.localParticipant?.setMicrophoneEnabled(true);
    }
    _changed('connected');
  }

  @override
  set talking(bool on) {
    _talking = on;
    _room?.localParticipant?.setMicrophoneEnabled(on).catchError((_) => null);
  }

  @override
  set hearing(bool on) {
    _hearing = on;
    for (final participant
        in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[]) {
      for (final publication in participant.audioTrackPublications) {
        _hear(publication, on);
      }
    }
  }

  /// The server stops sending a voice nobody hears, and it is silenced here at once.
  void _hear(lk.RemoteTrackPublication publication, bool on) {
    (on ? publication.enable() : publication.disable()).catchError((_) {});
    final track = publication.track;
    if (track != null) {
      (on ? track.enable() : track.disable()).catchError((_) {});
    }
  }

  @override
  bool get speaking =>
      _talking && (_room?.localParticipant?.isSpeaking ?? false);

  @override
  List<PeerVoice> get peers => [
    for (final participant
        in _room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[])
      PeerVoice(participant.identity, 'connected', participant.isSpeaking),
  ];

  Future<void> _close() async {
    final room = _room;
    _room = null;
    await _events?.dispose();
    _events = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
  }

  @override
  Future<void> leave() async {
    _leaving = true;
    _onChange = null;
    await _close();
    await PhoneAudio.voice(false);
  }
}
