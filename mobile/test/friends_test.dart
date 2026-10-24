import 'dart:io';

import 'package:anyps5_remote/together/friends.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anyps5_remote/together/together_account.dart';

import 'support/fake_server.dart';

Map<String, dynamic> friend(String id, String state, {String? titleId}) => {
  ...card(id),
  'presence': {'state': state, 'titleId': ?titleId},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('the friends list', () {
    late FakeServer server;
    late TogetherHub hub;

    setUp(() async {
      // A local server, not the mocked network widget tests get.
      HttpOverrides.global = null;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/friends') => (
          200,
          {
            'friends': [
              friend('ece', 'in_game', titleId: 'PPSA01'),
              friend('ali', 'online'),
              friend('can', 'offline'),
            ],
          },
        ),
        ('GET', '/api/v1/me/friends/requests') => (
          200,
          {
            'incoming': [card('deniz')],
            'outgoing': [card('fatma')],
          },
        ),
        ('POST', '/api/v1/me/friends/requests') => (201, {'state': 'pending'}),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Friends friends() => hub.friends;

    test('comes with presence and requests once the socket is live', () async {
      await until(() => friends().loaded);
      expect(friends().friends.map((f) => f.person.id), ['ece', 'ali', 'can']);
      expect(friends().friends.first.presence.state, PresenceState.inGame);
      expect(friends().friends.first.presence.titleId, 'PPSA01');
      expect(friends().incoming.single.id, 'deniz');
      expect(friends().outgoing.single.id, 'fatma');
      expect(hub.badge, 1);
    });

    test('a friend who starts playing moves to the top', () async {
      await until(() => friends().loaded);
      server.push('presence.updated', {
        'userId': 'can',
        'state': 'in_game',
        'titleId': 'PPSA02',
        'party': {'id': 'p1', 'size': 2, 'max': 8, 'open': true},
      });
      await until(() => friends().friends.first.person.id == 'can');
      final can = friends().byId('can')!;
      expect(can.presence.partyId, 'p1');
      expect(can.presence.partyOpen, isTrue);
      expect(friends().friends.first.person.id, 'can');
    });

    test(
      'adding by handle drops the @, and answering a request asks the server',
      () async {
        await until(() => friends().loaded);
        expect(await friends().add('@zeynep '), isFalse);
        expect(server.requests.where((r) => r.$1 == 'POST').single.$3, {
          'handle': 'zeynep',
        });
        await friends().answer('deniz', accept: false);
        expect(
          server.requests.last.$2,
          '/api/v1/me/friends/requests/deniz/decline',
        );
        expect(friends().incoming, isEmpty);
      },
    );

    test('a removed friend goes, and signing out forgets everyone', () async {
      await until(() => friends().loaded);
      server.push('friend.removed', {'userId': 'ali'});
      await until(() => friends().byId('ali') == null);
      await hub.account.signOut();
      expect(friends().friends, isEmpty);
      expect(friends().loaded, isFalse);
    });
  });

  /// An iPhone 14 Pro on its side: the rail and the friends side by side, on the screen.
  testWidgets('the friends screen fits a phone held sideways', (tester) async {
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
        Friend(
          Person.fromJson(card('ece', name: 'Ece Yılmaz')),
          const Presence(state: PresenceState.inGame, titleId: 'PPSA01'),
        ),
        Friend(
          Person.fromJson(card('ali', name: 'Ali')),
          const Presence(state: PresenceState.online),
        ),
      ]
      ..incoming = [Person.fromJson(card('deniz', name: 'Deniz'))]
      ..loaded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: TogetherScreen(
          hub: hub,
          gameName: (id) => id == 'PPSA01' ? 'Astro Bot' : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final text in ['Playing Astro Bot', 'Accept', 'Add', 'Ali']) {
      final box = tester.getRect(find.text(text));
      expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
      expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
    }
    expect(tester.takeException(), isNull);
  });
}
