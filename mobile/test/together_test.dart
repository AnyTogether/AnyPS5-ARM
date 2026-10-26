import 'dart:convert';
import 'dart:io';

import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AnyTogether's API, scripted: answers by method and path, keeps what it was asked.
class FakeTogether {
  late HttpServer http;
  final requests =
      <
        (
          String method,
          String path,
          Map<String, String> headers,
          Map<String, dynamic>? body,
        )
      >[];
  (int, Map<String, dynamic>) Function(
    String method,
    String path,
    Map<String, dynamic>? body,
  )
  answer = (_, _, _) =>
      (404, {'code': 'not_found', 'status': 404, 'title': 'no'});

  Uri get base => Uri.parse('http://127.0.0.1:${http.port}');

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      final text = await utf8.decodeStream(request);
      final body = text.isEmpty
          ? null
          : jsonDecode(text) as Map<String, dynamic>;
      final headers = <String, String>{};
      request.headers.forEach(
        (name, values) => headers[name] = values.join(','),
      );
      requests.add((request.method, request.uri.path, headers, body));
      final (status, json) = answer(request.method, request.uri.path, body);
      request.response.statusCode = status;
      if (status != 204) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(json));
      }
      await request.response.close();
    });
  }

  static Map<String, dynamic> tokens({
    String access = 'access-1',
    int expiresIn = 900,
  }) => {
    'accessToken': access,
    'expiresIn': expiresIn,
    'refreshToken': 'refresh-1',
    'user': {
      'id': 'u1',
      'handle': 'utku',
      'displayName': 'Utku',
      'avatar': null,
    },
  };
}

