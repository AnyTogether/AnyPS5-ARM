import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../protocol/packets.dart';
import '../stream/stream_packets.dart';
import 'people.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// A data channel the host opened: "pad" (this phone's pad up, the game's rumble and light
/// down) or "audio" (the game's sound down). Binary, unordered, never resent.
abstract class ShareChannel {
  String get label;
  bool get open;
  void send(Uint8List bytes);
  set onMessage(void Function(Uint8List bytes) handler);
  void close();
}

/// How the picture comes: frames per second, the round trip, what the network lost.
class ShareQuality {
  const ShareQuality({
    this.roundTripMs,
    this.framesPerSecond,
    this.kilobitsPerSecond,
    this.lostPercent,
    this.height,
  });

  final double? roundTripMs;
  final double? framesPerSecond;
  final double? kilobitsPerSecond;
  final double? lostPercent;
  final int? height;

  /// Good, fair or poor, from the round trip and the losses.
  int get bars {
    final rtt = roundTripMs ?? 0;
    final lost = lostPercent ?? 0;
    if (rtt > 180 || lost > 5) return 1;
    if (rtt > 90 || lost > 1.5) return 2;
    return 3;
  }
}

/// One receive-only connection to the host, as the watcher needs it; [WebRtcShareEngine] makes
/// real ones, tests make fakes. Descriptions and candidates are the browser's JSON shapes.
abstract class ShareLink {
  Future<void> setRemote(Map<String, dynamic> description);
  Future<Map<String, dynamic>> createAnswer();
  Future<void> setLocal(Map<String, dynamic> description);
  Future<void> addCandidate(Map<String, dynamic> candidate);

  /// stable, have-remote-offer.
  String get signalingState;

  /// new, connecting, connected, disconnected, failed, closed.
  String get connectionState;
  bool get hasRemote;

  set onCandidate(void Function(Map<String, dynamic> candidate) handler);
  set onState(void Function() handler);
  set onChannel(void Function(ShareChannel channel) handler);

  /// The picture, drawn as large as fits.
  Widget video();
  Future<ShareQuality> quality();
  Future<void> close();
}

abstract class ShareEngine {
  Future<ShareLink> link(List<Map<String, dynamic>> iceServers);
}

/// Where the game's sound goes: the speaker Remote Play uses.
abstract class ShareSound {
  void sound(AudioPacket packet);
  void stop();
}

/// Someone watching, and the pad the host gave them (2-4), or none.
class ShareViewer {
  const ShareViewer(this.person, this.device, this.slot);

  factory ShareViewer.fromJson(Map<String, dynamic> json) => ShareViewer(
    Person.fromJson(json['user'] as Map<String, dynamic>),
    json['device'] as String? ?? '',
    (json['slot'] as num?)?.toInt(),
  );

  final Person person;
  final String device;
  final int? slot;
}

/// A friend's share play as the server shows it.
class SharePlayView {
  const SharePlayView({
    required this.id,
    required this.host,
    required this.hostDevice,
    required this.titleId,
    this.title,
    this.open = true,
    this.maxViewers = 2,
    this.viewers = const [],
  });

  factory SharePlayView.fromJson(Map<String, dynamic> json) => SharePlayView(
    id: json['id'] as String,
    host: json['host'] is Map<String, dynamic>
        ? Person.fromJson(json['host'] as Map<String, dynamic>)
        : null,
    hostDevice: json['hostDevice'] as String? ?? '',
    titleId: json['titleId'] as String? ?? '',
    title: json['title'] as String?,
    open: json['open'] != false,
    maxViewers: (json['maxViewers'] as num?)?.toInt() ?? 2,
    viewers: [
      for (final viewer in (json['viewers'] as List? ?? const []))
        ShareViewer.fromJson(viewer as Map<String, dynamic>),
    ],
  );

  final String id;
  final Person? host;
  final String hostDevice;
  final String titleId;
  final String? title;
  final bool open;
  final int maxViewers;
  final List<ShareViewer> viewers;

  String get name => title ?? titleId;

  /// The pad [userId] plays with, or null while they only watch.
  int? slotOf(String? userId) =>
      viewers.where((viewer) => viewer.person.id == userId).firstOrNull?.slot;
}

/// A friend asking this phone to watch.
class ShareInvite {
  const ShareInvite(this.sharePlayId, this.from, this.titleId, this.title);

  factory ShareInvite.fromJson(Map<String, dynamic> json) => ShareInvite(
    json['sharePlayId'] as String,
    json['from'] is Map<String, dynamic>
        ? Person.fromJson(json['from'] as Map<String, dynamic>)
        : null,
    json['titleId'] as String? ?? '',
    json['title'] as String?,
  );

