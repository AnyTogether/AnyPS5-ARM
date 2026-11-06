import 'dart:io';

import 'package:anyps5_remote/together/activity.dart';
import 'package:anyps5_remote/together/profiles.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/profile_edit.dart';
import 'package:anyps5_remote/ui/profile_view.dart';
import 'package:anyps5_remote/ui/showcase_edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profiles_test.dart'
    show earned, libraryGame, ownProfile, profileAnswers, userCard;
import 'support/fake_server.dart';

Map<String, dynamic> theme({
  String id = '0190a000-0000-7000-8000-0000000000aa',
  String name = 'Nebula',
}) => {
  'id': id,
  'name': name,
  'colors': {
    'deep': '#05061a',
    'middle': '#2a1a6b',
    'bright': '#b9a6ff',
    'accent': '#a885ff',
  },
  'preview': 'https://anytogether.net/t/$id/preview.webp',
  'thumb': 'https://anytogether.net/t/$id/thumb.webp',
  'maker': {'handle': 'mira', 'displayName': 'Mira Vance'},
};

Map<String, dynamic> showcaseGame(String titleId, String name) => {
  'titleId': titleId,
  'names': {'en': name},
  'iconUrl': null,
  'secondsPlayed': 7200,
  'trophiesEarned': 30,
  'trophiesTotal': 40,
  'progress': 75,
};

Map<String, dynamic> showcaseJson({bool trophiesPrivate = false}) => {
  'trophies': trophiesPrivate
      ? null
      : [
          earned('PPSA01234', 1, 'platinum', rarity: 0.034, label: 'very_rare'),
          earned('PPSA01234', 7, 'gold', hidden: true),
        ],
  'games': [showcaseGame('PPSA05678', 'Stray')],
};

class ShowcaseProfiles extends Profiles {
  ShowcaseProfiles(
    super.account, {
    required this.page,
    this.own,
    this.themeCards = const [],
  });

  ProfilePage page;
  OwnProfile? own;
  final List<ProfileTheme> themeCards;
  final calls = <String>[];
  final saved = <Map<String, dynamic>>[];
  Object? saveError;

  @override
  Future<ProfilePage> load(String handle) async {
    calls.add('load $handle');
    return page;
  }

  @override
  Future<OwnProfile> mine() async => own!;

  @override
  Future<Showcase> saveShowcase(ShowcasePicks picks) async {
    calls.add('save showcase');
    saved.add(picks.toJson());
    if (saveError != null) throw saveError!;
    return Showcase.fromJson(showcaseJson());
  }

  @override
  Future<List<ProfileTheme>> themes() async {
    calls.add('themes');
    return themeCards;
  }

  @override
  Future<ProfileLook> wearTheme(String? id) async {
    calls.add('wear ${id ?? 'none'}');
    return ProfileLook(theme: themeCards.where((t) => t.id == id).firstOrNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the look a profile wears', () {
    test('a theme: its still behind the header, its accent, its tint', () {
      final profile = UserProfile.fromJson({
        ...userCard(),
        'cover': null,
        'accent': null,
        'theme': theme(),
      });
      final look = profile.look;
      expect(look.theme!.name, 'Nebula');
      expect(look.theme!.makerName, 'Mira Vance');
      expect(
        look.picture,
        'https://anytogether.net/t/${theme()['id']}/preview.webp',
      );
      expect(look.accentColor, 0xFFA885FF);
      expect(look.theme!.colors.deep, 0xFF05061A);
      expect(look.theme!.colors.middle, 0xFF2A1A6B);
    });

    test('a cover and an accent picked win over the theme', () {
      final look = ProfileLook.fromJson({
        'cover': {
          'kind': 'preset',
          'id': 'cosmic-ribbons',
          'url': 'https://anytogether.net/covers/cosmic-ribbons.webp',
        },
        'accent': 'mint',
        'theme': theme(),
      });
      expect(
        look.picture,
        'https://anytogether.net/covers/cosmic-ribbons.webp',
      );
      expect(look.accentColor, 0xFF5CEBBD);
    });

    test('an older server says nothing: the default look', () {
      final profile = UserProfile.fromJson(userCard());
      expect(profile.look.picture, isNull);
      expect(profile.look.accentColor, isNull);
      expect(profile.look.theme, isNull);
      expect(profile.look.isDefault, isTrue);
      final own = OwnProfile.fromJson(ownProfile());
      expect(own.look.isDefault, isTrue);
      final broken = ProfileLook.fromJson({
        'cover': 'nope',
        'accent': 'purple',
        'theme': {'id': 'x', 'name': 'No colours'},
      });
      expect(broken.isDefault, isTrue);
    });

    test('the own profile carries its theme too', () {
      final own = OwnProfile.fromJson({...ownProfile(), 'theme': theme()});
      expect(own.look.theme!.id, theme()['id']);
    });
  });