void main() {
  late FakeTogether server;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    server = FakeTogether();
    await server.start();
  });

  tearDown(() => server.http.close(force: true));

  TogetherAccount account() => TogetherAccount(
    preferences: preferences,
    base: server.base,
    clientName: 'remote-ios/1.9.1',
  );

  test(
    'client_too_old tells the app to update, with the minimum and where',
    () async {
      server.answer = (method, path, body) => (
        426,
        {
          'code': 'client_too_old',
          'status': 426,
          'title': 'This version is too old. Update to 1.17.0 or newer.',
          'client': 'phone',
          'current': '1.9.1',
          'minimum': '1.17.0',
          'downloadUrl': 'https://anytogether.test/download',
        },
      );
      final phone = account();
      expect(phone.tooOld.value, isNull);
      await expectLater(
        phone.startEmail('u@example.com'),
        throwsA(
          isA<TogetherProblem>().having(
            (p) => p.code,
            'code',
            'client_too_old',
          ),
        ),
      );
      expect(phone.tooOld.value?.minimum, '1.17.0');
      expect(phone.tooOld.value?.current, '1.9.1');
      expect(
        phone.tooOld.value?.downloadUrl,
        Uri.parse('https://anytogether.test/download'),
      );
      // Another refusal is not an update.
      final other = account();
      server.answer = (method, path, body) =>
          (409, {'code': 'conflict', 'status': 409, 'title': 'x'});
      await expectLater(
        other.startEmail('u@example.com'),
        throwsA(isA<TogetherProblem>()),
      );
      expect(other.tooOld.value, isNull);
    },
  );

  test('a hand-off goes to the launcher and back as JSON', () {
    const ask = TogetherHandoff(id: 'h1', deviceName: "Utku's iPhone");
    final json = jsonDecode(ask.toJson()) as Map<String, dynamic>;
    expect(json, {
      'type': 'togetherHandoff',
      'id': 'h1',
      'deviceName': "Utku's iPhone",
    });
    expect(
      Message.fromJson(ask.toJson()),
      isA<TogetherHandoff>().having(
        (m) => m.deviceName,
        'deviceName',
        "Utku's iPhone",
      ),
    );
    const answer = TogetherHandoffAnswer(id: 'h1', approved: true);
    expect(
      Message.fromJson(answer.toJson()),
      isA<TogetherHandoffAnswer>().having((m) => m.approved, 'approved', true),
    );
  });

  test(
    'an email code signs in and the session is kept for next time',
    () async {
      server.answer = (method, path, body) => switch (path) {
        '/api/v1/auth/email/start' => (202, {}),
        '/api/v1/auth/email/verify' => (200, FakeTogether.tokens()),
        _ => (404, {}),
      };
      final first = account();
      await first.startEmail('u@example.com');
      expect(first.step, isA<CodeSent>());
      await first.verifyEmail('123456');
      expect(first.user?.handle, 'utku');
      expect(server.requests[1].$4, {
        'email': 'u@example.com',
        'code': '123456',
      });
      expect(
        server.requests.first.$3['anytogether-client'],
        'remote-ios/1.9.1',
      );
      expect(account().user?.handle, 'utku');
    },
  );

  test('a wrong code says so with its code', () async {
    server.answer = (method, path, body) => switch (path) {
      '/api/v1/auth/email/start' => (202, {}),
      _ => (
        400,
        {
          'code': 'code_invalid',
          'status': 400,
          'title': 'That code is not right',
        },
      ),
    };
    final signingIn = account();
    await signingIn.startEmail('u@example.com');
    await expectLater(
      signingIn.verifyEmail('000000'),
      throwsA(
        isA<TogetherProblem>().having((p) => p.code, 'code', 'code_invalid'),
      ),
    );
    expect(signingIn.user, isNull);
  });

  test('a hand-off waits until the Mac approves it', () async {
    var polls = 0;
    server.answer = (method, path, body) {
      if (path == '/api/v1/auth/handoff/start') {
        return (201, {'handoffId': 'h1', 'secret': 's' * 43, 'expiresIn': 300});
      }
      if (path == '/api/v1/auth/token') {
        polls++;
        return polls < 3
            ? (
                400,
                {
                  'code': 'authorization_pending',
                  'status': 400,
                  'title': 'wait',
                },
              )
            : (200, FakeTogether.tokens());
      }
      return (404, {});
    };
    final signingIn = account();
    final handoff = await signingIn.startHandoff("Utku's iPhone");
    expect(handoff.id, 'h1');
    final user = await signingIn.waitForApproval(
      handoff,
      every: const Duration(milliseconds: 10),
    );
    expect(user.handle, 'utku');
    expect(polls, 3);
    expect(server.requests.last.$4, {
      'grantType': 'handoff',
      'handoffId': 'h1',
      'secret': 's' * 43,
    });
  });

  test('a turned down hand-off stops waiting', () async {
    server.answer = (method, path, body) => path == '/api/v1/auth/handoff/start'
        ? (201, {'handoffId': 'h1', 'secret': 's' * 43, 'expiresIn': 300})
        : (
            400,
            {'code': 'authorization_pending', 'status': 400, 'title': 'wait'},
          );
    final signingIn = account();
    final handoff = await signingIn.startHandoff("Utku's iPhone");
    final waiting = signingIn.waitForApproval(
      handoff,
      every: const Duration(milliseconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    signingIn.cancel();
    await expectLater(waiting, throwsA(isA<TogetherCancelled>()));
    expect(signingIn.step, isA<Idle>());
  });

  test('signed in, the phone approves the Mac with its session', () async {
    server.answer = (method, path, body) => path == '/api/v1/auth/email/verify'
        ? (200, FakeTogether.tokens())
        : (204, {});
    final signedIn = account();
    await signedIn.startEmail('u@example.com');
    await signedIn.verifyEmail('123456');
    await signedIn.approveHandoff('h9');
    final approve = server.requests.last;
    expect(
      (approve.$1, approve.$2),
      ('POST', '/api/v1/auth/handoff/h9/approve'),
    );
    expect(approve.$3['authorization'], 'Bearer access-1');
  });

  test('an expired access token is refreshed before the call', () async {
    server.answer = (method, path, body) => switch (path) {
      '/api/v1/auth/email/verify' => (200, FakeTogether.tokens(expiresIn: 0)),
      '/api/v1/auth/token' => (200, FakeTogether.tokens(access: 'access-2')),
      _ => (204, {}),
    };
    final signedIn = account();
    await signedIn.startEmail('u@example.com');
    await signedIn.verifyEmail('123456');
    await signedIn.approveHandoff('h9');
    expect(server.requests.last.$3['authorization'], 'Bearer access-2');
    expect(
      server.requests.where((r) => r.$2 == '/api/v1/auth/token').single.$4,
      {'grantType': 'refresh_token', 'refreshToken': 'refresh-1'},
    );
  });

  test('signing out tells the server and forgets', () async {
    server.answer = (method, path, body) => path == '/api/v1/auth/email/verify'
        ? (200, FakeTogether.tokens())
        : (204, {});
    final signedIn = account();
    await signedIn.startEmail('u@example.com');
    await signedIn.verifyEmail('123456');
    await signedIn.signOut();
    expect(signedIn.user, isNull);
    expect(server.requests.last.$2, '/api/v1/auth/logout');
    expect(account().user, isNull);
  });

  test('a server address is https, or http on the home network', () {
    expect(
      serverAddress(' https://together.example.org/ '),
      Uri.parse('https://together.example.org'),
    );
    expect(serverAddress('https://together.example.org:8443')?.port, 8443);
    for (final local in [
      'http://localhost:3000',
      'http://127.0.0.1:8080',
      'http://192.168.1.20',
      'http://10.0.0.5',
      'http://172.20.1.1',
      'http://nas.local',
    ]) {
      expect(serverAddress(local), isNotNull, reason: local);
    }
    for (final refused in [
      'http://together.example.org',
      'http://172.32.0.1',
      'http://8.8.8.8',
      'ftp://together.example.org',
      'together.example.org',
      'https://user@together.example.org',
      'https://together.example.org/?a=1',
      '',
    ]) {
      expect(serverAddress(refused), isNull, reason: refused);
    }
  });

  test('another server signs out of this one first and is kept', () async {
    server.answer = (method, path, body) => path == '/api/v1/auth/email/verify'
        ? (200, FakeTogether.tokens())
        : (204, {});
    SharedPreferences.setMockInitialValues({
      'together.server': server.base.toString(),
    });
    preferences = await SharedPreferences.getInstance();
    final chosen = TogetherAccount(
      preferences: preferences,
      clientName: 'remote-ios/1.9.1',
    );
    expect(chosen.base, server.base);
    expect(chosen.serverFixed, isFalse);
    await chosen.startEmail('u@example.com');
    await chosen.verifyEmail('123456');
    await chosen.useServer(Uri.parse('https://together.example.org'));
    expect(server.requests.last.$2, '/api/v1/auth/logout');
    expect(chosen.user, isNull);
    expect(chosen.base.host, 'together.example.org');
    expect(
      TogetherAccount(preferences: preferences, clientName: 'x').base.host,
      'together.example.org',
    );
    await chosen.useServer(standardServer);
    expect(preferences.getString('together.server'), isNull);
  });

  test('the launcher may say which server it uses', () {
    final welcome = Message.fromJson(
      '{"type":"welcome","session":"1","udpPort":2,"macName":"Mac","key":"k",'
      '"togetherServer":"https://together.example.org"}',
    );
    expect(
      welcome,
      isA<Welcome>().having(
        (w) => w.togetherServer,
        'togetherServer',
        'https://together.example.org',
      ),
    );
  });
}