  final String sharePlayId;
  final Person? from;
  final String titleId;
  final String? title;

  String get name => title ?? titleId;
}

enum WatchStatus { joining, connecting, watching, ended }

enum WatchEnd { stopped, removed, full, failed, left }

/// Watching a friend's share play on the phone: joined through the API (which gives the relay
/// credentials, renewed before they run out), the host's offer answered through the gateway, the
/// picture on a receive-only connection, the game's sound on the "audio" channel to Remote
/// Play's speaker, and, while the host lets this phone play, the pad on the "pad" channel: at
/// once on a change and 120 times a second besides.
class SharePlays extends ChangeNotifier {
  SharePlays({
    required this.account,
    required this.socket,
    required this.engine,
    required this.sound,
    this.padEvery = const Duration(microseconds: 8333),
    this.askAgainAfter = const Duration(seconds: 5),
    this.measureEvery = const Duration(seconds: 1),
    Random? random,
  }) : _random = random ?? Random.secure() {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  final ShareEngine Function() engine;
  final ShareSound Function() sound;
  final Duration padEvery;
  final Duration askAgainAfter;
  final Duration measureEvery;
  final Random _random;
  late final StreamSubscription<TogetherEvent> _events;

  List<ShareInvite> invites = const [];

  /// The share play this phone watches, while it does.
  SharePlayView? watching;
  WatchStatus status = WatchStatus.ended;
  WatchEnd? ended;
  ShareQuality quality = const ShareQuality();

  /// The game's last answer on the pad channel: rumble and light bar.
  Output? output;
  double? latencyMs;

  /// Told each answer from the game, for the phone's vibration.
  void Function(Output output, PadState state)? onOutput;

  ShareEngine? _engineNow;
  ShareSound? _soundNow;
  ShareLink? _link;
  ShareChannel? _pad;
  final _queued = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _ice = const [];
  Future<void> _queue = Future.value();
  Timer? _padTimer;
  Timer? _askTimer;
  Timer? _renewTimer;
  Timer? _measureTimer;
  final _clock = Stopwatch()..start();
  BigInt _session = BigInt.zero;
  int _sequence = 0;
  PadState _state = PadState();
  String? _hostDevice;
  int _generation = 0;

  String? get me => account.user?.id;

  /// The pad the host gave this phone (2-4), or null while it only watches.
  int? get slot => watching?.slotOf(me);

  /// The host's picture, once the connection is made.
  Widget? video() => _link?.video();

  /// Invites and, for a socket that reconnected, the share play still being watched.
  Future<void> refresh() async {
    final mine = await account.call('GET', 'me/share-play');
    invites = [
      for (final invite in (mine['invites'] as List? ?? const []))
        ShareInvite.fromJson(invite as Map<String, dynamic>),
    ];
    final watched = mine['watching'];
    if (watching != null && watched is Map<String, dynamic>) {
      _take(SharePlayView.fromJson(watched));
    }
    notifyListeners();
  }

  /// Watches a friend's share play on this phone; the host then calls it.
  Future<void> watch(String sharePlayId) async {
    if (watching?.id == sharePlayId && status != WatchStatus.ended) return;
    await _close(tell: true);
    final generation = ++_generation;
    status = WatchStatus.joining;
    ended = null;
    output = null;
    latencyMs = null;
    quality = const ShareQuality();
    invites = invites.where((i) => i.sharePlayId != sharePlayId).toList();
    notifyListeners();
    final Map<String, dynamic> joined;
    try {
      joined = await account.call('POST', 'share-plays/$sharePlayId/join');
    } on TogetherProblem catch (problem) {
      if (generation != _generation) return;
      status = WatchStatus.ended;
      ended = problem.code == 'full' ? WatchEnd.full : WatchEnd.failed;
      notifyListeners();
      rethrow;
    }
    if (generation != _generation) return;
    watching = SharePlayView.fromJson(
      joined['sharePlay'] as Map<String, dynamic>,
    );
    _hostDevice = watching!.hostDevice;
    _ice = _servers(joined['iceServers']);
    _renewBefore(joined['expiresAt']);
    _session =
        BigInt.from(_random.nextInt(1 << 32)) << 32 |
        BigInt.from(_random.nextInt(1 << 32));
    _sequence = 0;
    _soundNow = sound();
    _engineNow = engine();
    status = WatchStatus.connecting;
    _measureTimer = Timer.periodic(measureEvery, (_) => _measure());
    _slotChanged();
    notifyListeners();
    _askForOffer();
  }

  /// Stops watching; the host hears it from the server.
  Future<void> leave() => _close(tell: true, reason: WatchEnd.left);

  Future<void> decline(ShareInvite invite) async {
    invites = invites
        .where((i) => i.sharePlayId != invite.sharePlayId)
        .toList();
    notifyListeners();
    await account.call('POST', 'share-plays/${invite.sharePlayId}/decline');
  }

  /// The whole pad as the screen holds it: sent at once while this phone holds a pad.
  void update(PadState state) {
    _state = state.copy();
    _sendPad();
  }

  /// Signed out: nothing kept.
  void clear() {
    invites = const [];
    _close(tell: false);
  }

  /// Asks the host for an offer, and again a few times while none comes.
  void _askForOffer([int tries = 0]) {
    _askTimer?.cancel();
    final view = watching;
    if (view == null || status == WatchStatus.ended) return;
    _signal('renegotiate', null);
    if (tries >= 5) return;
    _askTimer = Timer(askAgainAfter, () {
      if (status == WatchStatus.connecting && _link?.hasRemote != true) {
        _askForOffer(tries + 1);
      }
    });
  }

  bool _signal(String kind, Object? data) {
    final view = watching;
    final host = view?.host?.id;
    if (view == null || host == null) return false;
    return socket.send({
      'op': 'signal',
      'to': host,
      'device': _hostDevice ?? view.hostDevice,
      'share': view.id,
      'kind': kind,
      'data': data,
    });
  }

  /// One signal at a time, in the order they came.
  Future<void> _serial(Future<void> Function() step) {
    final next = _queue.then((_) => step());
    _queue = next.catchError((_) {});
    return next;
  }

  Future<void> _onSignal(Map<String, dynamic> data) => _serial(() async {
    final view = watching;
    if (view == null || status == WatchStatus.ended) return;
    if (data['sharePlayId'] != view.id || data['from'] != view.host?.id) return;
    final kind = data['kind'];
    final payload = data['data'];
    switch (kind) {
      case 'offer':
        _hostDevice = data['device'] as String? ?? _hostDevice;
        var link = _link;
        if (link == null ||
            link.connectionState == 'failed' ||
            link.connectionState == 'closed') {
          // Candidates that came ahead of this offer belong to it.
          final early = [..._queued];
          await _dropLink();
          _queued.addAll(early);
          link = await _open();
        }
        await link.setRemote(_json(payload));
        final queued = [..._queued];
        _queued.clear();
        for (final candidate in queued) {
          await link.addCandidate(candidate).catchError((_) {});
        }
        final answer = await link.createAnswer();
        await link.setLocal(answer);
        _signal('answer', answer);
      case 'candidate' when payload != null:
        final link = _link;
        if (link != null && link.hasRemote) {
          await link.addCandidate(_json(payload)).catchError((_) {});
        } else {
          _queued.add(_json(payload));
        }
      case 'bye':
        await _dropLink();
        status = WatchStatus.connecting;
        notifyListeners();
    }
  });

  Future<ShareLink> _open() async {
    final link = await _engineNow!.link(_ice);
    _link = link;
    link.onCandidate = (candidate) => _signal('candidate', candidate);
    link.onState = () {
      if (_link != link) return;
      final state = link.connectionState;
      if (state == 'connected' && status == WatchStatus.connecting) {
        status = WatchStatus.watching;
      } else if (state == 'failed') {
        // Asked again: the host makes a fresh connection (through the relay if it must).
        status = WatchStatus.connecting;
        _serial(_dropLink).then((_) => _askForOffer());
      }
      notifyListeners();
    };
    link.onChannel = (channel) {
      if (_link != link) return;
      switch (channel.label) {
        case 'pad':
          _pad = channel;
          channel.onMessage = _fromGame;
          _slotChanged();
        case 'audio':
          channel.onMessage = (bytes) {
            final packet = decodeAudio(bytes);
            if (packet != null) _soundNow?.sound(packet);
          };
      }
    };
    notifyListeners();
    return link;
  }

  Future<void> _dropLink() async {
    final link = _link;
    _link = null;
    _pad = null;
    _queued.clear();
    if (link != null) await link.close();
  }

  void _fromGame(Uint8List bytes) {
    final answer = decodeOutput(bytes);
    if (answer == null) return;
    final light =
        output?.lightValid != answer.lightValid ||
        output?.r != answer.r ||
        output?.g != answer.g ||
        output?.b != answer.b;
    output = answer;
    onOutput?.call(answer, _state);
    final roundTrip = _clock.elapsedMicroseconds - answer.sentMicros;
    if (roundTrip >= 0 && roundTrip < 2000000) {
      final sample =
          (roundTrip - answer.waitMicros) / 2000 + answer.waitMicros / 1000;
      latencyMs = latencyMs == null ? sample : latencyMs! * 0.8 + sample * 0.2;
    }
    if (light) notifyListeners();
  }

  /// A pad held: packets go 120 times a second; taken back: they stop at once.
  void _slotChanged() {
    if (slot != null && _pad != null) {
      _padTimer ??= Timer.periodic(padEvery, (_) => _sendPad());
      _sendPad();
    } else {
      _padTimer?.cancel();
      _padTimer = null;
      _state = PadState();
    }
  }

  void _sendPad() {
    final pad = _pad;
    if (slot == null || pad == null || !pad.open) return;
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    pad.send(
      encodeInput(
        sequence: _sequence,
        sentMicros: _clock.elapsedMicroseconds,
        session: _session,
        state: _state,
      ),
    );
  }

  void _take(SharePlayView view) {
    final before = slot;
    watching = view;
    if (slot != before) _slotChanged();
  }

  Future<void> _measure() async {
    final link = _link;
    if (link == null) return;
    try {
      quality = await link.quality();
      notifyListeners();
    } on Object {
      // Next second.
    }
  }

  /// Fresh relay credentials ten minutes before these run out, for connections made after.
  void _renewBefore(Object? expiresAt) {
    final expiry = DateTime.tryParse(expiresAt as String? ?? '');
    _renewTimer?.cancel();
    final view = watching;
    if (expiry == null || view == null) return;
    final wait =
        expiry.difference(DateTime.now()) - const Duration(minutes: 10);
    _renewTimer = Timer(wait.isNegative ? Duration.zero : wait, () async {
      try {
        final fresh = await account.call(
          'GET',
          'share-plays/${view.id}/ice-servers',
        );
        if (watching?.id != view.id) return;
        _ice = _servers(fresh['iceServers']);
        _renewBefore(fresh['expiresAt']);
      } on Object {
        // The ones held still work until they expire.
      }
    });
  }

  Future<void> _close({required bool tell, WatchEnd? reason}) async {
    final view = watching;
    if (view != null && _link != null) _signal('bye', null);
    _generation++;
    watching = null;
    _padTimer?.cancel();
    _padTimer = null;
    _askTimer?.cancel();
    _renewTimer?.cancel();
    _measureTimer?.cancel();
    _soundNow?.stop();
    _soundNow = null;
    _engineNow = null;
    output = null;
    _state = PadState();
    if (view != null || status != WatchStatus.ended) {
      status = WatchStatus.ended;
      ended = reason ?? ended;
      notifyListeners();
    }
    await _serial(_dropLink);
    if (tell && view != null) {
      try {
        await account.call('POST', 'share-plays/${view.id}/leave');
      } on Object {
        // The server takes this phone out when its socket goes.
      }
    }
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    switch (event.type) {
      case 'live.ready':
        refresh().catchError((_) {});
        // Signals sent while the socket was gone are lost: the host is asked again.
        if (watching != null && _link?.connectionState != 'connected') {
          _askForOffer();
        }
      case 'share_play.invite':
        final invite = ShareInvite.fromJson(data);
        invites = [
          ...invites.where((i) => i.sharePlayId != invite.sharePlayId),
          invite,
        ];
        notifyListeners();
      case 'share_play.updated' when data['id'] == watching?.id:
        _take(SharePlayView.fromJson(data));
        notifyListeners();
      case 'share_play.ended':
        final id = data['sharePlayId'];
        invites = invites.where((i) => i.sharePlayId != id).toList();
        if (id == watching?.id) {
          _close(
            tell: false,
            reason: data['reason'] == 'removed'
                ? WatchEnd.removed
                : WatchEnd.stopped,
          );
        } else {
          notifyListeners();
        }
      case 'share_play.signal':
        _onSignal(data).catchError((_) {});
    }
  }

  static List<Map<String, dynamic>> _servers(Object? list) => [
    for (final server in (list as List? ?? const []))
      Map<String, dynamic>.from(server as Map),
  ];

  static Map<String, dynamic> _json(Object? data) =>
      data is Map ? Map<String, dynamic>.from(data) : const {};

  @override
  void dispose() {
    _events.cancel();
    _close(tell: false);
    super.dispose();
  }
}
