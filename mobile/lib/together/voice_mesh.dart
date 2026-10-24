import 'dart:async';

/// One peer connection, as the mesh needs it; [WebRtcVoice] makes real ones, tests make fakes.
/// Descriptions and candidates are JSON as the website's RTCPeerConnection gives them.
abstract class VoiceLink {
  Future<Map<String, dynamic>> createOffer({bool restart = false});
  Future<Map<String, dynamic>> createAnswer();
  Future<void> setLocal(Map<String, dynamic> description);
  Future<void> setRemote(Map<String, dynamic> description);
  Future<void> addCandidate(Map<String, dynamic> candidate);

  /// As the W3C names them: stable, have-local-offer, have-remote-offer.
  String get signalingState;

  /// new, connecting, connected, disconnected, failed, closed.
  String get connectionState;
  bool get hasRemote;

  /// The peer's voice and the microphone as this connection carries them, 0..1.
  Future<({double incoming, double outgoing})> levels();

  set onCandidate(void Function(Map<String, dynamic> candidate) handler);
  set onState(void Function() handler);
  Future<void> close();
}

/// The microphone and the connections to the others.
abstract class VoiceEngine {
  /// Asks for the microphone, with the platform's voice processing; [VoiceDenied] when the
  /// person or the phone says no.
  Future<void> start();
  Future<VoiceLink> link(List<Map<String, dynamic>> iceServers);

  /// Sends the microphone or not (muted).
  void setTalking(bool on);
  Future<void> stop();
}

class VoiceDenied implements Exception {
  const VoiceDenied();
}

/// How one peer is doing, for the members' rings.
class PeerVoice {
  const PeerVoice(this.userId, this.state, this.speaking);

  final String userId;
  final String state;
  final bool speaking;
}

class _Peer {
  _Peer(this.userId, this.device, this.link);

  final String userId;
  final String device;
  final VoiceLink link;
  final queued = <Map<String, dynamic>>[];
  bool makingOffer = false;
  bool speaking = false;
  DateTime quietSince = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Voice in a party as a peer-to-peer mesh, as the website does it: one connection per member,
/// Opus tuned for voice. Whoever joins later makes the offers; if two offer at once, the polite
/// side (the larger user id) gives way; the impolite side restarts ICE when a path fails.
class VoiceMesh {
  VoiceMesh({
    required this.me,
    required this.engine,
    required this.iceServers,
    required this.signal,
    required this.onChange,
  });

  final String me;
  final VoiceEngine engine;
  final List<Map<String, dynamic>> iceServers;
  final bool Function(String to, String device, String kind, Object? data)
  signal;
  final void Function() onChange;

  /// Above this the person is speaking; the ring stays a moment after, so it does not flicker.
  static const speakingLevel = 0.03;
  static const speakingHold = Duration(milliseconds: 400);

  final _peers = <String, _Peer>{};
  Future<void> _queue = Future.value();
  bool _talking = true;
  bool _closed = false;
  bool speaking = false;
  DateTime _quietSince = DateTime.fromMillisecondsSinceEpoch(0);

  List<PeerVoice> get peers => [
    for (final peer in _peers.values)
      PeerVoice(peer.userId, peer.link.connectionState, peer.speaking),
  ];

  bool get talking => _talking;

  set talking(bool on) {
    _talking = on;
    engine.setTalking(on);
    if (!on) speaking = false;
    onChange();
  }

  /// One signal at a time, in the order they came, as a browser would take them.
  Future<void> _serial(Future<void> Function() step) {
    final next = _queue.then((_) => _closed ? null : step());
    _queue = next.catchError((_) {});
    return next;
  }

  /// Calls a member already in the call: this phone is the newcomer, so it offers.
  Future<void> connectTo(String userId, String device) => _serial(() async {
    if (userId == me) return;
    final known = _peers[userId];
    if (known != null &&
        known.device == device &&
        known.link.connectionState != 'failed') {
      return;
    }
    if (known != null) await _drop(userId, sayBye: false);
    await _offer(await _open(userId, device));
  });

  Future<void> onSignal(
    String from,
    String device,
    String kind,
    Object? data,
  ) => _serial(() async {
    var peer = _peers[from];
    if (kind == 'bye') return _drop(from, sayBye: false);
    if (peer != null && peer.device != device && kind == 'offer') {
      await _drop(from, sayBye: false);
      peer = null;
    }
    if (kind == 'offer') {
      peer ??= await _open(from, device);
      final polite = me.compareTo(from) > 0;
      final collision =
          peer.makingOffer || peer.link.signalingState != 'stable';
      if (collision && !polite) return;
      if (collision) await peer.link.setLocal({'type': 'rollback'});
      await peer.link.setRemote(_json(data));
      await _flush(peer);
      final answer = await peer.link.createAnswer();
      final tuned = {
        'type': 'answer',
        'sdp': tuneOpus(answer['sdp'] as String? ?? ''),
      };
      await peer.link.setLocal(tuned);
      _send(peer, 'answer', tuned);
      return;
    }
    if (peer == null || peer.device != device) return;
    if (kind == 'answer' && peer.link.signalingState == 'have-local-offer') {
      await peer.link.setRemote(_json(data));
      await _flush(peer);
    } else if (kind == 'candidate' && data != null) {
      if (peer.link.hasRemote) {
        await peer.link.addCandidate(_json(data)).catchError((_) {});
      } else {
        peer.queued.add(_json(data));
      }
    } else if (kind == 'renegotiate') {
      await _offer(peer, restart: true);
    }
  });

