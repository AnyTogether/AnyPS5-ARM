import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anyps5_remote/together/activity.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/profiles.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/avatar_crop.dart';
import 'package:anyps5_remote/ui/profile_edit.dart';
import 'package:anyps5_remote/ui/profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

Map<String, dynamic> libraryGame(
  String titleId,
  String name, {
  int seconds = 3600,
  int? earned = 10,
  int total = 40,
  int? points = 300,
}) => {
  'titleId': titleId,
  'names': {'en': name, 'tr': '$name TR'},
  'iconUrl': null,
  'firstPlayedAt': '2026-09-01T10:00:00Z',
  'lastPlayedAt': '2026-10-20T10:00:00Z',
  'secondsPlayed': seconds,
  'trophiesEarned': earned,
  'trophiesTotal': total,
  'progress': earned == null ? null : earned * 100 ~/ total,
  'points': points,
};

Map<String, dynamic> earned(
  String titleId,
  int id,
  String grade, {
  double? rarity,
  String? label,
  bool hidden = false,
}) => {
  'titleId': titleId,
  'gameNames': {'en': 'Astro Bot'},
  'setHash': 'h',
  'trophyId': id,
  'grade': grade,
  'hidden': hidden,
  'texts': hidden
      ? null
      : {
          'en': {'name': 'Trophy $id', 'detail': 'Do the thing'},
        },
  'earnedAt': '2026-10-23T10:00:00Z',
  'earnedCount': 3,
  'rarity': rarity,
  'rarityLabel': label,
};

Map<String, dynamic> userCard({
  String friendship = 'friends',
  Map<String, bool>? visible,
}) => {
  ...card('ece-id', handle: 'ece', name: 'Ece Yılmaz'),
  'bio': 'Platinum hunter',
  'country': 'TR',
  'friendship': friendship,
  'visible':
      visible ??
      {'library': true, 'trophies': true, 'friends': false, 'presence': true},
  'presence': {'state': 'in_game', 'titleId': 'PPSA01234'},
};

Map<String, dynamic> ownProfile({String handle = 'utku', String? at}) => {
  'handle': handle,
  'displayName': 'Utku',
  'bio': null,
  'avatar': null,
  'country': null,
  'handleChangedAt': null,
  'handleChangeAt': at,
  'privacy': {'library': 'everyone', 'trophies': 'friends'},
};

/// A profile's answers, with the friends list private.
(int, Object?) profileAnswers(String method, String path, Object? body) =>
    switch ((method, path.split('?').first)) {
      ('GET', '/api/v1/users/ece') => (200, userCard()),
      ('GET', '/api/v1/users/ece/library') => (
        200,
        {
          'games': [
            libraryGame('PPSA01234', 'Astro Bot', seconds: 7200),
            libraryGame('PPSA05678', 'Stray', seconds: 1800, earned: 5),
          ],
        },
      ),
      ('GET', '/api/v1/users/ece/trophies') => (
        200,
        {
          'trophies': [
            earned(
              'PPSA01234',
              1,
              'platinum',
              rarity: 0.034,
              label: 'very_rare',
            ),
            earned('PPSA01234', 7, 'gold', hidden: true),
          ],
        },
      ),
      ('GET', '/api/v1/users/ece/friends') => (
        403,
        {
          'code': 'forbidden',
          'status': 403,
          'title': 'This friends list is private',
          'section': 'friends',
        },
      ),
      ('GET', '/api/v1/users/ece/activity') => (
        200,
        {
          'items': [
            {
              'id': '0190a000-0000-7000-8000-000000000001',
              'kind': 'platinum',
              'createdAt': DateTime.now()
                  .subtract(const Duration(hours: 2))
                  .toUtc()
                  .toIso8601String(),
              'actor': card('ece-id', handle: 'ece', name: 'Ece Yılmaz'),
              'game': {
                'titleId': 'PPSA01234',
                'names': {'en': 'Astro Bot'},
                'iconUrl': null,
              },
              'highlight': 'platinum',
              'trophies': [
                {
                  'trophyId': 1,
                  'grade': 'platinum',
                  'hidden': false,
                  'texts': {
                    'en': {'name': 'Bot Master'},
                  },
                  'rarity': 0.034,
                  'rarityLabel': 'very_rare',
                },
              ],
              'reactions': {
                'counts': {'fire': 2, 'heart': 1},
                'mine': 'fire',
              },
            },
            {'id': 'x', 'kind': 'something_new', 'actor': card('a')},
          ],
          'next': null,
        },
      ),
      _ => (204, null),
    };