  group('the showcase', () {
    test('trophies and games parse, a private part as null', () {
      final shown = Showcase.fromJson(showcaseJson());
      expect(shown.trophies!.first.grade, Grade.platinum);
      expect(shown.trophies!.first.game.name('en'), 'Astro Bot');
      expect(shown.trophies![1].hidden, isTrue);
      expect(shown.games!.single.game.name('en'), 'Stray');
      expect(shown.games!.single.progress, 75);
      expect(shown.count, 3);
      final private = Showcase.fromJson(showcaseJson(trophiesPrivate: true));
      expect(private.trophies, isNull);
      expect(private.count, 1);
      expect(Showcase.fromJson(const {}).isEmpty, isTrue);
    });

    test('at most six show, trophies first', () {
      final shown = Showcase.fromJson({
        'trophies': [
          for (var i = 1; i <= 5; i++) earned('PPSA01234', i, 'bronze'),
        ],
        'games': [
          showcaseGame('PPSA00001', 'One'),
          showcaseGame('PPSA00002', 'Two'),
        ],
      });
      expect(shown.trophies!.length, 5);
      expect(shown.games!.single.game.titleId, 'PPSA00001');
      expect(shown.count, 6);
    });

    test('six pins in all, trophies and games together', () {
      final picks = ShowcasePicks();
      for (var i = 1; i <= 4; i++) {
        expect(picks.toggle(ShowcasePin.trophy('PPSA01234', i)), isTrue);
      }
      expect(picks.toggle(const ShowcasePin.game('PPSA00001')), isTrue);
      expect(picks.toggle(const ShowcasePin.game('PPSA00002')), isTrue);
      expect(picks.count, 6);
      expect(picks.full, isTrue);
      expect(picks.toggle(const ShowcasePin.game('PPSA00003')), isFalse);
      expect(picks.has(const ShowcasePin.game('PPSA00003')), isFalse);
      expect(picks.toggle(const ShowcasePin.trophy('PPSA01234', 2)), isTrue);
      expect(picks.count, 5);
      expect(picks.toggle(const ShowcasePin.game('PPSA00003')), isTrue);
      expect(picks.toJson(), {
        'trophies': [
          {'titleId': 'PPSA01234', 'trophyId': 1},
          {'titleId': 'PPSA01234', 'trophyId': 3},
          {'titleId': 'PPSA01234', 'trophyId': 4},
        ],
        'games': ['PPSA00001', 'PPSA00002', 'PPSA00003'],
      });
    });

    test('a showcase saved before the shared limit is cut to six', () {
      final picks = ShowcasePicks([
        for (var i = 1; i <= 6; i++) ShowcasePin.trophy('PPSA01234', i),
        const ShowcasePin.game('PPSA00001'),
      ]);
      expect(picks.count, 6);
      expect(picks.toJson()['games'], isEmpty);
    });

    test('both lists are always sent, empty ones too', () {
      expect(ShowcasePicks().toJson(), {'trophies': [], 'games': []});
      final picks = Showcase.fromJson(showcaseJson()).picks;
      expect(picks.toJson(), {
        'trophies': [
          {'titleId': 'PPSA01234', 'trophyId': 1},
          {'titleId': 'PPSA01234', 'trophyId': 7},
        ],
        'games': ['PPSA05678'],
      });
    });
  });

  group('the showcase and themes from the API', () {
    late FakeServer server;
    late TogetherAccount account;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer();
      await server.start();
      account = await server.account();
    });

    tearDown(() => server.stop());

    test('a profile loads its showcase beside the card', () async {
      server.answer = (method, path, body) =>
          path == '/api/v1/users/ece/showcase'
          ? (200, showcaseJson(trophiesPrivate: true))
          : profileAnswers(method, path, body);
      final page = await Profiles(account).load('ece');
      expect(page.showcase!.trophies, isNull);
      expect(page.showcase!.games!.single.game.titleId, 'PPSA05678');
      expect(
        server.requests.map((r) => r.$2),
        contains('/api/v1/users/ece/showcase'),
      );
    });

