import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anyps5_remote/together/notifications.dart';
import 'package:anyps5_remote/together/push.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// The phone's own push code, as a test wants it: a token or none, the permission, the answer
/// to the system's question, and taps.
class FakePushChannel implements PushChannel {
  FakePushChannel({
    this.platform = 'fcm',
    this.given,
    this.allowed = PushPermission.undetermined,
    this.answer = true,
  });

  @override
  final String platform;
  PushToken? given;
  PushPermission allowed;
  bool answer;
  int asked = 0;
  final badges = <int>[];
  final cleared = <String>[];
  Map<Object?, Object?>? launch;
  final _taps = StreamController<Map<Object?, Object?>>.broadcast();
  final _renewed = StreamController<String>.broadcast();

  void tap(Map<Object?, Object?> payload) => _taps.add(payload);
  void renew(String token) => _renewed.add(token);

  @override
  Future<PushToken?> token() async => given;

  @override
  Future<PushPermission> permission() async => allowed;

  @override
  Future<bool> ask() async {
    asked++;
    allowed = answer ? PushPermission.granted : PushPermission.denied;
    return answer;
  }

  @override
  Future<Map<Object?, Object?>?> launchedWith() async => launch;

  @override
  Stream<Map<Object?, Object?>> get taps => _taps.stream;

  @override
  Stream<String> get renewed => _renewed.stream;

  @override
  Future<void> clearCall(String callId) async => cleared.add(callId);

  @override
  Future<void> badge(int count) async => badges.add(count);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late TogetherHub hub;
  Map<String, dynamic>? native;

  Future<void> start(FakePushChannel channel) async {
    hub = TogetherHub(account: await server.account(), pushChannel: channel);
    await until(() => hub.socket.status.name == 'ready');
  }

  setUp(() async {
    HttpOverrides.global = null;
    native = {'apns': ['org.anyps5.anyps5Remote'], 'fcm': true};
    server = FakeServer();
    server.answer = (method, path, body) => switch ((method, path)) {
      ('GET', '/api/v1/me/notifications/settings') => (
        200,
        {
          'settings': {'pushPreview': true, 'pushCalls': true},
          'push': null,
          'native': native,
          'canMail': true,
        },
      ),
      ('GET', '/api/v1/me/notifications/unread') => (200, {'unread': 0}),
      ('POST', '/api/v1/me/push/device') => (201, {'id': 'd1'}),
      _ => (204, null),
    };
    await server.start();
  });

  tearDown(() async {
    hub.dispose();
    await server.stop();
  });

  Iterable<(String, String, Map<String, dynamic>?)> pushCalls() =>
      server.requests.where((r) => r.$2.startsWith('/api/v1/me/push'));

  test('a build that cannot get a token asks the server nothing', () async {
    await start(FakePushChannel());
    await hub.push.start();
    expect(hub.push.available, isFalse);
    expect(
      server.requests.where((r) => r.$2 == '/api/v1/me/notifications/settings'),
      isEmpty,
    );
  });

  test('allowed already: the token goes to the server by itself', () async {
    final channel = FakePushChannel(
      given: const PushToken(token: 'fcm-1'),
      allowed: PushPermission.granted,
    );
    await start(channel);
    await until(() => hub.push.registered);
    expect(pushCalls().single.$3, {
      'platform': 'fcm',
      'token': 'fcm-1',
      'lang': 'en',
    });
    expect(channel.asked, 0);
    // A renewed token is sent again.
    channel.renew('fcm-2');
    await until(() => pushCalls().length == 2);
    expect(pushCalls().last.$3?['token'], 'fcm-2');
  });

  test('an iPhone app the server does not push to has no push', () async {
    native = {'apns': ['org.anyps5.anyps5Remote'], 'fcm': false};
    await start(
      FakePushChannel(
        platform: 'apns',
        given: const PushToken(token: 'ab12', app: 'com.altstore.resigned'),
        allowed: PushPermission.granted,
      ),
    );
    await hub.push.start();
    expect(hub.push.available, isFalse);
    expect(pushCalls(), isEmpty);
  });

