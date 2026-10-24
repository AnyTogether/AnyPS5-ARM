import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/connection/session.dart';
import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/protocol/packets.dart';
import 'package:anyps5_remote/stream/stream_packets.dart';
import 'package:anyps5_remote/stream/stream_player.dart';
import 'package:anyps5_remote/together/together_account.dart';

import 'stream_test.dart' show pieces;
import 'together_test.dart' show FakeTogether;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The launcher's side, scripted: a WebSocket control channel and a UDP pad port.
class FakeLauncher {
  FakeLauncher({this.askFirst = false, this.echo = false, this.refuseFirst});

  final bool askFirst;
  final bool echo;

  /// The reason the first hello is refused with, before later ones are welcomed.
  String? refuseFirst;
  late HttpServer http;
  late RawDatagramSocket udp;
  final hellos = <Map<String, dynamic>>[];
  final packets = <(DateTime, Uint8List)>[];

  /// Where the phone's pad came from, to send Remote Play's packets back to.
  (InternetAddress, int)? padFrom;

  /// Pad packets that came on the control channel, as a phone on a cable sends them.
  final channelPackets = <Uint8List>[];
  final sockets = <WebSocket>[];

  /// Everything but hellos the phone sent, in order.
  final received = <Map<String, dynamic>>[];

  /// Sent to every phone right after its welcome.
  Map<String, dynamic>? library;

  int get port => http.port;

  Future<void> start({int port = 0}) async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = udp.receive();
      if (datagram == null) return;
      packets.add((DateTime.now(), datagram.data));
      padFrom = (datagram.address, datagram.port);
      if (echo) {
        Timer(
          const Duration(milliseconds: 4),
          () =>
              udp.send(answer(datagram.data), datagram.address, datagram.port),
        );
      }
    });
    http.transform(WebSocketTransformer()).listen((socket) {
      sockets.add(socket);
      socket.listen((data) async {
        if (data is List<int>) {
          final packet = Uint8List.fromList(data);
          channelPackets.add(packet);
          // A packet still arriving as the phone closes is not answered.
          if (echo && socket.closeCode == null) {
            try {
              socket.add(answer(packet));
            } on StateError {
              // Closed in between.
            }
          }
          return;
        }
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        if (message['type'] == 'wantArt') {
          socket.add(
            jsonEncode({
              'type': 'art',
              'id': message['id'],
              'icon': base64Encode([1, 2, 3]),
              'background': null,
            }),
          );
        }
        if (message['type'] != 'hello') {
          received.add(message);
          return;
        }
        hellos.add(message);
        if (refuseFirst != null) {
          socket.add(jsonEncode({'type': 'rejected', 'reason': refuseFirst}));
          refuseFirst = null;
          await socket.close();
          return;
        }
        if (askFirst && message['key'] == null) {
          socket.add('{"type":"pairing","code":"4821"}');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        socket.add(
          jsonEncode({
            'type': 'welcome',
            'session': '42',
            'udpPort': udp.port,
            'macName': 'Test Mac',
            'key': 'c3RvcmVkLWtleQ==',
          }),
        );
        if (library != null) socket.add(jsonEncode(library));
      });
    });
  }

  Uint8List answer(Uint8List input) {
    final out = Uint8List(32);
    final data = ByteData.sublistView(out);
    data.setUint32(0, 0x4F525041, Endian.little);
    data.setUint16(4, 1, Endian.little);
    data.setUint16(6, 32, Endian.little);
    data.setUint32(
      8,
      ByteData.sublistView(input).getUint32(8, Endian.little),
      Endian.little,
    );
    data.setUint32(12, 1000, Endian.little);
    data.setUint64(
      16,
      ByteData.sublistView(input).getUint64(16, Endian.little),
      Endian.little,
    );
    return out;
  }

  void tell(Map<String, dynamic> message) {
    for (final socket in sockets) {
      socket.add(jsonEncode(message));
    }
  }

  Future<void> stop() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await http.close(force: true);
    udp.close();
  }
}

/// Remote Play's player, keeping what it was given.
class FakePlayer implements StreamPlayer {
  final frames = <VideoFrame>[];
  final sounds = <AudioPacket>[];

  @override
  void frame(VideoFrame frame) => frames.add(frame);

