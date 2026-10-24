import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../feedback/haptics.dart';
import '../feedback/motion.dart';
import '../protocol/messages.dart';
import '../protocol/packets.dart';
import '../stream/stream_packets.dart';
import '../stream/stream_player.dart';
import '../together/together_account.dart';
import '../version.dart';

enum ConnectionStatus { searching, connecting, pairing, connected, rejected }

/// The launcher's theme as the phone wears it.
class Look {
  const Look({required this.deep, required this.middle, required this.accent});

  final Color deep;
  final Color middle;
  final Color accent;

  static Color? _color(String? hex) {
    if (hex == null) return null;
    final digits = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
    return value == null ? null : Color(0xFF000000 | value);
  }

  static Look? parse(String? deep, String? middle, String? accent) {
    final colors = [_color(deep), _color(middle), _color(accent)];
    if (colors.contains(null)) return null;
    return Look(deep: colors[0]!, middle: colors[1]!, accent: colors[2]!);
  }
}

/// A game's pictures as the launcher sent them, for the [tag] they were sent for.
class GameArt {
  GameArt(this.tag);

  final String tag;
  Uint8List? icon;
  Uint8List? background;
  bool arrived = false;
}

/// The phone's link to the launcher: the WebSocket control channel (hello, pairing, welcome),
/// the UDP pad sender and the latency measured from the game's answers. On a cable there is no
/// UDP path: the pad and the answers go on the control channel as binary messages.
class Session extends ChangeNotifier {
  Session({
    required this.preferences,
    required this.deviceName,
    TogetherAccount? together,
  }) : together =
           together ??
           TogetherAccount(
             preferences: preferences,
             clientName: 'remote-${Platform.operatingSystem}/$appVersion',
           );

  final SharedPreferences preferences;
  final String deviceName;

  /// The phone's AnyTogether account, which signs the Mac in or is signed in by it.
  final TogetherAccount together;

  /// The AnyTogether server the connected launcher uses, when it says which.
  Uri? launcherServer;

  /// The Mac asking to be signed in to AnyTogether as this phone's account, until answered.
  final handoffAsked = ValueNotifier<TogetherHandoff?>(null);

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

  /// The launcher's theme, kept from the last time when not connected.
  late final look = ValueNotifier<Look?>(
    Look.parse(
      preferences.getString('lookDeep'),
      preferences.getString('lookMiddle'),
      preferences.getString('lookAccent'),
    ),
  );

  /// The trophy earned last, shown for a moment over whatever the phone shows.
  final trophy = ValueNotifier<TrophyEarned?>(null);

  /// What the launcher is doing with a game, and since when on this phone's clock.
  final activity = ValueNotifier<({Activity activity, DateTime since})?>(null);

  /// Off while the phone shows the launcher: the game gets no pad from it then.
  bool _padActive = true;

  /// Remote Play's decoder and speaker; the stream is asked for with [startStream].
  StreamPlayer? player;

  /// How Remote Play is going, as the launcher last said; null before it said anything.
  final streaming = ValueNotifier<String?>(null);

  /// The picture size asked for, while Remote Play is wanted.
  (int, int)? _streamSize;
  FrameAssembler? _assembler;
  int _keyAsked = -1 << 62;

  /// The game's rumble, light bar and trigger effects felt on the phone.
  HapticsDriver? haptics;

  /// The phone's tilt and turn, sent with every pad packet as the DualSense's motion.
  MotionSource? motion;

  InternetAddress? _host;
  int? _port;
  bool _cable = false;