    test(
      'an older server without a showcase still shows the profile',
      () async {
        server.answer = (method, path, body) =>
            path == '/api/v1/users/ece/showcase'
            ? (404, {'code': 'not_found', 'status': 404, 'title': 'Not found'})
            : profileAnswers(method, path, body);
        final page = await Profiles(account).load('ece');
        expect(page.profile.person.displayName, 'Ece Yılmaz');
        expect(page.showcase, isNull);
      },
    );

    test('saving the showcase sends both lists', () async {
      server.answer = (method, path, body) => (200, showcaseJson());
      final picks = ShowcasePicks([const ShowcasePin.game('PPSA05678')]);
      final saved = await Profiles(account).saveShowcase(picks);
      final (method, path, body) = server.requests.last;
      expect((method, path), ('PUT', '/api/v1/me/showcase'));
      expect(body, {
        'trophies': [],
        'games': ['PPSA05678'],
      });
      expect(saved.count, 3);
    });

    test('a theme goes on and comes off with PATCH /me/look', () async {
      server.answer = (method, path, body) => (
        200,
        {
          'cover': null,
          'accent': null,
          'theme': body!['theme'] == null ? null : theme(),
        },
      );
      final profiles = Profiles(account);
      final on = await profiles.wearTheme(theme()['id'] as String);
      expect(server.requests.last.$1, 'PATCH');
      expect(server.requests.last.$2, '/api/v1/me/look');
      expect(server.requests.last.$3, {'theme': theme()['id']});
      expect(on.theme!.name, 'Nebula');
      final off = await profiles.wearTheme(null);
      expect(server.requests.last.$3, {'theme': null});
      expect(off.theme, isNull);
    });

    test('the Theme Hub\'s popular themes to pick from', () async {
      server.answer = (method, path, body) => (
        200,
        {
          'themes': [
            theme(),
            theme(id: '0190a000-0000-7000-8000-0000000000bb', name: 'Dusk'),
            {'id': 'broken'},
          ],
          'next': 'abc',
        },
      );
      final cards = await Profiles(account).themes();
      expect(server.requests.last.$2, '/api/v1/themes?sort=popular&limit=24');
      expect(cards.map((t) => t.name), ['Nebula', 'Dusk']);
      expect(cards.first.thumb, endsWith('thumb.webp'));
    });
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

    ProfilePage page({
      String friendship = 'friends',
      Map<String, dynamic>? look,
      Map<String, dynamic>? showcase,
    }) => ProfilePage(
      profile: UserProfile.fromJson({
        ...userCard(friendship: friendship),
        ...?look,
      }),
      games: [
        LibraryGame.fromJson(libraryGame('PPSA05678', 'Stray')),
        LibraryGame.fromJson(libraryGame('PPSA09999', 'Tetris')),
      ],
      trophies: [
        EarnedTrophy.fromJson(earned('PPSA01234', 1, 'platinum')),
        EarnedTrophy.fromJson(earned('PPSA01234', 3, 'silver')),
      ],
      friends: null,
      activity: const FeedPage([], null),
      showcase: showcase == null ? null : Showcase.fromJson(showcase),
    );

    Widget view(Profiles profiles, {Future<void> Function()? onEdit}) =>
        MaterialApp(
          home: Scaffold(
            body: ProfileView(
              hub: hub,
              handle: 'ece',
              profiles: profiles,
              gameName: (_) => null,
              onMessage: (_) {},
              onEdit: onEdit,
            ),
          ),
        );

