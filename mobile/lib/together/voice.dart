import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media.dart';
import 'parties.dart';
import 'together_account.dart';
import 'together_socket.dart';
import 'voice_mesh.dart';
import 'voice_webrtc.dart';

enum VoiceProblem { microphone, failed }

/// The party's voice in the media server's room, once the call outgrew the mesh: the
/// microphone published (muted as asked), everyone else's voice heard (or nobody's, deafened).
/// [LiveKitVoiceRoom] makes real ones, tests make fakes.
abstract class VoiceRoom {
  Future<void> join(
    SfuAccess access, {
    required bool talking,
    required bool hearing,
  });

  /// Sends the microphone or not (muted).
  set talking(bool on);

  /// Plays the others or nobody (deafened).
  set hearing(bool on);

  /// This phone's microphone is heard right now.
  bool get speaking;

  /// The others in the room, and who of them speaks.
  List<PeerVoice> get peers;

  /// connecting, connected, failed (lost: join again), closed (taken out, or the room closed).
  String get state;
  set onChange(void Function() handler);
  Future<void> leave();
}

/// Voice in the party, the way the website does it: the call from /calls with its ICE servers
/// (renewed from /ice-servers before they run out),
/// the offers and candidates through the gateway, a mesh of peer connections. It lives beside
/// the screens, so the phone stays the pad while the party talks.
///
/// A call that outgrew the mesh (more voices than it holds, on a server with a media server)
/// goes through the media server's room instead: the mesh closed, the room joined, mute and
/// deafen told to the server as before.
class Voice extends ChangeNotifier {
  Voice({
    required this.account,
    required this.socket,
    required this.parties,
    VoiceEngine Function()? engine,
    this.room,
    this.measureEvery = const Duration(milliseconds: 250),
    this.joinAgainAfter = const Duration(seconds: 3),
  }) : _engine = engine ?? WebRtcVoice.new {
    _events = socket.events.listen(_event);
    parties.addListener(_partyChanged);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  final Parties parties;
  final VoiceEngine Function() _engine;

  /// Rooms on the media server; without, the voice stays on the mesh.
  final VoiceRoom Function()? room;
  final Duration measureEvery;
  final Duration joinAgainAfter;
  late final StreamSubscription<TogetherEvent> _events;

  VoiceMesh? _mesh;
  VoiceRoom? _room;
  int _roomTries = 0;
  Timer? _levels;
  Timer? _renew;
  String? callId;
  String? _partyId;
  bool joining = false;
  bool muted = false;

  /// Hears nobody and sends nothing, as Discord's deafen does.
  bool deafened = false;
  VoiceProblem? problem;

  /// The voice went to another of the person's devices (the computer took it back): the client
  /// there, such as "launcher-macos". Cleared when this phone joins again.
  String? movedTo;

  bool get active => _mesh != null || _room != null;

  /// Through the media server rather than the mesh.
  bool get viaServer => _room != null;

  /// This phone's microphone is heard right now.
  bool get speaking =>
      !muted && !deafened && (_room?.speaking ?? _mesh?.speaking ?? false);

  List<PeerVoice> get peers => _room?.peers ?? _mesh?.peers ?? const [];

  bool speakingOf(String userId) =>
      peers.any((peer) => peer.userId == userId && peer.speaking);

  /// Joins the party's voice (starting it if no one talks yet).
  Future<void> join() async {
    final party = parties.party;
    final me = account.user?.id;
    if (party == null || me == null || joining || active) return;
    joining = true;
    problem = null;
    movedTo = null;
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
      if (mediaRouteFrom(call['media']) == MediaRoute.sfu && room != null) {
        // The room has its own microphone.
        await engine.stop();
        callId = id;
        _partyId = party.id;
        if (muted || deafened) _tellMuted(id);
        await _toRoom(id, SfuAccess.fromJson(joined['sfu']));
        return;
      }
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
      _levels = Timer.periodic(measureEvery, (_) => _mesh?.measure());
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

  /// The call moved to the media server (or was there from the start): the mesh closed (a bye
  /// to everyone), the room joined with [access] or a fresh token.
  Future<void> _toRoom(String id, [SfuAccess? access]) async {
    final rooms = room;
    if (rooms == null || _room != null || callId != id) return;
    final mesh = _mesh;
    _mesh = null;
    final joining = rooms();
    _room = joining;
    _roomTries = 0;
    joining.onChange = () {
      if (_room != joining) return;
      switch (joining.state) {
        case 'connected':
          _roomTries = 0;
        case 'failed':
          _roomLost(id, joining);
        case 'closed':
          // Taken out, or the call is over: the server has it already.
          _stop();
      }
      notifyListeners();
    };
    notifyListeners();
    await mesh?.close();
    await _joinRoom(id, joining, access);
  }

  Future<void> _joinRoom(
    String id,
    VoiceRoom joining,
    SfuAccess? access,
  ) async {
    if (access == null || !access.usable) {
      try {
        access = SfuAccess.fromJson(await account.call('GET', 'calls/$id/sfu'));
      } on Object {
        access = null;
      }
    }
    if (_room != joining) return;
    try {
      if (access == null) throw StateError('no room');
      await joining.join(
        access,
        talking: !muted && !deafened,
        hearing: !deafened,
      );
    } on Object {
      if (_room == joining) _roomLost(id, joining);
    }
  }

  /// The room went away: joined again a few times with a fresh token, then out of the call.
  void _roomLost(String id, VoiceRoom lost) {
    if (_room != lost) return;
    if (_roomTries >= 3) {
      problem = VoiceProblem.failed;
      leave();
      return;
    }
    _roomTries++;
    Timer(joinAgainAfter, () {
      if (_room == lost && callId == id) _joinRoom(id, lost, null);
    });
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
      _room?.hearing = true;
    }
    _mesh?.talking = !on && !deafened;
    _room?.talking = !on && !deafened;
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
    _room?.hearing = !on;
    _room?.talking = !on && !muted;
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

  Future<void> _stop({bool sayBye = true}) async {
    final mesh = _mesh;
    final room = _room;
    _mesh = null;
    _room = null;
    callId = null;
    _partyId = null;
    _levels?.cancel();
    _renew?.cancel();
    notifyListeners();
    await mesh?.close(sayBye: sayBye);
    await room?.leave();
  }

  /// Out of the party, out of its voice: the server took this phone out of the call already.
  void _partyChanged() {
    if (!active) return;
    final party = parties.party;
    if (party == null || party.id != _partyId) {
      _stop();
    } else if (party.callMedia == MediaRoute.sfu &&
        party.callId != null &&
        party.callId == callId) {
      _toRoom(callId!).catchError((_) {});
    }
  }

  void _event(TogetherEvent event) {
    final mesh = _mesh;
    final data = event.json;
    if (!active) return;
    switch (event.type) {
      case 'signal' when data['call'] == callId && mesh != null:
        mesh
            .onSignal(
              data['from'] as String,
              data['device'] as String,
              data['kind'] as String,
              data['data'],
            )
            .catchError((_) {});
      case 'call.left' when data['callId'] == callId && mesh != null:
        mesh.drop(data['userId'] as String, sayBye: false).catchError((_) {});
      case 'call.media' when data['callId'] == callId && data['media'] == 'sfu':
        _toRoom(callId!).catchError((_) {});
      case 'call.ended' when data['callId'] == callId:
        _stop();
      // Joined on another device: this phone goes quiet and stays in the party. The other
      // device talks to everyone now, so no one is told goodbye.
      case 'call.moved' when data['callId'] == callId:
        movedTo = data['client'] as String? ?? '';
        _stop(sayBye: false);
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
