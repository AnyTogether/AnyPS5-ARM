import 'dart:io';

import 'package:anyps5_remote/together/parties.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'support/quiet_hub.dart';
import 'support/scripted_hub.dart';

Map<String, dynamic> party(
  String id, {
  List<String> members = const ['me'],
  String leader = 'me',
  List<String> invited = const [],
  Map<String, dynamic>? call,
  Map<String, dynamic>? public,
  List<String>? requests,
}) => {
  'id': id,
  'leaderId': leader,
  'privacy': 'invite',
  'members': [
    for (final member in members)
      {...card(member), 'joinedAt': '2026-10-24T12:00:00Z'},
  ],
  'invited': [for (final person in invited) card(person)],
  'call': call,
  'public': public,
  'requests': ?(requests == null
      ? null
      : [for (final person in requests) card(person)]),
  'createdAt': '2026-10-24T12:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parties', () {
    late FakeServer server;
    late TogetherHub hub;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/party') => (
          200,
          {
            'party': null,
            'invites': [
              {
                'partyId': 'p9',
                'from': card('ece'),
                'size': 2,
                'invitedAt': '2026-10-24T12:00:00Z',
              },
            ],
            'requests': [
              {'partyId': 'p7', 'askedAt': '2026-10-24T12:00:00Z'},
            ],
          },
        ),
        ('PATCH', '/api/v1/parties/p1') => (
          200,
          party(
            'p1',
            public: body?['public'] == null
                ? null
                : {
                    'join': (body!['public'] as Map)['join'],
                    'titleId': (body['public'] as Map)['titleId'],
                    'language': (body['public'] as Map)['language'],
                  },
            requests: const [],
          ),
        ),
        ('POST', '/api/v1/parties/p1/requests/ali/accept') => (
          200,
          party('p1', invited: ['ali'], requests: const []),
        ),
        ('POST', '/api/v1/parties') => (201, party('p1')),
        ('POST', '/api/v1/parties/p1/invites') => (
          200,
          party('p1', invited: ['ali']),
        ),
        ('POST', '/api/v1/parties/p9/join') => (
          200,
          party('p9', members: ['ece', 'can', 'me'], leader: 'ece'),
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Parties parties() => hub.parties;

    test('invites come once live and count on the people button', () async {
      await until(() => parties().loaded);
      expect(parties().party, isNull);
      expect(parties().invites.single.from?.handle, 'ece');
      expect(hub.badge, 1);
    });

    test('starting a party and inviting a friend', () async {
      await until(() => parties().loaded);
      await parties().create();
      expect(server.requests.last.$3, {'privacy': 'invite'});
      expect(parties().party?.leaderId, 'me');
      await parties().invite(['ali']);
      expect(server.requests.last.$3, {
        'userIds': ['ali'],
      });
      expect(parties().party?.invited.single.id, 'ali');
    });

    test('joining by invite, and the party changes live', () async {
      await until(() => parties().loaded);
      await parties().join('p9');
      expect(parties().invites, isEmpty);
      expect(parties().party?.members.length, 3);
      server.push('party.member_joined', {
        'partyId': 'p9',
        'member': card('deniz'),
      });
      await until(() => parties().party!.members.length == 4);
      server.push('call.joined', {
        'callId': 'call1',
        'partyId': 'p9',
        'userId': 'ece',
        'device': 'd',
      });
      await until(() => parties().party!.callId == 'call1');
      expect(parties().party!.inCall, {'ece'});
      server.push('party.member_left', {
        'partyId': 'p9',
        'userId': 'ece',
        'reason': 'left',
        'leaderId': 'can',
      });
      await until(() => parties().party!.leaderId == 'can');
      expect(parties().party!.inCall, isEmpty);
      expect(parties().party!.has('ece'), isFalse);
      server.push('party.member_left', {
        'partyId': 'p9',
        'userId': 'me',
        'reason': 'kicked',
        'leaderId': 'can',
      });
      await until(() => parties().party == null);
      expect(parties().kicked, isTrue);
    });

    test('the public parties this phone asked to join', () async {
      await until(() => parties().loaded);
      expect(parties().asked, {'p7'});
      server.push('party.request_answered', {
        'partyId': 'p7',
        'answer': 'declined',
      });
      await until(() => parties().asked.isEmpty);
    });

    test('the leader lists the party in public and lets someone in', () async {
      await until(() => parties().loaded);
      await parties().create();
      await parties().setPublic(
        const PartyListing(
          join: PublicJoin.open,
          titleId: 'PPSA01234',
          language: 'tr',
        ),
      );
      expect(server.requests.lastWhere((r) => r.$1 == 'PATCH').$3, {
        'public': {'join': 'open', 'titleId': 'PPSA01234', 'language': 'tr'},
      });
      expect(parties().party?.listing?.join, PublicJoin.open);
      expect(parties().party?.listing?.language, 'tr');
      server.push('party.request', {'partyId': 'p1', 'from': card('ali')});
      await until(() => parties().party!.requests.length == 1);
      // Told twice (the event, then the party as it is now): still one.
      server.push('party.request', {'partyId': 'p1', 'from': card('ali')});
      server.push('party.request', {'partyId': 'p1', 'from': card('can')});
      await until(() => parties().party!.requests.length == 2);
      server.push('party.request_cancelled', {
        'partyId': 'p1',
        'userId': 'can',
      });
      await until(() => parties().party!.requests.length == 1);
      await parties().answerRequest('ali', accept: true);
      expect(
        server.requests.lastWhere((r) => r.$1 == 'POST').$2,
        '/api/v1/parties/p1/requests/ali/accept',
      );
      expect(parties().party?.requests, isEmpty);
      expect(parties().party?.invited.single.id, 'ali');
      await parties().setPublic(null);
      expect(server.requests.lastWhere((r) => r.$1 == 'PATCH').$3, {
        'public': null,
      });
      expect(parties().party?.listing, isNull);
    });

    test('leaving tells the server', () async {
      await until(() => parties().loaded);
      await parties().create();
      await parties().leave();
      expect(parties().party, isNull);
      expect(server.requests.last.$2, '/api/v1/parties/p1/leave');
    });
  });

  /// An iPhone 14 Pro on its side: the members and the invite list side by side, on the screen.
  testWidgets('a party fits a phone held sideways', (tester) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final hub = TogetherHub(
      account: TogetherAccount(
        preferences: await SharedPreferences.getInstance(),
        clientName: 'test',
      ),
    );
    addTearDown(hub.dispose);
    hub.friends
      ..friends = [
        for (final id in ['zeynep', 'mert', 'ali'])
          Friend(
            Person.fromJson(card(id)),
            const Presence(state: PresenceState.online),
          ),
      ]
      ..loaded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: TogetherScreen(hub: hub, tab: TogetherTab.party),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start a party'), findsOneWidget);
    hub.parties
      ..party = Party.fromJson(
        party(
          'p1',
          members: ['ece', 'can', 'deniz', 'fatma', 'gul', 'hakan'],
          leader: 'ece',
          invited: ['ali'],
          call: {
            'id': 'c1',
            'in': ['ece', 'can'],
          },
        ),
      )
      ..notifyListeners();
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final text in ['HAKAN', 'Join voice', 'ZEYNEP']) {
      final box = tester.getRect(find.text(text).first);
      expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
      expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
    }
    expect(find.text('Invite'), findsNWidgets(2));
    // Two members in voice, and the button to join them.
    expect(find.byIcon(Icons.headset_mic_rounded), findsNWidgets(3));
    expect(find.text('2 in voice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leader\'s switches ripple on a Material, not under a box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final hub = await quietHub();
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TogetherScreen(hub: hub, tab: TogetherTab.party),
      ),
    );
    hub.parties
      ..party = Party.fromJson(party('p1', members: ['me', 'ece']))
      ..notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final ink = find.descendant(
      of: find.byType(SwitchListTile),
      matching: find.byType(InkWell),
    );
    expect(ink, findsWidgets);
    // Between the switch's ink and the Material it splashes on, nothing paints a colour over it.
    final painted = <String>[];
    tester.element(ink.first).visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Material) return false;
      if (widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          ((widget.decoration as BoxDecoration).color?.a ?? 0) > 0) {
        painted.add('$widget');
      }
      return true;
    });
    expect(painted, isEmpty);
    // Requests this test never answers run out.
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the leader lists the party in public and answers who asks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    Map<String, dynamic>? listing;
    var requests = ['zeynep'];
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'me/party') => {
        'party': party(
          'p1',
          members: ['me', 'ece'],
          public: listing,
          requests: requests,
        ),
        'invites': <Object>[],
        'requests': <Object>[],
      },
      ('PATCH', 'parties/p1') => party(
        'p1',
        members: ['me', 'ece'],
        public: listing = body!['public'] as Map<String, dynamic>?,
        requests: requests,
      ),
      ('POST', 'parties/p1/requests/zeynep/accept') => party(
        'p1',
        members: ['me', 'ece'],
        invited: ['zeynep'],
        public: listing,
        requests: requests = [],
      ),
      _ => null,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: TogetherScreen(hub: hub, tab: TogetherTab.party),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final text in ['ASKING TO JOIN', 'ZEYNEP', 'Accept', 'Decline']) {
      final box = tester.getRect(find.text(text).first);
      expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
      expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
    }
    // A request waits for the leader: counted on the rail.
    expect(find.text('1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Anyone can join'),
      80,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    final box = tester.getRect(find.text('Anyone can join'));
    expect(box.right, lessThanOrEqualTo(screen.width));
    await tester.tap(find.text('Anyone can join'));
    await tester.pump();
    expect(account.calls.lastWhere((c) => c.$1 == 'PATCH').$3, {
      'public': {'join': 'open', 'titleId': null, 'language': null},
    });
    expect(hub.parties.party?.listing?.join, PublicJoin.open);
    await tester.ensureVisible(find.text('Any'));
    await tester.pump();
    await tester.tap(find.text('Any'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Turkish').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(account.calls.lastWhere((c) => c.$1 == 'PATCH').$3, {
      'public': {'join': 'open', 'titleId': null, 'language': 'tr'},
    });
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(
      account.paths('POST'),
      contains('parties/p1/requests/zeynep/accept'),
    );
    expect(find.text('ASKING TO JOIN'), findsNothing);
    await tester.ensureVisible(find.text('Off'));
    await tester.pump();
    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(account.calls.lastWhere((c) => c.$1 == 'PATCH').$3, {
      'public': null,
    });
    expect(tester.takeException(), isNull);
  });
}
