import 'dart:async';

import 'package:flutter/foundation.dart';

import 'people.dart';
import 'together_account.dart';
import 'together_socket.dart';
import 'voice.dart';
import 'voice_mesh.dart';
import 'voice_webrtc.dart';

enum CallPhase { calling, connecting, live, ended }

/// Why a call is over, for the words shown a moment after.
enum CallEnd { ended, declined, noAnswer, elsewhere, failed, microphone }

/// The one call between two friends this phone is in, from ringing to a moment after it ends.
class ActiveCall {
  const ActiveCall({
    required this.id,
    required this.peer,
    required this.outgoing,
    required this.phase,
    this.since,
    this.ended,
    this.peerMuted = false,
  });

  /// null while the API is still being asked.
  final String? id;
  final Person peer;
  final bool outgoing;
  final CallPhase phase;

  /// When the voice started flowing.
  final DateTime? since;
  final CallEnd? ended;
  final bool peerMuted;

  ActiveCall copyWith({
    String? id,
    CallPhase? phase,
    DateTime? since,
    CallEnd? ended,
    bool? peerMuted,
  }) => ActiveCall(
    id: id ?? this.id,
    peer: peer,
    outgoing: outgoing,
    phase: phase ?? this.phase,
    since: since ?? this.since,
    ended: ended ?? this.ended,
    peerMuted: peerMuted ?? this.peerMuted,
  );
}

/// A friend calling this phone.
class IncomingCall {
  const IncomingCall(this.callId, this.from);

  final String callId;
  final Person from;
}

