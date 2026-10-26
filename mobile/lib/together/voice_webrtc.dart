import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'voice_mesh.dart';

/// Voice with flutter_webrtc: the microphone with the platform's echo cancellation, noise
/// suppression and gain, the sound on the speaker (or the headphones), and one
/// RTCPeerConnection per member. The pad keeps going alongside: the audio session lets the
/// game's sound mix in and haptics play while recording.
class WebRtcVoice implements VoiceEngine {
  MediaStream? _stream;

  @override
  Future<void> start() async {
    await _session(voice: true);
    try {
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
    } on Object {
      await _session(voice: false);
      throw const VoiceDenied();
    }
    if (_stream!.getAudioTracks().isEmpty) {
      await stop();
      throw const VoiceDenied();
    }
    try {
      if (Platform.isIOS) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } else {
        await Helper.setSpeakerphoneOn(true);
      }
    } on Object {
      // The earpiece, then; voice still works.
    }
  }

  /// A voice chat while in voice; back to plain playback (Remote Play's sound) after.
  static Future<void> _session({required bool voice}) async {
    try {
      if (Platform.isIOS) {
        await Helper.setAppleAudioConfiguration(
          voice
              ? AppleAudioConfiguration(
                  appleAudioCategory: AppleAudioCategory.playAndRecord,
                  appleAudioCategoryOptions: {
                    AppleAudioCategoryOption.mixWithOthers,
                    AppleAudioCategoryOption.allowBluetooth,
                    AppleAudioCategoryOption.allowBluetoothA2DP,
                    AppleAudioCategoryOption.defaultToSpeaker,
                  },
                  appleAudioMode: AppleAudioMode.voiceChat,
                )
              : AppleAudioConfiguration(
                  appleAudioCategory: AppleAudioCategory.playback,
                  appleAudioCategoryOptions: {
                    AppleAudioCategoryOption.mixWithOthers,
                  },
                  appleAudioMode: AppleAudioMode.default_,
                ),
        );
      } else if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(
          voice
              ? AndroidAudioConfiguration.communication
              : AndroidAudioConfiguration.media,
        );
        if (!voice) await Helper.clearAndroidCommunicationDevice();
      }
    } on Object {
      // The platform's defaults, then.
    }
  }

  @override
  Future<VoiceLink> link(List<Map<String, dynamic>> iceServers) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    final stream = _stream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
      }
    }
    return _Link(pc);
  }

  @override
  void setTalking(bool on) {
    for (final track
        in _stream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = on;
    }
  }

  @override
  Future<void> stop() async {
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    await _session(voice: false);
  }
}

class _Link implements VoiceLink {
  _Link(this.pc) {
    pc.onConnectionState = (_) => _onState?.call();
    // A voice that arrives while deafened stays silent.
    pc.onTrack = (event) {
      if (event.track.kind == 'audio') event.track.enabled = _hearing;
    };
  }

  bool _hearing = true;

  final RTCPeerConnection pc;
  void Function()? _onState;

  /// Kept here, not read from the plugin, which hears of changes a moment late.
  String _signaling = 'stable';
  bool _hasRemote = false;

  @override
  set onCandidate(void Function(Map<String, dynamic>) handler) =>
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate != null) handler(candidate.toMap());
      };

  @override
  set onState(void Function() handler) => _onState = handler;

  @override
  String get signalingState => _signaling;

  @override
  bool get hasRemote => _hasRemote;

  @override
  String get connectionState => switch (pc.connectionState) {
    RTCPeerConnectionState.RTCPeerConnectionStateConnecting => 'connecting',
    RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'connected',
    RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => 'disconnected',
    RTCPeerConnectionState.RTCPeerConnectionStateFailed => 'failed',
    RTCPeerConnectionState.RTCPeerConnectionStateClosed => 'closed',
    _ => 'new',
  };

  @override
  Future<Map<String, dynamic>> createOffer({bool restart = false}) async {
    if (restart) await pc.restartIce();
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    return {'type': offer.type, 'sdp': offer.sdp};
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await pc.createAnswer();
    return {'type': answer.type, 'sdp': answer.sdp};
  }

  @override
  Future<void> setLocal(Map<String, dynamic> description) async {
    final type = description['type'] as String?;
    await pc.setLocalDescription(
      RTCSessionDescription(description['sdp'] as String?, type),
    );
    _signaling = type == 'offer' ? 'have-local-offer' : 'stable';
  }

  @override
  Future<void> setRemote(Map<String, dynamic> description) async {
    final type = description['type'] as String?;
    await pc.setRemoteDescription(
      RTCSessionDescription(description['sdp'] as String?, type),
    );
    _hasRemote = true;
    _signaling = type == 'offer' ? 'have-remote-offer' : 'stable';
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) => pc.addCandidate(
    RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      (candidate['sdpMLineIndex'] as num?)?.toInt(),
    ),
  );

  @override
  Future<({double incoming, double outgoing})> levels() async {
    double incoming = 0;
    double outgoing = 0;
    for (final report in await pc.getStats()) {
      final values = report.values;
      final level = (values['audioLevel'] as num?)?.toDouble();
      if (level == null) continue;
      final kind = values['kind'] ?? values['mediaType'];
      if (report.type == 'inbound-rtp' && kind == 'audio') {
        incoming = level;
      } else if (report.type == 'media-source' && kind == 'audio') {
        outgoing = level;
      } else if (report.type == 'track') {
        // Older stats: one per track, the remote one marked as such.
        if (values['remoteSource'] == true) {
          incoming = level;
        } else {
          outgoing = level;
        }
      }
    }
    return (incoming: incoming, outgoing: outgoing);
  }

  @override
  Future<void> setHearing(bool on) async {
    _hearing = on;
    for (final receiver in await pc.getReceivers()) {
      final track = receiver.track;
      if (track != null && track.kind == 'audio') track.enabled = on;
    }
  }

  @override
  Future<void> close() async {
    _onState = null;
    await pc.close();
  }
}