    testWidgets('a theme worn: its name, its tint, and the showcase on top', (
      tester,
    ) async {
      sideways(tester);
      final profiles = ShowcaseProfiles(
        hub.account,
        page: page(look: {'theme': theme()}, showcase: showcaseJson()),
      );
      await tester.pumpWidget(view(profiles));
      await tester.pumpAndSettle();
      expect(find.text('Theme: Nebula'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-look-theme')), findsOneWidget);
      expect(find.text('SHOWCASE'), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-PPSA01234-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-PPSA01234-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-PPSA05678')), findsOneWidget);
      expect(find.text('Trophy 1'), findsWidgets);
      expect(find.text('Hidden trophy'), findsOneWidget);
      final showcaseTop = tester.getTopLeft(find.text('SHOWCASE')).dy;
      expect(showcaseTop, lessThan(tester.getTopLeft(find.text('GAMES')).dy));
      expect(
        showcaseTop,
        greaterThan(tester.getTopLeft(find.text('Ece Yılmaz')).dy),
      );
      // Someone else's profile: nothing to edit.
      expect(find.text('Edit showcase'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('private pins and an older server show nothing of them', (
      tester,
    ) async {
      sideways(tester);
      final profiles = ShowcaseProfiles(
        hub.account,
        page: page(showcase: showcaseJson(trophiesPrivate: true)),
      );
      await tester.pumpWidget(view(profiles));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pin-PPSA01234-1')), findsNothing);
      expect(find.byKey(const ValueKey('pin-PPSA05678')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-look-theme')), findsNothing);
      expect(find.textContaining('Theme:'), findsNothing);
      profiles.page = page();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(view(profiles));
      await tester.pumpAndSettle();
      expect(find.text('SHOWCASE'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'editing the showcase: six in all, then saved with both lists',
      (tester) async {
        sideways(tester);
        final profiles = ShowcaseProfiles(
          hub.account,
          page: page(friendship: 'me', showcase: {'trophies': [], 'games': []}),
        );
        await tester.pumpWidget(view(profiles, onEdit: () async {}));
        await tester.pumpAndSettle();
        expect(find.text('Nothing pinned yet.'), findsOneWidget);
        await tester.tap(find.text('Edit showcase'));
        await tester.pumpAndSettle();
        expect(find.byType(ShowcaseEditScreen), findsOneWidget);
        expect(find.text('0 of 6 pinned'), findsOneWidget);
        expect(find.text('Pin up to six trophies and games.'), findsOneWidget);
        final rows = [
          'pick-PPSA01234-1',
          'pick-PPSA01234-3',
          'pick-PPSA05678',
          'pick-PPSA09999',
        ];
        for (final key in rows) {
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
        }
        expect(find.text('4 of 6 pinned'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pick-PPSA05678')));
        await tester.pumpAndSettle();
        expect(find.text('3 of 6 pinned'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(profiles.saved.single, {
          'trophies': [
            {'titleId': 'PPSA01234', 'trophyId': 1},
            {'titleId': 'PPSA01234', 'trophyId': 3},
          ],
          'games': ['PPSA09999'],
        });
        expect(find.byType(ShowcaseEditScreen), findsNothing);
        expect(profiles.calls.where((c) => c.startsWith('load')).length, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the editor stops adding at six and keeps pins not in the lists',
      (tester) async {
        sideways(tester);
        final profiles = ShowcaseProfiles(
          hub.account,
          page: page(friendship: 'me'),
        );
        final current = Showcase.fromJson({
          'trophies': [
            for (var i = 10; i < 15; i++) earned('PPSA01234', i, 'bronze'),
          ],
          'games': [showcaseGame('PPSA07777', 'Old pin')],
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ShowcaseEditScreen(
              profiles: profiles,
              current: current,
              trophies: profiles.page.trophies!,
              games: profiles.page.games!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('6 of 6 pinned'), findsOneWidget);
        expect(find.byKey(const ValueKey('pick-PPSA07777')), findsOneWidget);
        expect(find.byKey(const ValueKey('pick-PPSA01234-10')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pick-PPSA05678')));
        await tester.pumpAndSettle();
        expect(find.text('6 of 6 pinned'), findsOneWidget);
        profiles.saveError = const TogetherProblem(
          400,
          'bad_request',
          'showcase: up to six pins',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('showcase: up to six pins'), findsOneWidget);
        expect(find.byType(ShowcaseEditScreen), findsOneWidget);
      },
    );

    testWidgets('the profile theme: picked from the Hub, then taken off', (
      tester,
    ) async {
      sideways(tester);
      final profiles = ShowcaseProfiles(
        hub.account,
        page: page(friendship: 'me'),
        own: OwnProfile.fromJson(ownProfile()),
        themeCards: [
          ProfileTheme.fromJson(theme())!,
          ProfileTheme.fromJson(
            theme(id: '0190a000-0000-7000-8000-0000000000bb', name: 'Dusk'),
          )!,
        ],
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
      expect(find.text('PROFILE THEME'), findsOneWidget);
      expect(find.text('Default look'), findsOneWidget);
      await tester.tap(find.text('Default look'));
      await tester.pumpAndSettle();
      expect(profiles.calls, ['themes']);
      expect(find.text('Dusk'), findsOneWidget);
      expect(find.text('Take it off'), findsNothing);
      await tester.tap(find.text('Nebula'));
      await tester.pumpAndSettle();
      expect(profiles.calls.last, 'wear ${theme()['id']}');
      expect(find.text('Nebula'), findsOneWidget);
      await tester.tap(find.text('Nebula'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take it off'));
      await tester.pumpAndSettle();
      expect(profiles.calls.last, 'wear none');
      expect(find.text('Default look'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