  @override
  void sound(AudioPacket packet) => sounds.add(packet);

  @override
  void stop() {}
}

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

int buttonsOf(Uint8List packet) =>
    ByteData.sublistView(packet).getUint32(32, Endian.little);

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('pairs on first connection', () async {
    final launcher = FakeLauncher(askFirst: true);
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    final seen = <ConnectionStatus>[];
    String? shownCode;
    session.addListener(() {
      seen.add(session.status);
      if (session.status == ConnectionStatus.pairing) shownCode = session.code;
    });
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    expect(seen, contains(ConnectionStatus.pairing));
    expect(shownCode, '4821');
    expect(session.code, isNull);
    expect(session.macName, 'Test Mac');
    expect(preferences.getString('key'), 'c3RvcmVkLWtleQ==');
    expect(launcher.hellos.single['deviceName'], 'Pixel 8');
    expect(launcher.hellos.single['protocol'], 1);
    await session.close();
    await launcher.stop();
  });

  test('sends state at least every 8 ms', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    launcher.packets.clear();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(launcher.packets.length, greaterThanOrEqualTo(10));
    final sequences = launcher.packets
        .map(
          (packet) =>
              ByteData.sublistView(packet.$2).getUint32(8, Endian.little),
        )
        .toList();
    for (var index = 1; index < sequences.length; index++) {
      expect(sequences[index], greaterThan(sequences[index - 1]));
    }
    expect(
      ByteData.sublistView(launcher.packets.first.$2)
          .getUint64(24, Endian.little),
      42,
    );
    await session.close();
    await launcher.stop();
  });

  test('sends at once on update', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    final before = DateTime.now();
    session.update(PadState()..buttons = PadButton.cross);
    await waitFor(
      () => launcher.packets.any(
        (packet) =>
            ByteData.sublistView(packet.$2).getUint32(32, Endian.little) ==
            PadButton.cross,
      ),
    );
    final first = launcher.packets.firstWhere(
      (packet) =>
          ByteData.sublistView(packet.$2).getUint32(32, Endian.little) ==
          PadButton.cross,
    );
    expect(first.$1.difference(before).inMilliseconds, lessThan(5));
    await session.close();
    await launcher.stop();
  });

  test(
    'on a cable the pad and its answers go on the control channel',
    () async {
      final launcher = FakeLauncher(echo: true);
      await launcher.start();
      final session = Session(preferences: preferences, deviceName: 'iPhone');
      await session.connect(
        InternetAddress.loopbackIPv4,
        launcher.port,
        cable: true,
      );
      await waitFor(() => session.status == ConnectionStatus.connected);
      await waitFor(() => launcher.channelPackets.length >= 5);
      await waitFor(() => session.latencyMs != null);
      expect(launcher.packets, isEmpty);
      expect(
        ByteData.sublistView(launcher.channelPackets.first)
            .getUint64(24, Endian.little),
        42,
      );
      await session.close();
      await launcher.stop();
    },
  );

  test('measures latency from echoes', () async {
    final launcher = FakeLauncher(echo: true);
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    await waitFor(() => session.latencyMs != null);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(session.latencyMs, inInclusiveRange(1, 15));
    await session.close();
    await launcher.stop();
  });

  test('sends a released pad after the session comes back', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    session.update(PadState()..buttons = PadButton.r2);
    final port = launcher.port;
    await launcher.stop();
    await waitFor(() => session.status != ConnectionStatus.connected);
    final again = FakeLauncher();
    await again.start(port: port);
    await waitFor(
      () => session.status == ConnectionStatus.connected,
      timeout: const Duration(seconds: 4),
    );
    await waitFor(() => again.packets.isNotEmpty);
    expect(
      again.packets.map((packet) => buttonsOf(packet.$2)),
      everyElement(0),
    );
    await session.close();
    await again.stop();
  });

  test('a busy launcher is tried again', () async {
    final launcher = FakeLauncher(refuseFirst: 'busy');
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(
      () => session.status == ConnectionStatus.connected,
      timeout: const Duration(seconds: 4),
    );
    expect(launcher.hellos.length, 2);
    await session.close();
    await launcher.stop();
  });

  test('a refusal can be tried again', () async {
    final launcher = FakeLauncher(refuseFirst: 'denied');
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.rejected);
    session.retry();
    await waitFor(
      () => session.status == ConnectionStatus.connected,
      timeout: const Duration(seconds: 4),
    );
    await session.close();
    await launcher.stop();
  });

  test('a second connect replaces the first', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final dead = unused.port;
    await unused.close();
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    final seen = <ConnectionStatus>[];
    session.addListener(() => seen.add(session.status));
    unawaited(session.connect(InternetAddress.loopbackIPv4, dead));
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(session.status, ConnectionStatus.connected);
    expect(seen, isNot(contains(ConnectionStatus.rejected)));
    expect(launcher.hellos.length, 1);
    await session.close();
    await launcher.stop();
  });

  test('follows the launcher to a new port', () async {
    final first = FakeLauncher();
    await first.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, first.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    await first.stop();
    await waitFor(() => session.status != ConnectionStatus.connected);
    final moved = FakeLauncher();
    await moved.start();
    await session.connect(InternetAddress.loopbackIPv4, moved.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    await session.close();
    await moved.stop();
  });

  test('tells its listeners a few times a second at most', () async {
    final launcher = FakeLauncher(echo: true);
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    await waitFor(() => session.latencyMs != null);
    var told = 0;
    session.addListener(() => told++);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(told, lessThanOrEqualTo(5));
    await session.close();
    await launcher.stop();
  });

  test('reconnects after the server restarts', () async {
    final launcher = FakeLauncher(askFirst: true);
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    final port = launcher.port;
    await launcher.stop();
    await waitFor(() => session.status != ConnectionStatus.connected);
    final again = FakeLauncher(askFirst: true);
    await again.start(port: port);
    final seen = <ConnectionStatus>[];
    session.addListener(() => seen.add(session.status));
    await waitFor(
      () => session.status == ConnectionStatus.connected,
      timeout: const Duration(seconds: 4),
    );
    expect(seen, isNot(contains(ConnectionStatus.pairing)));
    expect(again.hellos.single['key'], 'c3RvcmVkLWtleQ==');
    await session.close();
    await again.stop();
  });

  Map<String, dynamic> library(String art, {String? running}) => {
    'type': 'library',
    'games': [
      {
        'id': '/Games/DOOM',
        'name': 'DOOM',
        'state': 'installed',
        'trophies': '1/20',
        'art': art,
      },
    ],
    'selected': '/Games/DOOM',
    'running': running,
    'language': 'tr',
  };

  test('keeps the library and asks only for pictures it lacks', () async {
    final launcher = FakeLauncher()..library = library('a');
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.art['/Games/DOOM']?.icon != null);
    expect(session.library!.games.single.name, 'DOOM');
    expect(session.library!.language, 'tr');
    expect(session.art['/Games/DOOM']!.icon, [1, 2, 3]);
    expect(session.art['/Games/DOOM']!.background, isNull);
    expect(launcher.received.where((m) => m['type'] == 'wantArt').length, 1);
    launcher.tell(library('a', running: '/Games/DOOM'));
    await waitFor(() => session.library!.running == '/Games/DOOM');
    launcher.tell(library('b'));
    await waitFor(
      () => launcher.received.where((m) => m['type'] == 'wantArt').length == 2,
    );
    await session.close();
    await launcher.stop();
  });

  test('a paused pad lets go once and then stays quiet', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    session.update(PadState()..buttons = PadButton.cross);
    await waitFor(
      () => launcher.packets.any((p) => buttonsOf(p.$2) == PadButton.cross),
    );
    session.pausePad();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final count = launcher.packets.length;
    expect(buttonsOf(launcher.packets.last.$2), 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(launcher.packets.length, count);
    session.resumePad();
    await waitFor(() => launcher.packets.length > count + 3);
    await session.close();
    await launcher.stop();
  });

  test('sends what the launcher mode asks for', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    session.send(const Launch('/Games/DOOM'));
    session.send(const Command('left'));
    await waitFor(() => launcher.received.length == 2);
    expect(launcher.received[0], {'type': 'launch', 'id': '/Games/DOOM'});
    expect(launcher.received[1], {'type': 'command', 'name': 'left'});
    await session.close();
    await launcher.stop();
  });

  test('a layout edit goes to the launcher for the game', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    session.send(const SaveLayout('/Games/DOOM', '{"cross":{"hidden":true}}'));
    session.send(const SaveLayout('/Games/DOOM', null));
    await waitFor(() => launcher.received.length == 2);
    expect(launcher.received[0], {
      'type': 'saveLayout',
      'id': '/Games/DOOM',
      'layout': '{"cross":{"hidden":true}}',
    });
    expect(launcher.received[1], {
      'type': 'saveLayout',
      'id': '/Games/DOOM',
      'layout': null,
    });
    await session.close();
    await launcher.stop();
  });

  test('the launcher\'s theme is worn and kept for next time', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    launcher.tell({
      'type': 'look',
      'deep': '#0A0014',
      'middle': '#4A0E6B',
      'accent': '#FF4FD8',
    });
    await waitFor(() => session.look.value != null);
    expect(session.look.value!.accent, const Color(0xFFFF4FD8));
    expect(session.look.value!.middle, const Color(0xFF4A0E6B));
    await session.close();
    await launcher.stop();
    final later = Session(preferences: preferences, deviceName: 'Pixel 8');
    expect(later.look.value?.deep, const Color(0xFF0A0014));
  });

  test('Remote Play: the picture asked for comes to the player', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    final player = FakePlayer();
    session.player = player;
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    session.startStream(1280, 720);
    await waitFor(
      () => launcher.received.any((message) => message['type'] == 'stream'),
    );
    expect(
      launcher.received.lastWhere((message) => message['type'] == 'stream'),
      {'type': 'stream', 'on': true, 'width': 1280, 'height': 720},
    );
    await waitFor(() => launcher.padFrom != null);
    final (address, port) = launcher.padFrom!;
    for (final part in pieces(List.filled(2000, 7), number: 1, key: true)) {
      launcher.udp.send(part, address, port);
    }
    await waitFor(() => player.frames.isNotEmpty);
    expect(player.frames.single.data, hasLength(2000));
    // A frame starting from nothing but a non-key frame asks for a key frame.
    for (final part in pieces([1, 2, 3], number: 3)) {
      launcher.udp.send(part, address, port);
    }
    await waitFor(
      () => launcher.received.any((message) => message['type'] == 'keyFrame'),
    );
    session.stopStream();
    await waitFor(
      () =>
          launcher.received.last['type'] == 'stream' &&
          launcher.received.last['on'] == false,
    );
    await session.close();
    await launcher.stop();
  });

  test('Remote Play on a cable comes on the control channel', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'iPhone');
    final player = FakePlayer();
    session.player = player;
    await session.connect(
      InternetAddress.loopbackIPv4,
      launcher.port,
      cable: true,
    );
    await waitFor(() => session.status == ConnectionStatus.connected);
    session.startStream(1280, 720);
    await waitFor(
      () => launcher.received.any((message) => message['type'] == 'stream'),
    );
    for (final part in pieces(List.filled(1500, 9), number: 1, key: true)) {
      launcher.sockets.last.add(part);
    }
    final sound = Uint8List(16 + 960);
    ByteData.sublistView(sound)
      ..setUint32(0, audioMagic, Endian.little)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 16, Endian.little);
    launcher.sockets.last.add(sound);
    await waitFor(() => player.frames.isNotEmpty && player.sounds.isNotEmpty);
    expect(player.sounds.single.samples, hasLength(960));
    await session.close();
    await launcher.stop();
  });

  test(
    'the Mac asking to be signed in waits for the phone to approve',
    () async {
      final together = FakeTogether();
      await together.start();
      together.answer = (method, path, body) =>
          path == '/api/v1/auth/email/verify'
          ? (200, FakeTogether.tokens())
          : (204, {});
      final launcher = FakeLauncher();
      await launcher.start();
      final session = Session(
        preferences: preferences,
        deviceName: 'Pixel 8',
        together: TogetherAccount(
          preferences: preferences,
          base: together.base,
          clientName: 'test',
        ),
      );
      await session.together.startEmail('u@example.com');
      await session.together.verifyEmail('123456');
      await session.connect(InternetAddress.loopbackIPv4, launcher.port);
      await waitFor(() => session.status == ConnectionStatus.connected);
      launcher.tell({
        'type': 'togetherHandoff',
        'id': 'h1',
        'deviceName': 'MacBook',
      });
      await waitFor(() => session.handoffAsked.value != null);
      expect(session.handoffAsked.value!.deviceName, 'MacBook');
      await session.answerHandoff(session.handoffAsked.value!, approve: true);
      expect(together.requests.last.$2, '/api/v1/auth/handoff/h1/approve');
      await waitFor(() => launcher.received.isNotEmpty);
      expect(launcher.received.last, {
        'type': 'togetherHandoffAnswer',
        'id': 'h1',
        'approved': true,
      });
      expect(session.handoffAsked.value, isNull);
      await session.close();
      await launcher.stop();
      await together.http.close(force: true);
    },
  );

  test('the phone signs in with the Mac\'s account, and stops when the Mac says no', () async {
    final together = FakeTogether();
    await together.start();
    together.answer = (method, path, body) =>
        path == '/api/v1/auth/handoff/start'
        ? (201, {'handoffId': 'h2', 'secret': 's' * 43, 'expiresIn': 300})
        : (
            400,
            {'code': 'authorization_pending', 'status': 400, 'title': 'wait'},
          );
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(
      preferences: preferences,
      deviceName: 'Pixel 8',
      together: TogetherAccount(
        preferences: preferences,
        base: together.base,
        clientName: 'test',
      ),
    );
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    final signingIn = session.signInWithMac(
      every: const Duration(milliseconds: 10),
    );
    await waitFor(() => launcher.received.isNotEmpty);
    expect(launcher.received.last, {
      'type': 'togetherHandoff',
      'id': 'h2',
      'deviceName': 'Pixel 8',
    });
    launcher.tell({
      'type': 'togetherHandoffAnswer',
      'id': 'h2',
      'approved': false,
    });
    await expectLater(signingIn, throwsA(isA<TogetherCancelled>()));
    await session.close();
    await launcher.stop();
    await together.http.close(force: true);
  });

  test('a trophy from the launcher is kept to show', () async {
    final launcher = FakeLauncher();
    await launcher.start();
    final session = Session(preferences: preferences, deviceName: 'Pixel 8');
    await session.connect(InternetAddress.loopbackIPv4, launcher.port);
    await waitFor(() => session.status == ConnectionStatus.connected);
    launcher.tell({
      'type': 'trophy',
      'name': 'Bound',
      'detail': 'Bind your first Silk Skill',
      'grade': 'bronze',
      'icon': null,
    });
    await waitFor(() => session.trophy.value != null);
    expect(session.trophy.value!.name, 'Bound');
    expect(session.trophy.value!.grade, 'bronze');
    expect(session.trophy.value!.icon, isNull);
    await session.close();
    await launcher.stop();
  });

  test(
    'what the launcher is doing is kept, counting from when it began',
    () async {
      final launcher = FakeLauncher();
      await launcher.start();
      final session = Session(preferences: preferences, deviceName: 'Pixel 8');
      await session.connect(InternetAddress.loopbackIPv4, launcher.port);
      await waitFor(() => session.status == ConnectionStatus.connected);
      launcher.tell({
        'type': 'activity',
        'activity': {
          'id': '/Games/Cat',
          'phase': 'relink',
          'updating': true,
          'fraction': 0.5,
          'elapsed': 30,
        },
      });
      await waitFor(() => session.activity.value != null);
      final first = session.activity.value!;
      expect(first.activity.phase, ActivityPhase.relink);
      expect(first.activity.fraction, 0.5);
      expect(
        DateTime.now().difference(first.since).inSeconds,
        inInclusiveRange(29, 31),
      );
      launcher.tell({
        'type': 'activity',
        'activity': {
          'id': '/Games/Cat',
          'phase': 'starting',
          'updating': true,
          'fraction': null,
          'elapsed': 45,
        },
      });
      await waitFor(
        () => session.activity.value?.activity.phase == ActivityPhase.starting,
      );
      expect(
        session.activity.value!.since,
        first.since,
        reason: 'the count does not jump',
      );
      launcher.tell({'type': 'activity', 'activity': null});
      await waitFor(() => session.activity.value == null);
      await session.close();
      await launcher.stop();
    },
  );
}