/// Calls between friends on the phone, the way the website does them: ringing on every device
/// of the person called until one answers, the one who answers offering to the caller's device,
/// mute told to the other side, and the voice over the party's peer-to-peer mesh. One voice at
/// a time: a call leaves the party's voice, and joining the party's voice ends the call.
class Calls extends ChangeNotifier {
  Calls({
    required this.account,
    required this.socket,
    this.partyVoice,
    VoiceEngine Function()? engine,
    this.noAnswerAfter = const Duration(seconds: 45),
    this.endedShown = const Duration(milliseconds: 2600),
    this.measureEvery = const Duration(milliseconds: 250),
  }) : _engine = engine ?? WebRtcVoice.new {
    _events = socket.events.listen(_event);
    partyVoice?.addListener(_partyVoiceChanged);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  final Voice? partyVoice;
  final VoiceEngine Function() _engine;
  final Duration noAnswerAfter;
  final Duration endedShown;
  final Duration measureEvery;
  late final StreamSubscription<TogetherEvent> _events;

  ActiveCall? active;
  List<IncomingCall> incoming = const [];
  bool muted = false;

  /// An answer is on its way.
  bool busy = false;

  VoiceMesh? _mesh;
  VoiceEngine? _starting;
  Timer? _noAnswer;
  Timer? _clearEnded;
  Timer? _levels;
  Timer? _renew;

  /// Bumped whenever a call is over, so a ring still waiting on the API knows it was given up.
  int _attempt = 0;

  String? get _me => account.user?.id;

  /// A call is going on (not just shown as ended).
  bool get inCall => active != null && active!.phase != CallPhase.ended;

  /// This phone's microphone is heard right now.
  bool get speaking => !muted && (_mesh?.speaking ?? false);

  bool get peerSpeaking {
    final peer = active?.peer.id;
    return _mesh?.peers.any((p) => p.userId == peer && p.speaking) ?? false;
  }

  void _show(ActiveCall? call) {
    active = call;
    notifyListeners();
  }

  /// Calls a friend, unless a call is going on already.
  Future<void> ring(Person friend) async {
    if (inCall || _me == null) return;
    _clearEnded?.cancel();
    final mine = ++_attempt;
    _show(
      ActiveCall(
        id: null,
        peer: friend,
        outgoing: true,
        phase: CallPhase.calling,
      ),
    );
    await partyVoice?.leave();
    final engine = _engine();
    _starting = engine;
    try {
      await engine.start();
    } on Object {
      _starting = null;
      if (mine == _attempt) _finish(CallEnd.microphone, tell: false);
      return;
    }
    try {
      final joined = await account.call('POST', 'calls', {'userId': friend.id});
      final call = joined['call'] as Map<String, dynamic>;
      final id = call['id'] as String;
      _starting = null;
      if (mine != _attempt) {
        // Hung up while the API was asked: leave what it made.
        await engine.stop();
        account
            .call('POST', 'calls/$id/leave')
            .catchError((_) => <String, dynamic>{});
        return;
      }
      _startVoice(id, engine, joined);
      _show(active!.copyWith(id: id));
      _noAnswer = Timer(noAnswerAfter, () {
        if (active?.id == id && active?.phase == CallPhase.calling) {
          _finish(CallEnd.noAnswer, tell: true);
        }
      });
    } on Object {
      _starting = null;
      await engine.stop();
      if (mine == _attempt) _finish(CallEnd.failed, tell: false);
    }
  }

  /// Answers on this phone: the other devices stop ringing, and this one offers to the caller.
  Future<void> accept(IncomingCall call) async {
    if (busy) return;
    busy = true;
    if (inCall) _finish(CallEnd.ended, tell: true);
    _clearEnded?.cancel();
    final mine = ++_attempt;
    notifyListeners();
    await partyVoice?.leave();
    final engine = _engine();
    try {
      await engine.start();
    } on Object {
      _drop(call.callId);
      _show(_answered(call));
      _finish(CallEnd.microphone, tell: false);
      account
          .call('POST', 'calls/${call.callId}/decline')
          .catchError((_) => <String, dynamic>{});
      busy = false;
      notifyListeners();
      return;
    }
    try {
      final answered = await account.call(
        'POST',
        'calls/${call.callId}/answer',
      );
      _drop(call.callId);
      if (mine != _attempt) {
        await engine.stop();
        return;
      }
      final view = answered['call'] as Map<String, dynamic>;
      final caller = (view['in'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((peer) => peer['userId'] == call.from.id)
          .firstOrNull;
      _show(_answered(call, peerMuted: caller?['muted'] == true));
      final mesh = _startVoice(call.callId, engine, answered);
      // The one who answers last makes the offer.
      if (caller != null) {
        mesh
            .connectTo(caller['userId'] as String, caller['device'] as String)
            .catchError((_) {});
      }
    } on TogetherProblem catch (problem) {
      await engine.stop();
      _drop(call.callId);
      _show(_answered(call));
      _finish(
        problem.status == 409 ? CallEnd.elsewhere : CallEnd.failed,
        tell: false,
      );
    } on Object {
      await engine.stop();
      _drop(call.callId);
      _show(_answered(call));
      _finish(CallEnd.failed, tell: true);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  ActiveCall _answered(IncomingCall call, {bool peerMuted = false}) =>
      ActiveCall(
        id: call.callId,
        peer: call.from,
        outgoing: false,
        phase: CallPhase.connecting,
        peerMuted: peerMuted,
      );

  Future<void> decline(IncomingCall call) async {
    _drop(call.callId);
    notifyListeners();
    try {
      await account.call('POST', 'calls/${call.callId}/decline');
    } on Object {
      // It stops ringing here either way; the caller gives up after a while.
    }
  }

  /// Ends the call (or stops calling).
  void hangUp() {
    if (active != null && active!.phase != CallPhase.ended) {
      _finish(CallEnd.ended, tell: true);
    }
  }

  /// Muted or not; the other side is told, and sees it.
  void setMuted(bool on) {
    muted = on;
    _mesh?.talking = !on;
    notifyListeners();
    final id = active?.id;
    if (id != null && inCall) {
      account
          .call('POST', 'calls/$id/mute', {'muted': on})
          .catchError((_) => <String, dynamic>{});
    }
  }

  VoiceMesh _startVoice(
    String id,
    VoiceEngine engine,
    Map<String, dynamic> joined,
  ) {
    final mesh = VoiceMesh(
      me: _me ?? '',
      engine: engine,
      iceServers: _ice(joined['iceServers']),
      signal: (to, device, kind, data) => socket.send({
        'op': 'signal',
        'to': to,
        'device': device,
        'call': id,
        'kind': kind,
        'data': data,
      }),
      onChange: _meshChanged,
    )..talking = !muted;
    _mesh = mesh;
    _levels?.cancel();
    _levels = Timer.periodic(measureEvery, (_) => mesh.measure());
    _renewBefore(joined['expiresAt']);
    return mesh;
  }

  static List<Map<String, dynamic>> _ice(Object? list) => [
    for (final server in (list as List? ?? const []))
      Map<String, dynamic>.from(server as Map),
  ];

  /// Fresh relay credentials ten minutes before these run out.
  void _renewBefore(Object? expiresAt) {
    final expiry = DateTime.tryParse(expiresAt as String? ?? '');
    _renew?.cancel();
    if (expiry == null) return;
    final wait =
        expiry.difference(DateTime.now()) - const Duration(minutes: 10);
    _renew = Timer(wait.isNegative ? Duration.zero : wait, () async {
      try {
        final fresh = await account.call('GET', 'ice-servers');
        _mesh?.iceServers = _ice(fresh['iceServers']);
        if (_mesh != null) _renewBefore(fresh['expiresAt']);
      } on Object {
        // The ones held still work until they expire.
      }
    });
  }

  /// The voice is flowing: the call is live from now.
  void _meshChanged() {
    final call = active;
    if (call != null &&
        call.phase == CallPhase.connecting &&
        (_mesh?.peers.any((p) => p.state == 'connected') ?? false)) {
      active = call.copyWith(phase: CallPhase.live, since: DateTime.now());
    }
    notifyListeners();
  }

  void _finish(CallEnd reason, {required bool tell}) {
    _attempt++;
    final call = active;
    final mesh = _mesh;
    _mesh = null;
    _starting?.stop().catchError((_) {});
    _starting = null;
    _levels?.cancel();
    _renew?.cancel();
    _noAnswer?.cancel();
    muted = false;
    mesh?.close().catchError((_) {});
    if (tell && call?.id != null) {
      account
          .call('POST', 'calls/${call!.id}/leave')
          .catchError((_) => <String, dynamic>{});
    }
    if (call == null) {
      notifyListeners();
      return;
    }
    _show(call.copyWith(phase: CallPhase.ended, ended: reason));
    _clearEnded?.cancel();
    _clearEnded = Timer(endedShown, () {
      if (active?.phase == CallPhase.ended) _show(null);
    });
  }

  void _drop(String callId) =>
      incoming = incoming.where((i) => i.callId != callId).toList();

  /// Joining the party's voice ends a call: one voice at a time.
  void _partyVoiceChanged() {
    if ((partyVoice?.active ?? false) && inCall) {
      _finish(CallEnd.ended, tell: true);
    }
  }

  /// Shows a call or a ring without the server, for tests of the screens.
  @visibleForTesting
  void debugShow({ActiveCall? active, List<IncomingCall>? incoming}) {
    if (active != null) this.active = active;
    if (incoming != null) this.incoming = incoming;
    notifyListeners();
  }

  /// Signed out, or another account: everything goes, the server is not told.
  void clear() {
    if (inCall) _finish(CallEnd.ended, tell: false);
    _clearEnded?.cancel();
    active = null;
    incoming = const [];
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    final call = active;
    switch (event.type) {
      case 'call.ringing':
        final from = data['from'];
        final id = data['callId'];
        if (from is! Map<String, dynamic> || id is! String) return;
        final person = Person.fromJson(from);
        if (person.id == _me || incoming.any((i) => i.callId == id)) return;
        incoming = [...incoming, IncomingCall(id, person)];
        notifyListeners();
      case 'call.answered':
        // Answered here or on another device: this one stops ringing.
        _drop(data['callId'] as String? ?? '');
        if (call != null &&
            call.id == data['callId'] &&
            call.outgoing &&
            call.phase == CallPhase.calling) {
          _noAnswer?.cancel();
          active = call.copyWith(phase: CallPhase.connecting);
        }
        notifyListeners();
      case 'call.ended':
        _drop(data['callId'] as String? ?? '');
        if (call != null &&
            call.id == data['callId'] &&
            call.phase != CallPhase.ended) {
          _finish(
            data['reason'] == 'declined' ? CallEnd.declined : CallEnd.ended,
            tell: false,
          );
        } else {
          notifyListeners();
        }
      case 'call.updated'
          when call != null &&
              call.id == data['callId'] &&
              data['userId'] != _me:
        _show(call.copyWith(peerMuted: data['muted'] == true));
      case 'signal' when call?.id != null && data['call'] == call?.id:
        _mesh
            ?.onSignal(
              data['from'] as String,
              data['device'] as String,
              data['kind'] as String,
              data['data'],
            )
            .catchError((_) {});
      case 'live.ready':
        _catchUp();
    }
  }

  /// Back after the socket was away: calls that ended meanwhile are forgotten.
  void _catchUp() {
    final call = active;
    if (call?.id != null && call!.phase != CallPhase.ended) {
      account.call('GET', 'calls/${call.id}').catchError((Object error) {
        if (error is TogetherProblem &&
            error.status == 404 &&
            active?.id == call.id) {
          _finish(CallEnd.ended, tell: false);
        }
        return <String, dynamic>{};
      });
    }
    for (final ring in incoming) {
      account
          .call('GET', 'calls/${ring.callId}')
          .then((json) {
            if (json['answeredAt'] != null || json['endedAt'] != null) {
              _drop(ring.callId);
              notifyListeners();
            }
          })
          .catchError((Object error) {
            if (error is TogetherProblem && error.status == 404) {
              _drop(ring.callId);
              notifyListeners();
            }
          });
    }
  }

  @override
  void dispose() {
    _events.cancel();
    partyVoice?.removeListener(_partyVoiceChanged);
    _attempt++;
    _levels?.cancel();
    _renew?.cancel();
    _noAnswer?.cancel();
    _clearEnded?.cancel();
    _mesh?.close().catchError((_) {});
    _starting?.stop().catchError((_) {});
    super.dispose();
  }
}