  test(
    'asked only after reaching out; not now waits a week, and three times is enough',
    () async {
      var now = DateTime(2026, 11, 6);
      final channel = FakePushChannel(
        platform: 'apns',
        given: const PushToken(
          token: 'ab12',
          app: 'org.anyps5.anyps5Remote',
          sandbox: true,
        ),
      );
      await start(channel);
      await until(() => hub.push.available);
      // Never at the start.
      expect(hub.push.offering, isFalse);
      final push = PhonePush(
        account: hub.account,
        notifications: hub.notifications,
        channel: channel,
        clock: () => now,
      );
      await push.start();
      push.reachedOut();
      expect(push.offering, isTrue);
      await push.notNow();
      push.reachedOut();
      expect(push.offering, isFalse, reason: 'within the week');
      now = now.add(const Duration(days: 8));
      push.reachedOut();
      expect(push.offering, isTrue);
      await push.notNow();
      now = now.add(const Duration(days: 8));
      push.reachedOut();
      await push.notNow();
      now = now.add(const Duration(days: 8));
      push.reachedOut();
      expect(push.offering, isFalse, reason: 'three times is enough');
      push.dispose();
    },
  );

  test('turning on asks the phone, then registers; off takes it back', () async {
    final channel = FakePushChannel(
      platform: 'apns',
      given: const PushToken(
        token: 'ab12',
        app: 'org.anyps5.anyps5Remote',
        sandbox: true,
      ),
    );
    await start(channel);
    await until(() => hub.push.available);
    hub.friends.onReachOut!();
    expect(hub.push.offering, isTrue);
    expect(await hub.push.turnOn(), isTrue);
    expect(channel.asked, 1);
    expect(hub.push.registered, isTrue);
    expect(pushCalls().single.$3, {
      'platform': 'apns',
      'token': 'ab12',
      'app': 'org.anyps5.anyps5Remote',
      'sandbox': true,
      'lang': 'en',
    });
    await hub.push.turnOff();
    expect(hub.push.registered, isFalse);
    expect(pushCalls().last.$1, 'DELETE');
    expect(pushCalls().last.$3, {'token': 'ab12'});
    // Off by choice: the next start does not register again, nor offer.
    await hub.push.start();
    hub.push.reachedOut();
    expect(hub.push.offering, isFalse);
    expect(pushCalls().where((r) => r.$1 == 'POST'), hasLength(1));
  });

  test('the phone saying no registers nothing', () async {
    final channel = FakePushChannel(
      given: const PushToken(token: 'fcm-1'),
      answer: false,
    );
    await start(channel);
    await until(() => hub.push.available);
    expect(await hub.push.turnOn(), isFalse);
    expect(hub.push.permission, PushPermission.denied);
    expect(pushCalls(), isEmpty);
    hub.push.reachedOut();
    expect(hub.push.offering, isFalse);
  });

  test('taps open a notification or a call', () async {
    final channel = FakePushChannel(
      given: const PushToken(token: 'fcm-1'),
      allowed: PushPermission.granted,
    );
    channel.launch = {
      'kind': 'message',
      'notice': jsonEncode({
        'id': 'n1',
        'kind': 'message',
        'subjectId': 'c1',
        'actor': card('ece', name: 'Ece'),
        'data': {'conversationId': 'c1', 'count': 2},
        'read': false,
        'createdAt': '2026-11-06T10:00:00Z',
        'updatedAt': '2026-11-06T10:00:00Z',
      }),
    };
    final opened = <PushOpen>[];
    await start(channel);
    hub.push.opens.listen(opened.add);
    await until(() => opened.isNotEmpty);
    final notice = (opened.single as NoticeOpened).notice!;
    expect(notice.kind, NoticeKind.message);
    expect(notice.data['conversationId'], 'c1');
    expect(notice.actor!.displayName, 'Ece');

    channel.tap({
      'kind': 'call',
      'callId': 'call-1',
      'caller': jsonEncode(card('can', name: 'Can')),
      'action': 'answer',
    });
    await until(() => opened.length == 2);
    final call = opened.last as CallOpened;
    expect(call.callId, 'call-1');
    expect(call.from.displayName, 'Can');
    expect(call.action, CallAction.answer);
    // Something not ours is left alone.
    channel.tap({'google.message_id': 'x'});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(opened, hasLength(2));
  });

  test('the app icon follows the bell while push is on', () async {
    final channel = FakePushChannel(
      given: const PushToken(token: 'fcm-1'),
      allowed: PushPermission.granted,
    );
    await start(channel);
    await until(() => hub.push.registered);
    server.push('notification.read', {'ids': null, 'unread': 3});
    await until(() => channel.badges.contains(3));
    server.push('notification.read', {'ids': null, 'unread': 0});
    await until(() => channel.badges.last == 0);
  });
}
