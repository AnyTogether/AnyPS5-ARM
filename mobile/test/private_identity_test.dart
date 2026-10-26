import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/profiles.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/profile_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

/// The friends-only name and picture on the phone: shown when there, the public ones when not,
/// the handle always; set and cleared in the profile editor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => IdentityBook.shared.learn(const []));

  Person person(Map<String, dynamic> extra) => Person.fromJson({
    'userId': 'u2',
    'handle': 'selin',
    'displayName': 'Night Owl',
    'avatar': 'https://x/pub.jpg',
    ...extra,
  });

  group('showing them', () {
    test('a friend\'s private name and picture, with the handle and public name beside', () {
      final selin = person({
        'privateName': 'Selin Kaya',
        'privateAvatar': 'https://x/api/v1/avatars/private/h.jpg?e=1&s=2',
      });
      expect(selin.shownName, 'Selin Kaya');
      expect(
        selin.shownAvatar,
        startsWith('https://x/api/v1/avatars/private/'),
      );
      expect(selin.handleLine, '@selin · Night Owl');
      expect(selin.initials, 'SK');
    });

    test('without them (not set, or not for this user), the public ones', () {
      final unset = person({'privateName': null, 'privateAvatar': null});
      expect(unset.shownName, 'Night Owl');
      expect(unset.shownAvatar, 'https://x/pub.jpg');
      expect(unset.handleLine, '@selin');
      expect(person({}).shownName, 'Night Owl');
      expect(person({'privateName': '  '}).shownName, 'Night Owl');
    });

    test('a card from a realtime event keeps what the friends list said, until the next list', () {
      IdentityBook.shared.learn([
        Friend(person({'privateName': 'Selin Kaya'}), const Presence()),
      ]);
      expect(person({}).shownName, 'Selin Kaya');
      expect(
        person({'privateName': 'New'}).shownName,
        'New',
        reason: "the card's own wins",
      );
      IdentityBook.shared.learn(const []);
      expect(
        person({}).shownName,
        'Night Owl',
        reason: 'an ended friendship forgets them',
      );
    });
  });

  group('over the network', () {
    late FakeServer server;
    late TogetherHub hub;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/friends') => (
          200,
          {
            'friends': [
              {
                ...card('selin', name: 'Night Owl'),
                'privateName': 'Selin Kaya',
                'presence': {'state': 'online'},
              },
            ],
          },
        ),
        ('GET', '/api/v1/me/friends/requests') => (
          200,
          {'incoming': [], 'outgoing': []},
        ),
        ('PATCH', '/api/v1/me/profile') => (
          200,
          {
            'handle': 'utku',
            'displayName': 'Utku',
            'privateName': body?['privateName'],
          },
        ),
        ('PUT', '/api/v1/me/avatar/private') => (
          200,
          {'privateAvatar': 'https://x/api/v1/avatars/private/h.jpg?e=1&s=2'},
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

    test('the friends list brings the private names in', () async {
      await hub.friends.refresh();
      expect(hub.friends.friends.single.person.shownName, 'Selin Kaya');
      // A party card for the same friend, from an event that carries none.
      expect(
        Person.fromJson(card('selin', name: 'Night Owl')).shownName,
        'Selin Kaya',
      );
    });

    test('the private name is set and cleared; the picture goes up as itself and is removed', () async {
      final profiles = Profiles(hub.account);
      // The hub's own reads may come in between: only the profile's calls are looked at.
      List<Map<String, dynamic>?> patches() => [
        for (final request in server.requests)
          if (request.$1 == 'PATCH') request.$3,
      ];
      expect(await profiles.setPrivateName(' Utku Halis '), 'Utku Halis');
      expect(patches().last, {'privateName': 'Utku Halis'});
      expect(await profiles.setPrivateName(''), isNull);
      expect(patches().last, {'privateName': null}, reason: 'empty clears it');
      final png = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        ...List.filled(64, 0),
      ]);
      expect(
        await profiles.uploadPrivateAvatar(png),
        contains('/avatars/private/'),
      );
      expect(server.uploads.last.$2, '/api/v1/me/avatar/private');
      expect(server.uploads.last.$4, 'image/png');
      await profiles.removePrivateAvatar();
      expect(
        server.requests
            .where((request) => request.$1 == 'DELETE')
            .map((request) => request.$2),
        ['/api/v1/me/avatar/private'],
      );
    });
  });

  testWidgets('the editor has the friends-only name, saved with Save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profiles = _Profiles(
      TogetherAccount(
        preferences: preferences,
        base: Uri.parse('http://127.0.0.1:1'),
        clientName: 'remote-ios/test',
      ),
      OwnProfile.fromJson({
        'handle': 'utku',
        'displayName': 'Utku',
        'privateName': 'Utku H.',
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditScreen(
          profiles: profiles,
          pickPhoto: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Choose picture'),
      find.byType(ListView).first,
      const Offset(0, -80),
    );
    expect(find.text('FRIENDS ONLY'), findsOneWidget);
    expect(find.text('Utku H.'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'Utku H.'),
      'Utku Halis',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(profiles.calls, contains('private Utku Halis'));
    expect(tester.takeException(), isNull);
  });
}

class _Profiles extends Profiles {
  _Profiles(super.account, this.own);

  final OwnProfile own;
  final calls = <String>[];

  @override
  Future<OwnProfile> mine() async => own;

  @override
  Future<OwnProfile> save({
    required String displayName,
    required String bio,
    required String? country,
  }) async {
    calls.add('save $displayName');
    return own;
  }

  @override
  Future<String?> setPrivateName(String name) async {
    calls.add('private $name');
    return name.trim().isEmpty ? null : name.trim();
  }
}
