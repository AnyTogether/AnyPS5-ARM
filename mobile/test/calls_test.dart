import 'dart:io';

import 'package:anyps5_remote/together/calls.dart';
import 'package:anyps5_remote/together/groups.dart';
import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/parties.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/together/typing.dart';
import 'package:anyps5_remote/ui/call_layer.dart';
import 'package:anyps5_remote/ui/messages_view.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'voice_test.dart' show FakeEngine, offerSdp;

Map<String, dynamic> callView(
  String id, {
  List<Map<String, dynamic>> inCall = const [],
}) => {
  'id': id,
  'kind': 'direct',
  'partyId': null,
  'startedBy': 'ece',
  'calleeId': 'me',
  'in': inCall,
  'startedAt': '2026-10-24T10:00:00Z',
  'answeredAt': null,
  'endedAt': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calls with a friend', () {
    late FakeServer server;
    late TogetherHub hub;
    late List<FakeEngine> engines;
    var answerStatus = 200;
    var deny = false;

    setUp(() async {
      HttpOverrides.global = null;
      answerStatus = 200;
      deny = false;
      engines = [];
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('POST', '/api/v1/calls') => (
          201,
          {
            'call': {
              ...callView('out1'),
              'startedBy': 'me',
              'calleeId': 'ece',
              'in': [
                {'userId': 'me', 'device': 'device-1', 'muted': false},
              ],
            },
            'iceServers': [
              {
                'urls': ['stun:stun.example.org'],
              },
            ],
            'expiresAt': null,
          },
        ),
        ('POST', '/api/v1/calls/in1/answer') =>
          answerStatus == 200
              ? (
                  200,
                  {
                    'call': callView(
                      'in1',
                      inCall: [
                        {'userId': 'ece', 'device': 'dev-ece', 'muted': true},
                        {'userId': 'me', 'device': 'device-1', 'muted': false},
                      ],
                    ),
                    'iceServers': const [],
                    'expiresAt': null,
                  },
                )
              : (
                  409,
                  {
                    'code': 'conflict',
                    'status': 409,
                    'title': 'Answered on another device',
                  },
                ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(
        account: await server.account(),
        voiceEngine: () {
          final engine = FakeEngine(deny: deny);
          engines.add(engine);
          return engine;
        },
      );
      await until(() => hub.socket.session != null);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Calls calls() => hub.calls;
    final ece = Person.fromJson(card('ece', name: 'Ece'));

    void ringing(String id) => server.push('call.ringing', {
      'callId': id,
      'from': card('ece', name: 'Ece'),
      'device': 'dev-ece',
    });

    test(
      'a call rings, and answering offers to the caller\'s device',
      () async {
        ringing('in1');
        await until(() => calls().incoming.isNotEmpty);
        expect(calls().incoming.single.from.displayName, 'Ece');
        // The same ring twice is one call.
        ringing('in1');
        await calls().accept(calls().incoming.single);
        expect(calls().incoming, isEmpty);
        expect(calls().active!.phase, CallPhase.connecting);
        expect(calls().active!.peerMuted, isTrue);
        expect(engines.single.started, isTrue);
        await until(() => server.sent('signal').isNotEmpty);
        final offer = server.sent('signal').single;
        expect(offer['to'], 'ece');
        expect(offer['device'], 'dev-ece');
        expect(offer['call'], 'in1');
        expect(offer['kind'], 'offer');
        // The voice flows: the call is live and counts from now.
        final link = engines.single.links.single;
        link.connectionState = 'connected';
        link.state!();
        expect(calls().active!.phase, CallPhase.live);
        expect(calls().active!.since, isNotNull);
        // The friend unmutes; this phone mutes and the friend is told.
        server.push('call.updated', {
          'callId': 'in1',
          'partyId': null,
          'userId': 'ece',
          'muted': false,
        });
        await until(() => calls().active!.peerMuted == false);
        calls().setMuted(true);
        expect(engines.single.talking, isFalse);
        await until(
          () => server.requests.any((r) => r.$2 == '/api/v1/calls/in1/mute'),
        );
        expect(
          server.requests.lastWhere((r) => r.$2 == '/api/v1/calls/in1/mute').$3,
          {'muted': true},
        );
      },
    );

    test('answered on another device, this one stops ringing', () async {
      ringing('in1');
      await until(() => calls().incoming.isNotEmpty);
      server.push('call.answered', {
        'callId': 'in1',
        'userId': 'me',
        'device': 'other-device',
      });
      await until(() => calls().incoming.isEmpty);
      expect(calls().active, isNull);
    });

    test('an answer too late says it was answered elsewhere', () async {
      answerStatus = 409;
      ringing('in1');
      await until(() => calls().incoming.isNotEmpty);
      await calls().accept(calls().incoming.single);
      expect(calls().active!.phase, CallPhase.ended);
      expect(calls().active!.ended, CallEnd.elsewhere);
      expect(engines.single.stopped, isTrue);
    });

    test('declining tells the server and stops ringing', () async {
      ringing('in1');
      await until(() => calls().incoming.isNotEmpty);
      await calls().decline(calls().incoming.single);
      expect(calls().incoming, isEmpty);
      expect(server.requests.last.$2, '/api/v1/calls/in1/decline');
    });

    test('calling a friend: ringing, answered, then hung up', () async {
      await calls().ring(ece);
      expect(server.requests.firstWhere((r) => r.$2 == '/api/v1/calls').$3, {
        'userId': 'ece',
      });
      expect(calls().active!.id, 'out1');
      expect(calls().active!.phase, CallPhase.calling);
      server.push('call.answered', {
        'callId': 'out1',
        'userId': 'ece',
        'device': 'dev-ece',
      });
      await until(() => calls().active!.phase == CallPhase.connecting);
      // The one who answered offers; this phone answers.
      server.push('signal', {
        'call': 'out1',
        'from': 'ece',
        'device': 'dev-ece',
        'kind': 'offer',
        'data': {'type': 'offer', 'sdp': offerSdp},
      }, id: '17-a');
      await until(() => server.sent('signal').isNotEmpty);
      expect(server.sent('signal').single['kind'], 'answer');
      calls().hangUp();
      expect(calls().active!.phase, CallPhase.ended);
      expect(calls().active!.ended, CallEnd.ended);
      await until(
        () => server.requests.any((r) => r.$2 == '/api/v1/calls/out1/leave'),
      );
      expect(engines.single.stopped, isTrue);
    });

    test('a declined call says so, then goes', () async {
      await calls().ring(ece);
      server.push('call.ended', {
        'callId': 'out1',
        'partyId': null,
        'reason': 'declined',
      });
      await until(() => calls().active?.ended == CallEnd.declined);
      // Shown a moment, then gone.
      await until(
        () => calls().active == null,
        within: const Duration(seconds: 4),
      );
    });

    test('no answer within the time, the caller gives up', () async {
      final quick = Calls(
        account: hub.account,
        socket: hub.socket,
        engine: () => FakeEngine(),
        noAnswerAfter: const Duration(milliseconds: 80),
      );
      addTearDown(quick.dispose);
      await quick.ring(ece);
      await until(() => quick.active?.ended == CallEnd.noAnswer);
      await until(
        () => server.requests.any((r) => r.$2 == '/api/v1/calls/out1/leave'),
      );
    });

    test('no microphone, no call, and the reason', () async {
      deny = true;
      await calls().ring(ece);
      expect(calls().active!.ended, CallEnd.microphone);
      expect(server.requests.where((r) => r.$2 == '/api/v1/calls'), isEmpty);
    });
  });

  group('messages', () {
    late FakeServer server;
    late TogetherHub hub;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/conversations') => (
          200,
          {
            'conversations': [
              {
                'id': 'c1',
                'kind': 'direct',
                'title': null,
                'members': [card('me'), card('ece', name: 'Ece')],
                'lastSeq': 0,
                'readSeq': 0,
                'lastMessage': null,
                'updatedAt': '2026-10-24T10:00:00Z',
              },
            ],
          },
        ),
        ('GET', '/api/v1/me/conversations/unread') => (200, {'messages': 0}),
        ('GET', '/api/v1/conversations/c1/messages?limit=50') => (
          200,
          {'messages': [], 'more': false},
        ),
        ('POST', '/api/v1/conversations/c1/messages') => (
          400,
          {
            'code': 'link_blocked',
            'status': 400,
            'title': 'Links to grabify.link are not allowed',
            'domain': 'grabify.link',
          },
        ),
        ('POST', '/api/v1/conversations') => (
          201,
          {
            'id': 'g1',
            'kind': 'group',
            'title': 'Raid night',
            'members': [card('me'), card('ece'), card('can')],
            'lastSeq': 0,
            'readSeq': 0,
            'lastMessage': null,
            'updatedAt': '2026-10-24T10:00:00Z',
          },
        ),
        ('GET', '/api/v1/conversations/g1/messages?limit=50') => (
          200,
          {'messages': [], 'more': false},
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
      await until(() => hub.messages.loaded);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    test('a blocked link is not sent, says why, and is not retried', () async {
      await hub.messages.show('c1');
      await hub.messages.send('look grabify.link/x');
      final message = hub.messages.thread.single;
      expect(message.failed, isTrue);
      expect(message.problem!.code, 'link_blocked');
      expect(message.problem!.extra!['domain'], 'grabify.link');
      expect(message.refused, isTrue);
    });

    test('a group is made with the friends picked, and shown', () async {
      await hub.messages.startGroup(['ece', 'can'], title: ' Raid night ');
      final asked = server.requests.lastWhere(
        (r) => r.$1 == 'POST' && r.$2 == '/api/v1/conversations',
      );
      expect(asked.$3, {
        'members': ['ece', 'can'],
        'title': 'Raid night',
        'group': true,
      });
      expect(hub.messages.openId, 'g1');
      expect(hub.messages.conversations.first.group, isTrue);
    });

    test('typing shows for a while, and goes when the message comes', () async {
      final typing = Typing(
        account: hub.account,
        socket: hub.socket,
        shownFor: const Duration(milliseconds: 150),
      );
      addTearDown(typing.dispose);
      server.push('typing', {'conversationId': 'c1', 'userId': 'ece'});
      await until(() => typing.who('c1').isNotEmpty);
      expect(typing.who('c1'), ['ece']);
      // One's own typing on another device is not shown.
      server.push('typing', {'conversationId': 'c1', 'userId': 'me'});
      await until(() => typing.who('c1').isEmpty);
      server.push('typing', {'conversationId': 'c1', 'userId': 'ece'});
      await until(() => typing.who('c1').isNotEmpty);
      server.push('message.created', {
        'id': '0190a000-0000-7000-8000-000000000099',
        'conversationId': 'c1',
        'seq': 1,
        'authorId': 'ece',
        'text': 'hi',
        'createdAt': '2026-10-24T10:00:00Z',
      });
      await until(() => typing.who('c1').isEmpty);
    });

    test('saying it is typing goes at most every two seconds', () async {
      hub.typing.typed('c1');
      hub.typing.typed('c1');
      hub.typing.typed('c2');
      await until(() => server.sent('typing').length == 2);
      expect(server.sent('typing').map((f) => f['conversation']), ['c1', 'c2']);
    });
  });

  test('a party shows who in its voice muted themselves', () {
    final party = Party.fromJson({
      'id': 'p1',
      'leaderId': 'me',
      'privacy': 'invite',
      'members': [card('me'), card('ece')],
      'invited': [],
      'call': {
        'id': 'call1',
        'in': ['me', 'ece'],
        'muted': ['ece'],
      },
    });
    expect(party.muted, {'ece'});
    expect(party.copyWith(open: true).muted, {'ece'});
  });

  group('on the phone held sideways', () {
    late TogetherHub hub;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      hub = TogetherHub(
        account: TogetherAccount(
          preferences: await SharedPreferences.getInstance(),
          clientName: 'test',
        ),
      );
    });

    tearDown(() => hub.dispose());

    void sideways(WidgetTester tester) {
      tester.view.physicalSize = const Size(2556, 1179);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    /// The app's way: the call layer over the screens, here over the pad.
    Widget app(Widget home) => MaterialApp(
      builder: (context, child) => Stack(
        children: [
          ?child,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Stack(
                alignment: Alignment.topCenter,
                children: [CallLayer(calls: hub.calls)],
              ),
            ),
          ),
        ],
      ),
      home: home,
    );

    testWidgets('a call comes in over the pad, and can be declined', (
      tester,
    ) async {
      sideways(tester);
      await tester.pumpWidget(app(PadScreen(onState: (_) {})));
      hub.calls.debugShow(
        incoming: [
          IncomingCall('in1', Person.fromJson(card('ece', name: 'Ece'))),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(find.text('Ece is calling'), findsOneWidget);
      for (final label in ['Accept', 'Decline']) {
        final box = tester.getRect(find.bySemanticsLabel(label));
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: label);
        expect(box.right, lessThanOrEqualTo(screen.width), reason: label);
      }
      // Signed out here, so the server is not reached; the ring goes anyway.
      await tester.tap(find.bySemanticsLabel('Decline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Ece is calling'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the call bar shows the friend muted, and hangs up', (
      tester,
    ) async {
      sideways(tester);
      await tester.pumpWidget(app(const Scaffold()));
      hub.calls.debugShow(
        active: ActiveCall(
          id: 'c1',
          peer: Person.fromJson(card('ece', name: 'Ece')),
          outgoing: true,
          phase: CallPhase.live,
          since: DateTime.now().subtract(const Duration(seconds: 65)),
          peerMuted: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('1:05'), findsOneWidget);
      expect(find.textContaining('Ece is muted'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('End call'));
      await tester.pump();
      expect(find.text('Call ended'), findsOneWidget);
      // The ended call goes after a moment.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Call ended'), findsNothing);
    });

    testWidgets('a direct thread offers a call; a new group picks friends', (
      tester,
    ) async {
      sideways(tester);
      hub.friends
        ..friends = []
        ..loaded = true;
      hub.messages
        ..conversations = []
        ..loaded = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessagesPane(hub: hub)),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('New group'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add friends first: you can message your friends.'),
        findsOneWidget,
      );
      expect(find.text('1 of 32 people'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      hub.messages
        ..conversations = [
          Conversation.fromJson({
            'id': 'c1',
            'kind': 'direct',
            // Signed out here, so no one is "me": the friend alone.
            'members': [card('ece', name: 'Ece')],
            'updatedAt': '2026-10-24T10:00:00Z',
          }),
        ]
        ..openId = 'c1';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MessagesPane(hub: hub)),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Call Ece'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
