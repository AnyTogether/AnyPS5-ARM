import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../feedback/haptics.dart';
import '../protocol/messages.dart';
import '../protocol/packets.dart';

enum ConnectionStatus { searching, connecting, pairing, connected, rejected }

/// A game's pictures as the launcher sent them, for the [tag] they were sent for.
class GameArt {
  GameArt(this.tag);

  final String tag;
  Uint8List? icon;
  Uint8List? background;
  bool arrived = false;
}

/// The phone's link to the launcher: the WebSocket control channel (hello, pairing, welcome),
/// the UDP pad sender and the latency measured from the game's answers.
class Session extends ChangeNotifier {
  Session({required this.preferences, required this.deviceName});

  final SharedPreferences preferences;
  final String deviceName;

  static const sendInterval = Duration(milliseconds: 8);
  static const reportInterval = Duration(seconds: 2);
  static const retryInterval = Duration(seconds: 1);
  static const pingInterval = Duration(seconds: 2);

  /// The shortest time between two latency updates the listeners hear about.
  static const latencyNotice = Duration(milliseconds: 500);
  static final _clock = Stopwatch()..start();

  ConnectionStatus status = ConnectionStatus.searching;
  String? code;
  String? macName;
  String? rejectedReason;
  double? latencyMs;

  /// The game's latest answer: vibration, light bar and trigger fallbacks.
  Output? output;

  /// The launcher's games as it last told them, and their pictures by game.
  Library? library;
  final art = <String, GameArt>{};

  /// Off while the phone shows the launcher: the game gets no pad from it then.
  bool _padActive = true;

  /// The game's rumble, light bar and trigger effects felt on the phone.
  HapticsDriver? haptics;

  InternetAddress? _host;
  int? _port;
  WebSocket? _socket;
  RawDatagramSocket? _udp;
  int? _udpPort;
  BigInt? _session;
  Timer? _sender;
  Timer? _reporter;
  Timer? _retry;
  bool _closed = false;
  int _sequence = 0;
  PadState _state = PadState();
  int _handlingMicros = 0;
  int _latencyNoticed = -1 << 62;

  /// Bumped by every connect, retry and close: work started for an older one is dropped.
  int _generation = 0;

  String get _deviceID {
    final stored = preferences.getString('deviceID');
    if (stored != null) return stored;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    preferences.setString('deviceID', id);
    return id;
  }

  /// Connects to the launcher at [host]:[port], replacing any earlier target, and keeps
  /// reconnecting until [close].
  Future<void> connect(InternetAddress host, int port) async {
    _host = host;
    _port = port;
    _closed = false;
    await _restart();
  }

  /// Tries again after the launcher refused, or at once while waiting to reconnect.
  void retry() {
    if (_closed || _host == null) return;
    rejectedReason = null;
    _restart();
  }

  Future<void> _restart() async {
    final generation = ++_generation;
    _retry?.cancel();
    final old = _socket;
    _socket = null;
    _stopPad();
    await old?.close();
    await _open(generation);
  }

  Future<void> _open(int generation) async {
    if (_closed || _host == null || generation != _generation) return;
    _setStatus(ConnectionStatus.connecting);
    try {
      final socket = await WebSocket.connect(
        Uri(scheme: 'ws', host: _host!.address, port: _port).toString(),
      ).timeout(const Duration(seconds: 3));
      if (generation != _generation || _closed) {
        await socket.close();
        return;
      }
      socket.pingInterval = pingInterval;
      _socket = socket;
      socket.listen(
        (data) => _received(data, generation),
        onDone: () => _lost(generation),
        onError: (_) => _lost(generation),
        cancelOnError: true,
      );
      socket.add(
        Hello(
          deviceID: _deviceID,
          deviceName: deviceName,
          key: preferences.getString('key'),
        ).toJson(),
      );
    } on Object {
      if (generation == _generation) _scheduleRetry(generation);
    }
  }

  void _received(dynamic data, int generation) {
    if (data is! String || generation != _generation) return;
    switch (Message.fromJson(data)) {
      case Pairing(:final code):
        this.code = code;
        _setStatus(ConnectionStatus.pairing);
      case Welcome(:final session, :final udpPort, :final macName, :final key):
        preferences.setString('key', key);
        this.macName = macName;
        _session = session;
        _udpPort = udpPort;
        code = null;
        _startPad(generation);
        _setStatus(ConnectionStatus.connected);
      case final Library library:
        this.library = library;
        for (final game in library.games) {
          if (art[game.id]?.tag == game.art) continue;
          art[game.id] = GameArt(game.art);
          _socket?.add(WantArt(game.id).toJson());
        }
        notifyListeners();
      case Art(:final id, :final icon, :final background):
        final pictures = art[id];
        if (pictures == null) break;
        pictures
          ..icon = icon == null ? null : base64Decode(icon)
          ..background = background == null ? null : base64Decode(background)
          ..arrived = true;
        notifyListeners();
      case Rejected(:final reason):
        rejectedReason = reason;
        if (reason == 'busy') {
          _scheduleRetry(generation);
        } else {
          _setStatus(ConnectionStatus.rejected);
        }
      default:
        break;
    }
  }

