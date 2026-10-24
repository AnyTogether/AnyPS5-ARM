import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../stream/platform_player.dart';
import '../stream/stream_packets.dart';
import 'share_play.dart';

/// Share play's connections with flutter_webrtc: receive-only, the host's picture drawn by an
/// RTCVideoRenderer, its channels handed on as they open.
class WebRtcShareEngine implements ShareEngine {
  @override
  Future<ShareLink> link(List<Map<String, dynamic>> iceServers) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    return _Link(pc, renderer);
  }
}

class _Channel implements ShareChannel {
  _Channel(this.channel) {
    channel.onMessage = (message) {
      if (message.isBinary) _onMessage?.call(message.binary);
    };
  }

  final RTCDataChannel channel;
  void Function(Uint8List)? _onMessage;

  @override
  String get label => channel.label ?? '';

  @override
  bool get open => channel.state == RTCDataChannelState.RTCDataChannelOpen;

  @override
  void send(Uint8List bytes) {
    channel.send(RTCDataChannelMessage.fromBinary(bytes)).catchError((_) {});
  }

  @override
  set onMessage(void Function(Uint8List bytes) handler) => _onMessage = handler;

  @override
  void close() => channel.close();
}

class _Link implements ShareLink {
  _Link(this.pc, this.renderer) {
    pc.onConnectionState = (_) => _onState?.call();
    pc.onTrack = (event) {
      if (event.track.kind != 'video') return;
      final stream = event.streams.isNotEmpty ? event.streams.first : null;
      if (stream != null) {
        renderer.srcObject = stream;
        _picture.value = true;
      }
    };
    pc.onDataChannel = (channel) => _onChannel?.call(_Channel(channel));
  }

  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer;
  final _picture = ValueNotifier(false);
  void Function()? _onState;
  void Function(ShareChannel)? _onChannel;
  String _signaling = 'stable';
  bool _hasRemote = false;
  int? _bytes;
  DateTime? _bytesAt;

  @override
  set onCandidate(void Function(Map<String, dynamic>) handler) =>
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate != null) handler(candidate.toMap());
      };

  @override
  set onState(void Function() handler) => _onState = handler;

  @override
  set onChannel(void Function(ShareChannel) handler) => _onChannel = handler;

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
  Future<void> setRemote(Map<String, dynamic> description) async {
    await pc.setRemoteDescription(
      RTCSessionDescription(
        description['sdp'] as String?,
        description['type'] as String?,
      ),
    );
    _hasRemote = true;
    _signaling = 'have-remote-offer';
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await pc.createAnswer();
    return {'type': answer.type, 'sdp': answer.sdp};
  }

  @override
  Future<void> setLocal(Map<String, dynamic> description) async {
    await pc.setLocalDescription(
      RTCSessionDescription(
        description['sdp'] as String?,
        description['type'] as String?,
      ),
    );
    _signaling = 'stable';
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
  Widget video() => ValueListenableBuilder<bool>(
    valueListenable: _picture,
    builder: (context, shown, _) =>
        shown ? RTCVideoView(renderer) : const SizedBox.expand(),
  );

  @override
  Future<ShareQuality> quality() async {
    double? rtt;
    double? fps;
    double? kbps;
    double? lost;
    int? height;
    for (final report in await pc.getStats()) {
      final values = report.values;
      if (report.type == 'candidate-pair' &&
          (values['nominated'] == true || values['state'] == 'succeeded')) {
        final seconds = (values['currentRoundTripTime'] as num?)?.toDouble();
        if (seconds != null) rtt = seconds * 1000;
      } else if (report.type == 'inbound-rtp' &&
          (values['kind'] ?? values['mediaType']) == 'video') {
        fps = (values['framesPerSecond'] as num?)?.toDouble();
        height = (values['frameHeight'] as num?)?.toInt();
        final received = (values['packetsReceived'] as num?)?.toDouble() ?? 0;
        final missing = (values['packetsLost'] as num?)?.toDouble() ?? 0;
        if (received + missing > 0) {
          lost = missing / (received + missing) * 100;
        }
        final bytes = (values['bytesReceived'] as num?)?.toInt();
        final now = DateTime.now();
        if (bytes != null && _bytes != null && _bytesAt != null) {
          final seconds = now.difference(_bytesAt!).inMilliseconds / 1000;
          if (seconds > 0) kbps = (bytes - _bytes!) * 8 / 1000 / seconds;
        }
        _bytes = bytes;
        _bytesAt = now;
      }
    }
    return ShareQuality(
      roundTripMs: rtt,
      framesPerSecond: fps,
      kilobitsPerSecond: kbps,
      lostPercent: lost,
      height: height,
    );
  }

  @override
  Future<void> close() async {
    _onState = null;
    _onChannel = null;
    renderer.srcObject = null;
    await pc.close();
    await renderer.dispose();
  }
}

/// The game's sound on Remote Play's speaker, gathered 20 ms at a time as Remote Play does.
class PlatformShareSound implements ShareSound {
  final _sound = BytesBuilder(copy: false);
  int _packets = 0;
  bool _playing = false;

  MethodChannel get _channel => PlatformStreamPlayer.channel;

  @override
  void sound(AudioPacket packet) {
    _sound.add(packet.samples);
    _playing = true;
    if (++_packets < 4) return;
    _packets = 0;
    _channel.invokeMethod('sound', {'data': _sound.takeBytes()});
  }

  @override
  void stop() {
    _sound.clear();
    _packets = 0;
    if (!_playing) return;
    _playing = false;
    _channel.invokeMethod('close');
  }
}