  /// Connected, or connecting, over a cable.
  bool get cable => _cable;
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
  /// reconnecting until [close]; [cable] when that is the cable's local port.
  Future<void> connect(
    InternetAddress host,
    int port, {
    bool cable = false,
  }) async {
    _host = host;
    _port = port;
    _cable = cable;
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
    activity.value = null;
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
    if (generation != _generation) return;
    if (data is List<int>) {
      _datagram(data is Uint8List ? data : Uint8List.fromList(data));
      return;
    }
    if (data is! String) return;
    switch (Message.fromJson(data)) {
      case Pairing(:final code):
        this.code = code;
        _setStatus(ConnectionStatus.pairing);
      case Welcome(
        :final session,
        :final udpPort,
        :final macName,
        :final key,
        :final togetherServer,
      ):
        preferences.setString('key', key);
        this.macName = macName;
        launcherServer = serverAddress(togetherServer ?? '');
        _session = session;
        _udpPort = udpPort;
        code = null;
        _startPad(generation);
        _setStatus(ConnectionStatus.connected);
        final size = _streamSize;
        if (size != null) {
          _socket?.add(
            StreamRequest(on: true, width: size.$1, height: size.$2).toJson(),
          );
        }
      case final Library library:
        this.library = library;
        for (final game in library.games) {
          if (art[game.id]?.tag == game.art) continue;
          art[game.id] = GameArt(game.art);
          _socket?.add(WantArt(game.id).toJson());
        }
        notifyListeners();
      case LookUpdate(:final deep, :final middle, :final accent):
        final worn = Look.parse(deep, middle, accent);
        if (worn == null) break;
        look.value = worn;
        preferences
          ..setString('lookDeep', deep)
          ..setString('lookMiddle', middle)
          ..setString('lookAccent', accent);
        notifyListeners();
      case final TrophyEarned earned:
        trophy.value = earned;
        haptics?.celebrate();
      case ActivityUpdate(:final activity):
        final shown = this.activity.value;
        this.activity.value = activity == null
            ? null
            : (
                activity: activity,
                // The same game keeps its start, so the count does not jump.
                since: shown != null && shown.activity.id == activity.id
                    ? shown.since
                    : DateTime.now().subtract(activity.elapsed),
              );
      case Art(:final id, :final icon, :final background):
        final pictures = art[id];
        if (pictures == null) break;
        pictures
          ..icon = icon == null ? null : base64Decode(icon)
          ..background = background == null ? null : base64Decode(background)
          ..arrived = true;
        notifyListeners();
      case Streaming(:final state):
        streaming.value = state;
      case final TogetherHandoff ask:
        if (together.user == null) {
          // Nothing to sign the Mac in with: it says so and offers the other ways.
          _socket?.add(
            TogetherHandoffAnswer(id: ask.id, approved: false).toJson(),
          );
        } else {
          handoffAsked.value = ask;
        }
      case TogetherHandoffAnswer(:final id, approved: false):
        final waiting = together.step;
        if (waiting is WaitingForMac && waiting.handoff.id == id) {
          together.cancel();
        }
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
    if (_udp == null && !_cable) {
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
        if (datagram != null) _datagram(datagram.data);
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

  /// A pad answer, or Remote Play's picture or sound.
  void _datagram(Uint8List data) {
    final answer = decodeOutput(data);
    if (answer != null) return _answered(answer);
    if (_streamSize == null) return;
    final piece = decodeVideo(data);
    if (piece != null) return _assembler?.add(piece);
    final sound = decodeAudio(data);
    if (sound != null) player?.sound(sound);
  }

  /// Asks the launcher for the game's picture and sound at about [width] by [height].
  void startStream(int width, int height) {
    _streamSize = (width, height);
    _assembler = FrameAssembler(
      onFrame: (frame) => player?.frame(frame),
      onLoss: () {
        // One request at a time: the key frame takes a moment to come.
        final now = _clock.elapsedMilliseconds;
        if (now - _keyAsked < 250) return;
        _keyAsked = now;
        send(const KeyFrame());
      },
    );
    send(StreamRequest(on: true, width: width, height: height));
    // The launcher sends the picture to where the pad comes from: a still pad says where.
    _ping();
  }

  /// Back to the pad alone.
  void stopStream() {
    if (_streamSize == null) return;
    _streamSize = null;
    _assembler = null;
    streaming.value = null;
    player?.stop();
    send(const StreamRequest(on: false));
  }

  bool get streamWanted => _streamSize != null;

  void _ping() {
    final udp = _udp;
    final session = _session;
    if (_cable ||
        udp == null ||
        session == null ||
        _udpPort == null ||
        _padActive) {
      return;
    }
    try {
      udp.send(
        encodeInput(
          sequence: _sequence,
          sentMicros: _clock.elapsedMicroseconds,
          session: session,
          state: PadState(),
        ),
        _host!,
        _udpPort!,
      );
    } on SocketException {
      // The pad's next packet says it instead.
    }
  }

  /// The new pad state, sent at once; the moment it arrives is when the touch was received.
  void update(PadState state) {
    final touched = _clock.elapsedMicroseconds;
    _state = state.copy();
    _send();
    _handlingMicros = _clock.elapsedMicroseconds - touched;
  }

  /// Approves the Mac's sign-in with this phone's account, or turns it down.
  Future<void> answerHandoff(
    TogetherHandoff ask, {
    required bool approve,
  }) async {
    if (handoffAsked.value?.id == ask.id) handoffAsked.value = null;
    var approved = false;
    try {
      if (approve) {
        await together.approveHandoff(ask.id);
        approved = true;
      }
    } finally {
      send(TogetherHandoffAnswer(id: ask.id, approved: approved));
    }
  }

  /// Signs the phone in with the Mac's account: the Mac, signed in, approves it at once.
  Future<TogetherUser> signInWithMac({
    Duration every = const Duration(seconds: 2),
  }) async {
    final handoff = await together.startHandoff(deviceName);
    send(TogetherHandoff(id: handoff.id, deviceName: deviceName));
    return together.waitForApproval(handoff, every: every);
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
    final socket = _socket;
    final session = _session;
    if (session == null || _sender == null) return;
    if (_cable ? socket == null : udp == null || _udpPort == null) return;
    _sequence = (_sequence + 1) & 0xFFFFFFFF;
    final packet = encodeInput(
      sequence: _sequence,
      sentMicros: _clock.elapsedMicroseconds,
      session: session,
      state: _state,
      motion: motion?.latest,
    );
    try {
      _cable ? socket!.add(packet) : udp!.send(packet, _host!, _udpPort!);
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
    activity.value = null;
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
