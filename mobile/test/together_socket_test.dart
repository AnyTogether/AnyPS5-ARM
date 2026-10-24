import 'dart:io';
import 'dart:math';

import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/together/together_socket.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

void main() {
  // The hub listens to the app's lifecycle; the real network stays, for the local server.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late FakeServer server;
  final sockets = <TogetherSocket>[];

  setUp(() async {
    server = FakeServer();
    await server.start();
  });

  tearDown(() async {
    for (final socket in sockets) {
      socket.dispose();
    }
    sockets.clear();
    await server.stop();
  });

  Future<TogetherSocket> socket({String access = 'access-1'}) async {
    final made = TogetherSocket(
      account: await server.account(access: access),
      retryBase: const Duration(milliseconds: 20),
      retryMost: const Duration(milliseconds: 80),
      random: Random(1),
    );
    sockets.add(made);
    return made;
  }

  test('the gateway is /rt on the API host', () async {
    final live = await socket();
    expect(live.gateway.toString(), 'ws://127.0.0.1:${server.http.port}/rt');
  });

  test(
    'hello carries the access token, and heartbeats say the phone is online',
    () async {
      server.heartbeat = 0.02;
      final live = await socket();
      final events = <String>[];
      live.events.listen((event) => events.add(event.type));
      live.start();
      await until(() => live.status == SocketStatus.ready);
      expect(server.sent('hello').single, {
        'op': 'hello',
        'token': 'access-1',
        'client': 'remote-ios/test',
      });
      expect(live.session, 'device-1');
      expect(events, ['live.ready']);
      await until(() => server.sent('heartbeat').length >= 2);
      expect(server.sent('heartbeat').first, {
        'op': 'heartbeat',
        'presence': {'state': 'online'},
      });
    },
  );

  test('events reach the listeners with their data', () async {
    final live = await socket();
    final events = <TogetherEvent>[];
    live.events.listen(events.add);
    live.start();
    await until(() => live.status == SocketStatus.ready);
    server.push('friend.request', {'userId': 'u2', 'handle': 'ece'});
    await until(() => events.length == 2);
    expect(events.last.type, 'friend.request');
    expect(events.last.json['handle'], 'ece');
  });

  test(
    'a dropped socket comes back and resumes after the last API event',
    () async {
      final live = await socket();
      live.start();
      await until(() => live.status == SocketStatus.ready);
      final kept = server.push('message.created', {'seq': 1});
      // A signal's id is not one the gateway can resume from.
      server.push('signal', {'kind': 'offer'}, id: '1729-abc123');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await server.sockets.last.close(1011, 'try again');
      await until(() => server.sent('hello').length == 2);
      expect(server.sent('hello').last['resume'], kept);
      await until(() => live.status == SocketStatus.ready);
    },
  );

  test(
    '4003 means signed out elsewhere: forgotten, and no reconnect',
    () async {
      final live = await socket();
      live.start();
      await until(() => live.status == SocketStatus.ready);
      await server.sockets.last.close(TogetherSocket.signedOut, 'signed out');
      await until(() => live.status == SocketStatus.signedOut);
      expect(live.account.user, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.sent('hello'), hasLength(1));
    },
  );

  test('4001 gets a fresh token before the next hello', () async {
    server.answer = (method, path, body) => path == '/api/v1/auth/token'
        ? (
            200,
            {
              'accessToken': 'access-2',
              'expiresIn': 900,
              'refreshToken': 'refresh-2',
              'user': {'id': 'me', 'handle': 'utku', 'displayName': 'Utku'},
            },
          )
        : (404, {});
    final live = await socket();
    live.start();
    await until(() => live.status == SocketStatus.ready);
    await server.sockets.last.close(TogetherSocket.unauthorized, 'bad token');
    await until(
      () => server.sent('hello').any((hello) => hello['token'] == 'access-2'),
    );
    expect(server.requests.single.$3, {
      'grantType': 'refresh_token',
      'refreshToken': 'refresh-1',
    });
  });

  test('stopping closes the socket and sends nothing more', () async {
    final live = await socket();
    live.start();
    await until(() => live.status == SocketStatus.ready);
    live.stop();
    expect(live.status, SocketStatus.offline);
    expect(live.send({'op': 'heartbeat'}), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.sent('hello'), hasLength(1));
  });

  test(
    'the hub keeps the socket open while signed in, and closes it on sign-out',
    () async {
      server.answer = (method, path, body) => (204, null);
      final hub = TogetherHub(account: await server.account());
      addTearDown(hub.dispose);
      await until(() => hub.socket.status == SocketStatus.ready);
      await hub.account.signOut();
      expect(hub.socket.status, SocketStatus.offline);
      await until(() => server.sockets.single.closeCode != null);
    },
  );
}
