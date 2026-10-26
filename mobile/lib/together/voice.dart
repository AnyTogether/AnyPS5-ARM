import 'dart:async';

import 'package:flutter/foundation.dart';

import 'parties.dart';
import 'together_account.dart';
import 'together_socket.dart';
import 'voice_mesh.dart';
import 'voice_webrtc.dart';

enum VoiceProblem { microphone, failed }

/// Voice in the party, the way the website does it: the call from /calls with its ICE servers
/// (renewed from /ice-servers before they run out),
/// the offers and candidates through the gateway, a mesh of peer connections. It lives beside
/// the screens, so the phone stays the pad while the party talks.
class Voice extends ChangeNotifier {
  Voice({
    required this.account,
    required this.socket,
    required this.parties,
    VoiceEngine Function()? engine,
    this.measureEvery = const Duration(milliseconds: 250),
  }) : _engine = engine ?? WebRtcVoice.new {
    _events = socket.events.listen(_event);
    parties.addListener(_partyChanged);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  final Parties parties;
  final VoiceEngine Function() _engine;
  final Duration measureEvery;
  late final StreamSubscription<TogetherEvent> _events;

  VoiceMesh? _mesh;
  Timer? _levels;
  Timer? _renew;
  String? callId;
  String? _partyId;
  bool joining = false;
  bool muted = false;

  /// Hears nobody and sends nothing, as Discord's deafen does.
  bool deafened = false;
  VoiceProblem? problem;

  bool get active => _mesh != null;

  /// This phone's microphone is heard right now.
  bool get speaking => !muted && !deafened && (_mesh?.speaking ?? false);

  List<PeerVoice> get peers => _mesh?.peers ?? const [];

  bool speakingOf(String userId) =>
      peers.any((peer) => peer.userId == userId && peer.speaking);

  /// Joins the party's voice (starting it if no one talks yet).
  Future<void> join() async {
    final party = parties.party;
    final me = account.user?.id;
    if (party == null || me == null || joining || active) return;
    joining = true;
    problem = null;
    notifyListeners();
    final engine = _engine();
    try {
      await engine.start();
    } on Object {
      problem = VoiceProblem.microphone;
      joining = false;
      notifyListeners();
      return;
    }
    try {
      final joined = await account.call('POST', 'calls', {'partyId': party.id});
      final call = joined['call'] as Map<String, dynamic>;
      final id = call['id'] as String;
      final mesh = VoiceMesh(
        me: me,
        engine: engine,
        iceServers: [
          for (final server in (joined['iceServers'] as List? ?? const []))
            Map<String, dynamic>.from(server as Map),
        ],
        signal: (to, device, kind, data) => socket.send({
          'op': 'signal',
          'to': to,
          'device': device,
          'call': id,
          'kind': kind,
          'data': data,
        }),
        onChange: notifyListeners,
      )..talking = !muted && !deafened;
      if (deafened) mesh.hearing = false;
      _mesh = mesh;
      callId = id;
      _partyId = party.id;
      _levels = Timer.periodic(measureEvery, (_) => mesh.measure());
      _renewBefore(joined['expiresAt']);
      // Muted before joining: the others see it from the start.
      if (muted || deafened) _tellMuted(id);
      // The newcomer calls everyone already in.
      for (final peer in (call['in'] as List? ?? const [])) {
        final userId = (peer as Map)['userId'] as String;
        if (userId != me) {
          mesh.connectTo(userId, peer['device'] as String).catchError((_) {});
        }
      }
    } on Object {
      await engine.stop();
      problem = VoiceProblem.failed;
    } finally {
      joining = false;
      notifyListeners();
    }
  }

  /// Out of the voice; the server is told unless it already knows (the party or call ended).
  Future<void> leave({bool tell = true}) async {
    final id = callId;
    await _stop();
    if (tell && id != null) {
      try {
        await account.call('POST', 'calls/$id/leave');
      } on Object {
        // The call ends for the others when this phone stops answering.
      }
    }
  }

  /// Fresh relay credentials ten minutes before these run out (a call can outlast them).
  void _renewBefore(Object? expiresAt) {
    final expiry = DateTime.tryParse(expiresAt as String? ?? '');
    _renew?.cancel();
    if (expiry == null) return;
    final wait =
        expiry.difference(DateTime.now()) - const Duration(minutes: 10);
    _renew = Timer(wait.isNegative ? Duration.zero : wait, () async {
      try {
        final fresh = await account.call('GET', 'ice-servers');
        _mesh?.iceServers = [
          for (final server in (fresh['iceServers'] as List? ?? const []))
            Map<String, dynamic>.from(server as Map),
        ];
        if (_mesh != null) _renewBefore(fresh['expiresAt']);
      } on Object {
        // The ones held still work until they expire.
      }
    });
  }

  /// Muted or not; the others in the call are told, and see it on the party. Unmuting while
  /// deafened undeafens too.
  void setMuted(bool on) {
    muted = on;
    if (!on && deafened) {
      deafened = false;
      _mesh?.hearing = true;
    }
    _mesh?.talking = !on && !deafened;
    notifyListeners();
    final id = callId;
    if (id != null) _tellMuted(id);
  }

  /// Deafened or not: nobody heard and the microphone off; undeafening gives the microphone back
  /// as it was before.
  void setDeafened(bool on) {
    deafened = on;
    _mesh?.hearing = !on;
    _mesh?.talking = !on && !muted;
    notifyListeners();
    final id = callId;
    if (id != null) _tellMuted(id);
  }

  void _tellMuted(String id) => account
      .call('POST', 'calls/$id/mute', {
        'muted': muted || deafened,
        'deafened': deafened,
      })
      .catchError((_) => <String, dynamic>{});

  Future<void> _stop() async {
    final mesh = _mesh;
    _mesh = null;
    callId = null;
    _partyId = null;
    _levels?.cancel();
    _renew?.cancel();
    notifyListeners();
    await mesh?.close();
  }

  /// Out of the party, out of its voice: the server took this phone out of the call already.
  void _partyChanged() {
    if (!active) return;
    final party = parties.party;
    if (party == null || party.id != _partyId) _stop();
  }

  void _event(TogetherEvent event) {
    final mesh = _mesh;
    final data = event.json;
    if (mesh == null) return;
    switch (event.type) {
      case 'signal' when data['call'] == callId:
        mesh
            .onSignal(
              data['from'] as String,
              data['device'] as String,
              data['kind'] as String,
              data['data'],
            )
            .catchError((_) {});
      case 'call.left' when data['callId'] == callId:
        mesh.drop(data['userId'] as String, sayBye: false).catchError((_) {});
      case 'call.ended' when data['callId'] == callId:
        _stop();
    }
  }

  @override
  void dispose() {
    _events.cancel();
    parties.removeListener(_partyChanged);
    _stop();
    super.dispose();
  }
}