  /// Someone left the call: their connection goes.
  Future<void> drop(String userId, {bool sayBye = true}) =>
      _serial(() => _drop(userId, sayBye: sayBye));

  Future<void> _drop(String userId, {required bool sayBye}) async {
    final peer = _peers.remove(userId);
    if (peer == null) return;
    if (sayBye) _send(peer, 'bye', null);
    await peer.link.close();
    onChange();
  }

  /// Leaves: a bye to everyone, every connection closed, the microphone off.
  Future<void> close() async {
    for (final peer in _peers.values.toList()) {
      _send(peer, 'bye', null);
      await peer.link.close();
    }
    _peers.clear();
    _closed = true;
    await engine.stop();
  }

  /// Levels a few times a second, for the speaking rings.
  Future<void> measure() async {
    final now = DateTime.now();
    var changed = false;
    double outgoing = 0;
    for (final peer in _peers.values.toList()) {
      final ({double incoming, double outgoing}) levels;
      try {
        levels = await peer.link.levels();
      } on Object {
        continue;
      }
      if (levels.outgoing > outgoing) outgoing = levels.outgoing;
      final (talking, quiet) = _step(
        peer.speaking,
        levels.incoming,
        peer.quietSince,
        now,
      );
      changed |= talking != peer.speaking;
      peer.speaking = talking;
      peer.quietSince = quiet;
    }
    final (mine, quiet) = _step(
      speaking,
      _talking ? outgoing : 0,
      _quietSince,
      now,
    );
    changed |= mine != speaking;
    speaking = mine;
    _quietSince = quiet;
    if (changed) onChange();
  }

  static (bool, DateTime) _step(
    bool speaking,
    double level,
    DateTime quietSince,
    DateTime now,
  ) {
    if (level > speakingLevel) return (true, now);
    return (speaking && now.difference(quietSince) < speakingHold, quietSince);
  }

  void _send(_Peer peer, String kind, Object? data) =>
      signal(peer.userId, peer.device, kind, data);

  Future<_Peer> _open(String userId, String device) async {
    final link = await engine.link(iceServers);
    final peer = _Peer(userId, device, link);
    link.onCandidate = (candidate) => _send(peer, 'candidate', candidate);
    link.onState = () {
      // When a path breaks, the impolite side restarts ICE (through the relay if it must).
      if (link.connectionState == 'failed' &&
          me.compareTo(userId) < 0 &&
          _peers[userId] == peer) {
        _serial(() => _offer(peer, restart: true));
      }
      onChange();
    };
    _peers[userId] = peer;
    onChange();
    return peer;
  }

  Future<void> _offer(_Peer peer, {bool restart = false}) async {
    try {
      peer.makingOffer = true;
      final offer = await peer.link.createOffer(restart: restart);
      if (peer.link.signalingState != 'stable') return;
      final tuned = {
        'type': 'offer',
        'sdp': tuneOpus(offer['sdp'] as String? ?? ''),
      };
      await peer.link.setLocal(tuned);
      _send(peer, 'offer', tuned);
    } finally {
      peer.makingOffer = false;
    }
  }

  Future<void> _flush(_Peer peer) async {
    final queued = [...peer.queued];
    peer.queued.clear();
    for (final candidate in queued) {
      await peer.link.addCandidate(candidate).catchError((_) {});
    }
  }

  static Map<String, dynamic> _json(Object? data) =>
      data is Map ? Map<String, dynamic>.from(data) : const {};
}

/// Opus for voice: mono, in-band FEC (rides out about 10 % loss), DTX (silence costs almost
/// nothing), at most 32 kbit/s; the website's tuning, line for line.
String tuneOpus(String sdp) {
  final match = RegExp(
    r'a=rtpmap:(\d+) opus/48000/2',
    caseSensitive: false,
  ).firstMatch(sdp);
  if (match == null) return sdp;
  final payload = match.group(1)!;
  const wanted = {
    'useinbandfec': '1',
    'usedtx': '1',
    'stereo': '0',
    'maxaveragebitrate': '32000',
  };
  final fmtp = RegExp('a=fmtp:$payload ([^\\r\\n]*)');
  final existing = fmtp.firstMatch(sdp);
  if (existing == null) {
    final params = wanted.entries.map((e) => '${e.key}=${e.value}').join(';');
    return sdp.replaceFirst(
      match.group(0)!,
      '${match.group(0)}\r\na=fmtp:$payload $params',
    );
  }
  final params = <String, String>{};
  for (final pair in existing.group(1)!.split(';')) {
    if (pair.isEmpty) continue;
    final at = pair.indexOf('=');
    if (at < 0) {
      params[pair] = '';
    } else {
      params[pair.substring(0, at)] = pair.substring(at + 1);
    }
  }
  params.addAll(wanted);
  return sdp.replaceFirst(
    fmtp,
    'a=fmtp:$payload ${params.entries.map((e) => '${e.key}=${e.value}').join(';')}',
  );
}