class FakeProfiles extends Profiles {
  FakeProfiles(super.account, {this.page, this.own});

  final ProfilePage? page;
  OwnProfile? own;
  final calls = <String>[];
  Object? saveError;
  Object? handleError;

  @override
  Future<ProfilePage> load(String handle) async {
    calls.add('load $handle');
    return page!;
  }

  @override
  Future<OwnProfile> mine() async => own!;

  @override
  Future<OwnProfile> save({
    required String displayName,
    required String bio,
    required String? country,
  }) async {
    calls.add('save $displayName|$bio|$country');
    if (saveError != null) throw saveError!;
    return own!;
  }

  @override
  Future<OwnProfile> changeHandle(String handle) async {
    calls.add('handle $handle');
    if (handleError != null) throw handleError!;
    return own!;
  }

  @override
  Future<Privacy> setPrivacy(PrivacySection section, Audience audience) async {
    calls.add('privacy ${section.name} ${audience.name}');
    return {...own!.privacy, section: audience};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('profiles from the API', () {
    late FakeServer server;
    late TogetherAccount account;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer()..answer = profileAnswers;
      await server.start();
      account = await server.account();
    });

    tearDown(() => server.stop());

    test('a profile comes with its parts, a private one as null', () async {
      final page = await Profiles(account).load('@ece');
      final profile = page.profile;
      expect(profile.person.displayName, 'Ece Yılmaz');
      expect(profile.friendship, Friendship.friends);
      expect(profile.country, 'TR');
      expect(profile.presence!.state, PresenceState.inGame);
      expect(profile.visible, {
        PrivacySection.library,
        PrivacySection.trophies,
        PrivacySection.presence,
      });
      expect(page.friends, isNull);
      expect(page.games!.first.game.name('tr'), 'Astro Bot TR');
      expect(page.games!.first.game.name('de'), 'Astro Bot');
      final top = page.trophies!.first;
      expect(top.grade, Grade.platinum);
      expect(top.rarity, 0.034);
      expect(top.rarityLabel, Rarity.veryRare);
      expect(localTexts(page.trophies![1].texts, 'en'), isNull);
      final totals = page.totals!;
      expect(totals.games, 2);
      expect(totals.seconds, 9000);
      expect(totals.trophies, 15);
      expect(totals.points, 600);
      expect(totals.platinums, 1);
      expect(totals.countsHidden, isFalse);
      // The kind this app does not know is left out.
      expect(page.activity.items.single.reactions.mine, Reaction.fire);
      expect(page.activity.items.single.reactions.total, 3);
    });

    test('saving the profile and the handle renames the account', () async {
      server.answer = (method, path, body) => switch ((method, path)) {
        ('PATCH', '/api/v1/me/profile') => (
          200,
          {...ownProfile(), 'displayName': 'Utku H', 'country': 'TR'},
        ),
        ('PATCH', '/api/v1/me/handle') => (200, ownProfile(handle: 'utku.h')),
        _ => (204, null),
      };
      var told = 0;
      account.addListener(() => told++);
      final profiles = Profiles(account);
      await profiles.save(displayName: ' Utku H ', bio: '  ', country: 'TR');
      expect(server.requests.last.$3, {
        'displayName': 'Utku H',
        'bio': null,
        'country': 'TR',
      });
      expect(account.user!.displayName, 'Utku H');
      await profiles.changeHandle('@Utku.H');
      expect(server.requests.last.$3, {'handle': 'utku.h'});
      expect(account.user!.handle, 'utku.h');
      expect(told, 2);
      // Kept for the next start.
      final saved = jsonDecode(
        account.preferences.getString('together.session')!,
      );
      expect(saved['user']['handle'], 'utku.h');
    });

    test('a handle asked for too soon says when it can change', () async {
      server.answer = (method, path, body) => (
        429,
        {
          'code': 'handle_cooldown',
          'status': 429,
          'title': 'The handle can change again on 2026-11-02',
          'handleChangeAt': '2026-11-02T10:00:00.000Z',
        },
      );
      await expectLater(
        Profiles(account).changeHandle('newname'),
        throwsA(
          isA<TogetherProblem>()
              .having((p) => p.code, 'code', 'handle_cooldown')
              .having(
                (p) => p.extra?['handleChangeAt'],
                'when',
                '2026-11-02T10:00:00.000Z',
              ),
        ),
      );
    });

    test('privacy sends only the section changed', () async {
      server.answer = (method, path, body) =>
          (200, {'library': 'nobody', 'trophies': 'everyone'});
      final privacy = await Profiles(account)
          .setPrivacy(PrivacySection.library, Audience.nobody);
      expect(server.requests.last.$1, 'PATCH');
      expect(server.requests.last.$2, '/api/v1/me/privacy');
      expect(server.requests.last.$3, {'library': 'nobody'});
      expect(privacy[PrivacySection.library], Audience.nobody);
      expect(privacy[PrivacySection.trophies], Audience.everyone);
      // Sections the server left out keep their defaults.
      expect(privacy[PrivacySection.search], Audience.everyone);
    });
  });

  test('an avatar goes up as the bytes themselves, with its type', () async {
    HttpOverrides.global = null;
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => http.close(force: true));
    final got = <(String, String?, String?, List<int>)>[];
    http.listen((request) async {
      final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      got.add((
        '${request.method} ${request.uri.path}',
        request.headers.contentType?.mimeType,
        request.headers.value('authorization'),
        bytes,
      ));
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'avatar': 'https://x/api/v1/avatars/ab.jpg'}));
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({
      'together.session': jsonEncode({
        'accessToken': 'access-1',
        'accessExpiry': DateTime.now()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
        'refreshToken': 'r',
        'user': {'id': 'me', 'handle': 'utku', 'displayName': 'Utku'},
      }),
    });
    final account = TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      base: Uri.parse('http://127.0.0.1:${http.port}'),
      clientName: 'test',
    );
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final url = await Profiles(account).uploadAvatar(png);
    expect(url, 'https://x/api/v1/avatars/ab.jpg');
    expect(got.single.$1, 'PUT /api/v1/me/avatar');
    expect(got.single.$2, 'image/png');
    expect(got.single.$3, 'Bearer access-1');
    expect(got.single.$4, png);
  });

  group('the limits checked before sending', () {
    test('handles', () {
      expect(handleIssue('ab'), HandleIssue.length);
      expect(handleIssue('a' * 21), HandleIssue.length);
      expect(handleIssue('utku-h'), HandleIssue.characters);
      expect(handleIssue('.utku'), HandleIssue.dots);
      expect(handleIssue('ut..ku'), HandleIssue.dots);
      expect(handleIssue('@Utku_H.1'), isNull);
    });

    test('pictures: PNG or JPEG by their bytes, at most 5 MB', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(avatarIssue(jpeg), isNull);
      expect(
        avatarIssue(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])),
        AvatarIssue.wrongType,
      );
      final big = Uint8List(5 * 1024 * 1024 + 1)..setAll(0, [0xFF, 0xD8, 0xFF]);
      expect(avatarIssue(big), AvatarIssue.tooBig);
    });

    test('the square shown is found in the picture', () {
      // 4000 × 3000 in a 300 pt frame, not zoomed, centred.
      const image = Size(4000, 3000);
      const scale = 300 / 3000;
      final centred = cropOf(
        image: image,
        frame: 300,
        offset: const Offset(-50, 0),
        scale: scale,
      );
      expect(centred, const Rect.fromLTWH(500, 0, 3000, 3000));
      // Zoomed twice and moved to the right edge.
      final zoomed = cropOf(
        image: image,
        frame: 300,
        offset: const Offset(-500, -150),
        scale: scale * 2,
      );
      expect(zoomed, const Rect.fromLTWH(2500, 750, 1500, 1500));
    });

    testWidgets('the crop becomes a PNG square, never larger than 512', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 900, 600),
          Paint()..color = const Color(0xFF3366FF),
        );
        final image = await recorder.endRecording().toImage(900, 600);
        final png = await squarePng(
          image,
          const Rect.fromLTWH(150, 0, 600, 600),
        );
        expect(isPngOrJpeg(png), isTrue);
        final decoded = await (await ui.instantiateImageCodec(png))
            .getNextFrame();
        expect(decoded.image.width, 512);
        expect(decoded.image.height, 512);
        final small = await squarePng(
          image,
          const Rect.fromLTWH(0, 0, 100, 100),
        );
        final smallDecoded = await (await ui.instantiateImageCodec(small))
            .getNextFrame();
        expect(smallDecoded.image.width, 100);
      });
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
      Map<String, bool>? visible,
      String friendship = 'friends',
    }) {
      final card = userCard(friendship: friendship, visible: visible);
      return ProfilePage(
        profile: UserProfile.fromJson(card),
        games: [LibraryGame.fromJson(libraryGame('PPSA01234', 'Astro Bot'))],
        trophies: null,
        friends: null,
        activity: const FeedPage([], null),
      );
    }

    testWidgets('a friend\'s profile shows the card, totals and locks', (
      tester,
    ) async {
      sideways(tester);
      final profiles = FakeProfiles(hub.account, page: page());
      final messaged = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileView(
              hub: hub,
              handle: 'ece',
              profiles: profiles,
              gameName: (id) => id == 'PPSA01234' ? 'Astro Bot' : null,
              onMessage: messaged.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final text in [
        'Ece Yılmaz',
        'Playing Astro Bot',
        'Platinum hunter',
        'Friends',
        '1 h',
        'GAMES',
      ]) {
        final box = tester.getRect(find.text(text).first);
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
        expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
      }
      expect(find.textContaining('🇹🇷 TR'), findsOneWidget);
      expect(find.text('10 of 40 trophies'), findsOneWidget);
      await tester.tap(find.text('Trophies'));
      await tester.pumpAndSettle();
      expect(find.text('Ece Yılmaz keeps this private.'), findsOneWidget);
      await tester.tap(find.byTooltip('Message'));
      expect(messaged, ['ece-id']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('someone not a friend can be added from their profile', (
      tester,
    ) async {
      sideways(tester);
      final profiles = FakeProfiles(
        hub.account,
        page: page(friendship: 'none'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileView(hub: hub, handle: 'ece', profiles: profiles),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add friend'), findsOneWidget);
      expect(find.byTooltip('Message'), findsNothing);
    });

    testWidgets('editing: a wrong handle is caught before it is sent', (
      tester,
    ) async {
      sideways(tester);
      final profiles = FakeProfiles(
        hub.account,
        own: OwnProfile.fromJson(ownProfile()),
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
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final text in ['Save', 'Change picture', 'Name', 'Bio', 'PRIVACY']) {
        final box = tester.getRect(find.text(text).first);
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
        expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
      }
      await tester.enterText(find.widgetWithText(TextField, 'Handle'), 'u');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Use 3 to 20 characters.'), findsOneWidget);
      expect(profiles.calls, isEmpty);
    });

    testWidgets('editing: a taken handle shows under the handle', (
      tester,
    ) async {
      sideways(tester);
      final profiles = FakeProfiles(
        hub.account,
        own: OwnProfile.fromJson(ownProfile()),
      )..handleError = const TogetherProblem(409, 'handle_taken', 'taken');
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditScreen(
            profiles: profiles,
            pickPhoto: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Bio'), 'Hi');
      await tester.enterText(find.widgetWithText(TextField, 'Handle'), 'ece');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(profiles.calls, ['save Utku|Hi|null', 'handle ece']);
      expect(find.text('That handle is taken.'), findsOneWidget);
    });

    testWidgets('editing: privacy changes as it is picked', (tester) async {
      sideways(tester);
      final profiles = FakeProfiles(
        hub.account,
        own: OwnProfile.fromJson(ownProfile()),
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
      // Games and play time is the first row; its "Only me".
      await tester.tap(find.text('Only me').first);
      await tester.pumpAndSettle();
      expect(profiles.calls, ['privacy library nobody']);
      // Finding by name says "No one" rather than "Only me".
      await tester.dragUntilVisible(
        find.text('No one'),
        find.byType(ListView).last,
        const Offset(0, -80),
      );
      expect(find.text('No one'), findsOneWidget);
    });

    testWidgets('editing: a picture of the wrong kind is refused at once', (
      tester,
    ) async {
      sideways(tester);
      final profiles = FakeProfiles(
        hub.account,
        own: OwnProfile.fromJson(ownProfile()),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileEditScreen(
            profiles: profiles,
            pickPhoto: () async => Uint8List.fromList([0x47, 0x49, 0x46, 0x38]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change picture'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a PNG or JPEG picture.'), findsOneWidget);
    });
  });
}
