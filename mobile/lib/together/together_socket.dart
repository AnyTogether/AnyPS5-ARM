import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'together_account.dart';

/// Something AnyTogether's gateway pushed: a friend's presence, a message, a party change, a call
/// peer's signal. [type] `live.ready` is the phone's own, after every (re)connect, for the lists
/// to catch up with what they may have missed.
class TogetherEvent {
  const TogetherEvent(this.id, this.type, this.data);

  final String id;
  final String type;
  final Object? data;

  Map<String, dynamic> get json =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};
}

enum SocketStatus { offline, connecting, ready, signedOut }

/// The phone's socket to AnyTogether's realtime gateway (/rt): hello with the access token, a
/// heartbeat with the phone's presence as often as the gateway asks, the events handed on, what
/// was missed picked up after a reconnect, and the end when the session is signed out elsewhere.
///
/// The phone says it is online, never more: the gateway keeps each device's presence apart and
/// shows friends the highest (in a game, then online, then away), so a Mac playing still shows.
class TogetherSocket extends ChangeNotifier {
  TogetherSocket({
    required this.account,
    this.retryBase = const Duration(seconds: 1),
    this.retryMost = const Duration(seconds: 30),
    Random? random,
  }) : _random = random ?? Random();

  final TogetherAccount account;
  final Duration retryBase;
  final Duration retryMost;
  final Random _random;

  /// Close codes the gateway uses.
  static const unauthorized = 4001;
  static const signedOut = 4003;

  /// IDs the API gives events (UUIDv7), which a socket that comes back can resume after;
  /// presence and signals have others and are never replayed.
  static final _resumable = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  SocketStatus status = SocketStatus.offline;

  /// This device's session as the gateway and the calls name it.
  String? session;

  final _events = StreamController<TogetherEvent>.broadcast();
  Stream<TogetherEvent> get events => _events.stream;

  WebSocket? _socket;
  Timer? _beat;
  Timer? _retry;
  bool _running = false;
  bool _renew = false;
  int _attempt = 0;
  int _generation = 0;
  String? _lastId;

  /// Where the gateway is: /rt on AnyTogether's own host.
  Uri get gateway => account.base.replace(
    scheme: account.base.scheme == 'http' ? 'ws' : 'wss',
    path: '/rt',
  );

  void start() {
    if (_running) return;
    _running = true;
    _attempt = 0;
    _connect();
  }

  void stop() {
    _running = false;
    _generation++;
    _retry?.cancel();
    _beat?.cancel();
    _socket?.close(1000, 'signed out');
    _socket = null;
    _lastId = null;
    session = null;
    _set(SocketStatus.offline);
  }

  /// Back in the foreground: a socket the phone lost while asleep comes back at once, not after
  /// its back-off.
  void wake() {
    if (!_running || status != SocketStatus.offline) return;
    _retry?.cancel();
    _attempt = 0;
    _connect();
  }

  /// The gateway's limit on topics one socket watches.
  static const maxTopics = 8;

  /// The public topics (the board, the public lists) each part of the phone watches, by who
  /// asked; the gateway hears them together, and again on every new socket.
  final _watchers = <Object, Set<String>>{};
  List<String> _watched = const [];

  /// The topics the gateway is told to watch: everyone's, the ones asked first first.
  List<String> get topics => _watched;

  /// Watches [topics] for [owner] in place of what it watched before; empty stops. The
  /// gateway carries only "changed" events on them, for the lists to read themselves again.
  void watchTopics(Object owner, Set<String> topics) {
    if (topics.isEmpty) {
      _watchers.remove(owner);
    } else {
      _watchers[owner] = {...topics};
    }
    final next = <String>{for (final wanted in _watchers.values) ...wanted}
        .take(maxTopics)
        .toList();
    if (listEquals(next, _watched)) return;
    _watched = next;
    send({'op': 'watch', 'topics': next});
  }

  /// Sends a frame while connected; false when it could not go.
  bool send(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null || status != SocketStatus.ready) return false;
    socket.add(jsonEncode(frame));
    return true;
  }

  void _set(SocketStatus next) {
    if (status == next) return;
    status = next;
    notifyListeners();
  }

  Future<void> _connect() async {
    if (!_running) return;
    final mine = ++_generation;
    _set(SocketStatus.connecting);
    final WebSocket socket;
    try {
      final token = await account.accessToken(renew: _renew);
      _renew = false;
      if (mine != _generation) return;
      socket = await WebSocket.connect(gateway.toString())
          .timeout(const Duration(seconds: 15));
      if (mine != _generation) {
        socket.close(1000);
        return;
      }
      _socket = socket;
      socket.add(
        jsonEncode({
          'op': 'hello',
          'token': token,
          'client': account.clientName,
          'resume': ?_lastId,
        }),
      );
    } on TogetherProblem catch (problem) {
      // Not signed in any more (the refresh was turned down): nothing to connect.
      if (problem.status == 401 && account.user == null) {
        _end();
        return;
      }
      _later();
      return;
    } on Object {
      _later();
      return;
    }
    socket.listen(
      (message) {
        // A socket stopped or replaced may still deliver what was on its way.
        if (message is String && mine == _generation) _frame(message);
      },
      onDone: () => _closed(mine, socket.closeCode),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _frame(String text) {
    final Object? frame;
    try {
      frame = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (frame is! Map<String, dynamic>) return;
    switch (frame['op']) {
      case 'ready':
        _attempt = 0;
        session = frame['session'] as String?;
        final every = (frame['heartbeat'] as num?) ?? 25;
        _beat?.cancel();
        _beat = Timer.periodic(
          Duration(milliseconds: (every * 1000).round()),
          (_) => send({
            'op': 'heartbeat',
            'presence': {'state': 'online'},
          }),
        );
        _set(SocketStatus.ready);
        // A new socket watches nothing until told.
        if (_watched.isNotEmpty) send({'op': 'watch', 'topics': _watched});
        _events.add(const TogetherEvent('', 'live.ready', null));
      case 'event':
        final id = frame['id'] as String? ?? '';
        final type = frame['type'];
        if (type is! String) return;
        if (_resumable.hasMatch(id)) _lastId = id;
        _events.add(TogetherEvent(id, type, frame['data']));
    }
  }

  void _closed(int generation, int? code) {
    if (generation != _generation) return;
    _beat?.cancel();
    _socket = null;
    if (code == signedOut) {
      _end();
      account.signedOutElsewhere();
      return;
    }
    // A token the gateway turned down (it ran out while asleep): a fresh one next time.
    if (code == unauthorized) _renew = true;
    _later();
  }

  void _end() {
    _running = false;
    _beat?.cancel();
    _retry?.cancel();
    session = null;
    _set(SocketStatus.signedOut);
  }

  /// 1, 2, 4 … 30 s, spread a little so a gateway restart is not met by everyone at once.
  void _later() {
    if (!_running) return;
    _set(SocketStatus.offline);
    final step = retryBase * pow(2, _attempt++).toDouble();
    final wait =
        (step > retryMost ? retryMost : step) *
        (0.8 + _random.nextDouble() * 0.4);
    _retry?.cancel();
    _retry = Timer(wait, _connect);
  }

  @override
  void dispose() {
    stop();
    _events.close();
    super.dispose();
  }
}