  Future<void> _startPad(int generation) async {
    if (_udp == null) {
      final udp = await RawDatagramSocket.bind(
        _host!.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      _udp = udp;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = udp.receive();
        final answer = datagram == null ? null : decodeOutput(datagram.data);
        if (answer != null) _answered(answer);
      });
    }
    if (generation != _generation) return;
    _sender?.cancel();
    _sender = Timer.periodic(sendInterval, (_) => _send());
    _reporter?.cancel();
    _reporter = Timer.periodic(reportInterval, (_) {
      if (latencyMs != null) _socket?.add(Latency(latencyMs!).toJson());
    });
    _send();
  }

  /// The new pad state, sent at once; the moment it arrives is when the touch was received.
  void update(PadState state) {
    final touched = _clock.elapsedMicroseconds;
    _state = state.copy();
    _send();
    _handlingMicros = _clock.elapsedMicroseconds - touched;
  }

  /// A request to the launcher on the control channel; dropped while not connected.
  void send(Message message) => _socket?.add(message.toJson());

  /// The game lets go of everything held, then hears nothing from the phone until [resumePad].
  void pausePad() {
    haptics?.stop();
    if (!_padActive) return;
    _state = PadState();
    _send();
    _padActive = false;
  }

  void resumePad() {
    if (_padActive) return;
    _padActive = true;
    _send();
  }

  void _send() {
    if (!_padActive) return;
    final udp = _udp;
    final session = _session;
    if (udp == null || session == null || _udpPort == null || _sender == null) {
      return;
    }
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    try {
      udp.send(
        encodeInput(
          sequence: _sequence,
          sentMicros: _clock.elapsedMicroseconds,
          session: session,
          state: _state,
        ),
        _host!,
        _udpPort!,
      );
    } on SocketException {
      // No route while the Wi-Fi is gone: the next tick tries again.
    }
  }

  /// One-way latency from an answer: half the round trip without the time the input waited in
  /// the game's socket, plus that wait, plus the time from the touch to the send.
  void _answered(Output answer) {
    output = answer;
    if (_padActive) {
      haptics?.update(
        answer,
        l2Held: _state.l2 > 0 || _state.buttons & PadButton.l2 != 0,
        r2Held: _state.r2 > 0 || _state.buttons & PadButton.r2 != 0,
        now: _clock.elapsed,
      );
    }
    final now = _clock.elapsedMicroseconds;
    final roundTrip = now - answer.sentMicros;
    if (roundTrip < 0 || roundTrip > 2000000) return;
    final oneWay =
        (roundTrip - answer.waitMicros) / 2 +
        answer.waitMicros +
        _handlingMicros;
    final sample = oneWay / 1000;
    latencyMs = latencyMs == null ? sample : latencyMs! * 0.8 + sample * 0.2;
    if (now - _latencyNoticed >= latencyNotice.inMicroseconds) {
      _latencyNoticed = now;
      notifyListeners();
    }
  }

  void _lost(int generation) {
    if (generation != _generation) return;
    _socket = null;
    _stopPad();
    if (_closed || status == ConnectionStatus.rejected) return;
    _scheduleRetry(generation);
  }

  void _scheduleRetry(int generation) {
    _setStatus(ConnectionStatus.connecting);
    _retry?.cancel();
    _retry = Timer(retryInterval, () => _open(generation));
  }

  /// A session that ends lets go of everything: a pad held when it dropped is not sent again
  /// when it comes back.
  void _stopPad() {
    haptics?.stop();
    _sender?.cancel();
    _sender = null;
    _reporter?.cancel();
    _reporter = null;
    _session = null;
    _state = PadState();
    latencyMs = null;
  }

  void _setStatus(ConnectionStatus next) {
    if (status == next) return;
    status = next;
    notifyListeners();
  }

  /// Ends the session for good.
  Future<void> close() async {
    _closed = true;
    _generation++;
    _retry?.cancel();
    _stopPad();
    _udp?.close();
    _udp = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }
}
